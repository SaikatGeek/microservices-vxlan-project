#!/bin/bash
# Shows the gateway moving to the backup when a service dies, and coming
# back when it returns. Run it INSIDE node 1 (it uses DC1's gateway and
# DC1's user-nginx, with DC3's user-nginx as the backup):
#
#   bash scripts/testing/test-failover.sh
#
# It stops dc1-user-nginx for a moment and starts it again at the end.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib.sh"

GW=$(gateway_ip 1)
URL="http://$GW/users/"
VICTIM="dc1-user-nginx"
PRIMARY="10.20.2.10:8080"
BACKUP="10.40.2.10:8080"

if ! $DOCKER inspect "$VICTIM" >/dev/null 2>&1; then
    echo "$VICTIM not found. Run this on node 1, after deploying DC1." >&2
    exit 2
fi

# served_by  —  the X-Served-By header of one request
served_by() {
    curl -s -o /dev/null -m 10 -w '%header{x-served-by}' "$URL"
}

# dc_of_reply  —  which DC the reply says it came from
dc_of_reply() {
    curl -s -m 10 "$URL" | grep -o '"datacenter": *"DC[0-9]"' | grep -o 'DC[0-9]'
}

echo "=== failover: $URL ==="

# ------------------------------------------------------------
echo
echo "  1. normal — DC1 answers"
s=$(served_by); d=$(dc_of_reply)
echo "     served by: $s   reply from: $d"
if [ "$s" = "$PRIMARY" ] && [ "$d" = "DC1" ]; then
    pass "primary in DC1 answers"
else
    fail "primary in DC1 answers"
fi

# ------------------------------------------------------------
echo
echo "  2. stop $VICTIM"
$DOCKER stop "$VICTIM" >/dev/null
sleep 2

s=$(served_by); d=$(dc_of_reply)
echo "     served by: $s   reply from: $d"
# When it tries DC1 first and then moves on, the header lists both,
# e.g. "10.20.2.10:8080, 10.40.2.10:8080". What matters is who answered last.
case "$s" in
    *"$BACKUP")
        if [ "$d" = "DC3" ]; then pass "backup in DC3 took over"; else fail "backup in DC3 took over"; fi
        ;;
    *)
        fail "backup in DC3 took over"
        ;;
esac

# ------------------------------------------------------------
echo
echo "  3. start $VICTIM again"
$DOCKER start "$VICTIM" >/dev/null

back=no
for i in $(seq 1 20); do
    sleep 2
    if [ "$(served_by)" = "$PRIMARY" ]; then
        back=yes
        break
    fi
done
echo "     served by: $(served_by)"
if [ "$back" = yes ]; then
    pass "traffic went back to DC1"
else
    fail "traffic went back to DC1 (within 40s)"
fi

summary
