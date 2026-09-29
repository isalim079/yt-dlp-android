import { createHash, randomBytes } from 'node:crypto';

/**
 * PO token provider.
 *
 * Production deployments should wire bgutil / official PO provider here.
 * This implementation caches opaque tokens and synthesizes a placeholder
 * only when YXZ_PO_TOKEN_STUB=1 (local/dev). Real extraction still relies
 * on yt-dlp + EJS when PO is not strictly required.
 */
export class PoTokenProvider {
  private readonly memory = new Map<string, { token: string; exp: number }>();

  constructor(
    private readonly getRemote?: (
      videoId: string,
      contextHash: string,
    ) => Promise<string | null>,
    private readonly setRemote?: (
      videoId: string,
      contextHash: string,
      token: string,
      ttlSec: number,
    ) => Promise<void>,
  ) {}

  contextHash(client: string): string {
    return createHash('sha256').update(client).digest('hex').slice(0, 12);
  }

  async get(videoId: string, client: string): Promise<string | null> {
    const ctx = this.contextHash(client);
    const mem = this.memory.get(`${videoId}:${ctx}`);
    if (mem && mem.exp > Date.now()) return mem.token;
    if (this.getRemote) {
      const remote = await this.getRemote(videoId, ctx);
      if (remote) return remote;
    }
    if (process.env.YXZ_PO_TOKEN_STUB === '1') {
      const token = `stub.${randomBytes(16).toString('hex')}`;
      await this.cache(videoId, client, token, 300);
      return token;
    }
    return null;
  }

  async invalidate(videoId: string, client: string): Promise<void> {
    const ctx = this.contextHash(client);
    this.memory.delete(`${videoId}:${ctx}`);
  }

  async cache(
    videoId: string,
    client: string,
    token: string,
    ttlSec: number,
  ): Promise<void> {
    const ctx = this.contextHash(client);
    this.memory.set(`${videoId}:${ctx}`, {
      token,
      exp: Date.now() + ttlSec * 1000,
    });
    if (this.setRemote) {
      await this.setRemote(videoId, ctx, token, ttlSec);
    }
  }
}
