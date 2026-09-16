# Shared helpers for the test scripts. Loaded with:
#   source "$(dirname "$0")/lib.sh"

PASS=0
FAIL=0

pass() { echo "  PASS  $1"; PASS=$(( PASS + 1 )); }
fail() { echo "  FAIL  $1"; FAIL=$(( FAIL + 1 )); }

# check <what> <command...>  —  PASS if the command succeeds
check() {
    local what="$1"; shift
    if "$@" >/dev/null 2>&1; then
        pass "$what"
    else
        fail "$what"
    fi
}

# summary  —  prints the totals, returns non-zero if anything failed
summary() {
    echo
    echo "  result: $PASS pass, $FAIL fail"
    [ "$FAIL" -eq 0 ]
}

# need_node <arg>  —  sets NODE, or stops with a usage line
need_node() {
    case "${1:-}" in
        1|2|3) NODE="$1" ;;
        *)
            echo "usage: $0 <node number: 1, 2 or 3>  (the node you are on)" >&2
            exit 2
            ;;
    esac
}

# docker, with sudo until the docker group takes effect
if docker info >/dev/null 2>&1; then
    DOCKER="docker"
else
    DOCKER="sudo docker"
fi

# port_of <service>
port_of() {
    case "$1" in
        gateway-nginx)   echo 80 ;;
        user-nginx)      echo 8080 ;;
        catalog-nginx)   echo 8081 ;;
        order-nginx)     echo 8082 ;;
        payment-nginx)   echo 8083 ;;
        notify-nginx)    echo 8084 ;;
        analytics-nginx) echo 8085 ;;
        discovery-nginx) echo 8500 ;;
        *-stub)          echo 80 ;;
    esac
}

# gateway_ip <dc number>  —  the gateway container of that DC
gateway_ip() {
    case "$1" in
        1) echo 10.20.1.10 ;;
        2) echo 10.30.1.10 ;;
        3) echo 10.40.1.10 ;;
    esac
}
