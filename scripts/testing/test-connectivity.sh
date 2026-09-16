#!/bin/bash
# Checks the overlay network on one node. Run it INSIDE the node, after
# overlay-up.sh, with that node's number:
#
#   bash scripts/testing/test-connectivity.sh 1
#
# No containers are needed. If this passes, the tunnels, the fdb peers,
# ip_forward and the firewall rules are all in place.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../infrastructure/config.sh"
source "$HERE/lib.sh"

need_node "${1:-}"

echo "=== connectivity: node $NODE ==="

check "ip_forward is on" \
    test "$(sysctl -n net.ipv4.ip_forward)" = 1

for dc in 1 2 3; do
    v="DC${dc}_VNI";    VNI="${!v}"
    b="DC${dc}_BRIDGE"; BR="${!b}"
    g="DC${dc}_GW";     GW="${!g}"
    LINK="vxlan$VNI"

    echo
    echo "  --- DC$dc  (vni $VNI, $BR) ---"

    check "$LINK is up" \
        sh -c "ip link show $LINK | grep -q '[<,]UP[,>]'"
    check "$LINK is joined to $BR" \
        sh -c "ip link show $LINK | grep -q 'master $BR'"
    check "$LINK mtu is $OVERLAY_MTU" \
        sh -c "ip link show $LINK | grep -q 'mtu $OVERLAY_MTU'"

    peers=$(bridge fdb show dev "$LINK" 2>/dev/null | grep -c '^00:00:00:00:00:00')
    if [ "$peers" = 2 ]; then
        pass "$LINK has 2 peers in the fdb"
    else
        fail "$LINK has $peers peers in the fdb (expected 2)"
    fi

    check "DOCKER-USER lets $BR in and out" \
        sh -c "sudo iptables -C DOCKER-USER -i $BR -j ACCEPT && sudo iptables -C DOCKER-USER -o $BR -j ACCEPT"

    # The gateway of another DC lives on another node, so this ping
    # has to cross the tunnel.
    if [ "$dc" != "$NODE" ]; then
        check "ping DC$dc gateway $GW (across the tunnel)" \
            ping -c 2 -W 2 "$GW"
    fi
done

summary
