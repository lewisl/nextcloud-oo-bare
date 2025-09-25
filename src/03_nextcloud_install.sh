#!/bin/bash

# Automated Nextcloud installation
# - Downloads/extracts the specified Nextcloud release (idempotent)
# - Runs the CLI installer using database/admin credentials from params.yaml
# - Sets up the data directory and base trusted domain configuration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_LOADER="${SCRIPT_DIR}/lib/config_loader.py"
SYSTEM_CONFIG_DIR="/etc/nextcloud-onlyoffice"
PARAMS_FILE="${SYSTEM_CONFIG_DIR}/params.yaml"
LOG_FILE="/var/log/nextcloud-install.log"
NEXTCLOUD_ROOT="/var/www/nextcloud"
NEXTCLOUD_DATA="/srv/nextcloud-data"
NEXTCLOUD_VERSION="28.0.4"
NEXTCLOUD_ARCHIVE="nextcloud-${NEXTCLOUD_VERSION}.tar.bz2"
DOWNLOAD_URL="https://download.nextcloud.com/server/releases/${NEXTCLOUD_ARCHIVE}"

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

verify_prereqs() {
    command -v wget >/dev/null || abort "wget is required"
    command -v tar >/dev/null || abort "tar is required"
    systemctl is-active --quiet mariadb || warning "MariaDB not running; occ install may fail"
}

prepare_directories() {
    info "Preparing Nextcloud directories"
    mkdir -p "$NEXTCLOUD_DATA"
    chown -R www-data:www-data "$NEXTCLOUD_DATA"
    chmod 750 "$NEXTCLOUD_DATA"
}

download_nextcloud() {
    if [[ -f "$NEXTCLOUD_ROOT/occ" ]]; then
        info "Nextcloud already present at $NEXTCLOUD_ROOT; skipping download"
        return
    fi

    info "Fetching Nextcloud ${NEXTCLOUD_VERSION}"
    local tmp_dir
    tmp_dir=$(mktemp -d /tmp/nextcloud-download.XXXXXX)
    pushd "$tmp_dir" >/dev/null
    wget -q "$DOWNLOAD_URL"
    tar -xjf "$NEXTCLOUD_ARCHIVE"
    rm -rf "$NEXTCLOUD_ROOT"
    mv nextcloud "$NEXTCLOUD_ROOT"
    popd >/dev/null
    rm -rf "$tmp_dir"

    chown -R www-data:www-data "$NEXTCLOUD_ROOT"
    find "$NEXTCLOUD_ROOT" -type d -exec chmod 750 {} +
    find "$NEXTCLOUD_ROOT" -type f -exec chmod 640 {} +
    chmod 750 "$NEXTCLOUD_ROOT/occ"
    success "Nextcloud files deployed"
}

run_cli_install() {
    if [[ -f "$NEXTCLOUD_ROOT/config/config.php" ]]; then
        info "Existing Nextcloud config detected; skipping maintenance:install"
        return
    fi

    info "Running Nextcloud CLI installer"
    sudo -u www-data php "$NEXTCLOUD_ROOT/occ" maintenance:install \
        --database "mysql" \
        --database-name "$NEXTCLOUD_DB_NAME" \
        --database-user "$NEXTCLOUD_DB_USER" \
        --database-pass "$NEXTCLOUD_DB_PASSWORD" \
        --data-dir "$NEXTCLOUD_DATA" \
        --admin-user "$NEXTCLOUD_ADMIN_USER" \
        --admin-pass "$NEXTCLOUD_ADMIN_PASSWORD" >>"$LOG_FILE" 2>&1

    success "Nextcloud CLI installer completed"
}

apply_base_config() {
    info "Applying base Nextcloud configuration"
    sudo -u www-data php "$NEXTCLOUD_ROOT/occ" config:system:set trusted_domains 1 --value="$NEXTCLOUD_FQDN" >>"$LOG_FILE" 2>&1
    sudo -u www-data php "$NEXTCLOUD_ROOT/occ" config:system:set overwrite.cli.url --value="https://$NEXTCLOUD_FQDN" >>"$LOG_FILE" 2>&1
    sudo -u www-data php "$NEXTCLOUD_ROOT/occ" config:system:set default_phone_region --value="US" >>"$LOG_FILE" 2>&1 || true
    sudo -u www-data php "$NEXTCLOUD_ROOT/occ" config:system:set memcache.local --value="\OC\Memcache\APCu" >>"$LOG_FILE" 2>&1
    sudo -u www-data php "$NEXTCLOUD_ROOT/occ" config:system:set memcache.locking --value="\OC\Memcache\Redis" >>"$LOG_FILE" 2>&1
    sudo -u www-data php "$NEXTCLOUD_ROOT/occ" config:system:set redis host --value="/run/redis/redis-server.sock" >>"$LOG_FILE" 2>&1
    sudo -u www-data php "$NEXTCLOUD_ROOT/occ" config:system:set redis port --value="0" --type=integer >>"$LOG_FILE" 2>&1
    sudo -u www-data php "$NEXTCLOUD_ROOT/occ" config:system:set redis timeout --value="0.0" --type=float >>"$LOG_FILE" 2>&1
}

summarise() {
    success "Nextcloud installation script completed"
    printf "${CYAN}${BOLD}Admin credentials${NC}:\n"
    printf "  • Username: %s\n" "$NEXTCLOUD_ADMIN_USER"
    printf "  • Password: %s\n" "$NEXTCLOUD_ADMIN_PASSWORD"
    printf "${CYAN}${BOLD}Database${NC}:\n"
    printf "  • DSN: mysql://%s:***@localhost/%s\n" "$NEXTCLOUD_DB_USER" "$NEXTCLOUD_DB_NAME"
    printf "${CYAN}${BOLD}Next steps${NC}:\n"
    printf "  1. Run ./04_onlyoffice_install.sh once refactored\n"
}

main() {
    check_root
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"
    ensure_params_file
    load_params
    verify_prereqs
    prepare_directories
    download_nextcloud
    run_cli_install
    apply_base_config
    summarise
}

main "$@"
