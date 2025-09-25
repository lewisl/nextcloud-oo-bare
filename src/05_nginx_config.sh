#!/bin/bash

# Nginx configuration for single-domain Nextcloud + OnlyOffice deployment
# - Deploys managed nginx.conf and websocket helper
# - Renders the Nextcloud virtual host (HTTP-only if certs missing, HTTPS otherwise)
# - Reloads nginx after validation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_LOADER="${SCRIPT_DIR}/lib/config_loader.py"
SYSTEM_CONFIG_DIR="/etc/nextcloud-onlyoffice"
PARAMS_FILE="${SYSTEM_CONFIG_DIR}/params.yaml"
LOG_FILE="/var/log/nextcloud-install.log"
NGINX_CONF_TEMPLATE="${PROJECT_ROOT}/configs/nginx/nginx.conf"
WEBSOCKET_TEMPLATE="${PROJECT_ROOT}/configs/nginx/conf.d/00_websocket_upgrade_map.conf"
SITE_HTTP_TEMPLATE="${PROJECT_ROOT}/configs/nginx/sites-available/nextcloud_http.conf.tpl"
SITE_HTTPS_TEMPLATE="${PROJECT_ROOT}/configs/nginx/sites-available/nextcloud_https.conf.tpl"
LOCAL_JSON="/etc/onlyoffice/documentserver/local.json"
NGINX_MAIN_CONF="/etc/nginx/nginx.conf"
NGINX_CONF_D="/etc/nginx/conf.d"
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"

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

detect_php_socket() {
    local fallback="/run/php/php8.3-fpm.sock"
    if [[ -S "$fallback" ]]; then
        PHP_FPM_SOCKET="$fallback"
        return
    fi
    local candidates
    candidates=$(find /run/php -maxdepth 1 -name 'php*-fpm.sock' -print 2>/dev/null | head -n1 || true)
    if [[ -n "$candidates" ]]; then
        PHP_FPM_SOCKET="$candidates"
    else
        warning "PHP-FPM socket not found; falling back to $fallback"
        PHP_FPM_SOCKET="$fallback"
    fi
}

get_onlyoffice_port() {
    local ds_conf="/etc/onlyoffice/documentserver/nginx/ds.conf"
    if [[ -f "$ds_conf" ]]; then
        local port
        port=$(awk -F'[ :;]' '/listen/ {for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+$/){print $i; exit}}' "$ds_conf")
        [[ -n "$port" ]] && { ONLYOFFICE_PORT="$port"; return; }
    fi
    ONLYOFFICE_PORT="8080"
}

ensure_envsubst() {
    if ! command -v envsubst >/dev/null 2>&1; then
        info "Installing gettext-base for envsubst"
        DEBIAN_FRONTEND=noninteractive apt-get install -y gettext-base >>"$LOG_FILE" 2>&1
    fi
}

render_main_conf() {
    info "Deploying managed nginx.conf"
    install -m 0644 "$NGINX_CONF_TEMPLATE" "$NGINX_MAIN_CONF"
}

install_websocket_snippet() {
    info "Installing websocket upgrade map"
    install -m 0644 "$WEBSOCKET_TEMPLATE" "$NGINX_CONF_D/00_websocket_upgrade_map.conf"
}

render_site_config() {
    local template dest cert_dir
    mkdir -p "$NGINX_SITES_AVAILABLE" "$NGINX_SITES_ENABLED"
    dest="$NGINX_SITES_AVAILABLE/${NEXTCLOUD_FQDN}.conf"
    rm -f "$NGINX_SITES_AVAILABLE/${NEXTCLOUD_FQDN}" "$NGINX_SITES_ENABLED/${NEXTCLOUD_FQDN}" "$NGINX_SITES_ENABLED/${NEXTCLOUD_FQDN}.conf"
    cert_dir="/etc/letsencrypt/live/${NEXTCLOUD_FQDN}"
    if [[ -f "$cert_dir/fullchain.pem" && -f "$cert_dir/privkey.pem" ]]; then
        template="$SITE_HTTPS_TEMPLATE"
    else
        template="$SITE_HTTP_TEMPLATE"
        warning "TLS certificates not found for ${NEXTCLOUD_FQDN}; configuring HTTP-only until SSL script runs."
    fi
    ONLYOFFICE_PORT=${ONLYOFFICE_PORT} \
    NEXTCLOUD_FQDN=${NEXTCLOUD_FQDN} \
    PHP_FPM_SOCKET=${PHP_FPM_SOCKET} \
        envsubst '${NEXTCLOUD_FQDN} ${ONLYOFFICE_PORT} ${PHP_FPM_SOCKET}' < "$template" > "$dest"
    ln -sf "$dest" "$NGINX_SITES_ENABLED/${NEXTCLOUD_FQDN}.conf"
}

disable_legacy_sites() {
    local legacy_conf="$NGINX_SITES_AVAILABLE/${ONLYOFFICE_FQDN}"
    local legacy_link="$NGINX_SITES_ENABLED/${ONLYOFFICE_FQDN}"
    if [[ -e "$legacy_link" ]]; then
        info "Removing legacy OnlyOffice sites-enabled entry"
        rm -f "$legacy_link"
    fi
    if [[ -e "$legacy_conf" ]]; then
        info "Removing legacy OnlyOffice sites-available entry"
        rm -f "$legacy_conf"
    fi
}

ensure_log_dir() {
    mkdir -p /var/log/nginx
}

reload_nginx() {
    info "Testing nginx configuration"
    nginx -t
    info "Reloading nginx"
    systemctl reload nginx
}

summarise() {
    success "Nginx configuration updated"
    printf "${CYAN}${BOLD}Site file${NC}: %s\n" "$NGINX_SITES_AVAILABLE/${NEXTCLOUD_FQDN}.conf"
    printf "${CYAN}${BOLD}Backend${NC}: DocumentServer via 127.0.0.1:%s\n" "$ONLYOFFICE_PORT"
}

main() {
    check_root
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"
    ensure_params_file
    load_params
    ensure_envsubst
    detect_php_socket
    get_onlyoffice_port
    ensure_log_dir
    render_main_conf
    install_websocket_snippet
    render_site_config
    disable_legacy_sites
    reload_nginx
    summarise
}

main "$@"
