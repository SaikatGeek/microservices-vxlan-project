#!/bin/bash
# Checks traffic between datacenters. Run it INSIDE a node, after all three
# DCs are deployed:
#
#   bash scripts/testing/test-cross-dc.sh 1
#
# Part 1: every route through this DC's gateway. Each line shows which
#         server really answered (X-Served-By) and which DC it is in.
# Part 2: a container in this DC talks straight to containers in the
#         other two DCs — ping and HTTP, over the VXLAN tunnels.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib.sh"

need_node "${1:-}"

GW=$(gateway_ip "$NODE")
SRC="dc${NODE}-gateway-nginx"

HDR=$(mktemp)
BODY=$(mktemp)
trap 'rm -f "$HDR" "$BODY"' EXIT

echo "=== cross-DC: from DC$NODE ==="

# ------------------------------------------------------------
# Part 1: through the gateway
# ------------------------------------------------------------
echo
echo "  --- through the DC$NODE gateway ($GW) ---"

for route in users catalog orders payments notify analytics discovery; do
    code=$(curl -s -m 10 -D "$HDR" -o "$BODY" -w '%{http_code}' "http://$GW/$route/")
    served=$(grep -i '^x-served-by:' "$HDR" | tr -d '\r' | cut -d' ' -f2-)
    dc=$(grep -o '"datacenter": *"DC[0-9]"' "$BODY" | grep -o 'DC[0-9]')

    if [ "$code" = "200" ]; then
        pass "/$route/  →  $served  ($dc)"
    else
        fail "/$route/  →  HTTP $code"
    fi
done

# ------------------------------------------------------------
# Part 2: container to container
# ------------------------------------------------------------
# Two targets in each of the other DCs: "ip:port DCx"
case "$NODE" in
    1) TARGETS="10.30.2.10:8083 DC2  10.40.2.15:8085 DC3"; PINGS="10.30.1.10 10.40.1.10" ;;
    2) TARGETS="10.20.2.10:8080 DC1  10.40.2.16:8500 DC3"; PINGS="10.20.1.10 10.40.1.10" ;;
    3) TARGETS="10.20.2.11:8081 DC1  10.30.2.11:8084 DC2"; PINGS="10.20.1.10 10.30.1.10" ;;
esac

from_container() {
    $DOCKER exec "$SRC" wget -q -T 5 -O - "http://$1/" 2>/dev/null | grep -q "$2"
}

echo
echo "  --- from container $SRC ---"

for ip in $PINGS; do
    check "ping $ip" $DOCKER exec "$SRC" ping -c 2 -W 2 "$ip"
done

set -- $TARGETS
while [ $# -ge 2 ]; do
    check "HTTP to $1 answers from $2" from_container "$1" "$2"
    shift 2
done

summary
