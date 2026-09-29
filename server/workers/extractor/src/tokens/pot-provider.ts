import { createHash, randomBytes } from 'node:crypto';

export interface PoTokenBundle {
  gvs: string;
  player?: string;
}

export type PoRemoteGet = (
  videoId: string,
  contextHash: string,
) => Promise<string | null>;

export type PoRemoteSet = (
  videoId: string,
  contextHash: string,
  token: string,
  ttlSec: number,
) => Promise<void>;

export type PoRemoteDel = (
  videoId: string,
  contextHash: string,
) => Promise<void>;

/**
 * Automatic PO provider.
 *
 * Mint happens only for profiles that need it (e.g. mweb), before extract.
 * Never splice pot= onto finished stream URLs — tokens go via extractor-args.
 *
 * Sources (in order): memory → Redis → YXZ_PO_PROVIDER_URL → stub (dev only).
 */
export class PoTokenProvider {
  private readonly memory = new Map<string, { bundle: PoTokenBundle; exp: number }>();

  constructor(
    private readonly getRemote?: PoRemoteGet,
    private readonly setRemote?: PoRemoteSet,
    private readonly delRemote?: PoRemoteDel,
  ) {}

  contextHash(client: string): string {
    return createHash('sha256').update(`po:${client}`).digest('hex').slice(0, 12);
  }

  /** GVS token only (legacy). Prefer [getBundle]. */
  async get(videoId: string, client: string): Promise<string | null> {
    const bundle = await this.getBundle(videoId, client);
    return bundle?.gvs ?? null;
  }

  async getBundle(
    videoId: string,
    client: string,
  ): Promise<PoTokenBundle | null> {
    const ctx = this.contextHash(client);
    const key = `${videoId}:${ctx}`;
    const mem = this.memory.get(key);
    if (mem && mem.exp > Date.now()) return mem.bundle;

    if (this.getRemote) {
      const remote = await this.getRemote(videoId, ctx);
      if (remote) {
        const parsed = parseStored(remote);
        if (parsed) {
          this.memory.set(key, {
            bundle: parsed,
            exp: Date.now() + 240_000,
          });
          return parsed;
        }
      }
    }

    const minted = await this.mintFromProvider(videoId, client);
    if (minted) {
      await this.cacheBundle(videoId, client, minted, 300);
      return minted;
    }

    if (process.env.YXZ_PO_TOKEN_STUB === '1') {
      const stub: PoTokenBundle = {
        gvs: `stub.gvs.${randomBytes(16).toString('hex')}`,
        player: `stub.player.${randomBytes(16).toString('hex')}`,
      };
      await this.cacheBundle(videoId, client, stub, 300);
      return stub;
    }

    return null;
  }

  async invalidate(videoId: string, client: string): Promise<void> {
    const ctx = this.contextHash(client);
    this.memory.delete(`${videoId}:${ctx}`);
    if (this.delRemote) {
      await this.delRemote(videoId, ctx);
    }
  }

  async cache(
    videoId: string,
    client: string,
    token: string,
    ttlSec: number,
  ): Promise<void> {
    await this.cacheBundle(videoId, client, { gvs: token }, ttlSec);
  }

  async cacheBundle(
    videoId: string,
    client: string,
    bundle: PoTokenBundle,
    ttlSec: number,
  ): Promise<void> {
    const ctx = this.contextHash(client);
    this.memory.set(`${videoId}:${ctx}`, {
      bundle,
      exp: Date.now() + ttlSec * 1000,
    });
    if (this.setRemote) {
      await this.setRemote(
        videoId,
        ctx,
        JSON.stringify(bundle),
        ttlSec,
      );
    }
  }

  private async mintFromProvider(
    videoId: string,
    client: string,
  ): Promise<PoTokenBundle | null> {
    const base = process.env.YXZ_PO_PROVIDER_URL?.trim();
    if (!base) return null;
    const url = base.replace(/\/$/, '');
    try {
      const res = await fetch(`${url}/mint`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ videoId, client, context: 'gvs' }),
        signal: AbortSignal.timeout(8_000),
      });
      if (!res.ok) {
        // eslint-disable-next-line no-console
        console.warn(
          JSON.stringify({
            msg: 'po_provider_http_error',
            status: res.status,
            videoId,
            client,
          }),
        );
        return null;
      }
      const body = (await res.json()) as {
        gvs?: string;
        player?: string;
        token?: string;
      };
      const gvs = body.gvs ?? body.token;
      if (!gvs) return null;
      return { gvs, player: body.player };
    } catch (e) {
      // eslint-disable-next-line no-console
      console.warn(
        JSON.stringify({
          msg: 'po_provider_fetch_failed',
          videoId,
          client,
          error: String(e),
        }),
      );
      return null;
    }
  }
}

function parseStored(raw: string): PoTokenBundle | null {
  if (!raw) return null;
  if (raw.startsWith('{')) {
    try {
      const o = JSON.parse(raw) as { gvs?: string; player?: string; token?: string };
      const gvs = o.gvs ?? o.token;
      if (!gvs) return null;
      return { gvs, player: o.player };
    } catch {
      return null;
    }
  }
  // Legacy plain GVS string
  return { gvs: raw };
}
