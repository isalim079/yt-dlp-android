import path from 'node:path';
import { mkdir } from 'node:fs/promises';
import mongoose, { Schema } from 'mongoose';
import { Worker } from 'bullmq';
import { Redis } from 'ioredis';
import pino from 'pino';
import {
  QUEUE_DOWNLOAD,
  type DownloadJobPayload,
  AppError,
  ErrorCodes,
} from '@yxz/shared';
import { resolveWithStrategies, PoTokenProvider } from '@yxz/extractor';
import { downloadFormat, ffprobeOk, remuxCopy } from './ffmpeg/remux.js';

const log = pino({ name: 'yxz-downloader' });

const DownloadJobSchema = new Schema(
  {
    _id: { type: String, required: true },
    installationId: String,
    videoId: String,
    quality: String,
    format: String,
    status: String,
    progress: Number,
    errorCode: String,
    errorMessage: String,
    outputPath: String,
    fileName: String,
    fileSize: Number,
  },
  { timestamps: true },
);

async function main(): Promise<void> {
  const mongoUri = process.env.MONGO_URI ?? 'mongodb://mongo:27017/yxz';
  const redisUrl = process.env.REDIS_URL ?? 'redis://redis:6379';
  const downloadDir = process.env.DOWNLOAD_DIR ?? '/data/downloads';
  await mongoose.connect(mongoUri);
  const DownloadJob = mongoose.model('DownloadJob', DownloadJobSchema);
  const connection = new Redis(redisUrl, { maxRetriesPerRequest: null });
  const po = new PoTokenProvider();

  const worker = new Worker<DownloadJobPayload>(
    QUEUE_DOWNLOAD,
    async (job) => {
      const { jobId, videoId, quality } = job.data;
      await DownloadJob.findByIdAndUpdate(jobId, {
        status: 'running',
        progress: 5,
      });
      try {
        const manifest = await resolveWithStrategies({
          videoId,
          quality: quality === 'best' ? 'auto' : quality,
          codec: 'auto',
          audioLanguage: 'auto',
          hdr: 'auto',
          ytdlpBin: process.env.YTDLP_BIN ?? 'yt-dlp',
          timeoutMs: Number(process.env.PLAYBACK_TIMEOUT_MS ?? 20_000),
          po,
        });
        const video =
          manifest.videoStreams.find((v) => v.isVideoOnly) ??
          manifest.videoStreams[0];
        const audio = manifest.audioStreams[0];
        if (!video) {
          throw new AppError(ErrorCodes.EXTRACTOR_NO_STREAM, 'No video stream');
        }
        const work = path.join(downloadDir, 'tmp', jobId);
        await mkdir(work, { recursive: true });
        const watchUrl =
          manifest.webpageUrl ?? `https://www.youtube.com/watch?v=${videoId}`;
        const vOut = path.join(work, 'video.%(ext)s');
        await downloadFormat(
          process.env.YTDLP_BIN ?? 'yt-dlp',
          watchUrl,
          vOut,
          video.id,
        );
        await DownloadJob.findByIdAndUpdate(jobId, { progress: 50 });

        const fileName = `${videoId}_${quality}.mp4`;
        const finalPath = path.join(downloadDir, fileName);

        if (video.isVideoOnly && audio) {
          const aOut = path.join(work, 'audio.%(ext)s');
          await downloadFormat(
            process.env.YTDLP_BIN ?? 'yt-dlp',
            watchUrl,
            aOut,
            audio.id,
          );
          await DownloadJob.findByIdAndUpdate(jobId, { progress: 75 });
          // Resolve actual filenames (yt-dlp replaces ext)
          const { readdir } = await import('node:fs/promises');
          const files = await readdir(work);
          const vFile = files.find((f) => f.startsWith('video.'));
          const aFile = files.find((f) => f.startsWith('audio.'));
          if (!vFile || !aFile) {
            throw new AppError(ErrorCodes.INTERNAL_ERROR, 'Temp media missing');
          }
          await remuxCopy(
            process.env.FFMPEG_BIN ?? 'ffmpeg',
            path.join(work, vFile),
            path.join(work, aFile),
            finalPath,
          );
        } else {
          const { readdir, rename } = await import('node:fs/promises');
          const files = await readdir(work);
          const vFile = files.find((f) => f.startsWith('video.'));
          if (!vFile) {
            throw new AppError(ErrorCodes.INTERNAL_ERROR, 'Temp video missing');
          }
          await rename(path.join(work, vFile), finalPath);
        }

        const probe = await ffprobeOk(
          process.env.FFPROBE_BIN ?? 'ffprobe',
          finalPath,
        );
        await DownloadJob.findByIdAndUpdate(jobId, {
          status: 'completed',
          progress: 100,
          outputPath: finalPath,
          fileName,
          fileSize: probe.size,
        });
        return { fileName, size: probe.size };
      } catch (e) {
        const err =
          e instanceof AppError
            ? e
            : new AppError(ErrorCodes.INTERNAL_ERROR, String(e));
        await DownloadJob.findByIdAndUpdate(jobId, {
          status: 'failed',
          errorCode: err.code,
          errorMessage: err.message,
        });
        throw err;
      }
    },
    {
      connection,
      concurrency: Number(process.env.DOWNLOAD_CONCURRENCY ?? 1),
    },
  );

  worker.on('failed', (job, err) => {
    log.error({ jobId: job?.id, err: err.message }, 'download failed');
  });
  log.info('downloader worker listening');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
