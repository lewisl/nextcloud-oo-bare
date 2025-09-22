#!/bin/bash

# OnlyOffice ↔ Nextcloud integration script for dual-domain deployments
# Configures the Nextcloud OnlyOffice connector without touching DocumentServer files.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log()    { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; }
warning(){ echo -e "${YELLOW}[WARNING]${NC} $1"; }
info()   { echo -e "${BLUE}[INFO]${NC} $1"; }
success(){ echo -e "${GREEN}[SUCCESS]${NC} $1"; }
header() { echo -e "${CYAN}${BOLD}$1${NC}"; }

require_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

run_occ() {
    sudo -u www-data php /var/www/nextcloud/occ "$@"
}

load_config() {
    local cfg="/etc/nextcloud-onlyoffice/params.yaml"
    if [[ ! -f "$cfg" ]]; then
        error "Configuration file $cfg not found. Run 01_system_prep_dual_domain.sh first."
        exit 1
    fi

    BASE_DOMAIN=$(awk -F': *' '/^[[:space:]]*base_domain:/ {gsub(/[" ]/,"",$2); print $2; exit}' "$cfg")
    NEXTCLOUD_DOMAIN=$(awk -F': *' '/^[[:space:]]*nextcloud_domain:/ {gsub(/[" ]/,"",$2); print $2; exit}' "$cfg")
    ONLYOFFICE_DOMAIN=$(awk -F': *' '/^[[:space:]]*onlyoffice_domain:/ {gsub(/[" ]/,"",$2); print $2; exit}' "$cfg")
    ADMIN_EMAIL=$(awk -F': *' '/^[[:space:]]*admin_email:/ {gsub(/[" ]/,"",$2); print $2; exit}' "$cfg")

    OO_DB_NAME=$(awk -F': *' 'BEGIN{section=0} /^[[:space:]]*onlyoffice:/ {section=1; next} section && /^[[:space:]]*db_name:/ {gsub(/"/,"",$2); print $2; exit} /^[^[:space:]]/ {section=0}' "$cfg")
    OO_DB_USER=$(awk -F': *' 'BEGIN{section=0} /^[[:space:]]*onlyoffice:/ {section=1; next} section && /^[[:space:]]*db_user:/ {gsub(/"/,"",$2); print $2; exit} /^[^[:space:]]/ {section=0}' "$cfg")
    JWT_SECRET=$(awk -F': *' 'BEGIN{section=0} /^[[:space:]]*jwt:/ {section=1; next} section && /^[[:space:]]*secret:/ {gsub(/"/,"",$2); print $2; exit} /^[^[:space:]]/ {section=0}' "$cfg")

    if [[ -z "$JWT_SECRET" ]]; then
        error "JWT secret missing in $cfg. Re-run 04_onlyoffice_install_dual_domain.sh first."
        exit 1
    fi
}

ensure_slash() {
    local value="$1"
    if [[ $value != */ ]]; then
        value="$value/"
    fi
    echo "$value"
}

show_banner() {
    clear
    cat <<'BANNER'
╔══════════════════════════════════════════════════════════════════════════════╗
║                   2-DOMAIN ONLYOFFICE INTEGRATION                            ║
║              Configuring Nextcloud OnlyOffice connector                      ║
╚══════════════════════════════════════════════════════════════════════════════╝
BANNER
    echo
    info "Nextcloud domain : https://$NEXTCLOUD_DOMAIN"
    info "OnlyOffice domain : https://$ONLYOFFICE_DOMAIN"
    info "DocumentServer DB : $OO_DB_NAME (user $OO_DB_USER)"
    echo
}

check_prerequisites() {
    header "Checking prerequisites"

    local nc_status
    nc_status=$(curl -sk -o /dev/null -w "%{http_code}" "https://$NEXTCLOUD_DOMAIN/status.php" || echo "000")
    if [[ "$nc_status" != "200" ]]; then
        error "Nextcloud status.php returned HTTP $nc_status"
        exit 1
    fi
    success "Nextcloud reachable (status.php)"

    local oo_health
    oo_health=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:8080/healthcheck" || echo "000")
    if [[ "$oo_health" != "200" ]]; then
        error "DocumentServer healthcheck returned HTTP $oo_health"
        exit 1
    fi
    success "DocumentServer healthcheck reachable"

    local oo_discovery
    oo_discovery=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:8080/hosting/discovery" || echo "000")
    if [[ "$oo_discovery" != "200" ]]; then
        error "DocumentServer discovery endpoint returned HTTP $oo_discovery"
        exit 1
    fi
    success "DocumentServer discovery endpoint reachable"

    if run_occ --version >/dev/null 2>&1; then
        success "occ command available"
    else
        error "Unable to execute occ as www-data"
        exit 1
    fi
}

ensure_onlyoffice_app() {
    header "Ensuring OnlyOffice app is installed"
    local app_json
    app_json=$(run_occ app:list --output=json)

    local app_state
    app_state=$(printf '%s' "$app_json" | python3 - <<'PY'
import json, sys

state = 'missing'
try:
    data = json.load(sys.stdin)
    if 'onlyoffice' in data.get('enabled', {}):
        state = 'enabled'
    elif 'onlyoffice' in data.get('disabled', {}):
        state = 'disabled'
    else:
        state = 'missing'
except Exception:
    state = 'unknown'

print(state)
PY
)

    case "$app_state" in
        enabled)
            success "OnlyOffice app already enabled"
            ;;
        disabled)
            info "Enabling OnlyOffice app"
            run_occ app:enable onlyoffice
            ;;
        missing|unknown)
            info "Installing OnlyOffice app"
            if run_occ app:install onlyoffice >/tmp/occ_install.log 2>&1; then
                success "OnlyOffice app installed"
            else
                if grep -qi "already installed" /tmp/occ_install.log 2>/dev/null; then
                    warning "OnlyOffice app already installed"
                else
                    cat /tmp/occ_install.log >&2 || true
                    error "Failed to install OnlyOffice app"
                    exit 1
                fi
            fi
            ;;
    esac

    if run_occ app:enable onlyoffice >/dev/null 2>&1; then
        success "OnlyOffice app enabled"
    fi
}

configure_connector() {
    header "Configuring connector settings"
    local public_url internal_url storage_url
    public_url="https://$(ensure_slash "$ONLYOFFICE_DOMAIN")"
    internal_url="http://127.0.0.1:8080/"
    storage_url="https://$(ensure_slash "$NEXTCLOUD_DOMAIN")"

    run_occ config:app:set onlyoffice DocumentServerUrl --value="$public_url"
    run_occ config:app:set onlyoffice DocumentServerInternalUrl --value="$internal_url"
    run_occ config:app:set onlyoffice storage_url --value="$storage_url"
    run_occ config:app:set onlyoffice jwt_secret --value="$JWT_SECRET"
    run_occ config:app:set onlyoffice jwt_header --value="Authorization"
    run_occ config:app:set onlyoffice jwt_enabled --value="true"
    run_occ config:app:set onlyoffice verify_peer_off --value="false"
    success "Connector configuration updated"
}

display_configuration() {
    header "Current OnlyOffice connector settings"
    run_occ config:app:get onlyoffice DocumentServerUrl || true
    run_occ config:app:get onlyoffice DocumentServerInternalUrl || true
    run_occ config:app:get onlyoffice storage_url || true
    run_occ config:app:get onlyoffice jwt_enabled || true
}

run_health_checks() {
    header "Connector health check"
    if run_occ onlyoffice:documentserver --check >/tmp/onlyoffice_check.log 2>&1; then
        success "occ onlyoffice:documentserver --check succeeded"
        cat /tmp/onlyoffice_check.log
    else
        warning "occ onlyoffice:documentserver --check reported issues"
        cat /tmp/onlyoffice_check.log
    fi
}

main() {
    require_root
    load_config
    show_banner
    check_prerequisites
    ensure_onlyoffice_app
    configure_connector
    display_configuration
    run_health_checks

    info "Next steps:"
    info "  1. Log into https://$NEXTCLOUD_DOMAIN as admin"
    info "  2. Open the Files app and launch a DOCX/PPTX to confirm OnlyOffice loads"
    info "  3. Monitor /var/log/onlyoffice/documentserver/ and nextcloud.log for errors"
}

main "$@"
