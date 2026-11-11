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
  -e LS_MODE=PAPER "$IMG" >/dev/null
echo 'OPTIONTRADE_STARTED=127.0.0.1:18765'
