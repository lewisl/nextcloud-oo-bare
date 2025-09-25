#!/bin/bash
# Wrapper to run deployment scripts with maintenance safeguards.
# - Enables Nextcloud maintenance mode if occ exists
# - Optionally stops OnlyOffice Document Server
# - Runs the target script with any additional arguments
# - Restarts web-related services afterward
# - Disables maintenance mode when complete

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: sudo ./tests/run_with_guard.sh <script> [args...]" >&2
    exit 64
fi

TARGET_SCRIPT="$1"
shift

if [[ ! -x "$TARGET_SCRIPT" ]]; then
    echo "Error: target script '$TARGET_SCRIPT' is not executable" >&2
    exit 66
fi

NEXTCLOUD_ROOT=${NEXTCLOUD_ROOT:-/var/www/nextcloud}
OCC="$NEXTCLOUD_ROOT/occ"
MAINT_FLAG=0
STOPPED_SERVICES=()

enter_maintenance() {
    if [[ -f "$OCC" ]]; then
        if sudo -u www-data php "$OCC" maintenance:mode --status 2>/dev/null | grep -q 'enabled: false'; then
            sudo -u www-data php "$OCC" maintenance:mode --on >/dev/null
            MAINT_FLAG=1
            echo "[guard] Nextcloud maintenance mode enabled"
        else
            echo "[guard] Nextcloud maintenance mode already enabled"
        fi
    fi
}

stop_services() {
    local services=(onlyoffice-documentserver)
    for svc in "${services[@]}"; do
        if systemctl list-units --type=service | grep -q "^${svc}"; then
            if systemctl is-active --quiet "$svc"; then
                systemctl stop "$svc"
                STOPPED_SERVICES+=("$svc")
                echo "[guard] Stopped $svc"
            fi
        fi
    done
}

run_target() {
    echo "[guard] Running $TARGET_SCRIPT $*"
    "$TARGET_SCRIPT" "$@"
}

start_services() {
    local services=(nginx php8.3-fpm redis-server onlyoffice-documentserver)
    for svc in "${services[@]}"; do
        if systemctl list-units --type=service | grep -q "^${svc}"; then
            systemctl restart "$svc" || echo "[guard] Warning: failed to restart $svc"
        fi
    done
}

exit_maintenance() {
    if [[ $MAINT_FLAG -eq 1 ]]; then
        sudo -u www-data php "$OCC" maintenance:mode --off >/dev/null
        echo "[guard] Nextcloud maintenance mode disabled"
    fi
}

cleanup() {
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "[guard] Target exited with status $rc"
    fi
    start_services
    exit_maintenance
    exit $rc
}

trap cleanup EXIT

enter_maintenance
stop_services
run_target "$@"
