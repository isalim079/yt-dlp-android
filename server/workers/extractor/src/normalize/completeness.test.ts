import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import type { PlaybackManifest } from '@yxz/shared';
import { isCompleteForPlayback } from './completeness.js';

function base(partial: Partial<PlaybackManifest> = {}): PlaybackManifest {
  return {
    schemaVersion: 1,
    videoId: 'dQw4w9WgXcQ',
    title: 'test',
    source: 'youtube',
    resolvedAt: new Date().toISOString(),
    delivery: { type: 'adaptive' },
    videoStreams: [],
    audioStreams: [],
    subtitles: [],
    headers: {},
    ...partial,
  };
}

describe('isCompleteForPlayback', () => {
  it('rejects SABR-like video-only dumps', () => {
    const m = base({
      videoStreams: [
        {
          id: 'v1',
          url: 'https://googlevideo.com/v1',
          height: 1080,
          isVideoOnly: true,
          hdr: false,
        },
      ],
      audioStreams: [],
    });
    const r = isCompleteForPlayback(m, '1080p');
    assert.equal(r.ok, false);
    assert.equal(r.sabrLike, true);
    assert.match(r.reason, /sabr|video_only/);
  });

  it('accepts direct video + audio', () => {
    const m = base({
      videoStreams: [
        {
          id: 'v1',
          url: 'https://googlevideo.com/v1',
          height: 1080,
          isVideoOnly: true,
          hdr: false,
        },
      ],
      audioStreams: [
        {
          id: 'a1',
          url: 'https://googlevideo.com/a1',
        },
      ],
    });
    const r = isCompleteForPlayback(m, '1080p');
    assert.equal(r.ok, true);
    assert.equal(r.reason, 'direct_video_plus_audio');
  });

  it('accepts HLS without PO / without discrete audio rows', () => {
    const m = base({
      delivery: {
        type: 'hls',
        manifestUrl: 'https://manifest.googlevideo.com/api/manifest/hls_variant/x.m3u8',
      },
      videoStreams: [],
      audioStreams: [],
    });
    const r = isCompleteForPlayback(m, '1080p');
    assert.equal(r.ok, true);
    assert.equal(r.reason, 'hls_or_dash_manifest');
  });

  it('accepts progressive muxed', () => {
    const m = base({
      delivery: { type: 'progressive' },
      videoStreams: [
        {
          id: 'p1',
          url: 'https://googlevideo.com/p1',
          height: 720,
          isVideoOnly: false,
          hdr: false,
        },
      ],
    });
    const r = isCompleteForPlayback(m, '720p');
    assert.equal(r.ok, true);
    assert.equal(r.reason, 'progressive_muxed');
  });

  it('rejects empty dumps', () => {
    const r = isCompleteForPlayback(base(), 'auto');
    assert.equal(r.ok, false);
  });
});
