import { spawn } from 'node:child_process';
import { AppError, ErrorCodes } from '@yxz/shared';

export interface YtDlpRunOptions {
  bin: string;
  args: string[];
  timeoutMs: number;
  env?: NodeJS.ProcessEnv;
}

export interface YtDlpRunResult {
  stdout: string;
  stderr: string;
  code: number | null;
}

/** Safe argv spawn — never shell-interpolates user input. */
export async function runYtDlp(options: YtDlpRunOptions): Promise<YtDlpRunResult> {
  return new Promise((resolve, reject) => {
    const child = spawn(options.bin, options.args, {
      env: { ...process.env, ...options.env },
      stdio: ['ignore', 'pipe', 'pipe'],
      shell: false,
    });
    let stdout = '';
    let stderr = '';
    const timer = setTimeout(() => {
      child.kill('SIGKILL');
      reject(
        new AppError(ErrorCodes.EXTRACTOR_TIMEOUT, 'yt-dlp timed out', {
          statusCode: 504,
          retryable: true,
        }),
      );
    }, options.timeoutMs);

    child.stdout.on('data', (chunk: Buffer) => {
      stdout += chunk.toString('utf8');
    });
    child.stderr.on('data', (chunk: Buffer) => {
      stderr += chunk.toString('utf8');
    });
    child.on('error', (err) => {
      clearTimeout(timer);
      reject(
        new AppError(
          ErrorCodes.EXTRACTOR_JS_RUNTIME_ERROR,
          `Failed to spawn yt-dlp: ${err.message}`,
          { statusCode: 500, retryable: true },
        ),
      );
    });
    child.on('close', (code) => {
      clearTimeout(timer);
      resolve({ stdout, stderr, code });
    });
  });
}

export async function ytDlpVersion(bin: string): Promise<string> {
  const r = await runYtDlp({ bin, args: ['--version'], timeoutMs: 10_000 });
  return r.stdout.trim() || r.stderr.trim() || 'unknown';
}

export function mapYtDlpFailure(stderr: string, code: number | null): AppError {
  const s = stderr.toLowerCase();
  if (s.includes('private video') || s.includes('login required')) {
    return new AppError(ErrorCodes.EXTRACTOR_PRIVATE, 'Video is private', {
      statusCode: 403,
    });
  }
  if (s.includes('not available in your country') || s.includes('geo')) {
    return new AppError(ErrorCodes.EXTRACTOR_GEO_BLOCKED, 'Video geo-blocked', {
      statusCode: 451,
    });
  }
  if (s.includes('video unavailable') || s.includes('removed')) {
    return new AppError(
      ErrorCodes.EXTRACTOR_VIDEO_UNAVAILABLE,
      'Video unavailable',
      { statusCode: 404 },
    );
  }
  if (s.includes('rate') || s.includes('429') || s.includes('too many')) {
    return new AppError(ErrorCodes.EXTRACTOR_RATE_LIMITED, 'Upstream rate limited', {
      statusCode: 429,
      retryable: true,
    });
  }
  if (s.includes('po token') || s.includes('potoken')) {
    return new AppError(
      ErrorCodes.EXTRACTOR_PO_TOKEN_REQUIRED,
      'PO token required',
      { statusCode: 502, retryable: true },
    );
  }
  return new AppError(
    ErrorCodes.EXTRACTOR_NO_STREAM,
    `yt-dlp failed (code ${code ?? 'null'})`,
    { statusCode: 502, retryable: true, details: stderr.slice(0, 500) },
  );
}
