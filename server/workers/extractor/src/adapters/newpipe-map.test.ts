import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { PlaybackManifestSchema } from '@yxz/shared';
import { isCompleteForPlayback } from '../normalize/completeness.js';
import { applyQualityContract } from '../normalize/rank.js';

/**
 * Sample payload shaped like the NewPipe JVM ManifestMapper output.
 */
describe('NewPipe → PlaybackManifest mapping', () => {
  it('maps height + audio into a complete 1080 manifest', () => {
    const sample = {
      schemaVersion: 1 as const,
      videoId: 'npSample',
      title: 'NewPipe sample',
      source: 'youtube',
      durationMs: 120000,
      resolvedAt: new Date().toISOString(),
      expiresAt: new Date(Date.now() + 300_000).toISOString(),
      delivery: { type: 'adaptive' as const },
      videoStreams: [
        {
          id: 'np-v-1080-1',
          url: 'https://rr.googlevideo.com/videoplayback?itag=137',
          height: 1080,
          width: 1920,
          codec: 'avc1',
          mimeType: 'video/mp4',
          ext: 'mp4',
          isVideoOnly: true,
          hdr: false,
        },
      ],
      audioStreams: [
        {
          id: 'np-a-128-2',
          url: 'https://rr.googlevideo.com/videoplayback?itag=140',
          bitrate: 128000,
          codec: 'mp4a',
          mimeType: 'audio/mp4',
          ext: 'm4a',
        },
      ],
      subtitles: [],
      headers: {},
      uploader: 'Channel',
      webpageUrl: 'https://www.youtube.com/watch?v=npSample',
    };

    const parsed = PlaybackManifestSchema.parse(sample);
    assert.equal(isCompleteForPlayback(parsed, '1080p').ok, true);
    const ranked = applyQualityContract(parsed, '1080p', 'auto', 'auto');
    assert.equal(ranked.quality?.selectedQuality, '1080p');
    assert.equal(ranked.quality?.qualityFallback, false);
    assert.ok(ranked.audioStreams.length > 0);
  });
});
