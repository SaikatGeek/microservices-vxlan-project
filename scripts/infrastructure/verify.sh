#!/bin/bash
# Checks that what provision.sh built really works. It creates nothing and
# deletes nothing. Run it from the lab container.
#
# No -e: one failed check must not stop the rest.
# For the same reason verify_node uses return, not exit. If one node is
# broken the other two still get checked, so you see the whole picture.
set -uo pipefail
source "$(dirname "$0")/config.sh"

PASS=0
FAIL=0
REMOTE_FAIL=0

# ssh_node <ip> <command>
# BatchMode=yes: fail at once instead of hanging on a password prompt.
ssh_node() {
    ssh -i "$KEY_FILE" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        -o ConnectTimeout=10 \
        -o BatchMode=yes \
        "$SSH_USER@$1" "$2"
}

# ok <what> <expected: yes|no> <command...>
#   expected=yes → the command should succeed
#   expected=no  → the command should fail (the SG is blocking it)
ok() {
    local what="$1" expect="$2"; shift 2
    local rc

    "$@" >/dev/null 2>&1 && rc=0 || rc=1

    if { [ "$expect" = "yes" ] && [ "$rc" -eq 0 ]; } ||
       { [ "$expect" = "no"  ] && [ "$rc" -ne 0 ]; }; then
        echo "  PASS  $what"
        PASS=$(( PASS + 1 ))
    else
        echo "  FAIL  $what"
        FAIL=$(( FAIL + 1 ))
    fi
}

# ============================================================
# verify_node <name tag> <private IP from config.sh>
# ============================================================
verify_node() {
    local NAME="$1" WANT_IP="$2"
    local INSTANCE_ID PUBLIC_IP PRIVATE_IP rc

    echo
    echo "============================================"
    echo " $NAME"
    echo "============================================"

    # --------------------------------------------------------
    # 1. Is the instance there and running?
    # --------------------------------------------------------
    INSTANCE_ID=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=$NAME" \
                  "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null)

    if [ "$INSTANCE_ID" = "None" ] || [ -z "$INSTANCE_ID" ]; then
        echo "  FAIL  no running instance tagged $NAME"
        echo "        run provision.sh first"
        FAIL=$(( FAIL + 1 ))
        return 1
    fi
    echo "  PASS  instance running  $INSTANCE_ID"
    PASS=$(( PASS + 1 ))

    PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
    PRIVATE_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
    echo "        public  $PUBLIC_IP"
    echo "        private $PRIVATE_IP"

    if [ "$PRIVATE_IP" != "$WANT_IP" ]; then
        echo "  FAIL  private IP $PRIVATE_IP is not $WANT_IP from config.sh"
        FAIL=$(( FAIL + 1 ))
    else
        echo "  PASS  private IP matches config.sh"
        PASS=$(( PASS + 1 ))
    fi

    # --------------------------------------------------------
    # 2. From here, outside the VPC — does the SG do its job?
    # --------------------------------------------------------
    echo
    echo "  --- from here (outside the VPC) ---"

    # The SG only allows ICMP from 10.0.0.0/16. A ping from outside
    # should fail. If it works, someone opened ICMP to 0.0.0.0/0.
    ok "ping public IP blocked (SG working)" no \
        ping -c 2 -W 3 "$PUBLIC_IP"

    # TCP 22 is open to 0.0.0.0/0, so this should work. Not using ok()
    # here because the result is needed: without SSH, none of the
    # inside checks can run.
    if ssh_node "$PUBLIC_IP" true 2>/dev/null; then
        echo "  PASS  tcp/22 reachable"
        PASS=$(( PASS + 1 ))
    else
        echo "  FAIL  tcp/22 reachable"
        FAIL=$(( FAIL + 1 ))
        echo "        ssh does not get in — skipping the checks inside $NAME" >&2
        return 1
    fi

    # --------------------------------------------------------
    # 3. Inside the instance
    #    The heredoc sends a whole script over stdin and 'bash -s' runs it.
    #    <<'REMOTE' is quoted, so nothing is expanded here; it arrives on
    #    the node exactly as written.
    # --------------------------------------------------------
    echo
    echo "  --- inside $NAME ---"

    ssh_node "$PUBLIC_IP" 'bash -s' <<'REMOTE'
set -u

p=0; f=0
chk() {
    local what="$1"; shift
    if "$@" >/dev/null 2>&1; then
        echo "  PASS  $what"; p=$(( p + 1 ))
    else
        echo "  FAIL  $what"; f=$(( f + 1 ))
    fi
}

# tool <command> <apt package>
# If a tool is missing, the network checks that use it would fail and look
# like a network problem. On a fresh Ubuntu 24.04 node, ping itself is
# missing. So check the tools first, then the network.
tool() {
    if command -v "$1" >/dev/null 2>&1; then
        echo "  PASS  $1"; p=$(( p + 1 ))
        return 0
    fi
    echo "  FAIL  $1 missing — sudo apt-get install -y $2"; f=$(( f + 1 ))
    return 1
}

# The Docker registry answers 401 without a token. That is its normal
# reply. 'curl -f' would count 401 as a failure, so no -f here: any HTTP
# answer means DNS, egress and TLS all worked. 000 means no answer.
https_ok() {
    local code
    code=$(curl -s -o /dev/null -w '%{http_code}' -m 10 https://registry-1.docker.io/v2/)
    [ "$code" != "000" ]
}

# the vxlan devices are created on this NIC
NIC=$(ip route get 1.1.1.1 | awk '{print $5; exit}')
MTU=$(cat "/sys/class/net/$NIC/mtu")
echo "  nic   $NIC"
echo "  mtu   $MTU"

# ---- tools ----
echo
echo "  --- tools ---"
HAVE_PING=0; HAVE_CURL=0
tool ping    iputils-ping && HAVE_PING=1
tool curl    curl         && HAVE_CURL=1
tool ip      iproute2
tool bridge  iproute2
tool tcpdump tcpdump
tool docker  docker.io

# ---- egress ----
# If a tool is missing, SKIP. Its FAIL was already counted above.
echo
echo "  --- egress ---"
if [ "$HAVE_PING" = 1 ]; then
    chk "ping 8.8.8.8 (igw + route table)" ping -c 3 -W 3 8.8.8.8
    chk "ping google.com (dns)"            ping -c 3 -W 3 google.com
else
    echo "  SKIP  ping 8.8.8.8, ping google.com — no ping"
fi
if [ "$HAVE_CURL" = 1 ]; then
    chk "https egress (docker pull will work)" https_ok
else
    echo "  SKIP  https egress — no curl"
fi

# ---- MTU probe ----
# -M do   = do not fragment
# -s 1472 = payload; + 8 ICMP header + 20 IP header = a 1500-byte packet
# If it fails, the path MTU is below 1500.
echo
echo "  --- path mtu ---"
if [ "$HAVE_PING" = 1 ]; then
    chk "1500-byte packet (underlay)"          ping -c 2 -W 3 -M do -s 1472 8.8.8.8
    chk "1450-byte packet (what vxlan leaves)" ping -c 2 -W 3 -M do -s 1422 8.8.8.8
else
    echo "  SKIP  path mtu — no ping"
fi

echo
echo "  inside: $p pass, $f fail"
exit "$f"
REMOTE

    # Read $? right after the heredoc; any other command would replace it.
    # rc was declared with local above and is only assigned here —
    # 'local rc=$?' would capture local's own result, not ssh's.
    rc=$?
    REMOTE_FAIL=$(( REMOTE_FAIL + rc ))

    return 0
}

# ============================================================
echo "=== verify: $VPC_NAME in $REGION ==="

verify_node "$NODE1_NAME" "$NODE1_IP"
verify_node "$NODE2_NAME" "$NODE2_IP"
verify_node "$NODE3_NAME" "$NODE3_IP"

# ============================================================
echo
echo "======================================"
echo " local checks : $PASS pass, $FAIL fail"
echo " remote checks: $REMOTE_FAIL fail  (0 = all passed)"
echo "======================================"

if [ "$FAIL" -eq 0 ] && [ "$REMOTE_FAIL" -eq 0 ]; then
    echo "all good"
    exit 0
fi
exit 1
