import mongoose, { Schema, type InferSchemaType, type Model } from 'mongoose';

const InstallationSchema = new Schema(
  {
    _id: { type: String, required: true },
    refreshTokenHash: { type: String, required: true },
    status: {
      type: String,
      enum: ['active', 'disabled'],
      default: 'active',
    },
    lastSeenAt: { type: Date, default: Date.now },
    tokenVersion: { type: Number, default: 1 },
  },
  { timestamps: true },
);

export type InstallationDoc = InferSchemaType<typeof InstallationSchema> & {
  _id: string;
  createdAt: Date;
  updatedAt: Date;
};

export const InstallationModel: Model<InstallationDoc> =
  mongoose.models.Installation ??
  mongoose.model<InstallationDoc>('Installation', InstallationSchema);

const VideoSchema = new Schema(
  {
    _id: { type: String, required: true },
    title: String,
    uploader: String,
    thumbnail: String,
    durationMs: Number,
    webpageUrl: String,
    lastResolvedAt: Date,
  },
  { timestamps: true },
);

export type VideoDoc = InferSchemaType<typeof VideoSchema> & { _id: string };

export const VideoModel: Model<VideoDoc> =
  mongoose.models.Video ?? mongoose.model<VideoDoc>('Video', VideoSchema);

const DownloadJobSchema = new Schema(
  {
    _id: { type: String, required: true },
    installationId: { type: String, required: true, index: true },
    videoId: { type: String, required: true, index: true },
    quality: { type: String, required: true },
    format: { type: String, required: true },
    status: {
      type: String,
      enum: ['queued', 'running', 'completed', 'failed', 'cancelled'],
      default: 'queued',
      index: true,
    },
    progress: { type: Number, default: 0 },
    errorCode: String,
    errorMessage: String,
    outputPath: String,
    fileName: String,
    fileSize: Number,
  },
  { timestamps: true },
);

export type DownloadJobDoc = InferSchemaType<typeof DownloadJobSchema> & {
  _id: string;
};

export const DownloadJobModel: Model<DownloadJobDoc> =
  mongoose.models.DownloadJob ??
  mongoose.model<DownloadJobDoc>('DownloadJob', DownloadJobSchema);

export async function connectMongo(uri: string): Promise<typeof mongoose> {
  mongoose.set('strictQuery', true);
  return mongoose.connect(uri);
}
