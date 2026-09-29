# syntax=docker/dockerfile:1.7
FROM node:22.14.0-bookworm AS build
WORKDIR /app
COPY package.json ./
COPY packages/shared/package.json packages/shared/
COPY apps/api/package.json apps/api/
COPY workers/extractor/package.json workers/extractor/
COPY workers/downloader/package.json workers/downloader/
RUN npm install
COPY packages/shared packages/shared
COPY apps/api apps/api
COPY workers/extractor workers/extractor
COPY workers/downloader workers/downloader
RUN npm run build -w @yxz/shared \
 && npm run build -w @yxz/extractor \
 && npm run build -w @yxz/api \
 && npm run build -w @yxz/downloader

FROM node:22.14.0-bookworm AS runtime-base
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl ffmpeg python3 \
    && rm -rf /var/lib/apt/lists/*
# Pin yt-dlp release asset (update checksum when bumping)
ARG YTDLP_VERSION=2025.09.26
RUN curl -fsSL "https://github.com/yt-dlp/yt-dlp/releases/download/${YTDLP_VERSION}/yt-dlp" \
      -o /usr/local/bin/yt-dlp \
 && chmod a+rx /usr/local/bin/yt-dlp
# Deno for yt-dlp-ejs
ARG DENO_VERSION=2.3.1
RUN curl -fsSL "https://github.com/denoland/deno/releases/download/v${DENO_VERSION}/deno-x86_64-unknown-linux-gnu.zip" \
      -o /tmp/deno.zip \
 && apt-get update && apt-get install -y --no-install-recommends unzip \
 && unzip /tmp/deno.zip -d /usr/local/bin \
 && chmod a+rx /usr/local/bin/deno \
 && rm -rf /tmp/deno.zip /var/lib/apt/lists/*
# yt-dlp JS challenge runtime (ejs)
RUN python3 -m pip install --break-system-packages --no-cache-dir "yt-dlp-ejs==0.3.1" || \
    python3 -m pip install --no-cache-dir "yt-dlp-ejs==0.3.1" || true
WORKDIR /app
ENV NODE_ENV=production
RUN useradd -m -u 10001 yxz && mkdir -p /data/downloads /data/tmp && chown -R yxz:yxz /data

FROM runtime-base AS api
COPY --from=build /app /app
USER yxz
WORKDIR /app/apps/api
EXPOSE 8080
CMD ["node", "dist/server.js"]

FROM runtime-base AS extractor
COPY --from=build /app /app
USER yxz
WORKDIR /app/workers/extractor
CMD ["node", "dist/worker.js"]

FROM runtime-base AS downloader
COPY --from=build /app /app
USER yxz
WORKDIR /app/workers/downloader
CMD ["node", "dist/worker.js"]
