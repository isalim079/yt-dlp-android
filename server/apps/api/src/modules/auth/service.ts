import { createHash, randomBytes } from 'node:crypto';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { v4 as uuidv4 } from 'uuid';
import { AppError, ErrorCodes } from '@yxz/shared';
import type { Env } from '../../config/env.js';
import { InstallationModel } from '../../infrastructure/mongo/models.js';

export interface AccessClaims {
  sub: string;
  typ: 'access';
  ver: number;
}

export interface TokenPair {
  installationId: string;
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
}

export class AuthService {
  constructor(private readonly env: Env) {}

  async register(): Promise<TokenPair> {
    const installationId = uuidv4();
    const refreshToken = randomBytes(48).toString('base64url');
    const refreshTokenHash = await bcrypt.hash(refreshToken, 10);
    await InstallationModel.create({
      _id: installationId,
      refreshTokenHash,
      status: 'active',
      tokenVersion: 1,
      lastSeenAt: new Date(),
    });
    return this.issuePair(installationId, refreshToken, 1);
  }

  async refresh(installationId: string, refreshToken: string): Promise<TokenPair> {
    const doc = await InstallationModel.findById(installationId);
    if (!doc || doc.status !== 'active') {
      throw new AppError(ErrorCodes.AUTH_REVOKED, 'Installation disabled or unknown', {
        statusCode: 401,
      });
    }
    const ok = await bcrypt.compare(refreshToken, doc.refreshTokenHash);
    if (!ok) {
      throw new AppError(ErrorCodes.AUTH_INVALID, 'Invalid refresh token', {
        statusCode: 401,
      });
    }
    const nextRefresh = randomBytes(48).toString('base64url');
    const nextHash = await bcrypt.hash(nextRefresh, 10);
    const nextVer = (doc.tokenVersion ?? 1) + 1;
    doc.refreshTokenHash = nextHash;
    doc.tokenVersion = nextVer;
    doc.lastSeenAt = new Date();
    await doc.save();
    return this.issuePair(installationId, nextRefresh, nextVer);
  }

  async revoke(installationId: string): Promise<void> {
    await InstallationModel.findByIdAndUpdate(installationId, {
      status: 'disabled',
      tokenVersion: Date.now(),
    });
  }

  verifyAccess(token: string): AccessClaims {
    try {
      const payload = jwt.verify(token, this.env.JWT_SECRET) as AccessClaims;
      if (payload.typ !== 'access' || !payload.sub) {
        throw new AppError(ErrorCodes.AUTH_INVALID, 'Invalid access token', {
          statusCode: 401,
        });
      }
      return payload;
    } catch (e) {
      if (e instanceof AppError) throw e;
      throw new AppError(ErrorCodes.AUTH_EXPIRED, 'Access token expired or invalid', {
        statusCode: 401,
        retryable: true,
      });
    }
  }

  async assertActive(claims: AccessClaims): Promise<void> {
    const doc = await InstallationModel.findById(claims.sub);
    if (!doc || doc.status !== 'active') {
      throw new AppError(ErrorCodes.AUTH_REVOKED, 'Installation disabled', {
        statusCode: 401,
      });
    }
    if ((doc.tokenVersion ?? 1) !== claims.ver) {
      throw new AppError(ErrorCodes.AUTH_EXPIRED, 'Token superseded', {
        statusCode: 401,
        retryable: true,
      });
    }
    doc.lastSeenAt = new Date();
    await doc.save();
  }

  private issuePair(
    installationId: string,
    refreshToken: string,
    ver: number,
  ): TokenPair {
    const accessToken = jwt.sign(
      { sub: installationId, typ: 'access', ver } satisfies AccessClaims,
      this.env.JWT_SECRET,
      { expiresIn: this.env.JWT_ACCESS_TTL_SEC },
    );
    return {
      installationId,
      accessToken,
      refreshToken,
      expiresIn: this.env.JWT_ACCESS_TTL_SEC,
    };
  }
}

export function profileHash(parts: Record<string, string>): string {
  const canonical = Object.keys(parts)
    .sort()
    .map((k) => `${k}=${parts[k]}`)
    .join('&');
  return createHash('sha256').update(canonical).digest('hex').slice(0, 16);
}
