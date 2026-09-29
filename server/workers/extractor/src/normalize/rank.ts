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

function isH264(codec?: string): boolean {
  const c = (codec ?? '').toLowerCase();
  return c.includes('avc') || c.includes('h264');
}

function prefersMp4a(a: AudioStream): boolean {
  const c = (a.codec ?? '').toLowerCase();
  const e = (a.ext ?? '').toLowerCase();
  return c.includes('mp4a') || e === 'm4a' || e === 'mp4';
}

function codecScore(codec: string | undefined, prefer: string): number {
  const c = (codec ?? '').toLowerCase();
  if (prefer === 'avc1' && isH264(c)) return 3;
  if (prefer === 'vp9' && c.includes('vp9')) return 3;
  if (prefer === 'av01' && c.includes('av01')) return 3;
  if (prefer === 'auto') return isH264(c) ? 2 : 1;
  return 0;
}

function pickVideo(
  streams: VideoStream[],
  quality: string,
  codec: string,
  hdr: string,
): VideoStream | undefined {
  if (streams.length === 0) return undefined;
  let pool = [...streams];
  if (hdr === 'sdr') pool = pool.filter((v) => !v.hdr);
  if (hdr === 'hdr') {
    const hdrOnly = pool.filter((v) => v.hdr);
    if (hdrOnly.length) pool = hdrOnly;
  }
  const maxH = QUALITY_HEIGHT[quality] ?? null;
  if (maxH != null) {
    const atOrBelow = pool.filter((v) => v.height <= maxH);
    if (atOrBelow.length) {
      pool = atOrBelow;
    } else {
      pool = [...pool].sort((a, b) => a.height - b.height);
      pool = pool.length ? [pool[0]!] : [];
    }
  } else {
    // auto: prefer ≤1080
    const capped = pool.filter((v) => v.height <= 1080);
    if (capped.length) pool = capped;
  }
  pool.sort((a, b) => {
    const cs = codecScore(b.codec, codec) - codecScore(a.codec, codec);
    if (cs) return cs;
    if (a.height !== b.height) return b.height - a.height;
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

function heightLabel(h: number): string {
  if (h >= 2160) return '2160p';
  if (h >= 1440) return '1440p';
  if (h >= 1080) return '1080p';
  if (h >= 720) return '720p';
  if (h >= 480) return '480p';
  if (h >= 360) return '360p';
  return `${h}p`;
}

/** Apply quality contract without dropping other representations. */
export function applyQualityContract(
  manifest: PlaybackManifest,
  quality: string,
  codec: string,
  hdr: string,
): PlaybackManifest {
  const adaptive = manifest.videoStreams.filter((v) => v.isVideoOnly);
  const progressive = manifest.videoStreams.filter((v) => !v.isVideoOnly);
  const selectedVideo =
    pickVideo(adaptive, quality, codec, hdr) ??
    pickVideo(progressive, quality, codec, hdr);
  const selectedAudio = pickAudio(manifest.audioStreams);
  const selectedHeight = selectedVideo?.height ?? 0;
  const selectedQuality = selectedHeight ? heightLabel(selectedHeight) : 'none';
  const requested = quality === 'auto' ? 'auto' : quality;
  const qualityFallback =
    quality !== 'auto' &&
    QUALITY_HEIGHT[quality] != null &&
    selectedHeight > 0 &&
    selectedHeight < (QUALITY_HEIGHT[quality] as number);

  // Reorder so preferred streams come first (client may use as-is or re-select).
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

  let delivery = manifest.delivery;
  if (selectedVideo?.isVideoOnly && selectedAudio) {
    delivery = { type: 'direct' };
  } else if (selectedVideo && !selectedVideo.isVideoOnly) {
    delivery = { type: 'progressive' };
  }

  return {
    ...manifest,
    delivery,
    videoStreams,
    audioStreams,
    quality: {
      requestedQuality: requested,
      selectedQuality,
      qualityFallback: Boolean(qualityFallback),
    },
  };
}
