#!/bin/bash
# Takes down what overlay-up.sh built. Run it inside each node, with that
# node's own number:
#
#   bash scripts/infrastructure/overlay-down.sh 1
#
# No -e, same as teardown.sh: "already gone" is a success here, not a failure.
#
# The docker network is left alone. Containers may still be using it, and
# removing it means removing the DC. The command is printed at the end.
set -uo pipefail
source "$(dirname "$0")/config.sh"

NODE="${1:-}"
case "$NODE" in
    1|2|3) ;;
    *)
        echo "usage: $0 <node number: 1, 2 or 3>" >&2
        exit 1
        ;;
esac

for dc in 1 2 3; do
    v="DC${dc}_VNI";    VNI="${!v}"
    b="DC${dc}_BRIDGE"; BR="${!b}"
    n="DC${dc}_NET";    NET="${!n}"
    LINK="vxlan$VNI"

    if ip link show "$LINK" >/dev/null 2>&1; then
        sudo ip link del "$LINK"
        echo "  deleted  $LINK"
    else
        echo "  gone     $LINK"
    fi

    # The owner's bridge belongs to docker; touching it confuses docker.
    # The other two were made by hand, so they are removed by hand.
    if [ "$dc" != "$NODE" ]; then
        if ip link show "$BR" >/dev/null 2>&1; then
            sudo ip link del "$BR"
            echo "  deleted  $BR"
        else
            echo "  gone     $BR"
        fi
    else
        echo "  kept     $BR  (owned by docker, part of $NET)"
    fi

    for dir in -i -o; do
        while sudo iptables -C DOCKER-USER "$dir" "$BR" -j ACCEPT 2>/dev/null; do
            sudo iptables -D DOCKER-USER "$dir" "$BR" -j ACCEPT
        done
    done
done

v="DC${NODE}_NET"
echo
echo "To remove the docker network too (stop its containers first):"
echo "  docker network rm ${!v}"
