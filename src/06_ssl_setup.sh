#!/bin/bash

# Automated SSL provisioning for single-domain Nextcloud + OnlyOffice deployment
# - Issues/renews Let's Encrypt certificates for the docs.<domain> host
# - Installs certbot dependencies and enables timer-based renewals
# - Re-renders nginx configuration (script 05) after certificates are available

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_LOADER="${SCRIPT_DIR}/lib/config_loader.py"
SYSTEM_CONFIG_DIR="/etc/nextcloud-onlyoffice"
PARAMS_FILE="${SYSTEM_CONFIG_DIR}/params.yaml"
LOG_FILE="/var/log/nextcloud-install.log"
WEBROOT="/var/www/nextcloud"
CERTBOT_BIN="/usr/bin/certbot"
CLOUDFLARE_CREDS="/etc/letsencrypt/cloudflare.ini"
CLOUDFLARE_PROPAGATION_SECONDS=${CLOUDFLARE_PROPAGATION_SECONDS:-60}
APT_OPTS=(-o Acquire::Retries=5 -o Acquire::http::Timeout=30 -o Acquire::ftp::Timeout=30)

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

usage() {
    cat <<'USAGE'
Usage: 06_ssl_setup.sh [options]

Options:
  --email <address>   Override the Let's Encrypt contact email (defaults to letsencrypt_email in params.yaml)
  --staging           Use the Let's Encrypt staging environment (safe for dry-runs)
  --force             Force certificate issuance even if one already exists (passes --force-renewal)
  -h, --help          Show this help message
USAGE
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

parse_args() {
    STAGING=0
    FORCE=0
    EMAIL_OVERRIDE=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --staging)
                STAGING=1
                shift
                ;;
            --force)
                FORCE=1
                shift
                ;;
            --email)
                [[ $# -gt 1 ]] || abort "--email requires a value"
                EMAIL_OVERRIDE="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                abort "Unknown option: $1"
                ;;
        esac
    done
}

ensure_packages() {
    info "Ensuring certbot dependencies"
    DEBIAN_FRONTEND=noninteractive apt-get "${APT_OPTS[@]}" update -y >>"$LOG_FILE" 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get "${APT_OPTS[@]}" install -y \
        certbot \
        python3-certbot-nginx \
        python3-certbot-dns-cloudflare >>"$LOG_FILE" 2>&1
}

certificate_exists() {
    local domain="$1"
    [[ -d "/etc/letsencrypt/live/${domain}" ]]
}

request_certificate() {
    local domain="$1"
    local email="$2"
    local staging_flag="$3"
    local force_flag="$4"

    local -a args=(
        certonly
        --dns-cloudflare
        --dns-cloudflare-credentials "$CLOUDFLARE_CREDS"
        --dns-cloudflare-propagation-seconds "$CLOUDFLARE_PROPAGATION_SECONDS"
        --domain "$domain"
        --agree-tos
        --non-interactive
        --no-eff-email
        --email "$email"
    )
    if [[ "$staging_flag" -eq 1 ]]; then
        args+=(--staging)
    fi
    if [[ "$force_flag" -eq 1 ]]; then
        args+=(--force-renewal)
    fi

    info "Requesting certificate for ${domain}"
    info "Using Cloudflare DNS challenge with credentials at ${CLOUDFLARE_CREDS}"
    "$CERTBOT_BIN" "${args[@]}" >>"$LOG_FILE" 2>&1 || abort "Certbot failed to obtain certificate"
}

renew_dry_run() {
    local domain="$1"
    info "Existing certificate detected for ${domain}; running certbot renew --dry-run"
    if ! "$CERTBOT_BIN" renew --cert-name "$domain" --dry-run >>"$LOG_FILE" 2>&1; then
        warning "Certbot dry-run renewal failed (expected when the domain is proxied by Cloudflare). Skipping dry-run."
    fi
}

enable_timer() {
    info "Ensuring certbot.timer is enabled"
    systemctl enable certbot.timer >>"$LOG_FILE" 2>&1 || warning "Failed to enable certbot.timer"
    systemctl start certbot.timer >>"$LOG_FILE" 2>&1 || warning "Failed to start certbot.timer"
}

ensure_cloudflare_credentials() {
    [[ -f "$CLOUDFLARE_CREDS" ]] || abort "Missing Cloudflare credentials file at $CLOUDFLARE_CREDS"
    local perms
    perms=$(stat -c %a "$CLOUDFLARE_CREDS" 2>/dev/null || true)
    if [[ "$perms" != "600" ]]; then
        warning "Cloudflare credentials should have 600 permissions; adjusting"
        chmod 600 "$CLOUDFLARE_CREDS" || warning "Failed to chmod 600 $CLOUDFLARE_CREDS"
    fi
}

render_nginx() {
    info "Re-rendering nginx configuration via script 05"
    "$SCRIPT_DIR/05_nginx_config.sh"
}

summarise() {
    success "SSL setup complete"
    printf "${CYAN}${BOLD}Certificate Path:${NC} /etc/letsencrypt/live/%s\n" "$NEXTCLOUD_FQDN"
    printf "${CYAN}${BOLD}Renewal Timer:${NC} %s\n" "$(systemctl is-enabled certbot.timer 2>/dev/null || echo disabled)"
    printf "${CYAN}${BOLD}Next steps:${NC}\n"
    printf "  1. Run ./src/07_integration_config.sh once refactored.\n"
}

main() {
    check_root
    parse_args "$@"
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"
    ensure_params_file
    load_params

    : "${NEXTCLOUD_FQDN:?NEXTCLOUD_FQDN missing from parameters}" 
    local email
    if [[ -n "$EMAIL_OVERRIDE" ]]; then
        email="$EMAIL_OVERRIDE"
        info "Using email override: $email"
    else
        email="${LETSENCRYPT_EMAIL:-${ADMIN_EMAIL:-}}"
        [[ -n "$email" ]] || abort "No email defined in params.yaml and none provided via --email"
        info "Using email from parameters: $email"
    fi

    ensure_packages
    ensure_cloudflare_credentials

    if certificate_exists "$NEXTCLOUD_FQDN" && [[ "$FORCE" -eq 0 ]]; then
        renew_dry_run "$NEXTCLOUD_FQDN"
    else
        request_certificate "$NEXTCLOUD_FQDN" "$email" "$STAGING" "$FORCE"
    fi

    enable_timer
    render_nginx
    summarise
}

main "$@"
