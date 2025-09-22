#!/bin/bash

# OnlyOffice Installation Script for 2-Domain Setup
# Installs and configures OnlyOffice Document Server to run behind the
# system nginx reverse proxy on onlyoffice.DOMAIN.com.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Logging helpers keep the original script style
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

load_config() {
    local cfg="/etc/nextcloud-onlyoffice/params.yaml"
    if [[ ! -f "$cfg" ]]; then
        error "Configuration file $cfg not found. Run 01_system_prep_dual_domain.sh first."
        exit 1
    fi

    BASE_DOMAIN=$(awk -F': *' '/^[[:space:]]*base_domain:/ {gsub(/[" ]/,"",$2); print $2; exit}' "$cfg")
    NEXTCLOUD_DOMAIN=$(awk -F': *' '/^[[:space:]]*nextcloud_domain:/ {gsub(/[" ]/,"",$2); print $2; exit}' "$cfg")
    ONLYOFFICE_DOMAIN=$(awk -F': *' '/^[[:space:]]*onlyoffice_domain:/ {gsub(/"/,"",$2); gsub(/[[:space:]]/ ,"", $2); print $2; exit}' "$cfg")
    ADMIN_EMAIL=$(awk -F': *' '/^[[:space:]]*admin_email:/ {gsub(/"/,"",$2); gsub(/[[:space:]]/ ,"", $2); print $2; exit}' "$cfg")

    OO_DB_NAME=$(awk -F': *' 'BEGIN{section=0} /^[[:space:]]*onlyoffice:/ {section=1; next} section && /^[[:space:]]*db_name:/ {gsub(/"/,"",$2); print $2; exit} /^[^[:space:]]/ {section=0}' "$cfg")
    OO_DB_USER=$(awk -F': *' 'BEGIN{section=0} /^[[:space:]]*onlyoffice:/ {section=1; next} section && /^[[:space:]]*db_user:/ {gsub(/"/,"",$2); print $2; exit} /^[^[:space:]]/ {section=0}' "$cfg")
    OO_DB_PASSWORD=$(awk -F': *' 'BEGIN{section=0} /^[[:space:]]*onlyoffice:/ {section=1; next} section && /^[[:space:]]*db_password:/ {gsub(/"/,"",$2); print $2; exit} /^[^[:space:]]/ {section=0}' "$cfg")

    JWT_SECRET=$(awk -F': *' 'BEGIN{section=0} /^[[:space:]]*jwt:/ {section=1; next} section && /^[[:space:]]*secret:/ {gsub(/"/,"",$2); print $2; exit} /^[^[:space:]]/ {section=0}' "$cfg")

    PARAMS_FILE="$cfg"
}

ensure_jwt_secret() {
    if [[ -z "$JWT_SECRET" ]]; then
        JWT_SECRET=$(openssl rand -hex 32)
        info "Generated new JWT secret"
        if [[ -f "$PARAMS_FILE" ]]; then
            python3 - "$PARAMS_FILE" "$JWT_SECRET" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
secret = sys.argv[2]
lines = path.read_text().splitlines()
for idx, line in enumerate(lines):
    if line.strip().startswith('secret:'):
        prefix = line.split('secret:')[0]
        lines[idx] = f"{prefix}secret: \"{secret}\""
        break
path.write_text('\n'.join(lines) + '\n')
PY
        fi
    fi
}

show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat <<'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                   2-DOMAIN ONLYOFFICE INSTALLATION                          ║
║          Installing OnlyOffice for onlyoffice.DOMAIN.com                    ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo ""
    info "OnlyOffice public domain : https://$ONLYOFFICE_DOMAIN"
    info "Nextcloud domain         : https://$NEXTCLOUD_DOMAIN"
    info "PostgreSQL database      : $OO_DB_NAME (user: $OO_DB_USER)"
    echo ""
}

ensure_prerequisites() {
    header "Installing prerequisites"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y curl gnupg ca-certificates apt-transport-https jq > /dev/null
    success "Base packages present"
}

add_onlyoffice_repo() {
    header "Adding OnlyOffice repository"
    local keyring="/usr/share/keyrings/onlyoffice.gpg"
    curl -fsSL https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE | gpg --dearmor -o "$keyring"
    echo "deb [signed-by=$keyring] https://download.onlyoffice.com/repo/debian squeeze main" \
        > /etc/apt/sources.list.d/onlyoffice.list
    apt-get update -y
    success "OnlyOffice repository configured"
}

install_onlyoffice_packages() {
    header "Installing OnlyOffice Document Server"
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y onlyoffice-documentserver
    success "OnlyOffice packages installed"
}

configure_local_json() {
    header "Configuring /etc/onlyoffice/documentserver/local.json"
    local cfg="/etc/onlyoffice/documentserver/local.json"
    local dir="$(dirname "$cfg")"
    mkdir -p "$dir"
    if [[ ! -f "$cfg" ]]; then
        echo '{}' > "$cfg"
    fi

    python3 - "$cfg" "$JWT_SECRET" <<'PY'
import json
import sys
from pathlib import Path

cfg = Path(sys.argv[1])
secret = sys.argv[2]

try:
    data = json.loads(cfg.read_text())
except Exception:
    data = {}

services = data.setdefault('services', {})
coauthoring = services.setdefault('CoAuthoring', {})
coauthoring['server'] = {"ip": "127.0.0.1", "port": 8000}

token = coauthoring.setdefault('token', {})
token['enable'] = True
token['inbox'] = {"string": secret}
token['outbox'] = {"string": secret}
token['browser'] = {"string": secret}
token['authorizationHeader'] = "Authorization"

rabbitmq = data.setdefault('rabbitmq', {})
rabbitmq.setdefault('url', 'amqp://guest:guest@localhost')

cfg.write_text(json.dumps(data, indent=2) + '\n')
PY

    chown ds:ds "$cfg"
    chmod 600 "$cfg"
    success "local.json updated with JWT secret and loopback binding"
}

configure_internal_nginx() {
    header "Configuring OnlyOffice internal nginx"
    local conf="/etc/onlyoffice/documentserver/nginx/ds.conf"
    if [[ ! -f "$conf" ]]; then
        warning "OnlyOffice nginx configuration not found ($conf)"
        return
    fi

    cp "$conf" "$conf.bak.$(date +%s)"

    sed -i 's/listen 0\.0\.0\.0:80;/listen 127.0.0.1:8080;/' "$conf"
    if grep -q 'listen \[::\]:80;' "$conf"; then
        sed -i 's/listen \[::\]:80;/# listen [::]:80; # disabled for loopback proxy/' "$conf"
    fi

    if ! grep -q 'proxy_set_header X-Forwarded-Proto $the_scheme;' "$conf"; then
        warning "Expected proxy headers missing in $conf; review manually."
    fi

    success "Internal nginx configured to listen on 127.0.0.1:8080"
}

configure_main_nginx() {
    header "Configuring main nginx for $ONLYOFFICE_DOMAIN"
    local site="/etc/nginx/sites-available/$ONLYOFFICE_DOMAIN"
    local https_block=""
    local cert="/etc/letsencrypt/live/$ONLYOFFICE_DOMAIN/fullchain.pem"
    local key="/etc/letsencrypt/live/$ONLYOFFICE_DOMAIN/privkey.pem"
    if [[ -f "$cert" && -f "$key" ]]; then
        https_block="server {\n    listen 443 ssl http2;\n    listen [::]:443 ssl http2;\n    server_name $ONLYOFFICE_DOMAIN;\n\n    ssl_certificate     $cert;\n    ssl_certificate_key $key;\n    ssl_session_timeout 1d;\n    ssl_session_cache shared:SSL:10m;\n    ssl_protocols TLSv1.2 TLSv1.3;\n\n    add_header Strict-Transport-Security \"max-age=63072000\" always;\n    add_header X-Frame-Options \"SAMEORIGIN\" always;\n    add_header X-Content-Type-Options \"nosniff\" always;\n    add_header Referrer-Policy \"no-referrer-when-downgrade\" always;\n\n    location / {\n        proxy_pass http://127.0.0.1:8080;\n        proxy_http_version 1.1;\n        proxy_set_header Host              \$host;\n        proxy_set_header X-Real-IP         \$remote_addr;\n        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;\n        proxy_set_header X-Forwarded-Proto \$scheme;\n        proxy_set_header Upgrade           \$http_upgrade;\n        proxy_set_header Connection        \"upgrade\";\n        client_max_body_size 200m;\n        proxy_read_timeout 360s;\n        proxy_send_timeout 360s;\n        proxy_buffering off;\n    }\n\n    location /healthcheck {\n        proxy_pass http://127.0.0.1:8080/healthcheck;\n        access_log off;\n    }\n}\n"
    else
        warning "TLS certificates not found for $ONLYOFFICE_DOMAIN; configuring HTTP-only vhost"
    fi

    cat > "$site" <<EOF
# OnlyOffice public reverse proxy
server {
    listen 80;
    listen [::]:80;
    server_name $ONLYOFFICE_DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade           \$http_upgrade;
        proxy_set_header Connection        "upgrade";
        client_max_body_size 200m;
        proxy_read_timeout 360s;
        proxy_send_timeout 360s;
        proxy_buffering off;
    }

    location /healthcheck {
        proxy_pass http://127.0.0.1:8080/healthcheck;
        access_log off;
    }
}

$https_block
EOF

    ln -sf "$site" "/etc/nginx/sites-enabled/$ONLYOFFICE_DOMAIN"
    nginx -t
    systemctl reload nginx
    success "Main nginx site enabled"
}

restart_documentserver() {
    header "Restarting OnlyOffice services"
    local restarted=0
    if systemctl list-unit-files | grep -q '^onlyoffice-documentserver\.service'; then
        systemctl enable onlyoffice-documentserver >/dev/null 2>&1 || true
        systemctl restart onlyoffice-documentserver
        restarted=1
    fi

    local units=(ds-docservice ds-converter ds-metrics)
    for unit in "${units[@]}"; do
        if systemctl list-unit-files | grep -q "^${unit}\.service"; then
            systemctl enable "$unit" >/dev/null 2>&1 || true
            systemctl restart "$unit"
            restarted=1
        fi
    done

    if [[ $restarted -eq 0 ]] && command -v supervisorctl >/dev/null 2>&1; then
        warning "Falling back to supervisorctl for Document Server"
        supervisorctl reread && supervisorctl update && supervisorctl restart all
    fi

    sleep 5
}

run_health_checks() {
    header "Running health checks"
    local internal=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/healthcheck || echo 000)
    if [[ "$internal" == "200" ]]; then
        success "Internal healthcheck OK"
    else
        warning "Internal healthcheck returned $internal"
    fi

    local discovery=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/hosting/discovery || echo 000)
    if [[ "$discovery" == "200" ]]; then
        success "Discovery endpoint reachable"
    else
        warning "Discovery endpoint HTTP $discovery"
    fi
}

create_backup_script() {
    header "Ensuring OnlyOffice backup helper"
    cat > /usr/local/bin/backup-onlyoffice.sh <<'EOS'
#!/bin/bash
set -euo pipefail
BACKUP_DIR="/var/backups/onlyoffice"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_DIR"
tar -czf "$BACKUP_DIR/onlyoffice-config-$DATE.tar.gz" -C /etc onlyoffice
echo "OnlyOffice config backup: $BACKUP_DIR/onlyoffice-config-$DATE.tar.gz"
find "$BACKUP_DIR" -name 'onlyoffice-config-*.tar.gz' -mtime +7 -delete
EOS
    chmod +x /usr/local/bin/backup-onlyoffice.sh
    success "Backup script ready"
}

save_installation_info() {
    header "Saving installation notes"
    cat > /root/onlyoffice_installation_info.txt <<EOF
# OnlyOffice Installation - $(date)
Public URL : https://$ONLYOFFICE_DOMAIN
Internal   : http://127.0.0.1:8080
Health     : http://$ONLYOFFICE_DOMAIN/healthcheck

Database   : $OO_DB_NAME (user $OO_DB_USER)
JWT secret : $JWT_SECRET

Key files:
  - /etc/onlyoffice/documentserver/local.json
  - /etc/onlyoffice/documentserver/nginx/ds.conf
  - /etc/nginx/sites-available/$ONLYOFFICE_DOMAIN
EOF
    chmod 600 /root/onlyoffice_installation_info.txt
    success "Installation notes saved"
}

verify_installation() {
    header "Final verification"
    local issues=0

    if ! systemctl status onlyoffice-documentserver >/dev/null 2>&1; then
        warning "onlyoffice-documentserver service not reporting healthy"
        ((issues++))
    else
        success "onlyoffice-documentserver running"
    fi

    if curl -s http://127.0.0.1:8080/hosting/discovery >/dev/null; then
        success "Discovery XML reachable"
    else
        warning "Discovery XML not reachable"
        ((issues++))
    fi

    if [[ $issues -eq 0 ]]; then
        success "OnlyOffice installation completed successfully"
    else
        warning "OnlyOffice installation finished with $issues issues"
    fi
}

main() {
    require_root
    load_config
    ensure_jwt_secret
    show_banner
    ensure_prerequisites
    add_onlyoffice_repo
    install_onlyoffice_packages
    configure_local_json
    configure_internal_nginx
    configure_main_nginx
    restart_documentserver
    run_health_checks
    create_backup_script
    save_installation_info
    verify_installation
}

main "$@"
