#!/bin/bash

# OnlyOffice Document Server installation/configuration for single-domain deployment
# - Installs/updates the upstream apt repository and package
# - Applies database/JWT settings from /etc/nextcloud-onlyoffice/params.yaml
# - Forces DocumentServer to listen on localhost only and validates health endpoints

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_LOADER="${SCRIPT_DIR}/lib/config_loader.py"
SYSTEM_CONFIG_DIR="/etc/nextcloud-onlyoffice"
PARAMS_FILE="${SYSTEM_CONFIG_DIR}/params.yaml"
LOG_FILE="/var/log/nextcloud-install.log"
APT_LIST="/etc/apt/sources.list.d/onlyoffice.list"
KEYRING="/usr/share/keyrings/onlyoffice.gpg"
LOCAL_JSON="/etc/onlyoffice/documentserver/local.json"
DS_CONF="/etc/onlyoffice/documentserver/nginx/ds.conf"
DS_SERVICES=(ds-converter ds-docservice ds-metrics)
LOCAL_JSON_TEMPLATE="${PROJECT_ROOT}/configs/onlyoffice/local.json"
DS_CONF_TEMPLATE="${PROJECT_ROOT}/configs/onlyoffice/nginx/ds.conf.tpl"
POSTGRES_SCHEMA_DIR="/var/www/onlyoffice/documentserver/server/schema/postgresql"
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

ensure_ds_account() {
    info "Ensuring ds system account exists"
    if ! getent group ds >/dev/null 2>&1; then
        if command -v addgroup >/dev/null 2>&1; then
            addgroup --system ds >>"$LOG_FILE" 2>&1
        else
            groupadd --system ds >>"$LOG_FILE" 2>&1 || true
        fi
    fi
    if ! id -u ds >/dev/null 2>&1; then
        local home="/var/lib/onlyoffice/documentserver"
        mkdir -p "$home"
        if command -v adduser >/dev/null 2>&1; then
            adduser --system --home "$home" --shell /usr/sbin/nologin --ingroup ds ds >>"$LOG_FILE" 2>&1
        else
            useradd --system --home-dir "$home" --shell /usr/sbin/nologin --gid ds ds >>"$LOG_FILE" 2>&1
        fi
    fi
}

preseed_debconf() {
    info "Preseeding DocumentServer installation answers"
    local rabbitmq_pass="guest"
    cat <<EOF | debconf-set-selections
onlyoffice-documentserver onlyoffice/db-type select postgres
onlyoffice-documentserver onlyoffice/db-host string localhost
onlyoffice-documentserver onlyoffice/db-port string 5432
onlyoffice-documentserver onlyoffice/db-name string ${ONLYOFFICE_DB_NAME}
onlyoffice-documentserver onlyoffice/db-user string ${ONLYOFFICE_DB_USER}
onlyoffice-documentserver onlyoffice/db-pwd password ${ONLYOFFICE_DB_PASSWORD}
onlyoffice-documentserver onlyoffice/rabbitmq-host string localhost
onlyoffice-documentserver onlyoffice/rabbitmq-user string guest
onlyoffice-documentserver onlyoffice/rabbitmq-pwd password ${rabbitmq_pass}
EOF
}

prepare_documentserver_prereqs() {
    info "Pre-seeding DocumentServer config directories"
    local base="/etc/onlyoffice/documentserver"
    local logrotate_dir="$base/logrotate"
    local includes_dir="$base/nginx/includes"
    local logrotate_src="${PROJECT_ROOT}/configs/onlyoffice/logrotate/ds.conf"
    local includes_src="${PROJECT_ROOT}/configs/onlyoffice/nginx/includes"
    local log_root="/var/log/onlyoffice/documentserver"
    local app_data_root="/var/lib/onlyoffice/documentserver"
    local log4js_src="${PROJECT_ROOT}/configs/onlyoffice/log4js"

    mkdir -p "$logrotate_dir" "$includes_dir"

    if [[ -f "$logrotate_src" ]]; then
        install -m 00644 -o root -g root "$logrotate_src" "$logrotate_dir/ds.conf"
    elif [[ ! -f "$logrotate_dir/ds.conf" ]]; then
        touch "$logrotate_dir/ds.conf"
        chmod 644 "$logrotate_dir/ds.conf"
        chown root:root "$logrotate_dir/ds.conf"
    fi

    if [[ -d "$includes_src" ]]; then
        while IFS= read -r -d '' file; do
            install -m 00644 -o root -g root "$file" "$includes_dir/$(basename "$file")"
        done < <(find "$includes_src" -maxdepth 1 -type f -name '*.conf' -print0)
    fi

    # Remove upstream example include that breaks nginx reloads in non-default deployments
    rm -f "$includes_dir/ds-example.conf" /etc/nginx/includes/ds-example.conf

    chmod 755 "$base" "$base/nginx" "$includes_dir" "$logrotate_dir" 2>/dev/null || true

    mkdir -p "$log_root/docservice" "$log_root/converter" "$log_root/metrics"
    chown -R ds:ds "$log_root"

    mkdir -p "$app_data_root/App_Data" "$app_data_root/App_Data/cache/files" "$app_data_root/docbuilder"
    chown -R ds:ds "$app_data_root"

    if [[ -d "$log4js_src" ]]; then
        mkdir -p "$base/log4js"
        while IFS= read -r -d '' file; do
            install -m 00644 -o root -g root "$file" "$base/log4js/$(basename "$file")"
        done < <(find "$log4js_src" -maxdepth 1 -type f -name '*.json' -print0)
    fi
}

ensure_packages() {
    info "Ensuring apt dependencies for OnlyOffice"
    DEBIAN_FRONTEND=noninteractive apt-get "${APT_OPTS[@]}" update -y >>"$LOG_FILE" 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get "${APT_OPTS[@]}" install -y curl gnupg ca-certificates apt-transport-https >>"$LOG_FILE" 2>&1
}

configure_repository() {
    info "Configuring OnlyOffice apt repository"
    if [[ ! -f "$KEYRING" ]]; then
        curl -fsSL https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE | gpg --dearmor -o "$KEYRING"
    fi
    if [[ ! -f "$APT_LIST" ]]; then
        echo "deb [signed-by=$KEYRING] https://download.onlyoffice.com/repo/debian squeeze main" > "$APT_LIST"
    fi
    DEBIAN_FRONTEND=noninteractive apt-get "${APT_OPTS[@]}" update -y >>"$LOG_FILE" 2>&1
}

install_documentserver() {
    info "Installing onlyoffice-documentserver package"
    export UCF_FORCE_CONFFOLD=1
    export UCF_FORCE_CONFFNEW=0
    local apt_opts=(
        "-o" "Dpkg::Options::=--force-confold"
        "-o" "Dpkg::Options::=--force-confdef"
    )
    if ! DEBIAN_FRONTEND=noninteractive apt-get "${APT_OPTS[@]}" install "${apt_opts[@]}" -y onlyoffice-documentserver >>"$LOG_FILE" 2>&1; then
        warning "Package install reported an error, attempting to repair configuration"
        prepare_documentserver_prereqs
        if ! DEBIAN_FRONTEND=noninteractive dpkg --force-confdef --force-confold --configure -a >>"$LOG_FILE" 2>&1; then
            abort "dpkg --configure -a failed; check $LOG_FILE for details"
        fi
    fi
    for svc in "${DS_SERVICES[@]}"; do
        systemctl enable "$svc" >>"$LOG_FILE" 2>&1 || warning "Service $svc unavailable to enable"
    done
}

configure_local_json() {
    info "Configuring DocumentServer local.json"
    python3 -m src.lib.configure_onlyoffice render-local-json \
        --template "$LOCAL_JSON_TEMPLATE" \
        --output "$LOCAL_JSON" \
        --nextcloud-fqdn "$NEXTCLOUD_FQDN" \
        --onlyoffice-fqdn "${ONLYOFFICE_FQDN:-}" \
        --jwt-secret "$JWT_SECRET" \
        --db-name "$ONLYOFFICE_DB_NAME" \
        --db-user "$ONLYOFFICE_DB_USER" \
        --db-password "$ONLYOFFICE_DB_PASSWORD"
    chown ds:ds "$LOCAL_JSON"
    chmod 600 "$LOCAL_JSON"
}

configure_ds_conf() {
    info "Ensuring DocumentServer nginx listens on 127.0.0.1:8080"
    local ds_dir="$(dirname "$DS_CONF")"
    local includes_dir="$ds_dir/includes"
    local includes_src="${PROJECT_ROOT}/configs/onlyoffice/nginx/includes"
    local logrotate_dir="/etc/onlyoffice/documentserver/logrotate"
    local logrotate_src="${PROJECT_ROOT}/configs/onlyoffice/logrotate/ds.conf"
    mkdir -p "$ds_dir"

    if [[ -d "$includes_src" ]]; then
        mkdir -p "$includes_dir"
        cp -f "$includes_src"/*.conf "$includes_dir" 2>/dev/null || true
        chown root:root "$includes_dir"/*.conf 2>/dev/null || true
        chmod 644 "$includes_dir"/*.conf 2>/dev/null || true
    fi

    if [[ -f "$logrotate_src" ]]; then
        mkdir -p "$logrotate_dir"
        cp -f "$logrotate_src" "$logrotate_dir/ds.conf"
        chown root:root "$logrotate_dir/ds.conf"
        chmod 644 "$logrotate_dir/ds.conf"
    fi

    python3 -m src.lib.configure_onlyoffice render-ds-conf \
        --template "$DS_CONF_TEMPLATE" \
        --output "$DS_CONF" \
        --existing "$DS_CONF"

    chown root:root "$DS_CONF"
    chmod 644 "$DS_CONF"

    if [[ ! -L /etc/nginx/conf.d/ds.conf || "$(readlink -f /etc/nginx/conf.d/ds.conf 2>/dev/null)" != "$DS_CONF" ]]; then
        ln -sf "$DS_CONF" /etc/nginx/conf.d/ds.conf
    fi
}

initialize_database() {
    if [[ ! -d "$POSTGRES_SCHEMA_DIR" ]]; then
        warning "PostgreSQL schema directory not found at $POSTGRES_SCHEMA_DIR; skipping schema initialization"
        return
    fi

    info "Ensuring OnlyOffice database schema"
    PGPASSWORD="$ONLYOFFICE_DB_PASSWORD" psql -h localhost -U "$ONLYOFFICE_DB_USER" -d "$ONLYOFFICE_DB_NAME" -f "$POSTGRES_SCHEMA_DIR/removetbl.sql" >>"$LOG_FILE" 2>&1 || true
    if ! PGPASSWORD="$ONLYOFFICE_DB_PASSWORD" psql -h localhost -U "$ONLYOFFICE_DB_USER" -d "$ONLYOFFICE_DB_NAME" -f "$POSTGRES_SCHEMA_DIR/createdb.sql" >>"$LOG_FILE" 2>&1; then
        abort "Failed to initialize OnlyOffice database schema"
    fi
}

restart_documentserver() {
    info "Restarting DocumentServer services"
    for svc in "${DS_SERVICES[@]}"; do
        systemctl restart "$svc" >>"$LOG_FILE" 2>&1 || warning "Failed to restart $svc"
    done
    sleep 5
}

healthcheck() {
    info "Running DocumentServer health checks"
    local attempt=0
    local max_attempts=15
    until curl -fsS --max-time 10 http://127.0.0.1:8080/healthcheck >/dev/null 2>&1; do
        ((attempt++))
        if (( attempt >= max_attempts )); then
            abort "DocumentServer healthcheck failed after ${max_attempts} attempts"
        fi
        sleep 2
    done
    curl -fsS --max-time 30 http://127.0.0.1:8080/hosting/discovery >/dev/null 2>&1 || warning "Hosting discovery returned non-200 response"
}

summarise() {
    success "OnlyOffice installation/configuration complete"
    for svc in "${DS_SERVICES[@]}"; do
        printf "${CYAN}${BOLD}%s status${NC}: %s\n" "$svc" "$(systemctl is-active "$svc" 2>/dev/null || echo unknown)"
    done
    printf "${CYAN}${BOLD}Database${NC}: postgres://%s:***@localhost/%s\n" "$ONLYOFFICE_DB_USER" "$ONLYOFFICE_DB_NAME"
    printf "${CYAN}${BOLD}JWT secret${NC}: %s\n" "$JWT_SECRET"
    printf "${CYAN}${BOLD}Next steps${NC}:\n"
    printf "  1. Run ./05_nginx_config.sh (once refactored) to expose /onlyoffice/ via nginx.\n"
}

main() {
    check_root
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"
    ensure_params_file
    load_params
    ensure_ds_account
    prepare_documentserver_prereqs
    ensure_packages
    configure_repository
    preseed_debconf
    install_documentserver
    configure_local_json
    configure_ds_conf
    initialize_database
    restart_documentserver
    healthcheck
    summarise
}

main "$@"
