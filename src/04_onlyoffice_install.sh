#!/bin/bash

# Nextcloud + OnlyOffice Bare Metal Installation
# Step 4: OnlyOffice Document Server Installation
# 
# This script installs and configures OnlyOffice Document Server:
# - Adds OnlyOffice repository
# - Installs Document Server
# - Configures for localhost access
# - Sets up JWT authentication
# - Configures PostgreSQL connection
# - Optimizes for single-domain setup

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/nextcloud-install.log"
ONLYOFFICE_PORT="8080"
ONLYOFFICE_CONFIG_DIR="/etc/onlyoffice/documentserver"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

# Generate secure random password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if PostgreSQL credentials exist
    if [[ ! -f /root/onlyoffice-db-credentials.txt ]]; then
        error "OnlyOffice database not configured. Please run 02_database_setup.sh first."
    fi
    
    # Check if PostgreSQL is running
    if ! systemctl is-active --quiet postgresql; then
        error "PostgreSQL is not running. Please run 02_database_setup.sh first."
    fi
    
    # Check if Nextcloud is installed
    if [[ ! -f /root/nextcloud-admin-credentials.txt ]]; then
        error "Nextcloud not installed. Please run 03_nextcloud_install.sh first."
    fi
    
    log "Prerequisites check passed"
}

# Add OnlyOffice repository
add_repository() {
    log "Adding OnlyOffice repository..."
    
    # Install required packages
    apt update
    apt install -y gnupg2 ca-certificates apt-transport-https
    
    # Add OnlyOffice GPG key
    wget -qO - https://download.onlyoffice.com/repo/onlyoffice.key | gpg --dearmor > /usr/share/keyrings/onlyoffice.gpg
    
    # Add repository
    echo "deb [signed-by=/usr/share/keyrings/onlyoffice.gpg] https://download.onlyoffice.com/repo/debian squeeze main" > /etc/apt/sources.list.d/onlyoffice.list
    
    # Update package list
    apt update
    
    log "OnlyOffice repository added"
}

# Install OnlyOffice Document Server
install_onlyoffice() {
    log "Installing OnlyOffice Document Server..."
    
    # Set environment variables for non-interactive installation
    export DEBIAN_FRONTEND=noninteractive
    
    # Pre-configure database settings
    local db_host="localhost"
    local db_port="5432"
    local db_name=$(grep "Database:" /root/onlyoffice-db-credentials.txt | cut -d' ' -f2)
    local db_user=$(grep "Username:" /root/onlyoffice-db-credentials.txt | cut -d' ' -f2)
    local db_pass=$(grep "Password:" /root/onlyoffice-db-credentials.txt | cut -d' ' -f2)
    
    # Pre-seed debconf values
    echo "onlyoffice-documentserver onlyoffice/ds-port select 80" | debconf-set-selections
    echo "onlyoffice-documentserver onlyoffice/db-host string $db_host" | debconf-set-selections
    echo "onlyoffice-documentserver onlyoffice/db-port string $db_port" | debconf-set-selections
    echo "onlyoffice-documentserver onlyoffice/db-name string $db_name" | debconf-set-selections
    echo "onlyoffice-documentserver onlyoffice/db-user string $db_user" | debconf-set-selections
    echo "onlyoffice-documentserver onlyoffice/db-pwd password $db_pass" | debconf-set-selections
    
    # Install OnlyOffice Document Server
    apt install -y onlyoffice-documentserver
    
    log "OnlyOffice Document Server installed"
}

# Configure OnlyOffice for localhost access
configure_localhost_access() {
    log "Configuring OnlyOffice for localhost access..."
    
    # Stop OnlyOffice services
    systemctl stop onlyoffice-documentserver
    
    # Configure nginx to listen on localhost only
    local nginx_config="/etc/onlyoffice/documentserver/nginx/ds.conf"
    
    if [[ -f "$nginx_config" ]]; then
        # Backup original config
        cp "$nginx_config" "$nginx_config.backup.$(date +%s)"
        
        # Modify listen directive to localhost only
        sed -i "s/listen 80;/listen 127.0.0.1:$ONLYOFFICE_PORT;/" "$nginx_config"
        sed -i "s/listen \[::\]:80;/# listen [::]:80;/" "$nginx_config"
        
        log "OnlyOffice nginx configured for localhost:$ONLYOFFICE_PORT"
    else
        warning "OnlyOffice nginx config not found at $nginx_config"
    fi
    
    # Start OnlyOffice services
    systemctl start onlyoffice-documentserver
    systemctl enable onlyoffice-documentserver
}

# Configure JWT authentication
configure_jwt() {
    log "Configuring JWT authentication..."
    
    # Generate JWT secret
    local jwt_secret=$(generate_password)
    
    # Configure JWT in local.json
    local local_json="$ONLYOFFICE_CONFIG_DIR/local.json"
    
    if [[ ! -f "$local_json" ]]; then
        # Create local.json if it doesn't exist
        echo '{}' > "$local_json"
    fi
    
    # Backup original config
    cp "$local_json" "$local_json.backup.$(date +%s)"
    
    # Configure JWT settings
    jq --arg secret "$jwt_secret" '
    .services.CoAuthoring.token.enable = true |
    .services.CoAuthoring.token.secret = $secret |
    .services.CoAuthoring.token.header = "Authorization"
    ' "$local_json" > "$local_json.tmp" && mv "$local_json.tmp" "$local_json"
    
    # Save JWT secret for Nextcloud configuration
    cat > /root/onlyoffice-jwt-secret.txt << EOF
OnlyOffice JWT Configuration
===========================
JWT Secret: $jwt_secret
JWT Header: Authorization

Use this secret when configuring the OnlyOffice connector in Nextcloud.
EOF
    chmod 600 /root/onlyoffice-jwt-secret.txt
    
    log "JWT authentication configured"
}

# Configure OnlyOffice for single domain setup
configure_single_domain() {
    log "Configuring OnlyOffice for single domain setup..."
    
    local local_json="$ONLYOFFICE_CONFIG_DIR/local.json"
    
    # Configure for single domain with subpath
    jq '
    .services.CoAuthoring.server.port = 8080 |
    .services.CoAuthoring.server.host = "127.0.0.1" |
    .storage.fs.secretString = "onlyoffice_secret" |
    .rabbitmq.url = "amqp://guest:guest@localhost" |
    .redis.host = "127.0.0.1"
    ' "$local_json" > "$local_json.tmp" && mv "$local_json.tmp" "$local_json"
    
    log "Single domain configuration applied"
}

# Test OnlyOffice installation
test_onlyoffice() {
    log "Testing OnlyOffice installation..."
    
    # Wait for services to start
    sleep 10
    
    # Test if OnlyOffice is responding
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if curl -s "http://127.0.0.1:$ONLYOFFICE_PORT/healthcheck" | grep -q "true"; then
            log "✓ OnlyOffice healthcheck passed"
            break
        else
            if [[ $attempt -eq $max_attempts ]]; then
                error "✗ OnlyOffice healthcheck failed after $max_attempts attempts"
            fi
            warning "OnlyOffice not ready, attempt $attempt/$max_attempts..."
            sleep 5
            ((attempt++))
        fi
    done
    
    # Test discovery endpoint
    if curl -s "http://127.0.0.1:$ONLYOFFICE_PORT/hosting/discovery" | grep -q "wopi-discovery"; then
        log "✓ OnlyOffice discovery endpoint working"
    else
        warning "✗ OnlyOffice discovery endpoint not responding"
    fi
}

# Restart OnlyOffice services
restart_services() {
    log "Restarting OnlyOffice services..."
    
    # Stop all OnlyOffice services
    systemctl stop onlyoffice-documentserver
    
    # Wait a moment
    sleep 5
    
    # Start services
    systemctl start onlyoffice-documentserver
    
    # Check service status
    if systemctl is-active --quiet onlyoffice-documentserver; then
        log "✓ OnlyOffice Document Server is running"
    else
        error "✗ OnlyOffice Document Server failed to start"
    fi
}

# Save installation summary
save_install_info() {
    local info_file="/root/onlyoffice-install-summary.txt"
    local jwt_secret=$(grep "JWT Secret:" /root/onlyoffice-jwt-secret.txt | cut -d' ' -f3)
    
    cat > "$info_file" << EOF
OnlyOffice Document Server Installation Summary
==============================================
Date: $(date)

Installation Details:
- Service: onlyoffice-documentserver
- Port: $ONLYOFFICE_PORT (localhost only)
- Config Directory: $ONLYOFFICE_CONFIG_DIR
- Database: PostgreSQL (configured)

Access URLs:
- Internal: http://127.0.0.1:$ONLYOFFICE_PORT/
- Healthcheck: http://127.0.0.1:$ONLYOFFICE_PORT/healthcheck
- Discovery: http://127.0.0.1:$ONLYOFFICE_PORT/hosting/discovery

JWT Configuration:
- Secret: $jwt_secret
- Header: Authorization
- File: /root/onlyoffice-jwt-secret.txt

Database Configuration:
- Credentials: /root/onlyoffice-db-credentials.txt
- Type: PostgreSQL
- Host: localhost:5432

Next Steps:
1. Run 05_nginx_config.sh to configure reverse proxy
2. Run 06_integration_config.sh to connect with Nextcloud
3. Test document editing functionality

Service Management:
- Start: systemctl start onlyoffice-documentserver
- Stop: systemctl stop onlyoffice-documentserver
- Status: systemctl status onlyoffice-documentserver
- Logs: journalctl -u onlyoffice-documentserver

Log File: $LOG_FILE
EOF

    log "Installation summary saved to: $info_file"
}

# Main execution
main() {
    log "Starting OnlyOffice Document Server installation..."
    
    check_root
    check_prerequisites
    add_repository
    install_onlyoffice
    configure_localhost_access
    configure_jwt
    configure_single_domain
    restart_services
    test_onlyoffice
    save_install_info
    
    log "✓ OnlyOffice Document Server installation completed successfully!"
    echo ""
    info "JWT secret saved to: /root/onlyoffice-jwt-secret.txt"
    info "Installation summary: /root/onlyoffice-install-summary.txt"
    echo ""
    info "OnlyOffice is running on: http://127.0.0.1:$ONLYOFFICE_PORT/"
    echo ""
    info "Next step: Run 05_nginx_config.sh"
    echo ""
    info "Log file: $LOG_FILE"
}

# Run main function
main "$@"
