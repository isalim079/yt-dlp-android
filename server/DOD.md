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
- [x] Truthful 1080p / 4K quality contract + fallbackReason
- [x] Playback debug endpoint (`YXZ_PLAYBACK_DEBUG=1`)
- [x] Flutter HD reopen (adaptive first) + height assert + mismatch metric
- [x] Android debug/profile cleartext for LAN API
- [ ] Live 1080p/4K corpus on a deployed host (run after `docker compose up`)

## Run

```bash
cd server && cp .env.example .env && docker compose up --build -d
curl http://localhost:8080/health
TOKEN=$(curl -s -X POST http://localhost:8080/api/v1/installations | jq -r .accessToken)
ACCESS_TOKEN=$TOKEN ./scripts/staging_corpus.sh
```

## Wireless debugging (real device)

1. Mac + phone on the same Wi‑Fi.
2. Find Mac LAN IP: `ipconfig getifaddr en0`
3. App → Settings → Playback server → API base URL:
   `http://<LAN_IP>:8080` (not localhost, not 10.0.2.2)
4. Prefer server playback/download = on.
5. Debug builds allow cleartext HTTP to that URL.
6. Open a known 1080p video, wait for HD warm, confirm log
   `playback height assert … actual=…x1080` (or higher).
