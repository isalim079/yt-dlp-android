import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { PoTokenProvider } from './pot-provider.js';

describe('PoTokenProvider', () => {
  it('stub only when YXZ_PO_TOKEN_STUB=1', async () => {
    const prev = process.env.YXZ_PO_TOKEN_STUB;
    process.env.YXZ_PO_TOKEN_STUB = '0';
    delete process.env.YXZ_PO_PROVIDER_URL;
    const po = new PoTokenProvider();
    assert.equal(await po.get('vid', 'mweb'), null);

    process.env.YXZ_PO_TOKEN_STUB = '1';
    const stub = await po.getBundle('vid', 'mweb');
    assert.ok(stub?.gvs?.startsWith('stub.gvs.'));
    assert.ok(stub?.player?.startsWith('stub.player.'));

    process.env.YXZ_PO_TOKEN_STUB = prev;
  });

  it('uses Redis remote cache JSON bundles', async () => {
    const store = new Map<string, string>();
    const po = new PoTokenProvider(
      async (id, ctx) => store.get(`${id}:${ctx}`) ?? null,
      async (id, ctx, token) => {
        store.set(`${id}:${ctx}`, token);
      },
      async (id, ctx) => {
        store.delete(`${id}:${ctx}`);
      },
    );
    await po.cacheBundle('v1', 'mweb', { gvs: 'G', player: 'P' }, 60);
    const again = new PoTokenProvider(
      async (id, ctx) => store.get(`${id}:${ctx}`) ?? null,
    );
    const got = await again.getBundle('v1', 'mweb');
    assert.deepEqual(got, { gvs: 'G', player: 'P' });
  });

  it('invalidate clears memory and remote', async () => {
    const store = new Map<string, string>();
    const po = new PoTokenProvider(
      async (id, ctx) => store.get(`${id}:${ctx}`) ?? null,
      async (id, ctx, token) => {
        store.set(`${id}:${ctx}`, token);
      },
      async (id, ctx) => {
        store.delete(`${id}:${ctx}`);
      },
    );
    process.env.YXZ_PO_TOKEN_STUB = '1';
    await po.getBundle('v2', 'mweb');
    await po.invalidate('v2', 'mweb');
    process.env.YXZ_PO_TOKEN_STUB = '0';
    assert.equal(await po.get('v2', 'mweb'), null);
  });
});
