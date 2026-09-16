#!/bin/bash
# Runs a command inside one EC2 node, from the lab container.
#
#   ./scripts/remote.sh 1 bash scripts/deployment/deploy-services.sh 1 status
#
# The node is found by its Name tag, so no IP has to be typed.
# The command runs inside ~/microservices-vxlan-project on that node.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/infrastructure/config.sh"

usage() {
    echo "usage: $0 <node 1|2|3> <command...>" >&2
    exit 1
}

NODE="${1:-}"
case "$NODE" in
    1) NAME="$NODE1_NAME" ;;
    2) NAME="$NODE2_NAME" ;;
    3) NAME="$NODE3_NAME" ;;
    *) usage ;;
esac
shift
[ $# -gt 0 ] || usage

IP=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=$NAME" \
              "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text 2>/dev/null || true)

if [ -z "$IP" ] || [ "$IP" = "None" ]; then
    echo "No running instance tagged $NAME. Run provision.sh first." >&2
    exit 1
fi

# printf %q quotes each word, so arguments with spaces survive the trip.
ssh -i "$KEY_FILE" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    -o ConnectTimeout=10 \
    "$SSH_USER@$IP" \
    "cd ~/microservices-vxlan-project && $(printf '%q ' "$@")"
