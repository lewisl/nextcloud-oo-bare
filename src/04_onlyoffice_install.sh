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
PRODUCTION_JSON="/etc/onlyoffice/documentserver/production-linux.json"
DS_CONF="/etc/onlyoffice/documentserver/nginx/ds.conf"
DS_SERVICES=(ds-converter ds-docservice ds-metrics)

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

ensure_packages() {
    info "Ensuring apt dependencies for OnlyOffice"
    DEBIAN_FRONTEND=noninteractive apt-get update -y >>"$LOG_FILE" 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl gnupg ca-certificates apt-transport-https >>"$LOG_FILE" 2>&1
}

configure_repository() {
    info "Configuring OnlyOffice apt repository"
    if [[ ! -f "$KEYRING" ]]; then
        curl -fsSL https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE | gpg --dearmor -o "$KEYRING"
    fi
    if [[ ! -f "$APT_LIST" ]]; then
        echo "deb [signed-by=$KEYRING] https://download.onlyoffice.com/repo/debian squeeze main" > "$APT_LIST"
    fi
    DEBIAN_FRONTEND=noninteractive apt-get update -y >>"$LOG_FILE" 2>&1
}

install_documentserver() {
    info "Installing onlyoffice-documentserver package"
    DEBIAN_FRONTEND=noninteractive apt-get install -y onlyoffice-documentserver >>"$LOG_FILE" 2>&1
    for svc in "${DS_SERVICES[@]}"; do
        systemctl enable "$svc" >>"$LOG_FILE" 2>&1 || warning "Service $svc unavailable to enable"
    done
}

configure_local_json() {
    info "Configuring DocumentServer local.json"
    LOCAL_JSON_PATH="$LOCAL_JSON" python3 <<'PY'
from __future__ import annotations
import json
import os
from pathlib import Path

env = os.environ
local_path = Path(env["LOCAL_JSON_PATH"])
local_path.parent.mkdir(parents=True, exist_ok=True)

try:
    data = json.loads(local_path.read_text())
except Exception:
    data = {}

services = data.setdefault("services", {})
co = services.setdefault("CoAuthoring", {})

co["server"] = {"ip": "127.0.0.1", "port": 8000}
co["sql"] = {
    "type": "postgres",
    "dbHost": "localhost",
    "dbPort": "5432",
    "dbName": env["ONLYOFFICE_DB_NAME"],
    "dbUser": env["ONLYOFFICE_DB_USER"],
    "dbPass": env["ONLYOFFICE_DB_PASSWORD"],
}

token = co.setdefault("token", {})
token["enable"] = {"browser": True, "request": {"inbox": True, "outbox": True}}
token["browser"] = {"secretFromInbox": False}
token["inbox"] = {"header": "AuthorizationJwt", "prefix": "Bearer ", "inBody": False}
token["outbox"] = {
    "header": "AuthorizationJwt",
    "prefix": "Bearer ",
    "algorithm": "HS256",
    "expires": "5m",
    "inBody": False,
    "urlExclusionRegex": "",
}
token["session"] = {"algorithm": "HS256", "expires": "30d"}
token["verifyOptions"] = {"clockTolerance": 60}
co["secret"] = {
    "browser": {"string": env["JWT_SECRET"], "file": ""},
    "inbox": {"string": env["JWT_SECRET"], "file": ""},
    "outbox": {"string": env["JWT_SECRET"], "file": ""},
    "session": {"string": env["JWT_SECRET"], "file": ""},
}

rf = co.setdefault("request-filtering", {})
allowed = {h for h in rf.get("allowedHosts", []) if h}
allowed.update({env["NEXTCLOUD_FQDN"], env.get("ONLYOFFICE_FQDN", ""), "127.0.0.1"})
allowed = {h for h in allowed if h}
rf["enable"] = True
rf["allowPrivateIPAddress"] = True
rf["allowLoopback"] = True
rf["allowedHosts"] = sorted(allowed)

data.setdefault("rabbitmq", {})["url"] = "amqp://guest:guest@localhost"
data.setdefault("wopi", {})["enable"] = True

local_path.write_text(json.dumps(data, indent=2) + "\n")
PY
    chown ds:ds "$LOCAL_JSON"
    chmod 600 "$LOCAL_JSON"
}

configure_production_json() {
    info "Configuring DocumentServer production-linux.json"
    install -m 00644 -o ds -g ds "${PROJECT_ROOT}/configs/onlyoffice/production-linux.json" "$PRODUCTION_JSON"
}

configure_ds_conf() {
    info "Ensuring DocumentServer nginx listens on 127.0.0.1:8080"
    if [[ -f "$DS_CONF" ]]; then
        if ! grep -q "listen 127.0.0.1:8080" "$DS_CONF"; then
            sed -i 's/^\s*listen [^;]*;/  listen 127.0.0.1:8080;/' "$DS_CONF"
        fi
    else
        warning "ds.conf not found; skipping nginx binding update"
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
    until curl -fsS http://127.0.0.1:8080/healthcheck >/dev/null 2>&1; do
        ((attempt++))
        if (( attempt > 10 )); then
            abort "DocumentServer healthcheck failed after 10 attempts"
        fi
        sleep 2
    done
    curl -fsS http://127.0.0.1:8080/hosting/discovery >/dev/null 2>&1 || warning "Hosting discovery returned non-200 response"
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
    ensure_packages
    configure_repository
    install_documentserver
    configure_local_json
    configure_production_json
    configure_ds_conf
    restart_documentserver
    healthcheck
    summarise
}

main "$@"
