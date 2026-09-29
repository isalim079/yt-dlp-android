import { spawn } from 'node:child_process';
import { rename, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { AppError, ErrorCodes } from '@yxz/shared';

function run(
  bin: string,
  args: string[],
  timeoutMs: number,
): Promise<{ code: number | null; stderr: string }> {
  return new Promise((resolve, reject) => {
    const child = spawn(bin, args, { shell: false, stdio: ['ignore', 'pipe', 'pipe'] });
    let stderr = '';
    const t = setTimeout(() => {
      child.kill('SIGKILL');
      reject(
        new AppError(ErrorCodes.EXTRACTOR_TIMEOUT, `${bin} timed out`, {
          statusCode: 504,
          retryable: true,
        }),
      );
    }, timeoutMs);
    child.stderr.on('data', (c: Buffer) => {
      stderr += c.toString('utf8');
    });
    child.on('close', (code) => {
      clearTimeout(t);
      resolve({ code, stderr });
    });
    child.on('error', (err) => {
      clearTimeout(t);
      reject(err);
    });
  });
}

export async function remuxCopy(
  ffmpegBin: string,
  videoPath: string,
  audioPath: string,
  outPath: string,
  timeoutMs = 30 * 60_000,
): Promise<void> {
  const partial = `${outPath}.partial`;
  await mkdir(path.dirname(outPath), { recursive: true });
  const { code, stderr } = await run(
    ffmpegBin,
    [
      '-y',
      '-i',
      videoPath,
      '-i',
      audioPath,
      '-c',
      'copy',
      '-map',
      '0:v:0',
      '-map',
      '1:a:0',
      '-shortest',
      partial,
    ],
    timeoutMs,
  );
  if (code !== 0) {
    throw new AppError(ErrorCodes.INTERNAL_ERROR, 'FFmpeg remux failed', {
      statusCode: 500,
      details: stderr.slice(0, 400),
    });
  }
  await rename(partial, outPath);
}

export async function ffprobeOk(
  ffprobeBin: string,
  filePath: string,
): Promise<{ duration: number; size: number }> {
  const { code, stderr } = await run(
    ffprobeBin,
    [
      '-v',
      'error',
      '-show_entries',
      'format=duration,size',
      '-of',
      'json',
      filePath,
    ],
    60_000,
  );
  if (code !== 0) {
    throw new AppError(ErrorCodes.INTERNAL_ERROR, 'ffprobe failed', {
      statusCode: 500,
      details: stderr.slice(0, 200),
    });
  }
  // stdout not captured above — re-run collecting stdout
  return new Promise((resolve, reject) => {
    const child = spawn(
      ffprobeBin,
      [
        '-v',
        'error',
        '-show_entries',
        'format=duration,size',
        '-of',
        'json',
        filePath,
      ],
      { shell: false },
    );
    let out = '';
    child.stdout.on('data', (c: Buffer) => {
      out += c.toString('utf8');
    });
    child.on('close', (c) => {
      if (c !== 0) {
        reject(new AppError(ErrorCodes.INTERNAL_ERROR, 'ffprobe failed'));
        return;
      }
      try {
        const j = JSON.parse(out) as {
          format?: { duration?: string; size?: string };
        };
        resolve({
          duration: Number(j.format?.duration ?? 0),
          size: Number(j.format?.size ?? 0),
        });
      } catch (e) {
        reject(e);
      }
    });
  });
}

export async function downloadFormat(
  ytdlpBin: string,
  url: string,
  outTemplate: string,
  formatId: string,
  timeoutMs = 30 * 60_000,
): Promise<void> {
  const { code, stderr } = await run(
    ytdlpBin,
    [
      '-f',
      formatId,
      '-o',
      outTemplate,
      '--no-playlist',
      '--no-warnings',
      url,
    ],
    timeoutMs,
  );
  if (code !== 0) {
    throw new AppError(ErrorCodes.EXTRACTOR_NO_STREAM, 'Download failed', {
      statusCode: 502,
      details: stderr.slice(0, 400),
    });
  }
}
