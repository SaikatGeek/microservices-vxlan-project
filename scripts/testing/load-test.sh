#!/bin/bash
# Sends many requests at once to this DC's gateway and counts the results.
# Run it INSIDE a node:
#
#   bash scripts/testing/load-test.sh 1                   200 requests, 20 at a time, /orders/
#   bash scripts/testing/load-test.sh 1 1000 50 users     1000 requests, 50 at a time, /users/
#
# /orders/ is the default because order-nginx runs in both DC1 and DC2,
# so the split between the two servers is visible at the end.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib.sh"

need_node "${1:-}"
REQUESTS="${2:-200}"
PARALLEL="${3:-20}"
ROUTE="${4:-orders}"

URL="http://$(gateway_ip "$NODE")/$ROUTE/"
OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT

echo "=== load test: $REQUESTS requests, $PARALLEL at a time → $URL ==="

start=$(date +%s%N)

# One line per request: "<http code> <server that answered>"
seq "$REQUESTS" | xargs -P "$PARALLEL" -I{} \
    curl -s -o /dev/null -m 10 -w '%{http_code} %header{x-served-by}\n' "$URL" > "$OUT"

end=$(date +%s%N)
ms=$(( (end - start) / 1000000 ))
[ "$ms" -gt 0 ] || ms=1

total=$(wc -l < "$OUT")
ok=$(grep -c '^200 ' "$OUT")
bad=$(( total - ok ))
rps=$(( total * 1000 / ms ))

echo
echo "  requests    $total"
echo "  success     $ok"
echo "  failed      $bad"
echo "  time        ${ms} ms"
echo "  per second  $rps"
echo
echo "  answered by:"
awk '$1 == 200 { print $2 }' "$OUT" | sort | uniq -c | sed 's/^/    /'

echo
if [ "$bad" -eq 0 ]; then
    pass "all $total requests succeeded"
else
    fail "$bad of $total requests failed"
fi

summary
