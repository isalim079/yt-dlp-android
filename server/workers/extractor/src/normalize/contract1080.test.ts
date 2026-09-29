import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import type { PlaybackManifest } from '@yxz/shared';
import { applyQualityContract } from '../normalize/rank.js';
import { isCompleteForPlayback } from '../normalize/completeness.js';

describe('1080p quality contract fixture', () => {
  it('selects 1080p with audio and qualityFallback=false', () => {
    const fixture: PlaybackManifest = {
      schemaVersion: 1,
      videoId: 'fixture1080',
      title: '1080 fixture',
      source: 'youtube',
      resolvedAt: new Date().toISOString(),
      delivery: { type: 'adaptive' },
      videoStreams: [
        {
          id: '137',
          url: 'https://googlevideo.com/137',
          height: 1080,
          codec: 'avc1',
          isVideoOnly: true,
          hdr: false,
        },
        {
          id: '136',
          url: 'https://googlevideo.com/136',
          height: 720,
          codec: 'avc1',
          isVideoOnly: true,
          hdr: false,
        },
      ],
      audioStreams: [
        {
          id: '140',
          url: 'https://googlevideo.com/140',
          bitrate: 128000,
          codec: 'mp4a',
        },
      ],
      subtitles: [],
      headers: {},
    };

    assert.equal(isCompleteForPlayback(fixture, '1080p').ok, true);
    const ranked = applyQualityContract(fixture, '1080p', 'auto', 'auto');
    assert.equal(ranked.quality?.selectedQuality, '1080p');
    assert.equal(ranked.quality?.qualityFallback, false);
    assert.ok(ranked.audioStreams.length > 0);
    assert.ok(
      ranked.videoStreams.some((v) => v.height >= 1080),
    );
  });
});
