import { z } from 'zod';

export const ApiErrorBodySchema = z.object({
  error: z.object({
    code: z.string(),
    message: z.string(),
    retryable: z.boolean().optional(),
    details: z.unknown().optional(),
  }),
});

export type ApiErrorBody = z.infer<typeof ApiErrorBodySchema>;

export class AppError extends Error {
  readonly code: string;
  readonly statusCode: number;
  readonly retryable: boolean;
  readonly details?: unknown;

  constructor(
    code: string,
    message: string,
    options: { statusCode?: number; retryable?: boolean; details?: unknown } = {},
  ) {
    super(message);
    this.name = 'AppError';
    this.code = code;
    this.statusCode = options.statusCode ?? 500;
    this.retryable = options.retryable ?? false;
    this.details = options.details;
  }

  toBody(): ApiErrorBody {
    return {
      error: {
        code: this.code,
        message: this.message,
        retryable: this.retryable,
        details: this.details,
      },
    };
  }
}

export const QUEUE_EXTRACT = 'yxz-extract';
export const QUEUE_DOWNLOAD = 'yxz-download';

export interface ExtractJobPayload {
  videoId: string;
  quality: string;
  codec: string;
  audioLanguage: string;
  hdr: string;
  forceRefresh?: boolean;
  profileHash: string;
}

export interface DownloadJobPayload {
  jobId: string;
  videoId: string;
  quality: string;
  format: string;
  installationId: string;
}
