#!/bin/sh
set -eu
ROOT=/home/futures-options-trader
CLI=/home/ggul-docker/bin/docker
SOCK=unix:///home/ggul-docker/run/docker.sock
IMG=sf-optiontrade:latest
NAME=sf-optiontrade
for f in server.py app.js index.html Dockerfile requirements.txt; do
  test -s "$ROOT/app/$f" || { echo "Missing app/$f"; exit 2; }
done
test -s "$ROOT/secrets/ls-paper.env" || { echo "Missing LS PAPER env"; exit 2; }
test "$(stat -c '%a' "$ROOT/secrets/ls-paper.env")" = 600 || { echo "Secret env must be 600"; exit 2; }
# LIVE key is mounted read-only solely for public product-class margin data.
# Never enable orders or switch the existing market-data bridge from PAPER.
LIVE_KEY=/root/market-indicator-card/secrets/ls_openapi.local.json
# The self-hosted runner and Docker daemon have different filesystem views.
# Test the host secret from inside Docker, not from the runner namespace.
# Original LIVE secret may be owner-only (0600). Stage a separate owner-only
# read-only runtime copy for non-root container UID 11001; never relax original.
"$CLI" -H "$SOCK" run --rm --network none --read-only \
  -v "$LIVE_KEY:/source/live.json:ro" \
  -v "$ROOT/secrets:/destination:rw" \
  alpine:3.20 sh -c 'install -m 0400 -o 11001 -g 11001 /source/live.json /destination/ls-live-margin.json'
# Keep only previously fetched official contract codes/names across container restarts.
# No credentials or account data are ever written to this mount.
"$CLI" -H "$SOCK" run --rm --network none \
  -v "$ROOT/cache:/catalog-cache:rw" \
  alpine:3.20 sh -c 'install -d -m 0700 -o 11001 -g 11001 /catalog-cache'
"$CLI" -H "$SOCK" build -t "$IMG" "$ROOT/app"
if "$CLI" -H "$SOCK" container inspect "$NAME" >/dev/null 2>&1; then
  "$CLI" -H "$SOCK" rm -f "$NAME" >/dev/null
fi
"$CLI" -H "$SOCK" run -d --name "$NAME" --restart unless-stopped \
  --memory 512m --pids-limit 128 --read-only \
  --tmpfs /tmp:rw,nosuid,nodev,size=32m --cap-drop ALL \
  --security-opt no-new-privileges:true \
  -p 127.0.0.1:18765:8765 \
  --env-file "$ROOT/secrets/ls-paper.env" \
  -v "$ROOT/secrets/ls-live-margin.json:/run/ls-live-credentials.json:ro" \
  -v "$ROOT/cache:/var/lib/optiontrade:rw" \
  -e LS_CATALOG_CACHE_DIR=/var/lib/optiontrade \
  -e LS_MODE=PAPER -e LS_WS_URL=wss://openapi.ls-sec.co.kr:29443/websocket \
  -e LS_LIVE_MARGIN_CREDENTIALS=/run/ls-live-credentials.json \
  "$IMG" >/dev/null
echo 'OPTIONTRADE_STARTED=127.0.0.1:18765'
