#!/bin/sh
set -eu
BASE=http://127.0.0.1:18765
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS --max-time 4 "$BASE/api/status" >/tmp/optiontrade-status.json 2>/dev/null; then break; fi
  sleep 2
done
grep -Eq '"orders_enabled"[[:space:]]*:[[:space:]]*false' /tmp/optiontrade-status.json
grep -Eq '"configured"[[:space:]]*:[[:space:]]*true' /tmp/optiontrade-status.json
curl -fsS --max-time 5 "$BASE/app.js" -o /tmp/optiontrade-script.js
grep -Fq 'mergeSavedHoldings' /tmp/optiontrade-script.js
catalog_degraded=0
for kind in future option; do
  http=$(curl -sS --max-time 35 -o "/tmp/optiontrade-master-$kind.json" -w '%{http_code}' "$BASE/api/instruments?kind=$kind" || true)
  if [ "$http" = 200 ] && grep -q '"items"' "/tmp/optiontrade-master-$kind.json"; then
    echo "OPTIONTRADE_${kind}_MASTER=AVAILABLE"
  else
    catalog_degraded=1
    echo "OPTIONTRADE_${kind}_MASTER=UNAVAILABLE_HTTP_${http}"
  fi
done
curl -fsS --max-time 18 "$BASE/api/quote?code=A016C000" -o /tmp/optiontrade-quote.json
python3 -c 'import json; q=json.load(open("/tmp/optiontrade-quote.json")); assert any(isinstance(q.get(k),(int,float)) and q[k]>0 for k in ("price","bid","ask")), "No real LS quote"'
if [ "$catalog_degraded" = 0 ]; then
  echo 'OPTIONTRADE_READONLY_VERIFICATION=PASS'
else
  echo 'OPTIONTRADE_READONLY_VERIFICATION=DEGRADED_MASTER_REAL_QUOTE_OK'
fi
