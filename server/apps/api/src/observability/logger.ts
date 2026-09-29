import pino from 'pino';
import type { Env } from '../config/env.js';

export function createLogger(env: Env) {
  return pino({
    level: env.NODE_ENV === 'production' ? 'info' : 'debug',
    base: { service: 'yxz-api' },
    timestamp: pino.stdTimeFunctions.isoTime,
  });
}

export type Logger = ReturnType<typeof createLogger>;
