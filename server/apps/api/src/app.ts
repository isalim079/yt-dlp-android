import Fastify from 'fastify';
import cors from '@fastify/cors';
import rateLimit from '@fastify/rate-limit';
import type { Env } from './config/env.js';
import { createLogger } from './observability/logger.js';
import { connectMongo } from './infrastructure/mongo/models.js';
import { createRedis } from './infrastructure/redis/client.js';
import { AuthService } from './modules/auth/service.js';
import { PlaybackService } from './modules/playback/service.js';
import { registerRoutes } from './routes/index.js';

export async function buildApp(env: Env) {
  const log = createLogger(env);
  const app = Fastify({
    logger: false,
    trustProxy: true,
    requestTimeout: env.PLAYBACK_TIMEOUT_MS + 10_000,
  });

  await app.register(cors, { origin: true });
  await app.register(rateLimit, {
    max: env.RATE_LIMIT_MAX,
    timeWindow: env.RATE_LIMIT_WINDOW_MS,
    keyGenerator: (req) => {
      const auth = req.headers.authorization;
      if (auth?.startsWith('Bearer ')) return `jwt:${auth.slice(7, 32)}`;
      return req.ip;
    },
  });

  await connectMongo(env.MONGO_URI);
  const redis = createRedis(env);
  const auth = new AuthService(env);
  const playback = new PlaybackService(env, redis, log);

  registerRoutes(app, { auth, playback, env, redis });

  app.addHook('onClose', async () => {
    await redis.quit();
  });

  return { app, log, redis };
}
