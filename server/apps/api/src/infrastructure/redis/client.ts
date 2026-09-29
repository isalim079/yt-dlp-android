import { Redis } from 'ioredis';
import type { Env } from '../../config/env.js';

export function createRedis(env: Env): Redis {
  return new Redis(env.REDIS_URL, {
    maxRetriesPerRequest: null,
    enableReadyCheck: true,
  });
}

export class PlaybackCache {
  constructor(
    private readonly redis: Redis,
    private readonly maxTtlSec: number,
  ) {}

  key(videoId: string, profileHash: string): string {
    return `yt:playback:${videoId}:${profileHash}`;
  }

  lockKey(videoId: string, profileHash: string): string {
    return `yt:lock:${videoId}:${profileHash}`;
  }

  async get(videoId: string, profileHash: string): Promise<string | null> {
    return this.redis.get(this.key(videoId, profileHash));
  }

  async set(
    videoId: string,
    profileHash: string,
    json: string,
    expiresAtIso?: string,
  ): Promise<void> {
    let ttl = this.maxTtlSec;
    if (expiresAtIso) {
      const ms = Date.parse(expiresAtIso) - Date.now() - 60_000;
      if (ms > 0) {
        ttl = Math.min(this.maxTtlSec, Math.floor(ms / 1000));
      } else {
        ttl = 30;
      }
    }
    await this.redis.set(this.key(videoId, profileHash), json, 'EX', Math.max(30, ttl));
  }

  async del(videoId: string, profileHash: string): Promise<void> {
    await this.redis.del(this.key(videoId, profileHash));
  }

  /** Single-flight: acquire lock or wait for cache fill. */
  async withSingleFlight<T>(
    videoId: string,
    profileHash: string,
    ttlSec: number,
    work: () => Promise<T>,
    readCache: () => Promise<T | null>,
  ): Promise<T> {
    const lock = this.lockKey(videoId, profileHash);
    const acquired = await this.redis.set(lock, '1', 'EX', ttlSec, 'NX');
    if (acquired) {
      try {
        return await work();
      } finally {
        await this.redis.del(lock);
      }
    }
    for (let i = 0; i < 40; i++) {
      await new Promise((r) => setTimeout(r, 250));
      const cached = await readCache();
      if (cached) return cached;
      const still = await this.redis.exists(lock);
      if (!still) {
        const again = await readCache();
        if (again) return again;
        break;
      }
    }
    return work();
  }
}

export class PoTokenCache {
  constructor(private readonly redis: Redis) {}

  key(videoId: string, contextHash: string): string {
    return `po:video:${videoId}:${contextHash}`;
  }

  async get(videoId: string, contextHash: string): Promise<string | null> {
    return this.redis.get(this.key(videoId, contextHash));
  }

  async set(
    videoId: string,
    contextHash: string,
    token: string,
    ttlSec = 300,
  ): Promise<void> {
    await this.redis.set(this.key(videoId, contextHash), token, 'EX', ttlSec);
  }

  async invalidate(videoId: string, contextHash: string): Promise<void> {
    await this.redis.del(this.key(videoId, contextHash));
  }
}
