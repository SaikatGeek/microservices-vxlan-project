#!/bin/bash
# Copies this whole project folder to all three nodes, and installs the
# packages a fresh Ubuntu node does not have. Run it from the lab container.
#
#   bash scripts/infrastructure/push-project.sh             files + packages
#   bash scripts/infrastructure/push-project.sh --no-tools  files only
#
# Why: overlay-up.sh and the service deploy run INSIDE the nodes, and they
# need the scripts, Dockerfiles, configs and data there.
#
# The folder lands at ~/microservices-vxlan-project on each node.
# Running it again replaces the old copy.
#
# No -e: one unreachable node must not stop the other two.
set -uo pipefail
source "$(dirname "$0")/config.sh"

# the project folder: two levels up from scripts/infrastructure/
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT="$(basename "$ROOT")"
PKGS="iputils-ping tcpdump curl docker.io"

WITH_TOOLS=1
case "${1:-}" in
    "")         ;;
    --no-tools) WITH_TOOLS=0 ;;
    *)          echo "usage: $0 [--no-tools]" >&2; exit 1 ;;
esac

FAIL=0

SSH_OPTS=(-i "$KEY_FILE"
          -o StrictHostKeyChecking=no
          -o UserKnownHostsFile=/dev/null
          -o LogLevel=ERROR
          -o ConnectTimeout=10)

# public_ip <name tag>  →  prints the IP, or nothing
# --output text returns the word 'None' when nothing matched.
public_ip() {
    local ip
    ip=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=$1" \
                  "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text 2>/dev/null)
    [ "$ip" = "None" ] && ip=""
    echo "$ip"
}

echo "=== push $PROJECT to nodes: $VPC_NAME in $REGION ==="

for NAME in "$NODE1_NAME" "$NODE2_NAME" "$NODE3_NAME"; do
    echo
    echo "--- $NAME ---"

    IP=$(public_ip "$NAME")
    if [ -z "$IP" ]; then
        echo "  no running instance — run provision.sh first" >&2
        FAIL=$(( FAIL + 1 ))
        continue
    fi
    echo "  public    $IP"

    # tar over ssh: one connection for the whole folder.
    # On the node: remove the old copy, unpack the new one, strip any
    # Windows line endings, and make every script executable.
    if ! tar -C "$(dirname "$ROOT")" -czf - "$PROJECT" | \
         ssh "${SSH_OPTS[@]}" "$SSH_USER@$IP" \
            "rm -rf ~/$PROJECT && tar -xzf - -C ~ \
             && find ~/$PROJECT -name '*.sh' -exec sed -i 's/\r\$//' {} + \
             && find ~/$PROJECT -name '*.sh' -exec chmod +x {} +"; then
        echo "  copy FAILED" >&2
        FAIL=$(( FAIL + 1 ))
        continue
    fi
    echo "  copied    ~/$PROJECT"

    if [ "$WITH_TOOLS" = 1 ]; then
        # apt-get install -y is fine to run twice
        if ssh "${SSH_OPTS[@]}" "$SSH_USER@$IP" \
             "sudo apt-get update -qq && sudo apt-get install -y -qq $PKGS && sudo usermod -aG docker $SSH_USER" >/dev/null; then
            echo "  installed $PKGS"
        else
            echo "  package install FAILED" >&2
            FAIL=$(( FAIL + 1 ))
        fi
    fi
done

echo
echo "======================================"
if [ "$FAIL" -eq 0 ]; then
    echo " All three nodes are ready."
    echo " Next, inside each node, with its own number:"
    echo "   cd ~/$PROJECT && bash scripts/infrastructure/overlay-up.sh 1"
    echo "======================================"
    exit 0
fi
echo " $FAIL problem(s) — see the lines above"
echo "======================================"
exit 1
