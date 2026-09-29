import { AppError, ErrorCodes, type PlaybackManifest } from '@yxz/shared';
import { normalizeYtDlpJson } from '../normalize/manifest.js';
import { applyQualityContract } from '../normalize/rank.js';
import { mapYtDlpFailure, runYtDlp } from '../ytdlp/runner.js';
import type { PoTokenProvider } from '../tokens/pot-provider.js';

export interface ResolveOptions {
  videoId: string;
  quality: string;
  codec: string;
  audioLanguage: string;
  hdr: string;
  ytdlpBin: string;
  timeoutMs: number;
  po?: PoTokenProvider;
}

interface Strategy {
  name: string;
  buildArgs: (videoId: string, poToken?: string | null) => string[];
  client: string;
  needsPo?: boolean;
}

const STRATEGIES: Strategy[] = [
  {
    name: 'default',
    client: 'default',
    buildArgs: (videoId) => [
      '-J',
      '--no-warnings',
      '--no-playlist',
      `https://www.youtube.com/watch?v=${videoId}`,
    ],
  },
  {
    name: 'mweb-pot',
    client: 'mweb',
    needsPo: true,
    buildArgs: (videoId, poToken) => {
      const args = [
        '-J',
        '--no-warnings',
        '--no-playlist',
        '--extractor-args',
        `youtube:player_client=mweb`,
        `https://www.youtube.com/watch?v=${videoId}`,
      ];
      if (poToken) {
        args.splice(
          args.length - 1,
          0,
          '--extractor-args',
          `youtube:player_client=mweb;po_token=mweb.gvs+${poToken}`,
        );
      }
      return args;
    },
  },
  {
    name: 'web-safari',
    client: 'web_safari',
    buildArgs: (videoId) => [
      '-J',
      '--no-warnings',
      '--no-playlist',
      '--extractor-args',
      'youtube:player_client=web_safari',
      `https://www.youtube.com/watch?v=${videoId}`,
    ],
  },
];

function heightAvailable(m: PlaybackManifest, min: number): boolean {
  return m.videoStreams.some((v) => v.height >= min);
}

export async function resolveWithStrategies(
  options: ResolveOptions,
): Promise<PlaybackManifest> {
  let lastError: AppError | undefined;
  for (const strategy of STRATEGIES) {
    let poToken: string | null = null;
    if (strategy.needsPo && options.po) {
      poToken = await options.po.get(options.videoId, strategy.client);
    }
    try {
      const manifest = await runOnce(options, strategy, poToken);
      if (
        options.quality === '1080p' ||
        options.quality === 'auto' ||
        options.quality === '1440p' ||
        options.quality === '2160p'
      ) {
        if (!heightAvailable(manifest, 720) && strategy.name === 'default') {
          // try next strategy for HD
          lastError = new AppError(
            ErrorCodes.QUALITY_UNAVAILABLE,
            'Default client lacked HD',
            { statusCode: 502, retryable: true },
          );
          continue;
        }
      }
      return applyQualityContract(
        manifest,
        options.quality,
        options.codec,
        options.hdr,
      );
    } catch (e) {
      const err =
        e instanceof AppError
          ? e
          : new AppError(ErrorCodes.EXTRACTOR_NO_STREAM, String(e), {
              statusCode: 502,
              retryable: true,
            });
      lastError = err;
      if (
        err.code === ErrorCodes.EXTRACTOR_PO_TOKEN_REQUIRED &&
        options.po &&
        strategy.needsPo
      ) {
        await options.po.invalidate(options.videoId, strategy.client);
        const refreshed = await options.po.get(options.videoId, strategy.client);
        if (refreshed && refreshed !== poToken) {
          try {
            const retry = await runOnce(options, strategy, refreshed);
            return applyQualityContract(
              retry,
              options.quality,
              options.codec,
              options.hdr,
            );
          } catch (e2) {
            lastError =
              e2 instanceof AppError
                ? e2
                : err;
          }
        }
      }
      if (
        err.code === ErrorCodes.EXTRACTOR_PRIVATE ||
        err.code === ErrorCodes.EXTRACTOR_GEO_BLOCKED ||
        err.code === ErrorCodes.EXTRACTOR_VIDEO_UNAVAILABLE
      ) {
        throw err;
      }
    }
  }
  throw (
    lastError ??
    new AppError(ErrorCodes.EXTRACTOR_NO_STREAM, 'No playable streams', {
      statusCode: 502,
    })
  );
}

async function runOnce(
  options: ResolveOptions,
  strategy: Strategy,
  poToken: string | null,
): Promise<PlaybackManifest> {
  const args = strategy.buildArgs(options.videoId, poToken);
  const result = await runYtDlp({
    bin: options.ytdlpBin,
    args,
    timeoutMs: options.timeoutMs,
  });
  if (result.code !== 0) {
    throw mapYtDlpFailure(result.stderr, result.code);
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(result.stdout);
  } catch {
    throw new AppError(
      ErrorCodes.EXTRACTOR_UPSTREAM_CHANGED,
      'Failed to parse yt-dlp JSON',
      { statusCode: 502, retryable: true },
    );
  }
  const manifest = normalizeYtDlpJson(parsed);
  if (
    manifest.videoStreams.length === 0 &&
    !manifest.delivery.manifestUrl
  ) {
    throw new AppError(ErrorCodes.EXTRACTOR_NO_STREAM, 'No streams in dump', {
      statusCode: 502,
      retryable: true,
    });
  }
  return manifest;
}
