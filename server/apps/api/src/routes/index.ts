import type {
  FastifyInstance,
  FastifyReply,
  FastifyRequest,
} from 'fastify';
import { z } from 'zod';
import {
  AppError,
  ErrorCodes,
  CreateDownloadSchema,
  PlaybackQuerySchema,
  VideoIdSchema,
} from '@yxz/shared';
import type { AuthService, AccessClaims } from '../modules/auth/service.js';
import type { PlaybackService } from '../modules/playback/service.js';
import { metrics } from '../observability/metrics.js';
import { ytDlpVersion } from '@yxz/extractor';
import type { Env } from '../config/env.js';
import type { Redis } from 'ioredis';
import mongoose from 'mongoose';
import path from 'node:path';
import { createReadStream, existsSync } from 'node:fs';

declare module 'fastify' {
  interface FastifyRequest {
    auth?: AccessClaims;
  }
}

function sendError(reply: FastifyReply, err: unknown) {
  if (err instanceof AppError) {
    metrics.inc('yxz_api_errors');
    return reply.status(err.statusCode).send(err.toBody());
  }
  if (err instanceof z.ZodError) {
    return reply.status(400).send(
      new AppError(ErrorCodes.VALIDATION_ERROR, 'Invalid request', {
        statusCode: 400,
        details: err.flatten(),
      }).toBody(),
    );
  }
  metrics.inc('yxz_api_errors');
  return reply.status(500).send(
    new AppError(ErrorCodes.INTERNAL_ERROR, 'Internal error', {
      statusCode: 500,
    }).toBody(),
  );
}

export function registerRoutes(
  app: FastifyInstance,
  deps: {
    auth: AuthService;
    playback: PlaybackService;
    env: Env;
    redis: Redis;
  },
): void {
  const { auth, playback, env, redis } = deps;

  app.get('/health', async () => ({ status: 'ok' }));

  app.get('/ready', async (_req, reply) => {
    const checks: Record<string, string> = {};
    try {
      const s = mongoose.connection.readyState;
      checks.mongo = s === 1 ? 'ok' : `state:${s}`;
    } catch {
      checks.mongo = 'fail';
    }
    try {
      const pong = await redis.ping();
      checks.redis = pong === 'PONG' ? 'ok' : 'fail';
    } catch {
      checks.redis = 'fail';
    }
    try {
      checks.ytdlp = await ytDlpVersion(env.YTDLP_BIN);
    } catch {
      checks.ytdlp = 'unavailable';
    }
    const ok = checks.mongo === 'ok' && checks.redis === 'ok';
    return reply.status(ok ? 200 : 503).send({ ready: ok, checks });
  });

  app.get('/metrics', async (_req, reply) => {
    reply.header('content-type', 'text/plain; version=0.0.4');
    return metrics.toPrometheus();
  });

  app.post('/api/v1/installations', async (_req, reply) => {
    try {
      const pair = await auth.register();
      return reply.status(201).send(pair);
    } catch (e) {
      return sendError(reply, e);
    }
  });

  app.post('/api/v1/auth/refresh', async (req, reply) => {
    try {
      const body = z
        .object({
          installationId: z.string().uuid(),
          refreshToken: z.string().min(20),
        })
        .parse(req.body);
      const pair = await auth.refresh(body.installationId, body.refreshToken);
      return reply.send(pair);
    } catch (e) {
      return sendError(reply, e);
    }
  });

  app.post(
    '/api/v1/auth/revoke',
    { preHandler: requireAuth(auth) },
    async (req, reply) => {
      try {
        await auth.revoke(req.auth!.sub);
        return reply.status(204).send();
      } catch (e) {
        return sendError(reply, e);
      }
    },
  );

  app.get(
    '/api/v1/videos/:videoId',
    { preHandler: requireAuth(auth) },
    async (req, reply) => {
      try {
        const videoId = VideoIdSchema.parse(
          (req.params as { videoId: string }).videoId,
        );
        const meta = await playback.metadata(videoId);
        return reply.send(meta);
      } catch (e) {
        return sendError(reply, e);
      }
    },
  );

  app.get(
    '/api/v1/videos/:videoId/playback',
    { preHandler: requireAuth(auth) },
    async (req, reply) => {
      try {
        const videoId = VideoIdSchema.parse(
          (req.params as { videoId: string }).videoId,
        );
        const query = PlaybackQuerySchema.parse(req.query ?? {});
        const useWorker = process.env.YXZ_USE_EXTRACT_WORKER === '1';
        const manifest = await playback.resolve(videoId, query, { useWorker });
        return reply.send(manifest);
      } catch (e) {
        return sendError(reply, e);
      }
    },
  );

  app.get(
    '/api/v1/videos/:videoId/playback/debug',
    { preHandler: requireAuth(auth) },
    async (req, reply) => {
      try {
        if (process.env.YXZ_PLAYBACK_DEBUG !== '1') {
          throw new AppError(
            ErrorCodes.VALIDATION_ERROR,
            'Playback debug disabled (set YXZ_PLAYBACK_DEBUG=1)',
            { statusCode: 404 },
          );
        }
        const videoId = VideoIdSchema.parse(
          (req.params as { videoId: string }).videoId,
        );
        const query = PlaybackQuerySchema.parse(req.query ?? {});
        const debug = await playback.resolveDebug(videoId, query);
        return reply.send(debug);
      } catch (e) {
        return sendError(reply, e);
      }
    },
  );

  app.post(
    '/api/v1/playback/quality-mismatch',
    { preHandler: requireAuth(auth) },
    async (req, reply) => {
      try {
        const body = z
          .object({
            videoId: VideoIdSchema,
            requestedQuality: z.string(),
            selectedQuality: z.string(),
            actualWidth: z.number().int().nonnegative(),
            actualHeight: z.number().int().nonnegative(),
          })
          .parse(req.body);
        void body;
        metrics.inc('yxz_playback_quality_mismatch_total');
        return reply.status(204).send();
      } catch (e) {
        return sendError(reply, e);
      }
    },
  );

  app.get(
    '/api/v1/videos/:videoId/subtitles',
    { preHandler: requireAuth(auth) },
    async (req, reply) => {
      try {
        const videoId = VideoIdSchema.parse(
          (req.params as { videoId: string }).videoId,
        );
        const manifest = await playback.resolve(videoId, {
          quality: 'auto',
          codec: 'auto',
          audioLanguage: 'auto',
          hdr: 'auto',
          forceRefresh: false,
        });
        return reply.send({ videoId, subtitles: manifest.subtitles });
      } catch (e) {
        return sendError(reply, e);
      }
    },
  );

  app.post(
    '/api/v1/downloads',
    { preHandler: requireAuth(auth) },
    async (req, reply) => {
      try {
        const body = CreateDownloadSchema.parse(req.body);
        const result = await playback.enqueueDownload({
          installationId: req.auth!.sub,
          videoId: body.videoId,
          quality: body.quality,
          format: body.format,
        });
        return reply.status(202).send(result);
      } catch (e) {
        return sendError(reply, e);
      }
    },
  );

  app.get(
    '/api/v1/downloads/:jobId',
    { preHandler: requireAuth(auth) },
    async (req, reply) => {
      try {
        const jobId = z.string().uuid().parse(
          (req.params as { jobId: string }).jobId,
        );
        const status = await playback.downloadStatus(jobId, req.auth!.sub);
        return reply.send(status);
      } catch (e) {
        return sendError(reply, e);
      }
    },
  );

  app.get(
    '/api/v1/downloads/:jobId/file',
    { preHandler: requireAuth(auth) },
    async (req, reply) => {
      try {
        const jobId = z.string().uuid().parse(
          (req.params as { jobId: string }).jobId,
        );
        const status = await playback.downloadStatus(jobId, req.auth!.sub);
        if (status.status !== 'completed' || !status.fileName) {
          throw new AppError(
            ErrorCodes.VALIDATION_ERROR,
            'File not ready',
            { statusCode: 409 },
          );
        }
        const filePath = path.join(env.DOWNLOAD_DIR, status.fileName);
        if (!existsSync(filePath)) {
          throw new AppError(ErrorCodes.INTERNAL_ERROR, 'File missing', {
            statusCode: 404,
          });
        }
        reply.header(
          'content-disposition',
          `attachment; filename="${status.fileName}"`,
        );
        return reply.send(createReadStream(filePath));
      } catch (e) {
        return sendError(reply, e);
      }
    },
  );
}

function requireAuth(auth: AuthService) {
  return async (req: FastifyRequest, reply: FastifyReply) => {
    const header = req.headers.authorization;
    if (!header?.startsWith('Bearer ')) {
      return reply
        .status(401)
        .send(
          new AppError(ErrorCodes.AUTH_INVALID, 'Missing bearer token', {
            statusCode: 401,
          }).toBody(),
        );
    }
    try {
      const claims = auth.verifyAccess(header.slice(7));
      await auth.assertActive(claims);
      req.auth = claims;
    } catch (e) {
      return sendError(reply, e);
    }
  };
}
