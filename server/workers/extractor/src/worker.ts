import { Worker } from 'bullmq';
import { Redis } from 'ioredis';
import pino from 'pino';
import {
  QUEUE_EXTRACT,
  type ExtractJobPayload,
  type PlaybackManifest,
} from '@yxz/shared';
import { PoTokenProvider } from './tokens/pot-provider.js';
import { resolveWithStrategies } from './strategies/pipeline.js';

const log = pino({ name: 'yxz-extractor' });

async function main(): Promise<void> {
  const redisUrl = process.env.REDIS_URL ?? 'redis://redis:6379';
  const connection = new Redis(redisUrl, { maxRetriesPerRequest: null });
  const po = new PoTokenProvider();

  const worker = new Worker<ExtractJobPayload, PlaybackManifest>(
    QUEUE_EXTRACT,
    async (job) => {
      const p = job.data;
      log.info({ videoId: p.videoId, strategy: 'pipeline' }, 'extract start');
      return resolveWithStrategies({
        videoId: p.videoId,
        quality: p.quality,
        codec: p.codec,
        audioLanguage: p.audioLanguage,
        hdr: p.hdr,
        ytdlpBin: process.env.YTDLP_BIN ?? 'yt-dlp',
        timeoutMs: Number(process.env.PLAYBACK_TIMEOUT_MS ?? 20_000),
        po,
      });
    },
    { connection, concurrency: Number(process.env.EXTRACT_CONCURRENCY ?? 2) },
  );

  worker.on('failed', (job, err) => {
    log.error({ jobId: job?.id, err: err.message }, 'extract failed');
  });
  worker.on('completed', (job) => {
    log.info({ jobId: job.id, videoId: job.data.videoId }, 'extract done');
  });

  log.info('extractor worker listening');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
