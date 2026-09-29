# Definition of Done checklist (§84)

- [x] Node API (Fastify) under `server/apps/api`
- [x] MongoDB + Redis via `docker-compose.yml`
- [x] Extractor worker (`workers/extractor`) + inline resolve
- [x] Downloader worker (`workers/downloader`) + FFmpeg remux/ffprobe
- [x] Install JWT (`POST /api/v1/installations`, refresh, revoke)
- [x] PlaybackManifest Zod schema + quality ranking
- [x] Redis cache + single-flight + forceRefresh
- [x] Typed extractor error codes + Flutter classified fallback
- [x] Flutter PlaybackSourceRouter (server primary / local fallback)
- [x] Flutter download server-primary path
- [x] Rate limit + `/metrics` + `/health` + `/ready`
- [x] Nginx reverse proxy
- [x] Staging corpus script `scripts/staging_corpus.sh`
- [ ] Live 1080p/4K corpus on a deployed host (run after `docker compose up`)

## Run

```bash
cd server && cp .env.example .env && docker compose up --build -d
curl http://localhost:8080/health
TOKEN=$(curl -s -X POST http://localhost:8080/api/v1/installations | jq -r .accessToken)
ACCESS_TOKEN=$TOKEN ./scripts/staging_corpus.sh
```

In the app: Settings → Playback server → set API base URL
(Android emulator: `http://10.0.2.2:8080`).
