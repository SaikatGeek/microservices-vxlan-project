#!/bin/bash
# Manages one datacenter's containers. Run it ON the node that owns the DC.
#
#   ./deploy-services.sh 1 build     build the images this DC needs
#   ./deploy-services.sh 1 deploy    build the images, then (re)start every container
#   ./deploy-services.sh 1 stop      stop the containers, keep them
#   ./deploy-services.sh 1 start     start stopped containers again
#   ./deploy-services.sh 1 remove    delete the containers
#   ./deploy-services.sh 1 status    state and health of each container
#   ./deploy-services.sh 1 logs      last lines of each container's log
#   ./deploy-services.sh 1 list      service and IP, one per line (used by the tests)
#
# Node 1 owns DC1, node 2 owns DC2, node 3 owns DC3.
# The docker network (dc1-net and so on) is made by overlay-up.sh on the
# owning node, so run that first.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DC="${1:-}"
ACTION="${2:-deploy}"

usage() {
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 1
}

case "$DC" in
    1|2|3) ;;
    *)     usage ;;
esac

# The docker group only takes effect after logging in again.
# Until then, fall back to sudo.
if docker info >/dev/null 2>&1; then
    DOCKER="docker"
else
    DOCKER="sudo docker"
fi

NET="dc${DC}-net"

# One line per container:
#   service          ip           memory  reserved  cpus
#
# The *-stub lines are the data tier. They are plain nginx standing in for a
# database and a cache, so the tier has real addresses to test against.
case "$DC" in
1) PLAN="
gateway-nginx    10.20.1.10   256m    128m      0.50
user-nginx       10.20.2.10   128m    64m       0.25
catalog-nginx    10.20.2.11   128m    64m       0.25
order-nginx      10.20.2.12   128m    64m       0.25
db-stub          10.20.3.10   64m     32m       0.10
cache-stub       10.20.3.11   64m     32m       0.10" ;;
2) PLAN="
gateway-nginx    10.30.1.10   256m    128m      0.50
payment-nginx    10.30.2.10   128m    64m       0.25
notify-nginx     10.30.2.11   128m    64m       0.25
order-nginx      10.30.2.12   128m    64m       0.25
db-stub          10.30.3.10   64m     32m       0.10
cache-stub       10.30.3.11   64m     32m       0.10" ;;
3) PLAN="
gateway-nginx    10.40.1.10   256m    128m      0.50
user-nginx       10.40.2.10   128m    64m       0.25
catalog-nginx    10.40.2.11   128m    64m       0.25
order-nginx      10.40.2.12   128m    64m       0.25
payment-nginx    10.40.2.13   128m    64m       0.25
notify-nginx     10.40.2.14   128m    64m       0.25
analytics-nginx  10.40.2.15   128m    64m       0.25
discovery-nginx  10.40.2.16   128m    64m       0.25
db-stub          10.40.3.10   64m     32m       0.10
cache-stub       10.40.3.11   64m     32m       0.10" ;;
esac

# Container name, e.g. dc1-user-nginx
cname() {
    echo "dc${DC}-$1"
}

# Our own image for a service, plain nginx for the stubs.
image() {
    case "$1" in
        *-stub) echo "nginx:alpine" ;;
        *)      echo "$1" ;;
    esac
}

build() {
    local svc rest

    echo "=== DC$DC: build images ==="
    while read -r svc rest; do
        [ -n "$svc" ] || continue
        case "$svc" in *-stub) continue ;; esac
        echo "  build  $svc"
        $DOCKER build -q -f "$ROOT/dockerfiles/Dockerfile.$svc" -t "$svc" "$ROOT" >/dev/null
    done <<< "$PLAN"
}

deploy() {
    local svc ip mem res cpus name

    if ! $DOCKER network inspect "$NET" >/dev/null 2>&1; then
        echo "Network $NET is missing. Run overlay-up.sh $DC on this node first." >&2
        exit 1
    fi

    build

    echo "=== DC$DC: start containers on $NET ==="
    while read -r svc ip mem res cpus; do
        [ -n "$svc" ] || continue
        name=$(cname "$svc")

        # Replace any old copy, so running this again always gives a clean result.
        $DOCKER rm -f "$name" >/dev/null 2>&1 || true

        $DOCKER run -d \
            --name "$name" \
            --hostname "$name" \
            --network "$NET" \
            --ip "$ip" \
            -e DC="DC$DC" \
            --memory "$mem" \
            --memory-reservation "$res" \
            --cpus "$cpus" \
            --restart unless-stopped \
            "$(image "$svc")" >/dev/null

        printf '  run    %-24s %-12s mem %-5s cpu %s\n' "$name" "$ip" "$mem" "$cpus"
    done <<< "$PLAN"
}

# each <docker command...> — run it against every container of this DC
#   each stop     →  docker stop dc1-user-nginx, ...
#   each rm -f    →  docker rm -f dc1-user-nginx, ...
each() {
    local svc rest name
    while read -r svc rest; do
        [ -n "$svc" ] || continue
        name=$(cname "$svc")
        if $DOCKER "$@" "$name" >/dev/null 2>&1; then
            printf '  %-7s %s\n' "$1" "$name"
        else
            printf '  %-7s %s  (not found)\n' "$1" "$name"
        fi
    done <<< "$PLAN"
}

status() {
    local svc ip rest name state
    printf '  %-24s %-12s %s\n' "CONTAINER" "IP" "STATE"
    while read -r svc ip rest; do
        [ -n "$svc" ] || continue
        name=$(cname "$svc")
        state=$($DOCKER inspect -f '{{.State.Status}}{{if .State.Health}} ({{.State.Health.Status}}){{end}}' "$name" 2>/dev/null || echo "missing")
        printf '  %-24s %-12s %s\n' "$name" "$ip" "$state"
    done <<< "$PLAN"
}

logs() {
    local svc rest name
    while read -r svc rest; do
        [ -n "$svc" ] || continue
        name=$(cname "$svc")
        echo "--- $name ---"
        $DOCKER logs --tail 5 "$name" 2>&1 || true
    done <<< "$PLAN"
}

case "$ACTION" in
    build)  build ;;
    deploy) deploy ;;
    stop)   each stop ;;
    start)  each start ;;
    remove) each rm -f ;;
    status) status ;;
    logs)   logs ;;
    list)   awk 'NF { print $1, $2 }' <<< "$PLAN" ;;
    *)      usage ;;
esac
