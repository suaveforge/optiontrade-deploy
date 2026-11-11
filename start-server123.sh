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
test -f "$LIVE_KEY" || { echo "LIVE_MARGIN_KEY_MISSING"; exit 3; }
test -r "$LIVE_KEY" || { echo "LIVE_MARGIN_KEY_UNREADABLE"; exit 3; }
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
  -v "$LIVE_KEY:/run/ls-live-credentials.json:ro" \
  -e LS_MODE=PAPER -e LS_LIVE_MARGIN_CREDENTIALS=/run/ls-live-credentials.json \
  "$IMG" >/dev/null
echo 'OPTIONTRADE_STARTED=127.0.0.1:18765'
