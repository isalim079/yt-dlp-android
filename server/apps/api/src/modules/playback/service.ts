import { Queue, QueueEvents } from 'bullmq';
import {
  AppError,
  ErrorCodes,
  QUEUE_EXTRACT,
  QUEUE_DOWNLOAD,
  type ExtractJobPayload,
  type PlaybackManifest,
  type PlaybackQuery,
} from '@yxz/shared';
import {
  PoTokenProvider,
  resolveWithStrategies,
  selectWithDiagnostics,
  applyQualityContract,
  isCompleteForPlayback,
} from '@yxz/extractor';
import type { Env } from '../../config/env.js';
import type { Redis } from 'ioredis';
import { PlaybackCache, PoTokenCache } from '../../infrastructure/redis/client.js';
import { VideoModel, DownloadJobModel } from '../../infrastructure/mongo/models.js';
import { profileHash } from '../auth/service.js';
import { metrics } from '../../observability/metrics.js';
import { v4 as uuidv4 } from 'uuid';
import type { Logger } from '../../observability/logger.js';
import { NewPipeClient } from './newpipe-client.js';

/** Bump when strategy order / adapters change so incomplete caches do not stick. */
const EXTRACT_PROFILE = 'multi-v1';

export class PlaybackService {
  private readonly cache: PlaybackCache;
  private readonly poCache: PoTokenCache;
  private readonly po: PoTokenProvider;
  private readonly newpipe: NewPipeClient;
  private readonly extractQueue: Queue<ExtractJobPayload, PlaybackManifest>;
  private readonly extractEvents: QueueEvents;
  private readonly downloadQueue: Queue;

  constructor(
    private readonly env: Env,
    redis: Redis,
    private readonly log: Logger,
  ) {
    this.cache = new PlaybackCache(redis, env.PLAYBACK_CACHE_MAX_TTL_SEC);
    this.poCache = new PoTokenCache(redis);
    this.po = new PoTokenProvider(
      (videoId, ctx) => this.poCache.get(videoId, ctx),
      (videoId, ctx, token, ttl) => this.poCache.set(videoId, ctx, token, ttl),
      (videoId, ctx) => this.poCache.del(videoId, ctx),
    );
    this.newpipe = new NewPipeClient(
      env.NEWPIPE_URL,
      env.PLAYBACK_TIMEOUT_MS,
    );
    this.extractQueue = new Queue(QUEUE_EXTRACT, {
      connection: redis.duplicate(),
    });
    this.extractEvents = new QueueEvents(QUEUE_EXTRACT, {
      connection: redis.duplicate(),
    });
    this.downloadQueue = new Queue(QUEUE_DOWNLOAD, {
      connection: redis.duplicate(),
    });
  }

  async resolve(
    videoId: string,
    query: PlaybackQuery,
    opts: { useWorker?: boolean } = {},
  ): Promise<PlaybackManifest> {
    const hash = profileHash({
      quality: query.quality,
      codec: query.codec,
      audioLanguage: query.audioLanguage,
      hdr: query.hdr,
      extract: EXTRACT_PROFILE,
    });

    if (!query.forceRefresh) {
      const cached = await this.cache.get(videoId, hash);
      if (cached) {
        metrics.inc('yxz_playback_cache_hit');
        return JSON.parse(cached) as PlaybackManifest;
      }
    } else {
      await this.cache.del(videoId, hash);
    }

    metrics.inc('yxz_playback_cache_miss');

    return this.cache.withSingleFlight(
      videoId,
      hash,
      Math.ceil(this.env.PLAYBACK_TIMEOUT_MS / 1000) + 5,
      async () => {
        const manifest = opts.useWorker
          ? await this.resolveViaWorker(videoId, query, hash)
          : await this.resolveInline(videoId, query);
        await this.cache.set(
          videoId,
          hash,
          JSON.stringify(manifest),
          manifest.expiresAt,
        );
        await VideoModel.findByIdAndUpdate(
          videoId,
          {
            _id: videoId,
            title: manifest.title,
            uploader: manifest.uploader,
            thumbnail: manifest.thumbnail,
            durationMs: manifest.durationMs,
            webpageUrl: manifest.webpageUrl,
            lastResolvedAt: new Date(),
          },
          { upsert: true },
        );
        metrics.inc('yxz_playback_resolve_ok');
        return manifest;
      },
      async () => {
        const cached = await this.cache.get(videoId, hash);
        return cached ? (JSON.parse(cached) as PlaybackManifest) : null;
      },
    );
  }

  /** Env-gated debug resolve with candidate listing. */
  async resolveDebug(videoId: string, query: PlaybackQuery) {
    const base = await this.resolve(videoId, {
      ...query,
      forceRefresh: true,
    });
    const { diagnostics } = selectWithDiagnostics(
      base,
      query.quality,
      query.codec,
      query.hdr,
    );
    return {
      manifest: base,
      diagnostics,
    };
  }

  /**
   * Facade: yt-dlp representation ladder → NewPipe if incomplete.
   */
  private async resolveInline(
    videoId: string,
    query: PlaybackQuery,
  ): Promise<PlaybackManifest> {
    this.log.info({ videoId, quality: query.quality }, 'inline extract');
    try {
      const manifest = await resolveWithStrategies({
        videoId,
        quality: query.quality,
        codec: query.codec,
        audioLanguage: query.audioLanguage,
        hdr: query.hdr,
        ytdlpBin: this.env.YTDLP_BIN,
        timeoutMs: this.env.PLAYBACK_TIMEOUT_MS,
        po: this.po,
      });
      return this.tagAdapter(manifest, 'ytdlp');
    } catch (e) {
      const incomplete =
        e instanceof AppError &&
        Boolean(
          e.details &&
            typeof e.details === 'object' &&
            (e.details as { incomplete?: boolean }).incomplete,
        );

      if (
        e instanceof AppError &&
        (incomplete || e.code === ErrorCodes.EXTRACTOR_NO_STREAM) &&
        this.newpipe.enabled
      ) {
        this.log.info(
          { videoId, reason: incomplete ? 'incomplete' : e.code },
          'yt-dlp incomplete; trying NewPipe',
        );
        try {
          const np = await this.newpipe.extract(videoId);
          if (np) {
            const gate = isCompleteForPlayback(np, query.quality);
            if (gate.ok) {
              const ranked = applyQualityContract(
                np,
                query.quality,
                query.codec,
                query.hdr,
              );
              return this.tagAdapter(ranked, 'newpipe');
            }
            this.log.warn(
              { videoId, reason: gate.reason },
              'NewPipe also incomplete',
            );
          }
        } catch (npErr) {
          this.log.warn(
            { videoId, err: String(npErr) },
            'NewPipe fallback failed',
          );
        }
      }
      throw e;
    }
  }

  private tagAdapter(
    manifest: PlaybackManifest,
    adapter: string,
  ): PlaybackManifest {
    return {
      ...manifest,
      // Keep schema valid; adapter is observational via headers.
      headers: {
        ...manifest.headers,
        'x-yxz-adapter': adapter,
        'x-yxz-extract-profile': EXTRACT_PROFILE,
      },
    };
  }

  private async resolveViaWorker(
    videoId: string,
    query: PlaybackQuery,
    profileHashValue: string,
  ): Promise<PlaybackManifest> {
    const job = await this.extractQueue.add(
      'resolve',
      {
        videoId,
        quality: query.quality,
        codec: query.codec,
        audioLanguage: query.audioLanguage,
        hdr: query.hdr,
        forceRefresh: query.forceRefresh,
        profileHash: profileHashValue,
      },
      { removeOnComplete: 100, removeOnFail: 100 },
    );
    try {
      const result = await job.waitUntilFinished(
        this.extractEvents,
        this.env.PLAYBACK_TIMEOUT_MS + 5_000,
      );
      return this.tagAdapter(result, 'ytdlp');
    } catch (e) {
      if (this.newpipe.enabled) {
        try {
          const np = await this.newpipe.extract(videoId);
          if (np) {
            const gate = isCompleteForPlayback(np, query.quality);
            if (gate.ok) {
              return this.tagAdapter(
                applyQualityContract(
                  np,
                  query.quality,
                  query.codec,
                  query.hdr,
                ),
                'newpipe',
              );
            }
          }
        } catch {
          /* fall through */
        }
      }
      throw new AppError(
        ErrorCodes.EXTRACTOR_TIMEOUT,
        `Extractor worker failed: ${String(e)}`,
        { statusCode: 504, retryable: true },
      );
    }
  }

  async metadata(videoId: string) {
    const doc = await VideoModel.findById(videoId);
    if (doc) {
      return {
        videoId: doc._id,
        title: doc.title,
        uploader: doc.uploader,
        thumbnail: doc.thumbnail,
        durationMs: doc.durationMs,
        webpageUrl: doc.webpageUrl,
      };
    }
    const manifest = await this.resolve(videoId, {
      quality: 'auto',
      codec: 'auto',
      audioLanguage: 'auto',
      hdr: 'auto',
      forceRefresh: false,
    });
    return {
      videoId: manifest.videoId,
      title: manifest.title,
      uploader: manifest.uploader,
      thumbnail: manifest.thumbnail,
      durationMs: manifest.durationMs,
      webpageUrl: manifest.webpageUrl,
    };
  }

  async enqueueDownload(input: {
    installationId: string;
    videoId: string;
    quality: string;
    format: string;
  }) {
    const jobId = uuidv4();
    await DownloadJobModel.create({
      _id: jobId,
      installationId: input.installationId,
      videoId: input.videoId,
      quality: input.quality,
      format: input.format,
      status: 'queued',
      progress: 0,
    });
    await this.downloadQueue.add(
      'download',
      {
        jobId,
        videoId: input.videoId,
        quality: input.quality,
        format: input.format,
        installationId: input.installationId,
      },
      { jobId, removeOnComplete: 50, removeOnFail: 50 },
    );
    metrics.inc('yxz_download_enqueued');
    return { jobId, status: 'queued' as const };
  }

  async downloadStatus(jobId: string, installationId: string) {
    const doc = await DownloadJobModel.findById(jobId);
    if (!doc || doc.installationId !== installationId) {
      throw new AppError(ErrorCodes.VALIDATION_ERROR, 'Download job not found', {
        statusCode: 404,
      });
    }
    const fileUrl =
      doc.status === 'completed' && doc.fileName
        ? `${this.env.PUBLIC_BASE_URL}/api/v1/downloads/${jobId}/file`
        : undefined;
    return {
      jobId: doc._id,
      videoId: doc.videoId,
      status: doc.status,
      progress: doc.progress,
      errorCode: doc.errorCode,
      errorMessage: doc.errorMessage,
      fileName: doc.fileName,
      fileSize: doc.fileSize,
      fileUrl,
    };
  }
}
