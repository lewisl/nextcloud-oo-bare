#!/bin/bash

# System preparation for single-domain Nextcloud + OnlyOffice deployment
# Installs core packages, firewall rules, and baseline hardening without
# prompting for interactive input. All deployment parameters are read from
# /etc/nextcloud-onlyoffice/params.yaml (or NC_OO_PARAMS_PATH override).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_LOADER="${SCRIPT_DIR}/lib/config_loader.py"
SYSTEM_CONFIG_DIR="/etc/nextcloud-onlyoffice"
PARAMS_FILE="${SYSTEM_CONFIG_DIR}/params.yaml"
SAMPLE_PARAMS="${PROJECT_ROOT}/configs/params.yaml"
FAIL2BAN_SNIPPET="${PROJECT_ROOT}/configs/fail2ban/nextcloud-onlyoffice.conf"
PHP_SNIPPET="${PROJECT_ROOT}/configs/php/nextcloud.ini"
PHP_POOL_CONF="/etc/php/8.3/fpm/pool.d/www.conf"
LOG_FILE="/var/log/nextcloud-install.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log() {
    local message="$1"
    printf "${GREEN}[%s]${NC} %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$message" | tee -a "$LOG_FILE"
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
    mkdir -p "$SYSTEM_CONFIG_DIR"
    chmod 750 "$SYSTEM_CONFIG_DIR"
    if [[ ! -f "$PARAMS_FILE" ]]; then
        if [[ -f "$SAMPLE_PARAMS" ]]; then
            cp "$SAMPLE_PARAMS" "$PARAMS_FILE"
            chmod 640 "$PARAMS_FILE"
            warning "Parameter file missing. A template was copied to $PARAMS_FILE. Update it with production values and rerun."
            exit 2
        fi
        abort "Parameter file $PARAMS_FILE not found. Create it and rerun."
    fi
}

ensure_credentials() {
    PYTHONPATH="$PROJECT_ROOT" python3 <<'PY'
from __future__ import annotations

import os
import secrets
from pathlib import Path

import yaml

path = Path("/etc/nextcloud-onlyoffice/params.yaml")
with path.open("r", encoding="utf-8") as handle:
    data = yaml.safe_load(handle) or {}

updated = False

deployment = data.setdefault("deployment", {})
jwt = data.setdefault("jwt", {})

admin_password = deployment.get("nextcloud_admin_password", "")
if not admin_password or admin_password.startswith("CHANGE_ME"):
    deployment["nextcloud_admin_password"] = secrets.token_urlsafe(24)
    updated = True

jwt_secret = jwt.get("secret", "")
if not jwt_secret or jwt_secret in {"0" * 64, "CHANGE_ME_TO_SECURE_VALUE"} or len(jwt_secret) < 32:
    jwt["secret"] = secrets.token_hex(32)
    updated = True

if updated:
    tmp_path = path.with_suffix(".tmp")
    with tmp_path.open("w", encoding="utf-8") as handle:
        yaml.safe_dump(data, handle, sort_keys=False)
    os.replace(tmp_path, path)
    os.chmod(path, 0o640)
PY
}

reset_params_cache() {
    PYTHONPATH="$PROJECT_ROOT" python3 <<'PY'
from src.lib import config_loader

config_loader.reset_cache()
PY
}

load_params() {
    local exports
    if ! exports=$(python3 "$CONFIG_LOADER" --env 2>/tmp/config_loader.err); then
        cat /tmp/config_loader.err >&2
        abort "Failed to load deployment parameters."
    fi
    rm -f /tmp/config_loader.err
    eval "$exports"
}

APT_OPTS=(-o Acquire::Retries=5 -o Acquire::http::Timeout=30 -o Acquire::ftp::Timeout=30)

update_system() {
    info "Updating package index"
    apt-get "${APT_OPTS[@]}" update -y >>"$LOG_FILE" 2>&1
    info "Ensuring base system packages are current"
    DEBIAN_FRONTEND=noninteractive apt-get "${APT_OPTS[@]}" upgrade -y >>"$LOG_FILE" 2>&1
}

install_packages() {
    info "Installing base packages"
    local packages=(
        bzip2
        apt-transport-https
        ca-certificates
        curl
        fail2ban
        gnupg
        htop
        jq
        lsb-release
        mariadb-server
        nano
        nginx
        openssl
        php8.3
        php8.3-cli
        php8.3-common
        php8.3-fpm
        php8.3-gd
        php8.3-intl
        php8.3-mbstring
        php8.3-mysql
        php8.3-opcache
        php8.3-xml
        php8.3-zip
        php8.3-bcmath
        php8.3-curl
        php8.3-imagick
        php8.3-redis
        php8.3-apcu
        php8.3-gmp
        libmagickcore-6.q16-7-extra
        postgresql
        postgresql-contrib
        rabbitmq-server
        redis-server
        software-properties-common
        unzip
        vim
    )
    DEBIAN_FRONTEND=noninteractive apt-get "${APT_OPTS[@]}" install -y "${packages[@]}" >>"$LOG_FILE" 2>&1
    systemctl enable --now nginx php8.3-fpm mariadb postgresql redis-server rabbitmq-server fail2ban >>"$LOG_FILE" 2>&1
}

configure_firewall() {
    info "Configuring UFW firewall rules"
    if ufw status | grep -q "Status: active"; then
        warning "UFW already active – updating rules in-place"
    fi
    ufw --force reset >>"$LOG_FILE" 2>&1 || true
    ufw default deny incoming >>"$LOG_FILE" 2>&1
    ufw default allow outgoing >>"$LOG_FILE" 2>&1
    ufw allow OpenSSH >>"$LOG_FILE" 2>&1
    ufw allow 80/tcp >>"$LOG_FILE" 2>&1
    ufw allow 443/tcp >>"$LOG_FILE" 2>&1
    ufw --force enable >>"$LOG_FILE" 2>&1
}

configure_fail2ban() {
    info "Deploying fail2ban jail configuration"
    local jail_dir="/etc/fail2ban/jail.d"
    mkdir -p "$jail_dir"
    if [[ -f "$FAIL2BAN_SNIPPET" ]]; then
        install -m 0644 "$FAIL2BAN_SNIPPET" "$jail_dir/nextcloud-onlyoffice.conf"
    else
        warning "Fail2ban snippet not found at $FAIL2BAN_SNIPPET; skipping"
    fi
    systemctl restart fail2ban >>"$LOG_FILE" 2>&1
}

configure_php() {
    info "Applying PHP-FPM overrides"
    local fpm_override="/etc/php/8.3/fpm/conf.d/90-nextcloud.ini"
    local cli_override="/etc/php/8.3/cli/conf.d/90-nextcloud.ini"
    if [[ -f "$PHP_SNIPPET" ]]; then
        install -m 0644 "$PHP_SNIPPET" "$fpm_override"
        install -m 0644 "$PHP_SNIPPET" "$cli_override"
    else
        warning "PHP override snippet not found at $PHP_SNIPPET; skipping"
    fi

    if [[ -f "$PHP_POOL_CONF" ]]; then
        if grep -Eq '^\s*clear_env\s*=' "$PHP_POOL_CONF"; then
            sed -i 's/^\s*clear_env\s*=.*/clear_env = no/' "$PHP_POOL_CONF"
        else
            printf '\nclear_env = no\n' >>"$PHP_POOL_CONF"
        fi
    else
        warning "PHP-FPM pool file not found at $PHP_POOL_CONF; clear_env override skipped"
    fi

    systemctl reload php8.3-fpm >>"$LOG_FILE" 2>&1 || systemctl restart php8.3-fpm >>"$LOG_FILE" 2>&1
}

configure_redis() {
    info "Configuring Redis socket access"
    local redis_conf="/etc/redis/redis.conf"
    if grep -q '^unixsocket ' "$redis_conf"; then
        sed -i 's#^unixsocket .*#unixsocket /run/redis/redis-server.sock#' "$redis_conf"
    else
        echo 'unixsocket /run/redis/redis-server.sock' >>"$redis_conf"
    fi
    if grep -q '^unixsocketperm ' "$redis_conf"; then
        sed -i 's/^unixsocketperm .*/unixsocketperm 770/' "$redis_conf"
    else
        echo 'unixsocketperm 770' >>"$redis_conf"
    fi
    usermod -aG redis www-data >>"$LOG_FILE" 2>&1
    systemctl restart redis-server >>"$LOG_FILE" 2>&1
}

summarise() {
    success "System preparation completed"
    printf "${CYAN}${BOLD}Deployment inputs${NC}:\n"
    printf "  • Base domain: %s\n" "$DEPLOYMENT_BASE_DOMAIN"
    printf "  • Nextcloud FQDN: %s\n" "$NEXTCLOUD_FQDN"
    printf "  • Let's Encrypt contact: %s\n" "$LETSENCRYPT_EMAIL"
    printf "  • Admin email: %s\n" "$ADMIN_EMAIL"
    printf "  • Nextcloud admin user: %s\n" "$NEXTCLOUD_ADMIN_USER"
    printf "  • Nextcloud admin password: %s\n" "$NEXTCLOUD_ADMIN_PASSWORD"
    printf "${CYAN}${BOLD}Next steps${NC}:\n"
    printf "  1. Run ./02_database_setup.sh\n"
    printf "  2. Continue with application installation scripts\n"
}

main() {
    check_root
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"
    ensure_params_file
    ensure_credentials
    # reload after secrets generation
    reset_params_cache
    load_params
    info "Starting system preparation for ${NEXTCLOUD_FQDN}"
    update_system
    install_packages
    configure_firewall
    configure_fail2ban
    configure_php
    configure_redis
    summarise
}

main "$@"
