#!/bin/bash

# Database provisioning for Nextcloud (MariaDB) and OnlyOffice (PostgreSQL)
# Uses credentials supplied in /etc/nextcloud-onlyoffice/params.yaml via the
# shared config loader CLI. Designed to be idempotent and non-interactive.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_LOADER="${SCRIPT_DIR}/lib/config_loader.py"
SYSTEM_CONFIG_DIR="/etc/nextcloud-onlyoffice"
PARAMS_FILE="${SYSTEM_CONFIG_DIR}/params.yaml"
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

escape_sql() {
    printf '%s' "$1" | sed "s/'/''/g"
}

setup_mariadb() {
    info "Configuring MariaDB for Nextcloud"
    systemctl enable --now mariadb >>"$LOG_FILE" 2>&1

    local password_escaped
    password_escaped=$(escape_sql "$NEXTCLOUD_DB_PASSWORD")

    mysql -u root -e "CREATE DATABASE IF NOT EXISTS ${NEXTCLOUD_DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;" >>"$LOG_FILE" 2>&1
    mysql -u root -e "CREATE USER IF NOT EXISTS '${NEXTCLOUD_DB_USER}'@'localhost' IDENTIFIED BY '${password_escaped}';" >>"$LOG_FILE" 2>&1
    mysql -u root -e "ALTER USER '${NEXTCLOUD_DB_USER}'@'localhost' IDENTIFIED BY '${password_escaped}';" >>"$LOG_FILE" 2>&1
    mysql -u root -e "GRANT ALL PRIVILEGES ON ${NEXTCLOUD_DB_NAME}.* TO '${NEXTCLOUD_DB_USER}'@'localhost';" >>"$LOG_FILE" 2>&1
    mysql -u root -e "FLUSH PRIVILEGES;" >>"$LOG_FILE" 2>&1

    info "Testing MariaDB connectivity as $NEXTCLOUD_DB_USER"
    if ! mysql -u "$NEXTCLOUD_DB_USER" -p"$NEXTCLOUD_DB_PASSWORD" -e "SELECT 1;" "$NEXTCLOUD_DB_NAME" >>"$LOG_FILE" 2>&1; then
        abort "MariaDB connectivity test failed for user $NEXTCLOUD_DB_USER"
    fi
}

setup_postgresql() {
    info "Configuring PostgreSQL for OnlyOffice"
    systemctl enable --now postgresql >>"$LOG_FILE" 2>&1

    local password_escaped
    password_escaped=$(escape_sql "$ONLYOFFICE_DB_PASSWORD")

    if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname = '$ONLYOFFICE_DB_NAME'" | grep -q 1; then
        sudo -u postgres createdb "$ONLYOFFICE_DB_NAME" >>"$LOG_FILE" 2>&1
    fi

    if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname = '$ONLYOFFICE_DB_USER'" | grep -q 1; then
        sudo -u postgres psql -c "ALTER ROLE \"$ONLYOFFICE_DB_USER\" WITH PASSWORD '$password_escaped';" >>"$LOG_FILE" 2>&1
    else
        sudo -u postgres psql -c "CREATE ROLE \"$ONLYOFFICE_DB_USER\" LOGIN PASSWORD '$password_escaped';" >>"$LOG_FILE" 2>&1
    fi

    sudo -u postgres psql -c "ALTER DATABASE \"$ONLYOFFICE_DB_NAME\" OWNER TO \"$ONLYOFFICE_DB_USER\";" >>"$LOG_FILE" 2>&1 || true
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE \"$ONLYOFFICE_DB_NAME\" TO \"$ONLYOFFICE_DB_USER\";" >>"$LOG_FILE" 2>&1
    sudo -u postgres psql -d "$ONLYOFFICE_DB_NAME" -c "ALTER SCHEMA public OWNER TO \"$ONLYOFFICE_DB_USER\";" >>"$LOG_FILE" 2>&1 || true
    sudo -u postgres psql -d "$ONLYOFFICE_DB_NAME" -c "GRANT ALL PRIVILEGES ON SCHEMA public TO \"$ONLYOFFICE_DB_USER\";" >>"$LOG_FILE" 2>&1 || true
    sudo -u postgres psql -d "$ONLYOFFICE_DB_NAME" -c "ALTER DEFAULT PRIVILEGES FOR ROLE \"$ONLYOFFICE_DB_USER\" IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO \"$ONLYOFFICE_DB_USER\";" >>"$LOG_FILE" 2>&1 || true

    info "Testing PostgreSQL connectivity as $ONLYOFFICE_DB_USER"
    if ! PGPASSWORD="$ONLYOFFICE_DB_PASSWORD" psql -h localhost -U "$ONLYOFFICE_DB_USER" -d "$ONLYOFFICE_DB_NAME" -c "SELECT 1;" >>"$LOG_FILE" 2>&1; then
        abort "PostgreSQL connectivity test failed for user $ONLYOFFICE_DB_USER"
    fi
}

detect_postgres_version() {
    local version
    version=$(psql -V 2>/dev/null | awk '{print $3}') || return 1
    printf '%s' "${version%%.*}"
}

configure_postgres_hba() {
    info "Ensuring PostgreSQL pg_hba.conf restricts access to localhost"
    local major_version pg_hba
    if ! major_version=$(detect_postgres_version); then
        warning "Unable to detect PostgreSQL version; skipping pg_hba.conf hardening"
        return
    fi
    pg_hba="/etc/postgresql/${major_version}/main/pg_hba.conf"
    if [[ -f "$pg_hba" ]]; then
        cp "$pg_hba" "${pg_hba}.backup"
        cat >"$pg_hba" <<'PGHBA'
# Managed by Nextcloud + OnlyOffice toolkit
# Allow local connections only using md5 authentication.
local   all             postgres                                peer
local   all             all                                     peer
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5
PGHBA
        systemctl restart postgresql >>"$LOG_FILE" 2>&1
    else
        warning "PostgreSQL pg_hba.conf not found at $pg_hba; skipping hardening"
    fi
}

summarise() {
    printf "${CYAN}${BOLD}Database provisioning complete${NC}\n"
    printf "  • MariaDB database %s with user %s\n" "$NEXTCLOUD_DB_NAME" "$NEXTCLOUD_DB_USER"
    printf "  • PostgreSQL database %s with user %s\n" "$ONLYOFFICE_DB_NAME" "$ONLYOFFICE_DB_USER"
    printf "${CYAN}${BOLD}Next steps${NC}\n"
    printf "  1. Run ./03_nextcloud_install_dual_domain.sh (pending refactor)\n"
}

main() {
    check_root
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"
    ensure_params_file
    load_params
    setup_mariadb
    setup_postgresql
    configure_postgres_hba
    summarise
}

main "$@"
