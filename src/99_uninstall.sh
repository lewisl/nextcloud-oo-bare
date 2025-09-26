#!/bin/bash

# Safe uninstall helper for the single-domain Nextcloud + OnlyOffice deployment
# Removes application data, configs, certificates, and databases that were created
# by the automation scripts. Packages that shipped with the OS are left installed
# unless --purge-packages is supplied.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_LOADER="${SCRIPT_DIR}/lib/config_loader.py"
PARAMS_FILE="/etc/nextcloud-onlyoffice/params.yaml"
LOG_FILE="/var/log/nextcloud-install.log"
DEFAULT_BACKUP_DIR="${PROJECT_ROOT}/project-status-and-todo/test-results"

PURGE_PACKAGES=0
SKIP_BACKUP=0
ASSUME_YES=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()    { printf "${GREEN}[%s]${NC} %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$LOG_FILE"; }
info()   { printf "${BLUE}[INFO]${NC} %s\n" "$1" | tee -a "$LOG_FILE"; }
warning(){ printf "${YELLOW}[WARN]${NC} %s\n" "$1" | tee -a "$LOG_FILE"; }
error()  { printf "${RED}[ERROR]${NC} %s\n" "$1" | tee -a "$LOG_FILE" >&2; }
success(){ printf "${GREEN}[OK]${NC} %s\n" "$1" | tee -a "$LOG_FILE"; }

usage() {
    cat <<'USAGE'
Usage: 99_uninstall.sh [options]

Options:
  --yes                 Skip interactive confirmation prompts
  --skip-backup         Do not generate tarball backups before deletion
  --backup-dir <path>   Directory to store backup tarballs (default: project test-results)
  --purge-packages      Remove nginx, PHP-FPM, certbot, and onlyoffice packages after cleanup
  -h, --help            Show this help message
USAGE
}

parse_args() {
    BACKUP_DIR="$DEFAULT_BACKUP_DIR"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --yes)
                ASSUME_YES=1; shift ;;
            --skip-backup)
                SKIP_BACKUP=1; shift ;;
            --backup-dir)
                [[ $# -gt 1 ]] || { usage; exit 1; }
                BACKUP_DIR="$(readlink -f "$2")"; shift 2 ;;
            --purge-packages)
                PURGE_PACKAGES=1; shift ;;
            -h|--help)
                usage; exit 0 ;;
            *)
                usage; exit 1 ;;
        esac
    done
}

ensure_root() { [[ $EUID -eq 0 ]] || { error "Run as root"; exit 1; }; }

load_params() {
    local exports
    if ! exports=$(python3 "$CONFIG_LOADER" --env 2>/tmp/config_loader.err); then
        cat /tmp/config_loader.err >&2 || true
        error "Unable to load parameters"
        exit 1
    fi
    eval "$exports"
    rm -f /tmp/config_loader.err
    : "${NEXTCLOUD_FQDN:?missing NEXTCLOUD_FQDN}"
    : "${NEXTCLOUD_DB_NAME:?missing NEXTCLOUD_DB_NAME}"
    : "${NEXTCLOUD_DB_USER:?missing NEXTCLOUD_DB_USER}"
    : "${ONLYOFFICE_DB_NAME:?missing ONLYOFFICE_DB_NAME}"
    : "${ONLYOFFICE_DB_USER:?missing ONLYOFFICE_DB_USER}"
}

confirm_destructive() {
    if [[ "$ASSUME_YES" -eq 1 ]]; then
        return
    fi
    printf "${YELLOW}This will permanently remove Nextcloud, OnlyOffice, databases, certificates, and nginx configs for %s.${NC}\n" "$NEXTCLOUD_FQDN"
    read -p "Type the hostname ($NEXTCLOUD_FQDN) to continue: " reply
    [[ "$reply" == "$NEXTCLOUD_FQDN" ]] || { info "Aborted"; exit 0; }
}

stop_services() {
    info "Stopping related services"
    local services=(nginx php8.3-fpm php-fpm ds-docservice ds-converter ds-metrics redis-server certbot.timer certbot.service)
    for svc in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "^${svc}"; then
            systemctl stop "$svc" 2>/dev/null || true
            systemctl disable "$svc" 2>/dev/null || true
        fi
    done
    success "Services stopped/disabled"
}

clean_cron() {
    info "Removing scheduled jobs referencing Nextcloud"
    # Remove cron.d entry if present
    rm -f /etc/cron.d/nextcloud 2>/dev/null || true

    # Scrub root crontab of cron.php references
    if crontab -l >/tmp/root_cron.old 2>/dev/null; then
        if grep -q 'nextcloud/cron.php' /tmp/root_cron.old; then
            grep -v 'nextcloud/cron.php' /tmp/root_cron.old > /tmp/root_cron.new || true
            if [[ -s /tmp/root_cron.new ]]; then
                crontab /tmp/root_cron.new
            else
                crontab -r
            fi
            info "Removed cron.php entry from root crontab"
        fi
        rm -f /tmp/root_cron.old /tmp/root_cron.new
    fi

    success "Cron cleanup complete"
}

backup_assets() {
    [[ "$SKIP_BACKUP" -eq 1 ]] && { info "Skipping backups"; return; }
    mkdir -p "$BACKUP_DIR"
    local ts
    ts=$(date +%F_%H%M%S)
    local items=("/etc/nginx" "/var/www/nextcloud" "/etc/onlyoffice" "/etc/letsencrypt" "/var/lib/onlyoffice")
    for item in "${items[@]}"; do
        if [[ -e "$item" ]]; then
            local safe
            safe=$(echo "$item" | sed 's#^/##; s#[^a-zA-Z0-9_\-]#_#g')
            local archive="${BACKUP_DIR}/${safe}_backup_${ts}.tar.gz"
            info "Backing up $item -> $archive"
            tar -czf "$archive" -C "$(dirname "$item")" "$(basename "$item")" || warning "Failed to create $archive"
        fi
    done
    success "Backups (if any) created under $BACKUP_DIR"
}

remove_nginx_configs() {
    info "Removing nginx vhost"
    local site="/etc/nginx/sites-available/${NEXTCLOUD_FQDN}.conf"
    rm -f "$site" "/etc/nginx/sites-enabled/${NEXTCLOUD_FQDN}" "/etc/nginx/sites-enabled/${NEXTCLOUD_FQDN}.conf"
    nginx -t && systemctl reload nginx || warning "nginx reload returned non-zero"
}

remove_files() {
    info "Removing application directories"
    rm -rf /var/www/nextcloud /srv/nextcloud-data /var/www/html || true
    rm -rf /var/www/onlyoffice /var/lib/onlyoffice /var/log/onlyoffice /etc/onlyoffice || true
    rm -rf /etc/nextcloud-onlyoffice || true
    rm -rf "/etc/letsencrypt/live/${NEXTCLOUD_FQDN}" "/etc/letsencrypt/archive/${NEXTCLOUD_FQDN}" "/etc/letsencrypt/renewal/${NEXTCLOUD_FQDN}.conf" || true
    success "Directories removed"
}

remove_databases() {
    info "Dropping MariaDB (Nextcloud) database/user"
    mysql -uroot <<SQL || warning "MariaDB cleanup encountered issues"
DROP DATABASE IF EXISTS \`${NEXTCLOUD_DB_NAME}\`;
DROP USER IF EXISTS '${NEXTCLOUD_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

    info "Dropping PostgreSQL (OnlyOffice) database/user"
    sudo -u postgres psql <<SQL || warning "PostgreSQL cleanup encountered issues"
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${ONLYOFFICE_DB_NAME}';
DROP DATABASE IF EXISTS "${ONLYOFFICE_DB_NAME}";
DROP ROLE IF EXISTS "${ONLYOFFICE_DB_USER}";
SQL
    success "Databases removed"
}

purge_packages() {
    [[ "$PURGE_PACKAGES" -eq 1 ]] || { info "Package purge skipped"; return; }
    info "Purging application packages"
    DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y onlyoffice-documentserver nginx nginx-* php8.3-* php-fpm redis-server certbot python3-certbot-nginx || true
    DEBIAN_FRONTEND=noninteractive apt-get autoremove -y || true
    DEBIAN_FRONTEND=noninteractive apt-get autoclean || true
    success "Package purge completed"
}

summarise() {
    success "Uninstall completed"
    printf "${CYAN}${BOLD}Reminder:${NC} review ${BACKUP_DIR} for tarball backups if you wish to restore configs.\n"
}

main() {
    ensure_root
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"
    parse_args "$@"
    if [[ ! -f "$PARAMS_FILE" ]]; then
        info "No deployment metadata at $PARAMS_FILE; assuming stack already removed."
        info "If this is unexpected, rerun 01_system_prep.sh to regenerate parameters."
        exit 0
    fi
    load_params
    confirm_destructive
    stop_services
    clean_cron
    backup_assets
    remove_nginx_configs
    remove_files
    remove_databases
    purge_packages
    summarise
}

main "$@"
