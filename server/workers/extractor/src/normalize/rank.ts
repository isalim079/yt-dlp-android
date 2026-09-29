import type { AudioStream, PlaybackManifest, VideoStream } from '@yxz/shared';

const QUALITY_HEIGHT: Record<string, number | null> = {
  auto: null,
  '360p': 360,
  '480p': 480,
  '720p': 720,
  '1080p': 1080,
  '1440p': 1440,
  '2160p': 2160,
};

export interface RankDiagnostics {
  candidates: Array<{
    id: string;
    height: number;
    codec?: string;
    bitrate?: number;
    isVideoOnly: boolean;
    hdr: boolean;
  }>;
  pickedVideoId?: string;
  pickedAudioId?: string;
  rationale: string;
}

function isH264(codec?: string): boolean {
  const c = (codec ?? '').toLowerCase();
  return c.includes('avc') || c.includes('h264');
}

function isVp9(codec?: string): boolean {
  return (codec ?? '').toLowerCase().includes('vp9');
}

function isAv1(codec?: string): boolean {
  return (codec ?? '').toLowerCase().includes('av01');
}

function prefersMp4a(a: AudioStream): boolean {
  const c = (a.codec ?? '').toLowerCase();
  const e = (a.ext ?? '').toLowerCase();
  return c.includes('mp4a') || e === 'm4a' || e === 'mp4';
}

/**
 * Codec preference:
 * - explicit codec request wins
 * - for ≥1440 targets, VP9/AV1 are first-class (typical YouTube 4K)
 * - below that, mild H.264 preference for media_kit friendliness
 */
function codecScore(
  codec: string | undefined,
  prefer: string,
  targetHeight: number | null,
): number {
  const c = (codec ?? '').toLowerCase();
  if (prefer === 'avc1') return isH264(c) ? 4 : 0;
  if (prefer === 'vp9') return isVp9(c) ? 4 : 0;
  if (prefer === 'av01') return isAv1(c) ? 4 : 0;
  if (prefer !== 'auto') return 0;
  const hiRes = targetHeight == null || targetHeight >= 1440;
  if (hiRes) {
    if (isAv1(c) || isVp9(c)) return 3;
    if (isH264(c)) return 2;
    return 1;
  }
  if (isH264(c)) return 3;
  if (isVp9(c)) return 2;
  if (isAv1(c)) return 1;
  return 0;
}

function heightLabel(h: number): string {
  if (h >= 2160) return '2160p';
  if (h >= 1440) return '1440p';
  if (h >= 1080) return '1080p';
  if (h >= 720) return '720p';
  if (h >= 480) return '480p';
  if (h >= 360) return '360p';
  return `${h}p`;
}

function fallbackReason(
  requested: string,
  selectedHeight: number,
): string | undefined {
  const want = QUALITY_HEIGHT[requested];
  if (want == null || selectedHeight <= 0 || selectedHeight >= want) {
    return undefined;
  }
  return `NO_COMPATIBLE_${requested.toUpperCase()}_STREAM`;
}

function filterValid(streams: VideoStream[]): VideoStream[] {
  return streams.filter(
    (v) =>
      v.height > 0 &&
      typeof v.url === 'string' &&
      v.url.startsWith('http') &&
      Boolean(v.id),
  );
}

/**
 * README §14: prefer height >= requested (closest), else closest below.
 * Auto = highest compatible (no hard 1080 cap).
 */
function pickVideo(
  streams: VideoStream[],
  quality: string,
  codec: string,
  hdr: string,
): VideoStream | undefined {
  let pool = filterValid(streams);
  if (pool.length === 0) return undefined;

  if (hdr === 'sdr') pool = pool.filter((v) => !v.hdr);
  if (hdr === 'hdr') {
    const hdrOnly = pool.filter((v) => v.hdr);
    if (hdrOnly.length) pool = hdrOnly;
  }

  const target = QUALITY_HEIGHT[quality] ?? null;

  if (target != null) {
    const atOrAbove = pool.filter((v) => v.height >= target);
    if (atOrAbove.length) {
      // Closest at-or-above target (prefer exact / slightly above)
      atOrAbove.sort((a, b) => {
        const da = a.height - target;
        const db = b.height - target;
        if (da !== db) return da - db;
        return (
          codecScore(b.codec, codec, target) -
          codecScore(a.codec, codec, target)
        );
      });
      // Among closest height band, rank bitrate/fps
      const bestH = atOrAbove[0]!.height;
      const band = atOrAbove.filter((v) => v.height === bestH);
      band.sort((a, b) => {
        const cs =
          codecScore(b.codec, codec, target) -
          codecScore(a.codec, codec, target);
        if (cs) return cs;
        if ((b.fps ?? 0) !== (a.fps ?? 0)) return (b.fps ?? 0) - (a.fps ?? 0);
        return (b.bitrate ?? 0) - (a.bitrate ?? 0);
      });
      return band[0];
    }
    // Fallback ladder: highest below target
    pool = [...pool].sort((a, b) => {
      if (a.height !== b.height) return b.height - a.height;
      return (
        codecScore(b.codec, codec, target) - codecScore(a.codec, codec, target)
      );
    });
    return pool[0];
  }

  // AUTO: highest height, codec-aware (no 1080 cap)
  pool = [...pool].sort((a, b) => {
    if (a.height !== b.height) return b.height - a.height;
    const cs =
      codecScore(b.codec, codec, null) - codecScore(a.codec, codec, null);
    if (cs) return cs;
    if ((b.fps ?? 0) !== (a.fps ?? 0)) return (b.fps ?? 0) - (a.fps ?? 0);
    return (b.bitrate ?? 0) - (a.bitrate ?? 0);
  });
  return pool[0];
}

function pickAudio(streams: AudioStream[]): AudioStream | undefined {
  if (!streams.length) return undefined;
  const sorted = [...streams].sort((a, b) => {
    const p = Number(prefersMp4a(b)) - Number(prefersMp4a(a));
    if (p) return p;
    return (b.bitrate ?? 0) - (a.bitrate ?? 0);
  });
  return sorted[0];
}

export function buildRankDiagnostics(
  manifest: PlaybackManifest,
): RankDiagnostics['candidates'] {
  return manifest.videoStreams.map((v) => ({
    id: v.id,
    height: v.height,
    codec: v.codec,
    bitrate: v.bitrate,
    isVideoOnly: v.isVideoOnly,
    hdr: v.hdr,
  }));
}

/** Apply quality contract without dropping other representations. */
export function applyQualityContract(
  manifest: PlaybackManifest,
  quality: string,
  codec: string,
  hdr: string,
): PlaybackManifest {
  const candidates = buildRankDiagnostics(manifest);
  // eslint-disable-next-line no-console
  console.info(
    JSON.stringify({
      msg: 'quality_candidates',
      videoId: manifest.videoId,
      requested: quality,
      candidates,
    }),
  );

  const adaptive = manifest.videoStreams.filter((v) => v.isVideoOnly);
  const progressive = manifest.videoStreams.filter((v) => !v.isVideoOnly);
  const selectedVideo =
    pickVideo(adaptive, quality, codec, hdr) ??
    pickVideo(progressive, quality, codec, hdr);
  const selectedAudio = pickAudio(manifest.audioStreams);
  const selectedHeight = selectedVideo?.height ?? 0;
  const selectedQuality = selectedHeight ? heightLabel(selectedHeight) : 'none';
  const requested = quality === 'auto' ? 'auto' : quality;
  const want = QUALITY_HEIGHT[quality];
  const qualityFallback =
    quality !== 'auto' &&
    want != null &&
    selectedHeight > 0 &&
    selectedHeight < want;
  const reason = qualityFallback
    ? fallbackReason(quality, selectedHeight)
    : undefined;

  let videoStreams = [...manifest.videoStreams];
  if (selectedVideo) {
    videoStreams = [
      selectedVideo,
      ...videoStreams.filter((v) => v.id !== selectedVideo.id),
    ];
  }
  let audioStreams = [...manifest.audioStreams];
  if (selectedAudio) {
    audioStreams = [
      selectedAudio,
      ...audioStreams.filter((a) => a.id !== selectedAudio.id),
    ];
  }

  // Prefer direct V+A for ≥720; progressive only when no adaptive pair.
  let delivery = manifest.delivery;
  const preferDirect =
    selectedVideo?.isVideoOnly &&
    selectedAudio &&
    selectedHeight >= 720;
  if (preferDirect) {
    delivery = { type: 'direct' };
  } else if (selectedVideo?.isVideoOnly && selectedAudio) {
    delivery = { type: 'direct' };
  } else if (selectedVideo && !selectedVideo.isVideoOnly) {
    delivery = { type: 'progressive' };
  }

  // eslint-disable-next-line no-console
  console.info(
    JSON.stringify({
      msg: 'quality_selected',
      videoId: manifest.videoId,
      requested,
      selectedQuality,
      qualityFallback,
      fallbackReason: reason,
      videoIdPicked: selectedVideo?.id,
      audioIdPicked: selectedAudio?.id,
      height: selectedHeight,
      codec: selectedVideo?.codec,
    }),
  );

  return {
    ...manifest,
    delivery,
    videoStreams,
    audioStreams,
    quality: {
      requestedQuality: requested,
      selectedQuality,
      qualityFallback: Boolean(qualityFallback),
      fallbackReason: reason,
    },
  };
}

/** Exposed for debug endpoint / tests. */
export function selectWithDiagnostics(
  manifest: PlaybackManifest,
  quality: string,
  codec: string,
  hdr: string,
): { manifest: PlaybackManifest; diagnostics: RankDiagnostics } {
  const before = buildRankDiagnostics(manifest);
  const next = applyQualityContract(manifest, quality, codec, hdr);
  const picked = next.videoStreams[0];
  const pickedAudio = next.audioStreams[0];
  return {
    manifest: next,
    diagnostics: {
      candidates: before,
      pickedVideoId: picked?.id,
      pickedAudioId: pickedAudio?.id,
      rationale: [
        `requested=${quality}`,
        `selected=${next.quality?.selectedQuality}`,
        `fallback=${next.quality?.qualityFallback}`,
        next.quality?.fallbackReason
          ? `reason=${next.quality.fallbackReason}`
          : null,
      ]
        .filter(Boolean)
        .join('; '),
    },
  };
}
