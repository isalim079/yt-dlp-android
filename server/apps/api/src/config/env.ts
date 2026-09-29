import { z } from 'zod';

const EnvSchema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  HOST: z.string().default('0.0.0.0'),
  PORT: z.coerce.number().default(8080),
  MONGO_URI: z.string().default('mongodb://mongo:27017/yxz'),
  REDIS_URL: z.string().default('redis://redis:6379'),
  JWT_SECRET: z.string().min(16).default('dev-only-change-me-32chars!!'),
  JWT_ACCESS_TTL_SEC: z.coerce.number().default(900),
  JWT_REFRESH_TTL_SEC: z.coerce.number().default(60 * 60 * 24 * 30),
  PLAYBACK_CACHE_MAX_TTL_SEC: z.coerce.number().default(600),
  PLAYBACK_TIMEOUT_MS: z.coerce.number().default(20_000),
  YTDLP_BIN: z.string().default('yt-dlp'),
  DENO_BIN: z.string().default('deno'),
  FFMPEG_BIN: z.string().default('ffmpeg'),
  FFPROBE_BIN: z.string().default('ffprobe'),
  DOWNLOAD_DIR: z.string().default('/data/downloads'),
  PUBLIC_BASE_URL: z.string().default('http://localhost:8080'),
  RATE_LIMIT_MAX: z.coerce.number().default(120),
  RATE_LIMIT_WINDOW_MS: z.coerce.number().default(60_000),
});

export type Env = z.infer<typeof EnvSchema>;

export function loadEnv(raw: NodeJS.ProcessEnv = process.env): Env {
  return EnvSchema.parse(raw);
}
