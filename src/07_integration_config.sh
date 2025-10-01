#!/bin/bash

# Harmonise OnlyOffice ↔ Nextcloud integration for single-domain deployments
# - Ensures OnlyOffice app is installed/enabled in Nextcloud
# - Aligns connector URLs, JWT secret/header, and storage URL with nginx/D.S settings
# - Runs health checks to verify editing endpoints are reachable

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_LOADER="${SCRIPT_DIR}/lib/config_loader.py"
SYSTEM_CONFIG_DIR="/etc/nextcloud-onlyoffice"
PARAMS_FILE="${SYSTEM_CONFIG_DIR}/params.yaml"
LOCAL_JSON="/etc/onlyoffice/documentserver/local.json"
OCC_BIN="php /var/www/nextcloud/occ"
LOG_FILE="/var/log/nextcloud-install.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log() {
    printf "${GREEN}[%s]${NC} %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$LOG_FILE"
}

info() {
    printf "${BLUE}[INFO]${NC} %s\n" "$1" | tee -a "$LOG_FILE"
}

warning() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1" | tee -a "$LOG_FILE"
}

error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1" | tee -a "$LOG_FILE" >&2
}

success() {
    printf "${GREEN}[OK]${NC} %s\n" "$1" | tee -a "$LOG_FILE"
}

abort() {
    error "$1"
    exit 1
}

check_root() {
    [[ $EUID -eq 0 ]] || abort "This script must run as root. Use sudo."
}

ensure_params_file() {
    [[ -f "$PARAMS_FILE" ]] || abort "Missing deployment parameters at $PARAMS_FILE. Run 01_system_prep.sh first."
}

load_params() {
    local exports
    if ! exports=$(python3 "$CONFIG_LOADER" --env 2>/tmp/config_loader.err); then
        cat /tmp/config_loader.err >&2 || true
        abort "Failed to load deployment parameters."
    fi
    eval "$exports"
    rm -f /tmp/config_loader.err
}

occ() {
    sudo -u www-data $OCC_BIN "$@"
}

read_ds_jwt() {
    python3 - "$1" <<'PY'
import json, sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text())
except Exception:
    sys.exit(1)

try:
    secret = (
        data["services"]["CoAuthoring"]["secret"]["browser"]["string"]
    )
except Exception:
    secret = ""

if secret:
    print(secret)
PY
}

manual_install_onlyoffice() {
    # Fallback installer for the ONLYOFFICE connector when appstore is unavailable
    # Env override: ONLYOFFICE_CONNECTOR_VERSION (default 9.11.0)
    local version="${ONLYOFFICE_CONNECTOR_VERSION:-9.11.0}"
    local url="https://github.com/ONLYOFFICE/onlyoffice-nextcloud/releases/download/v${version}/onlyoffice-${version}.tar.gz"

    info "Attempting manual ONLYOFFICE app install (v${version}) from GitHub releases"
    local tmpd
    tmpd=$(mktemp -d /tmp/onlyoffice-app.XXXXXX)
    pushd "$tmpd" >/dev/null || return 1

    if ! curl -fsSL --max-time 120 -o "onlyoffice-${version}.tar.gz" "$url"; then
        warning "Failed to download ONLYOFFICE app tarball from GitHub"
        popd >/dev/null || true
        rm -rf "$tmpd"
        return 1
    fi

    if ! tar -xzf "onlyoffice-${version}.tar.gz"; then
        warning "Failed to extract ONLYOFFICE app tarball"
        popd >/dev/null || true
        rm -rf "$tmpd"
        return 1
    fi

    local srcdir=""
    if [[ -d "onlyoffice" ]]; then
        srcdir="onlyoffice"
    else
        srcdir=$(find . -maxdepth 1 -type d -name 'onlyoffice*' | head -n1)
    fi

    if [[ -z "$srcdir" || ! -f "$srcdir/appinfo/info.xml" ]]; then
        warning "Downloaded archive does not contain a valid ONLYOFFICE app"
        popd >/dev/null || true
        rm -rf "$tmpd"
        return 1
    fi

    rm -rf "/var/www/nextcloud/apps/onlyoffice"
    mv "$srcdir" "/var/www/nextcloud/apps/onlyoffice"
    chown -R www-data:www-data "/var/www/nextcloud/apps/onlyoffice"

    popd >/dev/null || true
    rm -rf "$tmpd"
    success "Manual ONLYOFFICE app files installed to apps/onlyoffice"
    return 0
}

ensure_onlyoffice_app() {
    info "Ensuring Nextcloud OnlyOffice app is installed"
    local state
    state=$(occ app:list --output=json | python3 - <<'PY'
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    print('unknown')
    sys.exit()
if 'onlyoffice' in data.get('enabled', {}):
    print('enabled')
elif 'onlyoffice' in data.get('disabled', {}):
    print('disabled')
else:
    print('missing')
PY
)
    case "$state" in
        enabled)
            success "OnlyOffice app already enabled"
            ;;
        disabled)
            occ app:enable onlyoffice
            success "OnlyOffice app enabled"
            ;;
        missing)
            if occ app:install onlyoffice >/tmp/occ_install.log 2>&1; then
                success "OnlyOffice app installed via appstore"
            else
                if grep -qi "already installed" /tmp/occ_install.log 2>/dev/null; then
                    warning "OnlyOffice app already installed"
                else
                    warning "Appstore install failed; attempting manual install fallback"
                    if manual_install_onlyoffice; then
                        success "OnlyOffice app installed manually"
                    else
                        cat /tmp/occ_install.log >&2 || true
                        abort "Failed to install OnlyOffice app (appstore + manual fallback)"
                    fi
                fi
            fi
            occ app:enable onlyoffice >/dev/null 2>&1 || true
            ;;
        *)
            warning "Unable to determine OnlyOffice app state; attempting enable"
            occ app:enable onlyoffice >/dev/null 2>&1 || true
            ;;
    esac
}

configure_connector() {
    info "Configuring OnlyOffice connector settings in Nextcloud"
    local public_url="https://${NEXTCLOUD_FQDN}/onlyoffice/"
    local internal_url="http://127.0.0.1:8080/"
    local storage_url="https://${NEXTCLOUD_FQDN}/"
    local jwt_secret="${JWT_SECRET:-}"

    if [[ -f "$LOCAL_JSON" ]]; then
        local extracted
        extracted=$(read_ds_jwt "$LOCAL_JSON" || true)
        if [[ -n "$extracted" ]]; then
            jwt_secret="$extracted"
        fi
    fi

    [[ -n "$jwt_secret" ]] || abort "JWT secret unavailable; rerun 04_onlyoffice_install.sh first."

    occ config:app:set onlyoffice DocumentServerUrl --value="$public_url" >>"$LOG_FILE" 2>&1
    occ config:app:set onlyoffice DocumentServerInternalUrl --value="$internal_url" >>"$LOG_FILE" 2>&1
    occ config:app:set onlyoffice StorageUrl --value="$storage_url" >>"$LOG_FILE" 2>&1
    occ config:app:set onlyoffice jwt_secret --value="$jwt_secret" >>"$LOG_FILE" 2>&1
    occ config:app:set onlyoffice jwt_header --value="Authorization" >>"$LOG_FILE" 2>&1
    occ config:app:set onlyoffice jwt_enabled --value="true" >>"$LOG_FILE" 2>&1
    occ config:app:set onlyoffice verify_peer_off --value="false" >>"$LOG_FILE" 2>&1
    occ config:app:set onlyoffice sameTab --value="true" >>"$LOG_FILE" 2>&1 || true
}

sync_core_config() {
    info "Verifying Nextcloud core URL overrides"
    local desired_cli="https://${NEXTCLOUD_FQDN}"
    local current_cli
    current_cli=$(occ config:system:get overwrite.cli.url 2>/dev/null || echo "")
    if [[ "$current_cli" != "$desired_cli" ]]; then
        occ config:system:set overwrite.cli.url --value="$desired_cli"
    fi
    local protocol
    protocol=$(occ config:system:get overwriteprotocol 2>/dev/null || echo "")
    if [[ "$protocol" != "https" ]]; then
        occ config:system:set overwriteprotocol --value="https"
    fi
}

configure_smtp() {
    local enabled="${SMTP_ENABLED:-false}"
    shopt -s nocasematch
    if [[ "$enabled" != "true" ]]; then
        info "SMTP automation disabled in parameters; skipping"
        shopt -u nocasematch
        return
    fi
    shopt -u nocasematch

    local host="${SMTP_HOST:-}"
    local port="${SMTP_PORT:-}"
    local secure="${SMTP_SECURE:-tls}"
    local mode="${SMTP_MODE:-smtp}"
    local authtype="${SMTP_AUTHTYPE:-LOGIN}"
    local username="${SMTP_USERNAME:-}"
    local password="${SMTP_PASSWORD:-}"
    local from_address="${SMTP_FROM_ADDRESS:-}"
    local from_name="${SMTP_FROM_NAME:-Nextcloud}"
    local auth_flag="${SMTP_AUTH:-true}"

    for value in "$host" "$username" "$password" "$from_address"; do
        if [[ -z "$value" || "$value" == *"CHANGE_ME"* ]]; then
            warning "SMTP parameters contain placeholder values; skipping automation"
            return
        fi
    done

    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        warning "SMTP port '$port' is not numeric; skipping automation"
        return
    fi

    local local_part="$from_address"
    local domain_part=""
    if [[ "$from_address" == *"@"* ]]; then
        local_part="${from_address%@*}"
        domain_part="${from_address#*@}"
    else
        warning "SMTP from_address '$from_address' lacks '@'; skipping automation"
        return
    fi

    local auth_value="0"
    shopt -s nocasematch
    if [[ "$auth_flag" == "true" || "$auth_flag" == "yes" || "$auth_flag" == "1" ]]; then
        auth_value="1"
    fi
    shopt -u nocasematch

    info "Configuring Nextcloud SMTP settings"
    occ config:system:set mail_smtpmode --value="$mode" >>"$LOG_FILE" 2>&1
    occ config:system:set mail_smtpsecure --value="$secure" >>"$LOG_FILE" 2>&1
    occ config:system:set mail_smtphost --value="$host" >>"$LOG_FILE" 2>&1
    occ config:system:set mail_smtpport --value="$port" --type=integer >>"$LOG_FILE" 2>&1
    occ config:system:set mail_smtpauth --value="$auth_value" --type=integer >>"$LOG_FILE" 2>&1
    occ config:system:set mail_smtpauthtype --value="$authtype" >>"$LOG_FILE" 2>&1
    occ config:system:set mail_smtpname --value="$username" >>"$LOG_FILE" 2>&1
    occ config:system:set mail_smtppassword --value="$password" >>"$LOG_FILE" 2>&1
    occ config:system:set mail_from_address --value="$local_part" >>"$LOG_FILE" 2>&1
    occ config:system:set mail_domain --value="$domain_part" >>"$LOG_FILE" 2>&1
    occ config:system:set mail_from_name --value="$from_name" >>"$LOG_FILE" 2>&1
    success "SMTP configuration applied"
}

wait_for_docservice() {
    info "Waiting for DocumentServer health endpoint"
    local attempt=0
    local max_attempts=15
    while ! curl -fsS --max-time 10 http://127.0.0.1:8080/healthcheck >/dev/null 2>&1; do
        ((attempt++))
        if (( attempt >= max_attempts )); then
            warning "DocumentServer healthcheck still failing after ${max_attempts} attempts"
            return 1
        fi
        sleep 4
    done
    success "DocumentServer healthcheck succeeded"
    return 0
}

connector_healthcheck() {
    info "Running occ onlyoffice:documentserver --check"
    wait_for_docservice || true
    if occ onlyoffice:documentserver --check >/tmp/onlyoffice_check.log 2>&1; then
        success "Connector check succeeded"
        cat /tmp/onlyoffice_check.log | tee -a "$LOG_FILE"
    else
        warning "Connector check reported issues"
        cat /tmp/onlyoffice_check.log | tee -a "$LOG_FILE"
        warning "If you're using a staging certificate or a proxy that rewrites TLS (e.g. Cloudflare), the self-check may fail until a production cert is in place."
    fi
}

run_smoke_tests() {
    info "Executing nginx smoke tests"
    "$PROJECT_ROOT/tests/nginx_smoke.sh"
}

summarise() {
    success "Integration configuration complete"
    printf "${CYAN}${BOLD}DocumentServerUrl${NC}: %s\n" "$(occ config:app:get onlyoffice DocumentServerUrl)"
    printf "${CYAN}${BOLD}InternalUrl${NC}: %s\n" "$(occ config:app:get onlyoffice DocumentServerInternalUrl)"
    printf "${CYAN}${BOLD}StorageUrl${NC}: %s\n" "$(occ config:app:get onlyoffice StorageUrl)"
}

main() {
    check_root
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"
    ensure_params_file
    load_params

    : "${NEXTCLOUD_FQDN:?NEXTCLOUD_FQDN missing from params}"
    : "${JWT_SECRET:-}" # allow empty; will attempt to pull from DS

    ensure_onlyoffice_app
    configure_connector
    sync_core_config
    configure_smtp
    connector_healthcheck
    run_smoke_tests
    summarise
}

main "$@"
