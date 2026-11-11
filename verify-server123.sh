#!/bin/sh
set -eu
BASE=http://127.0.0.1:18765
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS --max-time 4 "$BASE/api/status" >/tmp/optiontrade-status.json 2>/dev/null; then break; fi
  sleep 2
done
grep -Eq '"orders_enabled"[[:space:]]*:[[:space:]]*false' /tmp/optiontrade-status.json
grep -Eq '"configured"[[:space:]]*:[[:space:]]*true' /tmp/optiontrade-status.json
for kind in future option; do
  curl -fsS --max-time 35 "$BASE/api/instruments?kind=$kind" | grep -q '"items"'
done
curl -fsS --max-time 35 "$BASE/api/quote?code=A016C000" | grep -q '"price"'
echo 'OPTIONTRADE_READONLY_VERIFICATION=PASS'
