import type { PlaybackManifest } from '@yxz/shared';

const QUALITY_HEIGHT: Record<string, number | null> = {
  auto: null,
  '360p': 360,
  '480p': 480,
  '720p': 720,
  '1080p': 1080,
  '1440p': 1440,
  '2160p': 2160,
};

export interface CompletenessResult {
  ok: boolean;
  reason: string;
  maxVideoHeight: number;
  hasAudio: boolean;
  hasProgressive: boolean;
  hasManifest: boolean;
  sabrLike: boolean;
}

/**
 * Whether a normalized dump is usable for playback (representation-driven).
 *
 * Incomplete / SABR-like: video-only rows with no audio and no HLS/progressive.
 */
export function isCompleteForPlayback(
  manifest: PlaybackManifest,
  requestedQuality = 'auto',
): CompletenessResult {
  const adaptive = manifest.videoStreams.filter((v) => v.isVideoOnly);
  const progressive = manifest.videoStreams.filter((v) => !v.isVideoOnly);
  const hasAudio = manifest.audioStreams.length > 0;
  const hasProgressive = progressive.length > 0;
  const hasManifest = Boolean(manifest.delivery.manifestUrl);
  const maxVideoHeight = Math.max(
    0,
    ...manifest.videoStreams.map((v) => v.height),
  );

  const sabrLike =
    adaptive.length > 0 && !hasAudio && !hasProgressive && !hasManifest;

  if (hasManifest) {
    return {
      ok: true,
      reason: 'hls_or_dash_manifest',
      maxVideoHeight,
      hasAudio,
      hasProgressive,
      hasManifest,
      sabrLike: false,
    };
  }

  if (sabrLike) {
    return {
      ok: false,
      reason: 'sabr_or_video_only_no_audio',
      maxVideoHeight,
      hasAudio,
      hasProgressive,
      hasManifest,
      sabrLike: true,
    };
  }

  if (hasProgressive && maxVideoHeight > 0) {
    return {
      ok: true,
      reason: 'progressive_muxed',
      maxVideoHeight,
      hasAudio,
      hasProgressive,
      hasManifest,
      sabrLike: false,
    };
  }

  if (adaptive.length > 0 && hasAudio) {
    const want = QUALITY_HEIGHT[requestedQuality] ?? null;
    // For HD requests, require at least some useful height (≥480) when asking ≥720.
    if (want != null && want >= 720 && maxVideoHeight < 480) {
      return {
        ok: false,
        reason: `max_height_${maxVideoHeight}_below_usable_for_${requestedQuality}`,
        maxVideoHeight,
        hasAudio,
        hasProgressive,
        hasManifest,
        sabrLike: false,
      };
    }
    return {
      ok: true,
      reason: 'direct_video_plus_audio',
      maxVideoHeight,
      hasAudio,
      hasProgressive,
      hasManifest,
      sabrLike: false,
    };
  }

  if (manifest.videoStreams.length === 0 && !hasManifest) {
    return {
      ok: false,
      reason: 'no_streams',
      maxVideoHeight,
      hasAudio,
      hasProgressive,
      hasManifest,
      sabrLike: false,
    };
  }

  return {
    ok: false,
    reason: 'incomplete_representations',
    maxVideoHeight,
    hasAudio,
    hasProgressive,
    hasManifest,
    sabrLike: false,
  };
}

export function logCompleteness(
  videoId: string,
  profile: string,
  result: CompletenessResult,
  manifest: PlaybackManifest,
): void {
  // eslint-disable-next-line no-console
  console.info(
    JSON.stringify({
      msg: 'extraction_completeness',
      videoId,
      profile,
      ok: result.ok,
      reason: result.reason,
      maxVideoHeight: result.maxVideoHeight,
      hasAudio: result.hasAudio,
      hasProgressive: result.hasProgressive,
      hasManifest: result.hasManifest,
      sabrLike: result.sabrLike,
      heights: [...new Set(manifest.videoStreams.map((v) => v.height))].sort(
        (a, b) => a - b,
      ),
      delivery: manifest.delivery.type,
    }),
  );
}
