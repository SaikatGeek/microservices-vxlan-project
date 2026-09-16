#!/bin/bash
# Builds this node's whole overlay. Run it once on each node, INSIDE the
# EC2 node, with that node's own number:
#
#   on dc1-node:  bash scripts/infrastructure/overlay-up.sh 1
#   on dc2-node:  bash scripts/infrastructure/overlay-up.sh 2
#   on dc3-node:  bash scripts/infrastructure/overlay-up.sh 3
#
# For each of the three DCs it:
#   1. makes the bridge — docker makes it if this node owns the DC,
#      otherwise it is made by hand
#   2. makes the vxlan device and joins it to the bridge
#   3. writes the other two nodes into the fdb (a VPC has no multicast)
#   4. allows the bridge through DOCKER-USER
#
# Once for the node: turns on ip_forward, or nothing crosses from one
# bridge to another.
set -euo pipefail
source "$(dirname "$0")/config.sh"

NODE="${1:-}"
case "$NODE" in
    1|2|3) ;;
    *)
        echo "usage: $0 <node number: 1, 2 or 3>" >&2
        echo "  give the number of THIS host:" >&2
        echo "  $NODE1_NAME=1  $NODE2_NAME=2  $NODE3_NAME=3" >&2
        exit 1
        ;;
esac

ALL_IPS=("$NODE1_IP" "$NODE2_IP" "$NODE3_IP")
MY_IP="${ALL_IPS[$(( NODE - 1 ))]}"

# ============================================================
# once per node
# ============================================================

# The NIC name changes between instance families — never hard-code it.
NIC=$(ip route get 1.1.1.1 | awk '{print $5; exit}')
if [ -z "$NIC" ]; then
    echo "Could not find the NIC name. Try 'ip route get 1.1.1.1' by hand." >&2
    exit 1
fi

# In the docker group: no sudo needed. Not yet: use sudo.
if docker info >/dev/null 2>&1; then
    DOCKER="docker"
else
    DOCKER="sudo docker"
fi

if ! $DOCKER info >/dev/null 2>&1; then
    echo "Docker is not running. Install it first: sudo apt-get install -y docker.io" >&2
    exit 1
fi

# By default Linux does not pass packets from one interface to another.
# Without this, br-dc1 → br-dc3 does not happen, and no error says so.
sudo sysctl -qw net.ipv4.ip_forward=1
echo "ip_forward  on"

# Docker creates the DOCKER-USER chain. Without it the rules below
# cannot be added.
if ! sudo iptables -L DOCKER-USER -n >/dev/null 2>&1; then
    echo "DOCKER-USER chain is missing — docker did not start properly" >&2
    exit 1
fi

echo "node        $NODE  ($MY_IP)"
echo "nic         $NIC"
echo

# ============================================================
# allow_bridge <bridge>
#   Docker's FORWARD policy is DROP, and our bridges are not on its list,
#   so their packets are dropped silently. Both directions need a rule,
#   or the ping goes out and the reply never comes back.
#   -C checks first, so running this again does not stack up rules.
# ============================================================
allow_bridge() {
    local br="$1" dir
    for dir in -i -o; do
        if ! sudo iptables -C DOCKER-USER "$dir" "$br" -j ACCEPT 2>/dev/null; then
            sudo iptables -I DOCKER-USER "$dir" "$br" -j ACCEPT
        fi
    done
}

# ============================================================
# setup_dc <dc number>
# ============================================================
setup_dc() {
    local dc="$1"
    local v b g c n

    # Build the names DC1_VNI, DC1_BRIDGE ... and read them with ${!v}
    v="DC${dc}_VNI";    local VNI="${!v}"
    b="DC${dc}_BRIDGE"; local BR="${!b}"
    g="DC${dc}_GW";     local GW="${!g}"
    c="DC${dc}_CIDR";   local CIDR="${!c}"
    n="DC${dc}_NET";    local NET="${!n}"

    local LINK="vxlan$VNI"
    local PREFIX="${CIDR#*/}"          # 10.20.0.0/16 → 16
    local i

    echo "--- dc$dc  vni $VNI  $CIDR ---"

    # --------------------------------------------------------
    # 1. bridge
    # --------------------------------------------------------
    if [ "$dc" = "$NODE" ]; then
        # This node owns the DC. Its containers run here, so docker makes
        # the network. Only the owner holds the gateway address (.1).
        if $DOCKER network inspect "$NET" >/dev/null 2>&1; then
            echo "  network reused  $NET"
        else
            $DOCKER network create \
                --subnet "$CIDR" \
                --gateway "$GW" \
                -o com.docker.network.bridge.name="$BR" \
                -o com.docker.network.driver.mtu="$OVERLAY_MTU" \
                "$NET" >/dev/null
            echo "  network created $NET  gw $GW"
        fi
    else
        # Not the owner. No containers of this DC run here, so no docker
        # network. The bridge is still needed: giving it an address makes
        # the kernel add a route for $CIDR, and that route is what carries
        # traffic from one DC to another.
        local HOST_IP="${GW%.*}.$(( NON_OWNER_HOST_OFFSET + NODE ))"

        if ip link show "$BR" >/dev/null 2>&1; then
            echo "  bridge reused   $BR"
        else
            sudo ip link add "$BR" type bridge
            echo "  bridge created  $BR"
        fi

        # The same address in two places confuses ARP: once the tunnel is
        # up, the three bridges are one broadcast domain. So the owner has
        # .1 and this node has .1(10+node).
        if ! ip addr show dev "$BR" | grep -q "$HOST_IP/"; then
            sudo ip addr add "$HOST_IP/$PREFIX" dev "$BR"
        fi
        sudo ip link set "$BR" mtu "$OVERLAY_MTU"
        echo "  bridge ip       $HOST_IP/$PREFIX"
    fi

    sudo ip link set "$BR" up

    # --------------------------------------------------------
    # 2. vxlan device
    #    Always delete and recreate, never reuse. A tunnel pointing at a
    #    dead peer is worse than half a second of downtime, and a new lab
    #    means new IPs. Deleting it also clears its fdb.
    # --------------------------------------------------------
    if ip link show "$LINK" >/dev/null 2>&1; then
        sudo ip link del "$LINK"
    fi

    # No 'remote': three hosts means two peers, and 'remote' takes only one.
    sudo ip link add "$LINK" type vxlan \
        id "$VNI" \
        dstport "$VXLAN_PORT" \
        dev "$NIC"

    sudo ip link set "$LINK" mtu "$OVERLAY_MTU"
    sudo ip link set "$LINK" master "$BR"     # this is the line that joins them
    sudo ip link set "$LINK" up
    echo "  link            $LINK  mtu $OVERLAY_MTU  dev $NIC"

    # --------------------------------------------------------
    # 3. peers
    #    A VPC has no multicast, so 'group 239.x' silently does nothing.
    #    A switch looking for an unknown address asks everyone; over a
    #    tunnel, "everyone" has to be listed by hand.
    #    00:00:00:00:00:00 means "for anyone I do not know yet, send here".
    # --------------------------------------------------------
    for i in 0 1 2; do
        if [ "$i" -ne "$(( NODE - 1 ))" ]; then
            sudo bridge fdb append 00:00:00:00:00:00 \
                dev "$LINK" dst "${ALL_IPS[$i]}"
            echo "  peer            ${ALL_IPS[$i]}"
        fi
    done

    # --------------------------------------------------------
    # 4. firewall
    # --------------------------------------------------------
    allow_bridge "$BR"
    echo "  docker-user     $BR in+out accept"
    echo
}

setup_dc 1
setup_dc 2
setup_dc 3

# ============================================================
echo "======================================"
ip -br addr show type bridge
echo
echo "peers per tunnel:"
bridge fdb show | grep '^00:00:00:00:00:00' || echo "  (none — something is wrong)"
echo "======================================"
echo
echo "After all three nodes are done, from node 1:"
echo "  ping -c 2 $DC2_GW        # DC2 gateway, on node 2"
echo "  ping -c 2 $DC3_GW        # DC3 gateway, on node 3"
