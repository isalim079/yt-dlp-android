import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const pipelineSrc = readFileSync(
  join(__dirname, '../strategies/pipeline.ts'),
  'utf8',
);

describe('yt-dlp strategy ladder order', () => {
  it('starts with web_safari then default then mweb then android', () => {
    const names = [...pipelineSrc.matchAll(/name:\s*'([^']+)'/g)].map(
      (m) => m[1],
    );
    assert.deepEqual(names.slice(0, 4), [
      'web-safari',
      'default',
      'mweb-pot',
      'android',
    ]);
  });

  it('mints PO only on mweb profile (needsPo)', () => {
    const blocks = [...pipelineSrc.matchAll(/\{\s*name:\s*'([^']+)'([\s\S]*?)\},/g)];
    const byName = Object.fromEntries(blocks.map((m) => [m[1], m[2]]));
    assert.match(byName['mweb-pot'] ?? '', /needsPo:\s*true/);
    assert.doesNotMatch(byName['web-safari'] ?? '', /needsPo:\s*true/);
    assert.doesNotMatch(byName['default'] ?? '', /needsPo:\s*true/);
    assert.doesNotMatch(byName['android'] ?? '', /needsPo:\s*true/);
  });

  it('never splices pot= onto finished URLs', () => {
    assert.doesNotMatch(pipelineSrc, /pot=/);
    assert.match(pipelineSrc, /po_token=/);
  });
});
