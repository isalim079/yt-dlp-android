import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import type { PlaybackManifest } from '@yxz/shared';
import {
  applyQualityContract,
  selectWithDiagnostics,
} from './rank.js';

function baseManifest(
  videos: PlaybackManifest['videoStreams'],
  audios: PlaybackManifest['audioStreams'] = [
    {
      id: '140',
      url: 'https://example.com/a.m4a',
      codec: 'mp4a.40.2',
      bitrate: 128000,
    },
  ],
): PlaybackManifest {
  return {
    schemaVersion: 1,
    videoId: 'dQw4w9WgXcQ',
    title: 'Demo',
    source: 'youtube',
    resolvedAt: new Date().toISOString(),
    delivery: { type: 'direct' },
    videoStreams: videos,
    audioStreams: audios,
    subtitles: [],
    headers: {},
  };
}

describe('applyQualityContract 1080p', () => {
  it('selects 1080 adaptive when present', () => {
    const m = applyQualityContract(
      baseManifest([
        {
          id: '18',
          url: 'https://example.com/360.mp4',
          height: 360,
          isVideoOnly: false,
          codec: 'avc1',
          hdr: false,
        },
        {
          id: '137',
          url: 'https://example.com/1080.mp4',
          height: 1080,
          width: 1920,
          isVideoOnly: true,
          codec: 'avc1.640028',
          bitrate: 4000000,
          hdr: false,
        },
        {
          id: '136',
          url: 'https://example.com/720.mp4',
          height: 720,
          isVideoOnly: true,
          codec: 'avc1',
          hdr: false,
        },
      ]),
      '1080p',
      'auto',
      'auto',
    );
    assert.equal(m.quality?.selectedQuality, '1080p');
    assert.equal(m.quality?.qualityFallback, false);
    assert.equal(m.videoStreams[0]?.height, 1080);
    assert.equal(m.delivery.type, 'direct');
  });

  it('honest fallback when 2160 missing', () => {
    const m = applyQualityContract(
      baseManifest([
        {
          id: '271',
          url: 'https://example.com/1440.webm',
          height: 1440,
          width: 2560,
          isVideoOnly: true,
          codec: 'vp9',
          hdr: false,
        },
      ]),
      '2160p',
      'auto',
      'auto',
    );
    assert.equal(m.quality?.selectedQuality, '1440p');
    assert.equal(m.quality?.qualityFallback, true);
    assert.equal(m.quality?.fallbackReason, 'NO_COMPATIBLE_2160P_STREAM');
  });

  it('auto picks highest including 2160', () => {
    const m = applyQualityContract(
      baseManifest([
        {
          id: '137',
          url: 'https://example.com/1080.mp4',
          height: 1080,
          isVideoOnly: true,
          codec: 'avc1',
          hdr: false,
        },
        {
          id: '313',
          url: 'https://example.com/2160.webm',
          height: 2160,
          width: 3840,
          isVideoOnly: true,
          codec: 'vp9',
          hdr: false,
        },
      ]),
      'auto',
      'auto',
      'auto',
    );
    assert.equal(m.quality?.selectedQuality, '2160p');
    assert.equal(m.videoStreams[0]?.height, 2160);
  });

  it('diagnostics expose candidates', () => {
    const { diagnostics } = selectWithDiagnostics(
      baseManifest([
        {
          id: '137',
          url: 'https://example.com/1080.mp4',
          height: 1080,
          isVideoOnly: true,
          codec: 'avc1',
          hdr: false,
        },
      ]),
      '1080p',
      'auto',
      'auto',
    );
    assert.equal(diagnostics.candidates.length, 1);
    assert.ok(diagnostics.rationale.includes('selected=1080p'));
  });
});
