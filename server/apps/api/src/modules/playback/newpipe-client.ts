import {
  AppError,
  ErrorCodes,
  PlaybackManifestSchema,
  type PlaybackManifest,
} from '@yxz/shared';

/**
 * HTTP client for the NewPipe Extractor JVM worker.
 */
export class NewPipeClient {
  constructor(
    private readonly baseUrl: string,
    private readonly timeoutMs: number,
  ) {}

  get enabled(): boolean {
    return Boolean(this.baseUrl?.trim());
  }

  async extract(videoId: string): Promise<PlaybackManifest | null> {
    if (!this.enabled) return null;
    const url = `${this.baseUrl.replace(/\/$/, '')}/internal/extract`;
    try {
      const res = await fetch(url, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ videoId }),
        signal: AbortSignal.timeout(this.timeoutMs),
      });
      if (!res.ok) {
        const text = await res.text().catch(() => '');
        throw new AppError(
          ErrorCodes.EXTRACTOR_NO_STREAM,
          `NewPipe extract HTTP ${res.status}: ${text.slice(0, 200)}`,
          { statusCode: 502, retryable: true },
        );
      }
      const json: unknown = await res.json();
      const parsed = PlaybackManifestSchema.safeParse(json);
      if (!parsed.success) {
        throw new AppError(
          ErrorCodes.EXTRACTOR_UPSTREAM_CHANGED,
          `NewPipe manifest invalid: ${parsed.error.message}`,
          { statusCode: 502, retryable: true },
        );
      }
      return parsed.data;
    } catch (e) {
      if (e instanceof AppError) throw e;
      throw new AppError(
        ErrorCodes.EXTRACTOR_NO_STREAM,
        `NewPipe extract failed: ${String(e)}`,
        { statusCode: 502, retryable: true },
      );
    }
  }
}
