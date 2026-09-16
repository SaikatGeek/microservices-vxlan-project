#!/bin/bash
# Checks every container of one DC. Run it INSIDE the node that owns the DC,
# after deploy-services.sh:
#
#   bash scripts/testing/test-services.sh 1
#
# For each container: it is running, it is healthy (the stubs have no
# health check), it answers HTTP on its own IP and port, and the answer
# carries the right DC name.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib.sh"

need_node "${1:-}"
DEPLOY="$HERE/../deployment/deploy-services.sh"

is_running() {
    [ "$($DOCKER inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]
}

health_of() {
    $DOCKER inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$1" 2>/dev/null
}

# A fresh container reports "starting" until its first health check.
# Wait up to 40 seconds for it to settle.
wait_healthy() {
    local i state
    for i in $(seq 1 20); do
        state=$(health_of "$1")
        [ "$state" = "healthy" ] && return 0
        [ "$state" = "unhealthy" ] && return 1
        sleep 2
    done
    return 1
}

http_ok() {
    [ "$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://$1")" = "200" ]
}

answers_with() {
    curl -s -m 5 "http://$1" | grep -q "$2"
}

echo "=== services: DC$NODE ==="

while read -r svc ip; do
    [ -n "$svc" ] || continue
    name="dc${NODE}-$svc"
    port=$(port_of "$svc")

    echo
    echo "  --- $name  $ip:$port ---"

    if ! is_running "$name"; then
        fail "$name is running"
        continue
    fi
    pass "$name is running"

    check "answers HTTP 200 on $ip:$port" http_ok "$ip:$port/"

    case "$svc" in
        *-stub)
            ;;
        *)
            check "health check says healthy" wait_healthy "$name"
            check "/health says ok"           answers_with "$ip:$port/health" "ok"
            check "reply names DC$NODE"       answers_with "$ip:$port/" "DC$NODE"
            ;;
    esac
done < <(bash "$DEPLOY" "$NODE" list)

summary
