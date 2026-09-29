# YXZ Tube — Production-Grade High-Resolution YouTube Playback Server

## 0. Executive Decision

This implementation uses:

```text
Flutter Android
    |
    | HTTPS
    v
Node.js + Fastify API
    |
    +-----------------------------+
    |                             |
    v                             v
MongoDB                        Redis
persistent data               cache / locks / jobs
    |
    v
Extraction Worker
    |
    +-- yt-dlp
    +-- yt-dlp-ejs
    +-- Deno
    +-- PO-token provider
    |
    v
Normalized PlaybackManifest
    |
    v
Flutter
    |
    v
existing media_kit/libmpv
```

### Critical design choice

For normal playback:

```text
DO NOT:
YouTube -> server downloads full video -> FFmpeg -> Flutter
```

Instead:

```text
YouTube
   |
   +-- 1080p/1440p/2160p video representation
   |
   +-- compatible audio representation
   |
   v
PlaybackManifest
   |
   v
Flutter media_kit
```

FFmpeg is only used for the separate download/export pipeline.

This is the first production architecture to implement.

---

# 1. Exact Goal

The immediate production goal is:

> Given a YouTube video that exposes 1080p, the server must resolve a valid 1080p video representation plus a compatible audio representation and return them to Flutter in a normalized manifest that the existing media_kit player can play without pre-downloading or transcoding the video.

The system must support, when the source and device allow it:

```text
360p
480p
720p
1080p
1440p
2160p / 4K
```

Higher resolution is an availability/capability result, not a guarantee that every video/device has it.

---

# 2. Why the Current Client Fallback Must Be Replaced

Do not build the production system around this:

```text
mweb
android_vr
web_safari
web_embedded
```

as a static fallback loop.

YouTube changes:

- player clients
- SABR behavior
- JS challenges
- PO-token requirements
- available representations
- response formats

Current yt-dlp documentation says some YouTube clients require PO tokens for GVS or player requests, and recommends a PO-token provider for the `mweb` GVS path. Current yt-dlp documentation also requires an external JavaScript runtime plus yt-dlp-ejs for full YouTube support.

Therefore:

```text
client selection = extractor implementation detail

NOT

Flutter application logic
```

---

# 3. Current Upstream Requirements

The server must treat these as a versioned compatibility set:

```text
yt-dlp
yt-dlp-ejs
Deno
PO-token provider
FFmpeg
ffprobe
```

The current yt-dlp EJS documentation recommends Deno and states that Deno >= 2.3 is supported. Node >= 22 is also supported as a JS runtime when explicitly enabled.

Do not install "latest" in production containers without pinning and testing.

Recommended rule:

```text
one tested image
=
one known-good combination
```

---

# 4. Technology Stack

## API

```text
Node.js
TypeScript
Fastify
Zod
Pino
MongoDB
Mongoose OR native MongoDB driver
Redis
BullMQ
```

## Extraction

```text
yt-dlp
yt-dlp-ejs
Deno
PO-token provider
```

## Media

```text
FFmpeg
ffprobe
```

## Reverse proxy

```text
Nginx
```

## Container

```text
Docker
Docker Compose
```

---

# 5. Service Architecture

Run separate processes/containers.

```text
                    +------------------+
                    |      Nginx       |
                    +--------+---------+
                             |
                             v
                    +------------------+
                    |   yxz-api        |
                    |   Fastify        |
                    +---+----------+---+
                        |          |
                        |          |
                        v          v
                  +---------+  +---------+
                  | MongoDB |  |  Redis  |
                  +---------+  +----+----+
                                     |
                          +----------+----------+
                          |                     |
                          v                     v
                  +-------------+      +---------------+
                  | extractor   |      | download      |
                  | worker      |      | worker        |
                  | yt-dlp     |      | yt-dlp+FFmpeg |
                  +-------------+      +---------------+
```

The API process must never perform a long-running FFmpeg operation.

The API process may perform a short extraction synchronously for a first request, but production should prefer a dedicated extraction worker with single-flight locking.

---

# 6. MongoDB Responsibilities

MongoDB stores persistent application data.

Recommended collections:

```text
users
videos
download_jobs
download_history
playback_events
extractor_health
```

MongoDB MUST NOT be treated as the long-term store for signed YouTube media URLs.

Do not persist a signed media URL for days.

---

# 7. Redis Responsibilities

Redis stores short-lived state.

Use Redis for:

```text
playback cache
single-flight locks
rate limits
BullMQ
short-lived extraction state
temporary failure suppression
```

Example keys:

```text
yt:playback:{videoId}:{profileHash}
yt:singleflight:{videoId}:{profileHash}
yt:ratelimit:{identity}
yt:failure:{videoId}
```

---

# 8. Playback Request Flow

The exact high-resolution flow is:

```text
Flutter
  |
  | GET /api/v1/videos/:videoId/playback
  |
  v
Fastify
  |
  v
Redis playback cache
  |
  +-- HIT --> return normalized manifest
  |
  +-- MISS
        |
        v
   single-flight lock
        |
        +-- another request already resolving
        |       |
        |       v
        |    wait/cache
        |
        +-- current request owns lock
                |
                v
          Extraction Worker
                |
                v
             yt-dlp
                |
        +-------+--------+
        |                |
        v                v
   EJS challenge      PO-token
      solving          provider
        |                |
        +-------+--------+
                |
                v
          raw extractor result
                |
                v
        format normalization
                |
                v
          stream validation
                |
                v
          stream ranking
                |
                v
       PlaybackManifest
                |
                v
          Redis short TTL
                |
                v
             Flutter
                |
                v
          media_kit/libmpv
```

---

# 9. High-Resolution Rule

The server must NOT assume:

```text
1080p = one combined MP4
```

A high-resolution video may be exposed as:

```text
1080p video-only
+
separate audio-only
```

Therefore the server MUST model them separately.

Example:

```text
VIDEO

1920x1080
30 FPS
AVC
4.5 Mbps
video-only
```

and:

```text
AUDIO

Opus
160 kbps
48 kHz
2 channels
audio-only
```

Together:

```text
1080p playback
```

---

# 10. PlaybackManifest

Create one server-owned schema.

Example:

```json
{
  "schemaVersion": 1,
  "videoId": "abc123",
  "title": "Example Video",
  "durationMs": 542000,
  "resolvedAt": "2026-09-29T05:30:00Z",
  "expiresAt": "2026-09-29T06:00:00Z",
  "delivery": {
    "type": "direct"
  },
  "videoStreams": [
    {
      "id": "video-1080-avc",
      "width": 1920,
      "height": 1080,
      "fps": 30,
      "codec": "avc1",
      "mimeType": "video/mp4",
      "bitrate": 4500000,
      "url": "https://...",
      "isVideoOnly": true,
      "hdr": false
    },
    {
      "id": "video-720-avc",
      "width": 1280,
      "height": 720,
      "fps": 30,
      "codec": "avc1",
      "mimeType": "video/mp4",
      "bitrate": 2500000,
      "url": "https://...",
      "isVideoOnly": true,
      "hdr": false
    }
  ],
  "audioStreams": [
    {
      "id": "audio-aac",
      "codec": "mp4a",
      "mimeType": "audio/mp4",
      "bitrate": 128000,
      "sampleRate": 48000,
      "channels": 2,
      "url": "https://..."
    },
    {
      "id": "audio-opus",
      "codec": "opus",
      "mimeType": "audio/webm",
      "bitrate": 160000,
      "sampleRate": 48000,
      "channels": 2,
      "url": "https://..."
    }
  ],
  "subtitles": []
}
```

Do not expose the entire raw yt-dlp JSON.

---

# 11. Delivery Strategy

Support three delivery modes.

```text
adaptive
direct
progressive
```

## Adaptive

Preferred when a usable DASH/HLS manifest exists.

```text
DASH/HLS
    |
    +-- video representations
    +-- audio representations
    |
    v
media_kit
```

## Direct

Use separate direct video/audio URLs.

```text
video URL
+
audio URL
    |
    v
media_kit/libmpv
```

## Progressive

Use one combined A/V stream when available.

```text
combined MP4/WebM
    |
    v
media_kit
```

Priority:

```text
ADAPTIVE
   >
DIRECT VIDEO + AUDIO
   >
PROGRESSIVE
```

---

# 12. Important Note About media_kit

This pass keeps:

```text
media_kit/libmpv
```

to reduce simultaneous changes.

The server must therefore expose a media representation that libmpv can actually consume.

Do not build a server contract that assumes Media3-only behavior.

Later, the same `PlaybackManifest` can be adapted to Media3.

---

# 13. Exact Quality Selection Algorithm

Input:

```text
requestedQuality
deviceCapabilities
availableStreams
```

Example:

```text
requested = 1080p
```

Algorithm:

```text
1. Filter streams with usable URL.
2. Filter streams compatible with requested delivery.
3. Filter unsupported codecs if device capabilities are known.
4. Select exact requested height when possible.
5. Prefer the highest compatible bitrate for the selected resolution.
6. If exact resolution does not exist:
     return nearest lower resolution.
7. If no lower resolution exists:
     return nearest available compatible resolution.
8. Pair the selected video with the best compatible audio stream.
9. Return the pair.
```

Example:

```text
Available:

2160p AV1
1440p VP9
1080p AVC
1080p VP9
720p AVC
audio AAC
audio Opus
```

A broadly compatible 1080p request becomes:

```text
1080p AVC
+
best compatible audio
```

not:

```text
2160p AV1
```

just because 4K exists.

---

# 14. Quality Ranking

Resolution is not the only ranking value.

Rank by:

```text
1. supported/playable
2. requested resolution match
3. codec compatibility
4. HDR preference
5. frame rate
6. bitrate
```

For compatible devices:

```text
AV1
>
VP9
>
AVC
```

may be preferred for efficiency.

For maximum device compatibility:

```text
AVC
>
VP9
>
AV1
```

may be preferred.

Make codec preference configurable.

---

# 15. Audio Pairing

When a video stream is selected:

```text
videoStream
```

select audio using:

```text
1. compatible codec/container
2. desired language
3. source/original language preference
4. highest sensible bitrate
5. sample rate/channel compatibility
```

Do not blindly pair the first audio stream returned by yt-dlp.

---

# 16. Do Not Use FFmpeg for Normal Playback

This is mandatory.

DO NOT:

```text
resolve 1080p
    |
download video
    |
download audio
    |
FFmpeg merge
    |
play
```

This produces:

```text
high latency
high bandwidth
server storage usage
server CPU usage
poor startup time
```

Instead:

```text
resolve 1080p video URL
+
resolve audio URL
        |
        v
PlaybackManifest
        |
        v
Flutter
        |
        v
media_kit/libmpv
```

FFmpeg is for downloads.

---

# 17. yt-dlp Execution

Use argument arrays rather than shell strings.

Conceptually:

```text
yt-dlp
--dump-single-json
--no-playlist
--skip-download
VIDEO_URL
```

The server should not run:

```text
shell("yt-dlp " + userInput)
```

Use a process API with explicit arguments.

---

# 18. yt-dlp Configuration

Do not hard-code a permanent client list.

The extractor adapter is responsible for choosing supported current strategies.

A strategy may include:

```text
default
mweb + PO token
web_safari + HLS
other currently supported clients
```

The actual strategy should be configuration-driven.

Example:

```json
{
  "youtube": {
    "strategies": [
      "default",
      "mweb-po-token",
      "web-safari-hls"
    ]
  }
}
```

Do not place strategy selection in Flutter.

---

# 19. PO Token Architecture

Current yt-dlp documentation says PO Tokens can be required for GVS and, for some clients, player requests. The current recommendation is to use a PO-token provider plugin rather than manually copying tokens.

The architecture MUST therefore contain:

```text
PoTokenProvider
```

Concept:

```ts
interface PoTokenProvider {
  getVideoToken(videoId: string, context: TokenContext): Promise<string>;
}
```

Provider output is used internally by the yt-dlp adapter.

Never return PO tokens to Flutter.

Never write PO tokens to logs.

Never persist PO tokens permanently.

---

# 20. PO Token Cache

PO tokens are contextual and time-sensitive.

Use a short-lived encrypted/secure cache only if required by the provider.

Example:

```text
po:video:{videoId}:{contextHash}
```

Use an expiration shorter than the provider's documented validity when possible.

When token validation fails:

```text
invalidate token
refresh token
retry extraction once
```

Do not retry forever.

---

# 21. EJS Runtime

Production extraction MUST include:

```text
yt-dlp
yt-dlp-ejs
Deno >= 2.3
```

or another supported runtime/configuration explicitly tested for the deployed yt-dlp version.

Preferred deployment:

```text
/usr/local/bin/yt-dlp
/usr/local/bin/ffmpeg
/usr/local/bin/ffprobe
/usr/local/bin/deno
```

Keep exact versions in a lock/manifest file:

```yaml
yt_dlp: pinned
yt_dlp_ejs: pinned
deno: pinned
ffmpeg: pinned
```

---

# 22. Extraction Timeout

Never allow unlimited yt-dlp execution.

Example starting defaults:

```text
metadata resolve: 10 seconds
playback resolve: 20 seconds
download job: 30 minutes
ffmpeg merge: 30 minutes
```

Tune these values using production metrics.

On timeout:

```text
kill process
clean temp files
release Redis lock
return typed failure
```

---

# 23. Extraction Failure Codes

Never return one generic exception.

Use:

```text
EXTRACTOR_TIMEOUT
EXTRACTOR_NO_STREAM
EXTRACTOR_PO_TOKEN_REQUIRED
EXTRACTOR_JS_RUNTIME_ERROR
EXTRACTOR_RATE_LIMITED
EXTRACTOR_VIDEO_UNAVAILABLE
EXTRACTOR_PRIVATE
EXTRACTOR_GEO_BLOCKED
EXTRACTOR_CHALLENGE_FAILED
EXTRACTOR_UPSTREAM_CHANGED
```

Player-side:

```text
PLAYBACK_STREAM_EXPIRED
PLAYBACK_403
PLAYBACK_410
PLAYBACK_UNSUPPORTED_CODEC
PLAYBACK_NETWORK_ERROR
PLAYBACK_PREPARE_FAILED
```

---

# 24. URL Expiration

YouTube media URLs are temporary.

Every stream object must include:

```text
expiresAt
```

Do NOT store URLs indefinitely in MongoDB.

Do NOT put long-lived URLs into permanent history records.

If playback gets:

```text
403
410
expired
```

perform:

```text
currentPosition = player.position

resolvePlayback(videoId, forceRefresh = true)

replace media source

seek currentPosition

resume
```

---

# 25. Playback Cache

Cache the normalized manifest in Redis.

Key:

```text
yt:playback:{videoId}:{profileHash}
```

TTL:

```text
min(
  configuredMaximumTTL,
  upstreamExpiresAt - now - safetyMargin
)
```

Example safety margin:

```text
60 seconds
```

Never let cache TTL extend beyond expected URL validity.

---

# 26. Single-Flight Resolution

Suppose 50 clients ask for the same video simultaneously.

Do NOT execute:

```text
50 x yt-dlp
```

Use Redis locking:

```text
SET yt:singleflight:{key} token NX EX 30
```

One request becomes the resolver.

Other requests:

```text
wait for cache
```

If the lock owner fails:

```text
release lock
allow next resolver
```

Use a robust lock implementation rather than a homemade unsafe distributed lock.

---

# 27. API Endpoints

## Metadata

```http
GET /api/v1/videos/:videoId
```

## Playback

```http
GET /api/v1/videos/:videoId/playback
```

Optional parameters:

```text
quality=auto
quality=1080p
codec=auto
audioLanguage=auto
hdr=auto
```

## Subtitles

```http
GET /api/v1/videos/:videoId/subtitles
```

## Download

```http
POST /api/v1/downloads
```

## Download Status

```http
GET /api/v1/downloads/:jobId
```

## Health

```http
GET /health
```

## Readiness

```http
GET /ready
```

---

# 28. Playback API Request

Example:

```http
GET /api/v1/videos/abc123/playback?quality=1080p
```

Header:

```http
Authorization: Bearer <token>
```

---

# 29. Playback API Response

Example:

```json
{
  "schemaVersion": 1,
  "video": {
    "id": "abc123",
    "title": "Example",
    "durationMs": 542000
  },
  "playback": {
    "mode": "direct",
    "expiresAt": "2026-09-29T06:00:00Z"
  },
  "videoStreams": [
    {
      "id": "v1080avc",
      "width": 1920,
      "height": 1080,
      "fps": 30,
      "codec": "avc1",
      "bitrate": 4500000,
      "mimeType": "video/mp4",
      "url": "https://..."
    }
  ],
  "audioStreams": [
    {
      "id": "a160opus",
      "codec": "opus",
      "bitrate": 160000,
      "sampleRate": 48000,
      "channels": 2,
      "mimeType": "audio/webm",
      "url": "https://..."
    }
  ]
}
```

---

# 30. Flutter Integration

Flutter becomes a thin client.

Current service:

```text
PlaybackRepository
```

calls:

```text
GET /api/v1/videos/:id/playback
```

and converts JSON into:

```text
PlaybackManifest
```

Then:

```text
PlayerController
    |
    v
StreamSelector
    |
    v
media_kit
```

Flutter must not:

```text
execute yt-dlp
choose YouTube clients
handle PO tokens
run EJS
parse raw yt-dlp JSON
```

---

# 31. media_kit Direct A/V Playback

When the server returns separate video and audio URLs, build the player input appropriately for media_kit/libmpv.

Do not merge the files first.

The implementation must verify the exact media_kit API used by the current project version.

If the installed media_kit version cannot reliably consume separate external A/V URLs in the required configuration, the fallback is:

```text
use an adaptive manifest
```

or migrate the playback layer to Media3 in a later phase.

Do not silently transcode every request to make the player happy.

---

# 32. Recommended Server Output Order

When possible:

```text
1. DASH/HLS manifest
2. direct video + audio representations
3. progressive A/V
```

The client should use the first compatible mode.

---

# 33. Adaptive Manifest Mode

If a valid DASH MPD is available:

```json
{
  "delivery": {
    "type": "dash",
    "manifestUrl": "https://..."
  }
}
```

If HLS is available:

```json
{
  "delivery": {
    "type": "hls",
    "manifestUrl": "https://..."
  }
}
```

Media3 is the future target for full adaptive playback.

For the current media_kit pass, direct streams may be simpler and more deterministic.

---

# 34. Important SABR Handling

Current YouTube behavior can involve SABR responses.

NewPipe's current releases explicitly contain fixes for YouTube SABR enforcement that previously caused:

```text
missing resolutions
no separate audio
only 360p MP4
```

This confirms that a production extractor must detect and handle upstream changes rather than assuming a fixed response format.

Therefore the adapter must check:

```text
Did the extractor return expected video representations?
Did it return audio?
Did it return only SABR/limited representations?
Did it return zero direct formats?
```

If the result is incomplete, try the next supported extraction strategy.

---

# 35. Strategy Pipeline

Implement a controlled strategy pipeline:

```text
Strategy 1:
current yt-dlp default

if no usable 1080p/direct/adaptive stream:
    Strategy 2:
    mweb + PO token

if no usable stream:
    Strategy 3:
    web_safari HLS where applicable

if no usable stream:
    Strategy 4:
    another currently supported extractor profile

if still no stream:
    typed failure
```

The exact strategies must be enabled/disabled based on current yt-dlp compatibility testing.

Do not keep dead client names simply because they worked historically.

---

# 36. High-Resolution Availability Contract

The API should explicitly return:

```json
{
  "requestedQuality": "1080p",
  "selectedQuality": "1080p",
  "qualityFallback": false
}
```

If 1080p does not exist:

```json
{
  "requestedQuality": "1080p",
  "selectedQuality": "720p",
  "qualityFallback": true,
  "fallbackReason": "QUALITY_UNAVAILABLE"
}
```

This prevents the UI from claiming "1080p" when it is actually playing 720p.

---

# 37. Device Capabilities

Flutter should optionally send:

```json
{
  "device": {
    "maxResolution": "2160p",
    "codecs": [
      "avc",
      "vp9",
      "av1"
    ],
    "hdr": true
  }
}
```

The server may use this to rank representations.

Do not blindly trust it for security.

It is a playback preference/capability hint.

---

# 38. Security

## Authentication

Use JWT or another proper authentication mechanism.

## Rate limiting

Limit:

```text
per account
per IP
per installation
per video
```

## Input validation

Validate:

```text
videoId
quality
codec
language
```

Never pass arbitrary strings to a shell.

---

# 39. SSRF Protection

Do not create a generic endpoint like:

```text
POST /fetch
{
  "url": "http://..."
}
```

where the server fetches arbitrary URLs.

This creates SSRF risk.

The application should accept normalized YouTube identifiers/URLs only.

Protect against:

```text
127.0.0.1
localhost
10.0.0.0/8
172.16.0.0/12
192.168.0.0/16
169.254.169.254
IPv6 link-local
file://
gopher://
```

and redirect-based SSRF.

---

# 40. Process Isolation

Extraction and FFmpeg must run in restricted workers.

Run as non-root.

Use:

```text
read-only filesystem where possible
no-new-privileges
drop Linux capabilities
CPU limits
memory limits
process limits
timeout
temporary filesystem
```

---

# 41. Docker Layout

Recommended:

```text
docker-compose.yml

services:

  api:
    build: ./apps/api

  extractor:
    build: ./workers/extractor

  downloader:
    build: ./workers/downloader

  redis:
    image: redis:8-alpine

  mongo:
    image: mongo:8
```

Pin image tags after testing.

Do not use unpinned:

```text
latest
```

in production.

---

# 42. Node API Structure

```text
apps/api/
├── src/
│   ├── app.ts
│   ├── server.ts
│   ├── config/
│   │   └── env.ts
│   ├── routes/
│   │   ├── health.ts
│   │   ├── videos.ts
│   │   └── downloads.ts
│   ├── modules/
│   │   ├── playback/
│   │   ├── extraction/
│   │   ├── videos/
│   │   └── downloads/
│   ├── infrastructure/
│   │   ├── mongo/
│   │   ├── redis/
│   │   └── process/
│   └── observability/
│       ├── logger.ts
│       └── metrics.ts
└── package.json
```

---

# 43. Extraction Worker Structure

```text
workers/extractor/
├── src/
│   ├── worker.ts
│   ├── strategies/
│   │   ├── default.strategy.ts
│   │   ├── mweb-pot.strategy.ts
│   │   └── web-safari.strategy.ts
│   ├── ytdlp/
│   │   ├── runner.ts
│   │   ├── parser.ts
│   │   └── version.ts
│   ├── tokens/
│   │   └── pot-provider.ts
│   ├── normalize/
│   │   ├── manifest.ts
│   │   └── streams.ts
│   └── validation/
│       └── stream-validator.ts
└── package.json
```

---

# 44. Domain Interfaces

Create a stable abstraction.

```ts
export interface VideoExtractor {
  resolve(
    videoId: string,
    options: ResolveOptions
  ): Promise<ExtractionResult>;
}
```

And:

```ts
export interface PlaybackResolver {
  resolve(
    videoId: string,
    options: PlaybackOptions
  ): Promise<PlaybackManifest>;
}
```

The rest of the system must not import yt-dlp implementation classes directly.

---

# 45. Extractor Result Types

Example:

```ts
type ExtractionResult =
  | {
      ok: true;
      manifest: PlaybackManifest;
      extractor: ExtractorMetadata;
    }
  | {
      ok: false;
      code: ExtractionErrorCode;
      retryable: boolean;
      extractor: ExtractorMetadata;
      message: string;
    };
```

---

# 46. MongoDB Models

## Video

```text
videoId
title
durationMs
thumbnail
channel
createdAt
updatedAt
```

## DownloadJob

```text
jobId
userId
videoId
requestedQuality
requestedFormat
status
progress
outputPath
errorCode
createdAt
completedAt
```

## PlaybackEvent

Use for aggregated analytics, not raw URLs.

```text
userId/hash
videoId
requestedQuality
selectedQuality
codec
deliveryType
startupMs
result
failureCode
createdAt
```

Never store:

```text
signedMediaUrl
PO token
cookies
authorization headers
```

---

# 47. Redis Cache Policy

Playback cache:

```text
key:
yt:playback:{videoId}:{profileHash}
```

Value:

```text
compressed normalized manifest
```

TTL:

```text
min(
    MAX_PLAYBACK_CACHE_TTL,
    expiresAt - now - SAFETY_MARGIN
)
```

Example initial configuration:

```text
MAX_PLAYBACK_CACHE_TTL = 10 minutes
SAFETY_MARGIN = 60 seconds
```

Tune later from telemetry.

---

# 48. Download Pipeline

Downloads are asynchronous.

```text
POST /api/v1/downloads
        |
        v
BullMQ
        |
        v
Downloader Worker
        |
        v
Resolve video/audio
        |
        v
Download temporary files
        |
        v
FFmpeg merge/remux
        |
        v
ffprobe validation
        |
        v
atomic finalize
```

---

# 49. Download Quality

For:

```text
1080p
```

select:

```text
1080p video
+
best compatible audio
```

For MP4 output, prefer a compatible combination.

Do not transcode by default.

Use remux/stream copy whenever possible.

---

# 50. FFmpeg Download Example

Conceptually:

```text
input video
+
input audio
    |
    v
ffmpeg
-map 0:v:0
-map 1:a:0
-copy compatible codecs
    |
    v
output.mp4
```

The actual command must be generated from validated internal stream metadata, not arbitrary client input.

---

# 51. Atomic Download Completion

Never write directly to:

```text
final.mp4
```

Use:

```text
jobId.partial
```

then:

```text
ffprobe
   |
   v
success
   |
   v
rename to final
```

---

# 52. Media URL Refresh

When media_kit reports an HTTP failure:

```text
403
410
connection closed due to expired URL
```

Flutter should call:

```text
GET /api/v1/videos/:id/playback?forceRefresh=true
```

or the server should expose an internal refresh path.

Then:

```text
resolve
replace stream
seek
resume
```

---

# 53. Logging

Use Pino structured logging.

Example:

```json
{
  "level": "info",
  "event": "playback_resolution",
  "videoId": "abc123",
  "requestedQuality": "1080p",
  "selectedQuality": "1080p",
  "delivery": "direct",
  "codec": "avc1",
  "durationMs": 812,
  "extractor": "yt-dlp",
  "extractorVersion": "pinned-version"
}
```

Never log signed URLs or tokens.

---

# 54. Metrics

Required metrics:

```text
playback_resolution_total
playback_resolution_success_total
playback_resolution_failure_total
playback_resolution_duration_ms
playback_1080_success_total
playback_1440_success_total
playback_2160_success_total
stream_refresh_total
stream_refresh_success_total
stream_403_total
stream_410_total
po_token_required_total
po_token_failure_total
js_runtime_failure_total
download_total
download_success_total
download_failure_total
ffmpeg_duration_ms
```

---

# 55. Health

## /health

Must be cheap.

```json
{
  "status": "ok"
}
```

Do not call YouTube from `/health`.

## /ready

Check local dependencies:

```text
MongoDB
Redis
worker dependency
required binary presence
configuration
```

Do not make readiness depend on YouTube.

---

# 56. Production Error Mapping

Server:

```text
EXTRACTOR_PO_TOKEN_REQUIRED
```

Flutter message:

```text
This video is temporarily unavailable. Please try again.
```

Server:

```text
PLAYBACK_UNSUPPORTED_CODEC
```

Flutter:

```text
This video quality is not supported on this device.
```

Server:

```text
QUALITY_UNAVAILABLE
```

Flutter:

```text
1080p is unavailable. The highest available quality is 720p.
```

Do not expose internal yt-dlp stack traces.

---

# 57. Test Matrix

The production test suite must include:

```text
standard 360p/480p video
720p
1080p
1440p
2160p
60 FPS
HDR when available
AVC
VP9
AV1
separate video/audio
progressive video
long video
shorts
live stream
subtitles
```

Also test failure conditions:

```text
expired URL
403
410
network timeout
missing audio
missing requested quality
unsupported codec
PO token failure
JS runtime failure
yt-dlp version mismatch
```

---

# 58. 1080p Acceptance Test

The following MUST pass before declaring the feature complete.

```text
Given:
  a test video known to expose 1080p

When:
  GET /api/v1/videos/:id/playback?quality=1080p

Then:
  response = 200
  selectedQuality = 1080p
  qualityFallback = false

And:
  videoStreams contains:
    width >= 1920
    height >= 1080

And:
  audioStreams is not empty

And:
  selected video URL is reachable

And:
  selected audio URL is reachable

And:
  media_kit starts playback

And:
  audio is audible

And:
  video resolution is 1920x1080 or higher

And:
  seek works

And:
  pause/resume works
```

---

# 59. 4K Acceptance Test

For a known 2160p source:

```text
selectedQuality = 2160p
```

and:

```text
width >= 3840
height >= 2160
```

The device must also support the chosen codec/profile.

Do not fail the server because one phone cannot decode a particular 4K codec.

---

# 60. Direct Stream Validation

Before returning a direct stream:

```text
URL present
expiresAt present
mimeType known
codec known
height known
bitrate known when available
```

Optionally perform a lightweight range probe:

```text
Range: bytes=0-1
```

where appropriate.

Do not download the full object just to validate it.

---

# 61. Extractor Version Canary

Before deploying a new yt-dlp build:

```text
Build new Docker image
       |
       v
Run test corpus
       |
       +-- 1080p pass
       +-- 4K pass
       +-- audio pass
       +-- subtitles pass
       +-- direct URL validation pass
       |
       v
staging
       |
       v
canary production
```

Keep the previous image available for rollback.

---

# 62. Dependency Pinning Example

Create:

```text
versions.env
```

Example:

```env
YTDLP_VERSION=<tested-version>
YTDLP_EJS_VERSION=<tested-version>
DENO_VERSION=<tested-version>
FFMPEG_VERSION=<tested-version>
```

CI must refuse to build if one of these is missing.

---

# 63. CI Pipeline

Required stages:

```text
lint
typecheck
unit tests
integration tests
Docker build
extractor test corpus
1080p test
4K test
security scan
image publish
staging deployment
```

Do not deploy an extractor version that fails the 1080p acceptance test.

---

# 64. Observability Correlation

Every playback request needs:

```text
requestId
traceId
videoId
user/session hash
quality
strategy
extractor version
duration
result
failureCode
```

Pass the same correlation ID to:

```text
API
Redis
worker
yt-dlp log context
```

Do not pass secrets into log context.

---

# 65. Rate Limits

Start with conservative limits and tune from telemetry.

Separate:

```text
metadata lookup
playback resolution
download creation
download status
```

Download creation must have the strictest resource controls.

---

# 66. Resource Limits

Extractor worker:

```text
CPU limit
memory limit
process limit
time limit
```

Downloader worker:

```text
CPU limit
memory limit
disk quota
concurrent job limit
time limit
```

This protects the rest of the server.

---

# 67. MongoDB Indexes

Required examples:

```text
videos:
  unique(videoId)

download_jobs:
  unique(jobId)
  index(userId, createdAt)
  index(status, createdAt)

playback_events:
  index(videoId, createdAt)
  index(createdAt)
```

Do not create high-cardinality indexes without measuring usage.

---

# 68. API Security

Use:

```text
HTTPS
JWT/API authentication
rate limiting
request size limits
schema validation
security headers
CORS allowlist
```

Never expose:

```text
MongoDB
Redis
yt-dlp worker port
FFmpeg worker port
```

to the public Internet.

Only Nginx/API should be public.

---

# 69. Production Docker Rules

Containers:

```text
run as non-root
read-only root filesystem where possible
drop all capabilities
no-new-privileges
resource limits
private internal networks
```

Only mounted paths that need writes should be writable.

---

# 70. Recommended Network

```text
public network:
  nginx

private network:
  api
  extractor
  downloader
  redis
  mongodb
```

Nginx -> API only.

API -> Redis/Mongo only.

Workers -> Redis/Mongo + controlled upstream network.

Do not expose Redis/Mongo ports publicly.

---

# 71. Exact Implementation Phases

## Phase 1 — Backend skeleton

Implement:

```text
Fastify
TypeScript
MongoDB
Redis
Zod
Pino
Docker
```

## Phase 2 — yt-dlp runner

Implement:

```text
safe child process
timeout
stdout/stderr capture
JSON parser
version check
```

## Phase 3 — EJS runtime

Install:

```text
yt-dlp-ejs
Deno
```

and verify:

```text
yt-dlp
+
EJS
+
Deno
```

work together.

## Phase 4 — PO-token integration

Implement:

```text
PoTokenProvider
```

and verify required strategies.

## Phase 5 — format normalization

Convert raw yt-dlp result into:

```text
PlaybackManifest
```

## Phase 6 — quality selector

Implement:

```text
360
480
720
1080
1440
2160
```

selection.

## Phase 7 — Redis caching

Add:

```text
manifest cache
single-flight
TTL
refresh
```

## Phase 8 — Flutter integration

Replace direct local extraction with:

```text
Playback API
```

## Phase 9 — media_kit 1080p validation

Prove:

```text
1080p video
+
audio
=
working playback
```

## Phase 10 — 1440p/4K

Add:

```text
higher resolution
codec ranking
device capability
```

## Phase 11 — Download workers

Add:

```text
BullMQ
yt-dlp
FFmpeg
ffprobe
```

## Phase 12 — Production hardening

Add:

```text
metrics
alerts
rate limits
resource limits
canary
rollback
```

---

# 72. Cursor Agent Implementation Rules

The coding agent MUST follow these constraints:

```text
1. Do not modify Flutter player architecture until PlaybackManifest works.
2. Do not add arbitrary YouTube clients to fix a failing test.
3. Do not hard-code PO tokens.
4. Do not store signed media URLs in MongoDB permanently.
5. Do not use FFmpeg for normal playback.
6. Do not return raw yt-dlp JSON to Flutter.
7. Do not execute user-controlled shell commands.
8. Do not expose internal extractor errors to users.
9. Do not silently claim 1080p when actually playing 720p.
10. Do not use "latest" dependency versions in production containers.
11. Preserve backward compatibility of PlaybackManifest schema.
12. Write tests before changing extractor strategy.
```

---

# 73. Required Environment Variables

Example:

```env
NODE_ENV=production

PORT=3000

MONGO_URI=mongodb://mongo:27017/yxz_tube
REDIS_URL=redis://redis:6379

JWT_SECRET=<secret>

YTDLP_PATH=/usr/local/bin/yt-dlp
FFMPEG_PATH=/usr/local/bin/ffmpeg
FFPROBE_PATH=/usr/local/bin/ffprobe
DENO_PATH=/usr/local/bin/deno

YTDLP_CONFIG=/etc/yxz/yt-dlp.conf

PLAYBACK_CACHE_TTL_SECONDS=600
PLAYBACK_EXPIRY_SAFETY_SECONDS=60

EXTRACTION_TIMEOUT_MS=20000
DOWNLOAD_TIMEOUT_MS=1800000

MAX_CONCURRENT_EXTRACTIONS=4
MAX_CONCURRENT_DOWNLOADS=2
```

Secrets must come from a real secret-management mechanism in production.

Do not commit `.env`.

---

# 74. Development Commands

Example:

```bash
docker compose up -d mongo redis
```

Check binaries:

```bash
yt-dlp --version
deno --version
ffmpeg -version
ffprobe -version
```

Test EJS:

```bash
yt-dlp --verbose \
  --dump-single-json \
  --no-playlist \
  "VIDEO_URL"
```

Test formats:

```bash
yt-dlp --verbose \
  --list-formats \
  "VIDEO_URL"
```

Test a requested 1080p-capable selection:

```bash
yt-dlp --verbose \
  -f "bv*[height<=1080]+ba/b[height<=1080]" \
  --simulate \
  "VIDEO_URL"
```

The exact command used in production should be generated by the extractor adapter and validated against the pinned yt-dlp version.

---

# 75. Production Playback Selection Pseudocode

```ts
const candidates = normalize(rawExtraction);

const compatibleVideo = candidates.video
  .filter(isUsable)
  .filter(v => supportsCodec(device, v.codec))
  .sort(rankVideo);

const selectedVideo = chooseRequestedQuality(
  compatibleVideo,
  requestedQuality
);

if (!selectedVideo) {
  return failure("QUALITY_UNAVAILABLE");
}

const compatibleAudio = candidates.audio
  .filter(isUsable)
  .sort(rankAudio);

const selectedAudio = chooseAudio(
  compatibleAudio,
  preferences
);

if (!selectedAudio) {
  return failure("NO_AUDIO_STREAM");
}

return {
  schemaVersion: 1,
  videoStreams: [selectedVideo],
  audioStreams: [selectedAudio]
};
```

Do not put extractor-specific client logic in this code.

---

# 76. Why This Produces 1080p

The chain is:

```text
YouTube source has 1080p
        |
        v
yt-dlp successfully resolves current formats
        |
        v
EJS solves current JS challenge requirements
        |
        v
PO-token provider satisfies the selected GVS/client path
        |
        v
server receives 1080p video representation
        |
        +-- 1080p video URL
        |
        +-- audio URL
        |
        v
normalize
        |
        v
PlaybackManifest
        |
        v
Flutter/media_kit
        |
        v
1080p playback
```

The important point is:

```text
1080p is solved at the extraction/representation level.
```

It is not solved by adding "1080p" to the Flutter quality dropdown.

---

# 77. What Happens If YouTube Returns Only 360p

Do not fabricate 1080p.

The extraction result must be inspected.

If the source returns:

```text
360p only
```

then return:

```json
{
  "requestedQuality": "1080p",
  "selectedQuality": "360p",
  "qualityFallback": true,
  "fallbackReason": "UPSTREAM_DID_NOT_EXPOSE_1080P"
}
```

If an alternate extraction strategy can legitimately expose additional representations, try it.

If all supported strategies expose only 360p:

```text
return the highest legitimate available quality
```

---

# 78. What Happens If 1080p Exists But Returns 403

Treat this as a stream/access failure, not a quality failure.

Flow:

```text
1080p URL
   |
   v
403
   |
   v
invalidate cached playback
   |
   v
refresh extraction
   |
   v
retry once
```

If the refreshed URL also fails:

```text
try compatible fallback representation
```

Do not repeatedly retry the same expired URL.

---

# 79. What Happens If 1080p Is AV1 Only

Check device capabilities.

If AV1 is supported:

```text
play AV1 1080p
```

If not:

```text
try VP9 1080p
```

If not:

```text
try AVC 1080p
```

If no supported 1080p codec exists:

```text
fall back to next resolution
```

---

# 80. What Happens If Video and Audio Are Separate

This is normal.

The server returns:

```text
videoStream
audioStream
```

Flutter uses the pair.

Do not merge with FFmpeg before playback.

---

# 81. What Happens If Media Kit Cannot Handle the Exact Combination

First try:

```text
adaptive manifest
```

If the current media_kit/libmpv integration cannot reliably consume the selected A/V combination, do not add a server-side transcoding layer by default.

Record:

```text
PLAYBACK_PREPARE_FAILED
```

and evaluate Media3 migration as the playback-layer change.

The server's PlaybackManifest remains the stable contract.

---

# 82. Future Media3 Migration

Do not change the API contract later.

The same response can become:

```text
PlaybackManifest
   |
   +-- DASH
   +-- HLS
   +-- direct video/audio
```

Media3 can use DASH/HLS manifests directly and can adapt between representations based on bandwidth and device capabilities.

Therefore:

```text
Phase 1:
Node + yt-dlp + media_kit

Phase 2:
Node + yt-dlp + Media3

Phase 3:
Node + adaptive DASH/HLS + Media3
```

The backend does not need a redesign.

---

# 83. Legal and Distribution Review

This architecture is technically capable of resolving and playing third-party media streams, but technical capability is not permission.

Before public distribution, review:

```text
YouTube Terms
app store policies
copyright/downloading rules
licenses for yt-dlp, yt-dlp-ejs, FFmpeg and other dependencies
license compatibility of any alternate extractor
```

Do not represent YXZ Tube as an official YouTube client.

Do not permanently store or redistribute content without the necessary rights.

---

# 84. Definition of Done

The first production milestone is complete only when:

```text
[ ] Node API running
[ ] MongoDB running
[ ] Redis running
[ ] extractor worker running
[ ] yt-dlp pinned
[ ] yt-dlp-ejs installed
[ ] Deno installed and tested
[ ] PO-token strategy implemented where required
[ ] extraction timeout implemented
[ ] PlaybackManifest implemented
[ ] video stream normalization implemented
[ ] audio stream normalization implemented
[ ] codec ranking implemented
[ ] 1080p exact selection implemented
[ ] quality fallback implemented
[ ] signed URL expiry tracked
[ ] Redis playback cache implemented
[ ] single-flight implemented
[ ] 403/410 refresh implemented
[ ] Flutter consumes PlaybackManifest
[ ] media_kit plays 1080p V+A
[ ] 720p fallback works
[ ] 1440p tested where available
[ ] 2160p tested where available
[ ] no FFmpeg used during playback
[ ] download worker separated from API
[ ] FFmpeg merge works for downloads
[ ] ffprobe verifies downloads
[ ] security controls active
[ ] structured logs active
[ ] metrics active
[ ] staging test corpus passes
```

---

# 85. Final Architecture

```text
                         YXZ Tube
                            |
                    HTTPS / JSON API
                            |
                            v
                 +----------------------+
                 | Fastify API           |
                 |                       |
                 | /videos/:id           |
                 | /videos/:id/playback  |
                 | /downloads            |
                 +----------+------------+
                            |
                +-----------+-----------+
                |                       |
                v                       v
             MongoDB                  Redis
                |                       |
                |              +--------+--------+
                |              |                 |
                |              v                 v
                |        extraction lock    playback cache
                |
                v
        persistent application data


             Extraction Worker
                    |
                    v
                 yt-dlp
                    |
         +----------+----------+
         |                     |
         v                     v
     yt-dlp-ejs              Deno
         |
         v
    PO-token provider
         |
         v
   YouTube representations
         |
         v
   Normalization + ranking
         |
         v
    PlaybackManifest
         |
         v
        Flutter
         |
         v
    media_kit/libmpv
         |
         v
     1080p / 1440p / 2160p
```

Download path:

```text
Flutter
   |
   v
POST /downloads
   |
   v
BullMQ
   |
   v
Download Worker
   |
   +-- yt-dlp
   +-- video
   +-- audio
   |
   v
FFmpeg
   |
   v
ffprobe
   |
   v
atomic final file
```

---

# 86. Final Implementation Rule

Do not solve the current 1080p issue by adding more client strings.

Solve it through this exact boundary:

```text
YouTube
  |
  v
current supported extractor strategy
  |
  +-- EJS/runtime
  +-- PO-token provider when required
  |
  v
raw representations
  |
  v
normalization
  |
  v
quality + codec + audio pairing
  |
  v
PlaybackManifest
  |
  v
Flutter
  |
  v
media_kit
```

A successful 1080p implementation is:

```text
1080p video representation
+
compatible audio representation
+
valid non-expired URLs
+
successful media_kit playback
```

It is NOT:

```text
"1080p" selected in the UI
```

That distinction must remain true throughout the implementation.
