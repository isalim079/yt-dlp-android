import type { AudioStream, PlaybackManifest, VideoStream } from '@yxz/shared';

const DEFAULT_HEADERS: Record<string, string> = {
  'User-Agent':
    'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
  Referer: 'https://www.youtube.com/',
  Origin: 'https://www.youtube.com',
};

function readInt(v: unknown): number | undefined {
  if (typeof v === 'number') return Math.round(v);
  const n = Number.parseInt(String(v ?? ''), 10);
  return Number.isFinite(n) ? n : undefined;
}

function readFloat(v: unknown): number | undefined {
  if (typeof v === 'number') return v;
  const n = Number.parseFloat(String(v ?? ''));
  return Number.isFinite(n) ? n : undefined;
}

function expireOf(url: string): string | undefined {
  const m = /[?&]expire=(\d+)/.exec(url);
  if (!m) return undefined;
  const epoch = Number.parseInt(m[1]!, 10);
  if (!Number.isFinite(epoch)) return undefined;
  return new Date(epoch * 1000).toISOString();
}

function earlier(a?: string, b?: string): string | undefined {
  if (!a) return b;
  if (!b) return a;
  return Date.parse(a) < Date.parse(b) ? a : b;
}

function isStoryboard(row: Record<string, unknown>): boolean {
  const note = String(row.format_note ?? '').toLowerCase();
  const id = String(row.format_id ?? '').toLowerCase();
  return note.includes('storyboard') || id.includes('sb');
}

function isHdr(row: Record<string, unknown>): boolean {
  const note = String(row.format_note ?? '').toLowerCase();
  const dyn = String(row.dynamic_range ?? '').toLowerCase();
  return note.includes('hdr') || dyn.includes('hdr');
}

export function normalizeYtDlpJson(raw: unknown): PlaybackManifest {
  if (!raw || typeof raw !== 'object') {
    throw new Error('Invalid yt-dlp JSON');
  }
  const root = raw as Record<string, unknown>;
  const videoId = String(root.id ?? '');
  const title = String(root.title ?? videoId);
  const formats = Array.isArray(root.formats) ? root.formats : [];
  const videoStreams: VideoStream[] = [];
  const audioStreams: AudioStream[] = [];
  let hlsUrl: string | undefined;
  let expiresAt: string | undefined;

  const httpHeaders: Record<string, string> = { ...DEFAULT_HEADERS };
  if (root.http_headers && typeof root.http_headers === 'object') {
    for (const [k, v] of Object.entries(root.http_headers as Record<string, unknown>)) {
      if (v != null) httpHeaders[k] = String(v);
    }
  }

  for (const item of formats) {
    if (!item || typeof item !== 'object') continue;
    const row = item as Record<string, unknown>;
    if (isStoryboard(row)) continue;
    const url = String(row.url ?? '');
    if (!url) continue;
    const protocol = String(row.protocol ?? '').toLowerCase();
    const ext = String(row.ext ?? '').toLowerCase();
    if (protocol.includes('m3u8') || ext === 'm3u8') {
      hlsUrl ??= url;
      expiresAt = earlier(expiresAt, expireOf(url));
      continue;
    }
    if (!url.startsWith('http')) continue;

    const vcodec = String(row.vcodec ?? '').toLowerCase();
    const acodec = String(row.acodec ?? '').toLowerCase();
    const hasV = vcodec.length > 0 && vcodec !== 'none';
    const hasA = acodec.length > 0 && acodec !== 'none';
    const id = String(row.format_id ?? '');
    if (!id) continue;
    expiresAt = earlier(expiresAt, expireOf(url));

    if (hasV && !hasA) {
      const height = readInt(row.height) ?? 0;
      if (height <= 0) continue;
      const tbr = readFloat(row.tbr);
      videoStreams.push({
        id,
        url,
        height,
        width: readInt(row.width),
        fps: readInt(row.fps),
        bitrate: tbr ? Math.round(tbr * 1000) : undefined,
        codec: String(row.vcodec ?? ''),
        mimeType: ext === 'mp4' ? 'video/mp4' : ext === 'webm' ? 'video/webm' : undefined,
        ext: ext || undefined,
        isVideoOnly: true,
        hdr: isHdr(row),
        expiresAt: expireOf(url),
      });
    } else if (hasV && hasA) {
      const height = readInt(row.height) ?? 0;
      if (height <= 0) continue;
      const tbr = readFloat(row.tbr);
      videoStreams.push({
        id,
        url,
        height,
        width: readInt(row.width),
        fps: readInt(row.fps),
        bitrate: tbr ? Math.round(tbr * 1000) : undefined,
        codec: String(row.vcodec ?? ''),
        mimeType: ext === 'mp4' ? 'video/mp4' : undefined,
        ext: ext || undefined,
        isVideoOnly: false,
        hdr: isHdr(row),
        expiresAt: expireOf(url),
      });
    } else if (!hasV && hasA) {
      const abr = readFloat(row.abr) ?? readFloat(row.tbr);
      audioStreams.push({
        id,
        url,
        bitrate: abr ? Math.round(abr * 1000) : undefined,
        codec: String(row.acodec ?? ''),
        mimeType: ext === 'm4a' || ext === 'mp4' ? 'audio/mp4' : undefined,
        ext: ext || undefined,
        sampleRate: readInt(row.asr),
        channels: readInt(row.audio_channels),
        expiresAt: expireOf(url),
      });
    }
  }

  const isLive = root.is_live === true || root.live_status === 'is_live';
  let deliveryType: PlaybackManifest['delivery']['type'] = 'progressive';
  let manifestUrl: string | undefined;
  if (isLive && hlsUrl) {
    deliveryType = 'hls';
    manifestUrl = hlsUrl;
  } else if (videoStreams.some((v) => v.isVideoOnly) && audioStreams.length > 0) {
    deliveryType = 'direct';
  } else if (videoStreams.some((v) => !v.isVideoOnly)) {
    deliveryType = 'progressive';
  } else if (hlsUrl) {
    deliveryType = 'hls';
    manifestUrl = hlsUrl;
  }

  const durationSec = readInt(root.duration);
  return {
    schemaVersion: 1,
    videoId,
    title,
    source: 'youtube',
    durationMs: durationSec != null ? durationSec * 1000 : undefined,
    resolvedAt: new Date().toISOString(),
    expiresAt,
    delivery: { type: deliveryType, manifestUrl },
    videoStreams,
    audioStreams,
    subtitles: [],
    headers: httpHeaders,
    uploader: root.uploader != null ? String(root.uploader) : undefined,
    thumbnail: root.thumbnail != null ? String(root.thumbnail) : undefined,
    webpageUrl:
      root.webpage_url != null
        ? String(root.webpage_url)
        : `https://www.youtube.com/watch?v=${videoId}`,
  };
}
