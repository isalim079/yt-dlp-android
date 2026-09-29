import { AppError, ErrorCodes, type PlaybackManifest } from '@yxz/shared';
import { normalizeYtDlpJson } from '../normalize/manifest.js';
import { applyQualityContract } from '../normalize/rank.js';
import {
  isCompleteForPlayback,
  logCompleteness,
} from '../normalize/completeness.js';
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
  buildArgs: (
    videoId: string,
    poToken?: string | null,
    playerToken?: string | null,
  ) => string[];
  client: string;
  needsPo?: boolean;
}

/** Representation-driven order — not “favorite client”. */
const STRATEGIES: Strategy[] = [
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
    buildArgs: (videoId, gvsToken, playerToken) => {
      const parts = ['player_client=mweb'];
      if (gvsToken || playerToken) {
        const tokens: string[] = [];
        if (playerToken) tokens.push(`mweb.player+${playerToken}`);
        if (gvsToken) tokens.push(`mweb.gvs+${gvsToken}`);
        parts.push(`po_token=${tokens.join(',')}`);
      }
      return [
        '-J',
        '--no-warnings',
        '--no-playlist',
        '--extractor-args',
        `youtube:${parts.join(';')}`,
        `https://www.youtube.com/watch?v=${videoId}`,
      ];
    },
  },
  {
    name: 'android',
    client: 'android',
    buildArgs: (videoId) => [
      '-J',
      '--no-warnings',
      '--no-playlist',
      '--extractor-args',
      'youtube:player_client=android',
      `https://www.youtube.com/watch?v=${videoId}`,
    ],
  },
];

export async function resolveWithStrategies(
  options: ResolveOptions,
): Promise<PlaybackManifest> {
  let lastError: AppError | undefined;
  let bestIncomplete: PlaybackManifest | undefined;

  for (const strategy of STRATEGIES) {
    let gvsToken: string | null = null;
    let playerToken: string | null = null;

    if (strategy.needsPo) {
      if (!options.po) {
        // eslint-disable-next-line no-console
        console.info(
          JSON.stringify({
            msg: 'skip_profile',
            profile: strategy.name,
            reason: 'po_provider_missing',
          }),
        );
        continue;
      }
      // Mint BEFORE extract for this profile only.
      const bundle = await options.po.getBundle(options.videoId, strategy.client);
      if (!bundle?.gvs) {
        // eslint-disable-next-line no-console
        console.info(
          JSON.stringify({
            msg: 'skip_profile',
            profile: strategy.name,
            reason: 'po_token_unavailable',
          }),
        );
        continue;
      }
      gvsToken = bundle.gvs;
      playerToken = bundle.player ?? null;
    }

    try {
      const raw = await runOnce(options, strategy, gvsToken, playerToken);
      const gate = isCompleteForPlayback(raw, options.quality);
      logCompleteness(options.videoId, strategy.name, gate, raw);

      if (!gate.ok) {
        lastError = new AppError(
          ErrorCodes.EXTRACTOR_NO_STREAM,
          `Profile ${strategy.name} incomplete: ${gate.reason}`,
          { statusCode: 502, retryable: true },
        );
        if (
          !bestIncomplete ||
          gate.maxVideoHeight >
            Math.max(0, ...bestIncomplete.videoStreams.map((v) => v.height))
        ) {
          bestIncomplete = raw;
        }
        continue;
      }

      return applyQualityContract(
        raw,
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
        const refreshed = await options.po.getBundle(
          options.videoId,
          strategy.client,
        );
        if (refreshed?.gvs && refreshed.gvs !== gvsToken) {
          try {
            const retry = await runOnce(
              options,
              strategy,
              refreshed.gvs,
              refreshed.player ?? null,
            );
            const gate = isCompleteForPlayback(retry, options.quality);
            logCompleteness(options.videoId, `${strategy.name}-retry`, gate, retry);
            if (gate.ok) {
              return applyQualityContract(
                retry,
                options.quality,
                options.codec,
                options.hdr,
              );
            }
          } catch (e2) {
            lastError = e2 instanceof AppError ? e2 : err;
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

  // Soft: return best incomplete ranked so API can try NewPipe next.
  if (bestIncomplete) {
    const tagged = applyQualityContract(
      bestIncomplete,
      options.quality,
      options.codec,
      options.hdr,
    );
    throw new AppError(
      ErrorCodes.EXTRACTOR_NO_STREAM,
      'yt-dlp ladder incomplete',
      {
        statusCode: 502,
        retryable: true,
        details: {
          incomplete: true,
          partial: tagged,
        },
      },
    );
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
  gvsToken: string | null,
  playerToken: string | null,
): Promise<PlaybackManifest> {
  const args = strategy.buildArgs(options.videoId, gvsToken, playerToken);
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
  if (manifest.videoStreams.length === 0 && !manifest.delivery.manifestUrl) {
    throw new AppError(ErrorCodes.EXTRACTOR_NO_STREAM, 'No streams in dump', {
      statusCode: 502,
      retryable: true,
    });
  }
  return manifest;
}

export { isCompleteForPlayback } from '../normalize/completeness.js';
