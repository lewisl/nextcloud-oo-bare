#!/bin/bash

# Nextcloud + OnlyOffice Bare Metal Installation
# CORRECTED Master Installation Script
# 
# This script runs all installation steps in the correct order with proper verification

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/nextcloud-master-install.log"

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

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

# Run a script and verify it succeeded
run_script() {
    local script_name="$1"
    local description="$2"
    
    log "=== STEP: $description ==="
    
    if [[ ! -f "$SCRIPT_DIR/$script_name" ]]; then
        error "Script not found: $script_name"
    fi
    
    if ! bash "$SCRIPT_DIR/$script_name"; then
        error "Failed: $description ($script_name)"
    fi
    
    log "✓ Completed: $description"
    echo ""
}

# Verify step completed successfully
verify_step() {
    local step_name="$1"
    local verification_command="$2"
    
    log "Verifying: $step_name"
    
    if ! eval "$verification_command"; then
        error "Verification failed: $step_name"
    fi
    
    log "✓ Verified: $step_name"
}

# Test Nextcloud web access
test_nextcloud_web() {
    log "Testing Nextcloud web access..."
    
    # Test HTTP response
    if curl -s -o /dev/null -w "%{http_code}" http://localhost/ | grep -q "200"; then
        log "✓ Nextcloud web interface is accessible"
        
        # Display login information
        if [[ -f /root/nextcloud-admin-credentials.txt ]]; then
            info "=== NEXTCLOUD LOGIN CREDENTIALS ==="
            grep -E "^(Admin Username|Admin Password):" /root/nextcloud-admin-credentials.txt
            info "URL: http://localhost/ (or your server's IP)"
            info "=================================="
        fi
    else
        warning "Nextcloud web interface not accessible via HTTP"
    fi
}

# Main installation process
main() {
    log "Starting Nextcloud + OnlyOffice installation (CORRECTED ORDER)"
    log "Installation log: $LOG_FILE"
    
    check_root
    
    # Step 1: System preparation with ALL required PHP modules
    run_script "01_system_prep.sh" "System Preparation & PHP Installation"
    verify_step "Nginx installed" "command -v nginx"
    verify_step "PHP 8.3 installed" "php --version | grep -q '8.3'"
    verify_step "PHP modules loaded" "php -m | grep -q posix && php -m | grep -q SimpleXML"
    
    # Step 2: Database setup
    run_script "02_database_setup.sh" "Database Setup (MariaDB + PostgreSQL)"
    verify_step "MariaDB running" "systemctl is-active --quiet mariadb"
    verify_step "PostgreSQL running" "systemctl is-active --quiet postgresql"
    verify_step "Nextcloud DB exists" "mysql -e 'SHOW DATABASES;' | grep -q nextcloud"
    verify_step "OnlyOffice DB exists" "sudo -u postgres psql -l | grep -q onlyoffice"
    
    # Step 3: Basic nginx configuration (HTTP only)
    log "=== STEP: Basic Nginx Configuration (HTTP) ==="
    create_basic_nginx_config
    verify_step "Nginx config valid" "nginx -t"
    systemctl reload nginx
    log "✓ Completed: Basic Nginx Configuration"
    echo ""
    
    # Step 4: Nextcloud installation
    run_script "03_nextcloud_install.sh" "Nextcloud Installation"
    verify_step "Nextcloud installed" "[[ -f /root/nextcloud-admin-credentials.txt ]]"
    verify_step "Nextcloud config exists" "[[ -f /var/www/nextcloud/config/config.php ]]"
    
    # Step 5: Test Nextcloud web access
    test_nextcloud_web
    
    # Step 6: OnlyOffice installation
    run_script "04_onlyoffice_install.sh" "OnlyOffice Document Server Installation"
    verify_step "OnlyOffice services running" "systemctl is-active --quiet onlyoffice-documentserver"
    verify_step "OnlyOffice responding" "curl -s http://localhost:8080/healthcheck | grep -q 'true'"
    
    # Step 7: Update nginx for OnlyOffice proxy
    log "=== STEP: Update Nginx for OnlyOffice Proxy ==="
    update_nginx_for_onlyoffice
    verify_step "Nginx config valid" "nginx -t"
    systemctl reload nginx
    log "✓ Completed: Nginx OnlyOffice Proxy"
    echo ""
    
    # Step 8: Integration configuration
    run_script "07_integration_config.sh" "Nextcloud-OnlyOffice Integration"
    
    # Final verification
    log "=== FINAL VERIFICATION ==="
    test_nextcloud_web
    verify_step "OnlyOffice accessible via proxy" "curl -s http://localhost/onlyoffice/healthcheck | grep -q 'true'"
    
    log "🎉 Installation completed successfully!"
    
    # Display summary
    info "=== INSTALLATION SUMMARY ==="
    info "Nextcloud: http://localhost/"
    info "OnlyOffice: http://localhost/onlyoffice/"
    if [[ -f /root/nextcloud-admin-credentials.txt ]]; then
        info "Admin credentials: /root/nextcloud-admin-credentials.txt"
    fi
    info "Installation log: $LOG_FILE"
    info "=========================="
}

# Create basic HTTP-only nginx config
create_basic_nginx_config() {
    log "Creating basic nginx configuration..."
    
    # Backup existing default
    if [[ -f /etc/nginx/sites-enabled/default ]]; then
        mv /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/default.backup
    fi
    
    # Create basic Nextcloud config
    cat > /etc/nginx/sites-available/nextcloud-basic << 'EOF'
server {
    listen 80;
    server_name _;
    
    root /var/www/nextcloud;
    index index.php index.html;
    
    client_max_body_size 512M;
    fastcgi_buffers 64 4K;
    
    location / {
        try_files $uri $uri/ /index.php$request_uri;
    }
    
    location ~ ^\/(?:build|tests|config|lib|3rdparty|templates|data)\/ {
        deny all;
    }
    
    location ~ ^\/(?:\.|autotest|occ|issue|indie|db_|console) {
        deny all;
    }
    
    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.*)$;
        try_files $fastcgi_script_name =404;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
    }
}
EOF
    
    # Enable the site
    ln -sf /etc/nginx/sites-available/nextcloud-basic /etc/nginx/sites-enabled/
    
    log "Basic nginx configuration created"
}

# Update nginx to include OnlyOffice proxy
update_nginx_for_onlyoffice() {
    log "Adding OnlyOffice proxy to nginx..."
    
    # Add OnlyOffice location block to existing config
    sed -i '/location ~ \.php\$ {/i\
    # OnlyOffice Document Server proxy\
    location /onlyoffice/ {\
        proxy_pass http://127.0.0.1:8080/;\
        proxy_http_version 1.1;\
        proxy_set_header Upgrade $http_upgrade;\
        proxy_set_header Connection "upgrade";\
        proxy_set_header Host $host;\
        proxy_set_header X-Real-IP $remote_addr;\
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\
        proxy_set_header X-Forwarded-Proto $scheme;\
        proxy_redirect off;\
    }\
    \
    location /onlyoffice/healthcheck {\
        proxy_pass http://127.0.0.1:8080/healthcheck;\
        proxy_http_version 1.1;\
        proxy_set_header Host $host;\
    }\
' /etc/nginx/sites-available/nextcloud-basic
    
    log "OnlyOffice proxy configuration added"
}

# Run main function
main "$@"
