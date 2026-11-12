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
grep -Eq '"(price|bid|ask)"[[:space:]]*:[[:space:]]*[1-9][0-9]*(\.[0-9]+)?' /tmp/optiontrade-quote.json
# Verify the actual container override, not just server.py's compiled default.
# This makes a wrong websocket URL fail deployment smoke immediately.
CLI=/home/ggul-docker/bin/docker
SOCK=unix:///home/ggul-docker/run/docker.sock
"$CLI" -H "$SOCK" exec -i sf-optiontrade python - <<'PY'
import asyncio, json, os, time
import websockets

broker_url = os.environ.get("LS_WS_URL", "")
assert broker_url.endswith("/websocket"), (
    "WRONG_LS_DERIVATIVES_WS_PATH: " + broker_url.split("://")[-1].split("/")[0])
print("LS_DERIVATIVES_WS_PATH=VERIFIED", flush=True)

async def check_broker_port(name, port):
    uri = f"wss://openapi.ls-sec.co.kr:{port}/websocket"
    try:
        async with websockets.connect(uri, open_timeout=7, close_timeout=2) as conn:
            print(f"LS_BROKER_{name}_WSS=HANDSHAKE_OK", flush=True)
    except Exception as exc:
        # Only classification; never include tokens, secrets or credentials.
        print(f"LS_BROKER_{name}_WSS={type(exc).__name__}", flush=True)

async def probe():
    await asyncio.gather(check_broker_port("PAPER", 29443), check_broker_port("LIVE", 9443))
    uri = "ws://127.0.0.1:8765/ws/market?code=A016C000&kind=future"
    opened = False
    deadline = time.monotonic() + 14
    async with websockets.connect(uri, open_timeout=10, close_timeout=2) as connection:
        while time.monotonic() < deadline:
            try:
                payload = json.loads(await asyncio.wait_for(connection.recv(), timeout=min(8, max(.1, deadline-time.monotonic()))))
            except asyncio.TimeoutError:
                if opened:
                    print("LS_DERIVATIVES_WS_DATA=QUIET_SUBSCRIPTION", flush=True)
                    return
                continue
            kind = payload.get("type")
            if kind == "subscribed":
                opened = True
                print("LS_DERIVATIVES_WS_SUBSCRIPTION=OPEN", flush=True)
            elif kind in ("confirmed", "book", "tick"):
                print("LS_DERIVATIVES_WS_LIVE_FRAME=YES", flush=True)
                return
            elif kind in ("error", "fallback"):
                print("LS_DERIVATIVES_WS_STATUS=DEGRADED_REST_ACTIVE_" + str(kind).upper(), flush=True)
                return
            elif kind == "warning" and "구독 거절" in str(payload.get("message", "")):
                print("LS_DERIVATIVES_WS_STATUS=SUBSCRIPTION_REJECTED_REST_ACTIVE", flush=True)
                return
    if not opened:
        # Broker WSS is an external dependency. Keep REST healthy and report degradation.
        print("LS_DERIVATIVES_WS_STATUS=UPSTREAM_TIMEOUT_REST_ACTIVE", flush=True)
        return
    print("LS_DERIVATIVES_WS_DATA=QUIET_SUBSCRIPTION", flush=True)

asyncio.run(probe())
PY
if [ "$catalog_degraded" = 0 ]; then
  echo 'OPTIONTRADE_READONLY_VERIFICATION=PASS'
else
  echo 'OPTIONTRADE_READONLY_VERIFICATION=DEGRADED_MASTER_REAL_QUOTE_OK'
fi
