# YXZ Tube production server

## Quick start

```bash
cd server
cp .env.example .env
# edit JWT_SECRET
docker compose up --build -d
curl http://localhost:8080/health
```

## Register an installation

```bash
curl -s -X POST http://localhost:8080/api/v1/installations | jq
```

Use `accessToken` as `Authorization: Bearer …` for playback:

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8080/api/v1/videos/dQw4w9WgXcQ/playback?quality=1080p" | jq
```

## Layout

- `apps/api` — Fastify API
- `workers/extractor` — BullMQ extract worker + shared resolve library
- `workers/downloader` — BullMQ download + FFmpeg remux
- `packages/shared` — Zod schemas / error codes

See `readmeFiles/YXZ_Tube_High_Resolution_Production_Server_README.md`.
