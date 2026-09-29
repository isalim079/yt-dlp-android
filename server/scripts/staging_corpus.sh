#!/usr/bin/env bash
# Minimal staging corpus smoke (requires running stack + ACCESS_TOKEN).
set -euo pipefail
BASE="${BASE_URL:-http://localhost:8080}"
TOKEN="${ACCESS_TOKEN:?set ACCESS_TOKEN}"
IDS=("dQw4w9WgXcQ" "jNQXAC9IVRw")
for id in "${IDS[@]}"; do
  echo "== playback $id =="
  curl -fsS -H "Authorization: Bearer $TOKEN" \
    "$BASE/api/v1/videos/$id/playback?quality=1080p" | head -c 200
  echo
done
echo OK
