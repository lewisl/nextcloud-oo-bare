#!/bin/bash

# Nextcloud + OnlyOffice Bare Metal Installation
# Step 3: Nextcloud Installation
# 
# This script downloads and installs Nextcloud:
# - Downloads latest Nextcloud tarball
# - Extracts and sets proper permissions
# - Configures Nextcloud via command line
# - Sets up caching and optimization
# - Prepares for OnlyOffice integration

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/nextcloud-install.log"
NEXTCLOUD_WEB_DIR="/var/www/nextcloud"
NEXTCLOUD_DATA_DIR="/srv/nextcloud-data"
NEXTCLOUD_USER="www-data"

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
    
    # Check if database credentials exist
    if [[ ! -f /root/nextcloud-db-credentials.txt ]]; then
        error "Database not configured. Please run 02_database_setup.sh first."
    fi
    
    # Check if PHP is installed
    if ! command -v php &> /dev/null; then
        error "PHP not installed. Please run 01_system_prep.sh first."
    fi
    
    # Check if web server is running
    if ! systemctl is-active --quiet nginx; then
        error "Nginx is not running. Please run 01_system_prep.sh first."
    fi
    
    log "Prerequisites check passed"
}

# Get domain name for Nextcloud
get_domain() {
    local domain=""
    
    # Try to detect from existing nginx config
    if [[ -f /etc/nginx/sites-enabled/test-collab-site.com ]]; then
        domain="test-collab-site.com"
    else
        # Ask user for domain
        echo ""
        read -p "Enter the domain name for Nextcloud (e.g., cloud.example.com): " domain
        
        if [[ -z "$domain" ]]; then
            error "Domain name is required"
        fi
    fi
    
    echo "$domain"
}

# Download and extract Nextcloud
download_nextcloud() {
    log "Downloading Nextcloud..."
    
    local temp_dir="/tmp/nextcloud-install"
    mkdir -p "$temp_dir"
    cd "$temp_dir"
    
    # Check if already installed
    if [[ -d "$NEXTCLOUD_WEB_DIR" ]]; then
        warning "Nextcloud directory already exists: $NEXTCLOUD_WEB_DIR"
        read -p "Remove and reinstall? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$NEXTCLOUD_WEB_DIR"
            log "Removed existing installation"
        else
            error "Installation cancelled"
        fi
    fi
    
    # Download latest Nextcloud
    local download_url="https://download.nextcloud.com/server/releases/latest.tar.bz2"
    wget -O nextcloud.tar.bz2 "$download_url"
    
    # Verify download
    if [[ ! -f nextcloud.tar.bz2 ]]; then
        error "Failed to download Nextcloud"
    fi
    
    log "Extracting Nextcloud..."
    
    # Extract to web directory
    mkdir -p "$(dirname "$NEXTCLOUD_WEB_DIR")"
    tar -xjf nextcloud.tar.bz2 -C "$(dirname "$NEXTCLOUD_WEB_DIR")"
    
    # Clean up
    rm -rf "$temp_dir"
    
    log "Nextcloud downloaded and extracted"
}

# Set proper permissions
set_permissions() {
    log "Setting file permissions..."
    
    # Create data directory if it doesn't exist
    mkdir -p "$NEXTCLOUD_DATA_DIR"
    
    # Set ownership
    chown -R "$NEXTCLOUD_USER:$NEXTCLOUD_USER" "$NEXTCLOUD_WEB_DIR"
    chown -R "$NEXTCLOUD_USER:$NEXTCLOUD_USER" "$NEXTCLOUD_DATA_DIR"
    
    # Set directory permissions
    find "$NEXTCLOUD_WEB_DIR" -type d -exec chmod 750 {} \;
    find "$NEXTCLOUD_DATA_DIR" -type d -exec chmod 750 {} \;
    
    # Set file permissions
    find "$NEXTCLOUD_WEB_DIR" -type f -exec chmod 640 {} \;
    find "$NEXTCLOUD_DATA_DIR" -type f -exec chmod 640 {} \;
    
    # Set executable permissions for occ
    chmod +x "$NEXTCLOUD_WEB_DIR/occ"
    
    log "Permissions set correctly"
}

# Install Nextcloud via command line
install_nextcloud() {
    log "Installing Nextcloud via command line..."
    
    # Load database credentials
    local db_host="localhost"
    local db_name=$(grep "Database:" /root/nextcloud-db-credentials.txt | cut -d' ' -f2)
    local db_user=$(grep "Username:" /root/nextcloud-db-credentials.txt | cut -d' ' -f2)
    local db_pass=$(grep "Password:" /root/nextcloud-db-credentials.txt | cut -d' ' -f2)
    
    # Get domain
    local domain=$(get_domain)
    
    # Generate admin credentials
    local admin_user="admin"
    local admin_pass=$(generate_password)
    
    # Run Nextcloud installation
    cd "$NEXTCLOUD_WEB_DIR"
    
    sudo -u "$NEXTCLOUD_USER" php occ maintenance:install \
        --database "mysql" \
        --database-name "$db_name" \
        --database-host "$db_host" \
        --database-user "$db_user" \
        --database-pass "$db_pass" \
        --admin-user "$admin_user" \
        --admin-pass "$admin_pass" \
        --data-dir "$NEXTCLOUD_DATA_DIR"
    
    # Save admin credentials
    cat > /root/nextcloud-admin-credentials.txt << EOF
Nextcloud Admin Credentials
==========================
Admin Username: $admin_user
Admin Password: $admin_pass
Domain: $domain
URL: https://$domain/

Login at: https://$domain/login
EOF
    chmod 600 /root/nextcloud-admin-credentials.txt
    
    log "Nextcloud installed successfully"
}

# Configure Nextcloud
configure_nextcloud() {
    log "Configuring Nextcloud..."
    
    local domain=$(get_domain)
    
    cd "$NEXTCLOUD_WEB_DIR"
    
    # Set trusted domains
    sudo -u "$NEXTCLOUD_USER" php occ config:system:set trusted_domains 0 --value="localhost"
    sudo -u "$NEXTCLOUD_USER" php occ config:system:set trusted_domains 1 --value="$domain"
    
    # Set overwrite URL
    sudo -u "$NEXTCLOUD_USER" php occ config:system:set overwrite.cli.url --value="https://$domain/"
    
    # Configure caching
    sudo -u "$NEXTCLOUD_USER" php occ config:system:set memcache.local --value="\\OC\\Memcache\\APCu"
    sudo -u "$NEXTCLOUD_USER" php occ config:system:set memcache.locking --value="\\OC\\Memcache\\Redis"
    
    # Configure Redis
    sudo -u "$NEXTCLOUD_USER" php occ config:system:set redis host --value="/var/run/redis/redis-server.sock"
    sudo -u "$NEXTCLOUD_USER" php occ config:system:set redis port --value="0" --type=integer
    
    # Enable local remote servers (required for OnlyOffice)
    sudo -u "$NEXTCLOUD_USER" php occ config:system:set allow_local_remote_servers --value=true --type=boolean
    
    # Set log level
    sudo -u "$NEXTCLOUD_USER" php occ config:system:set loglevel --value="2" --type=integer
    
    # Configure default phone region (optional)
    sudo -u "$NEXTCLOUD_USER" php occ config:system:set default_phone_region --value="US"
    
    # Set maintenance window (for updates)
    sudo -u "$NEXTCLOUD_USER" php occ config:system:set maintenance_window_start --value="1" --type=integer
    
    log "Nextcloud configuration completed"
}

# Setup background jobs
setup_background_jobs() {
    log "Setting up background jobs..."
    
    # Configure cron for background jobs
    local cron_job="*/5 * * * * php -f $NEXTCLOUD_WEB_DIR/cron.php"
    
    # Add cron job for www-data user
    (sudo -u "$NEXTCLOUD_USER" crontab -l 2>/dev/null; echo "$cron_job") | sudo -u "$NEXTCLOUD_USER" crontab -
    
    # Set background jobs mode to cron
    cd "$NEXTCLOUD_WEB_DIR"
    sudo -u "$NEXTCLOUD_USER" php occ background:cron
    
    log "Background jobs configured"
}

# Install and configure apps
configure_apps() {
    log "Configuring Nextcloud apps..."
    
    cd "$NEXTCLOUD_WEB_DIR"
    
    # Update all apps
    sudo -u "$NEXTCLOUD_USER" php occ app:update --all
    
    # Enable recommended apps
    local apps_to_enable=(
        "files_external"
        "files_sharing"
        "files_versions"
        "files_trashbin"
        "activity"
        "notifications"
        "updatenotification"
        "user_ldap"
        "encryption"
    )
    
    for app in "${apps_to_enable[@]}"; do
        sudo -u "$NEXTCLOUD_USER" php occ app:enable "$app" || warning "Failed to enable app: $app"
    done
    
    # Disable unnecessary apps
    local apps_to_disable=(
        "survey_client"
        "firstrunwizard"
    )
    
    for app in "${apps_to_disable[@]}"; do
        sudo -u "$NEXTCLOUD_USER" php occ app:disable "$app" || warning "Failed to disable app: $app"
    done
    
    log "Apps configured"
}

# Save installation summary
save_install_info() {
    local info_file="/root/nextcloud-install-summary.txt"
    local domain=$(get_domain)
    
    cat > "$info_file" << EOF
Nextcloud Installation Summary
=============================
Date: $(date)
Version: $(sudo -u "$NEXTCLOUD_USER" php "$NEXTCLOUD_WEB_DIR/occ" status --output=json | jq -r '.version')

Installation Details:
- Web Directory: $NEXTCLOUD_WEB_DIR
- Data Directory: $NEXTCLOUD_DATA_DIR
- Domain: $domain
- URL: https://$domain/

Admin Credentials: /root/nextcloud-admin-credentials.txt
Database Credentials: /root/nextcloud-db-credentials.txt

Key Features Enabled:
- Redis caching for performance
- APCu local memory cache
- Background jobs via cron
- Local remote servers (for OnlyOffice)
- Server-side encryption available

Apps Enabled:
- Files external storage
- File sharing and versioning
- Activity monitoring
- Notifications
- Update notifications
- LDAP user backend
- Encryption

Next Steps:
1. Run 04_onlyoffice_install.sh to install OnlyOffice Document Server
2. Run 05_nginx_config.sh to configure web server
3. Run 06_ssl_setup.sh to configure SSL certificates
4. Access https://$domain/ to complete setup

Log File: $LOG_FILE
EOF

    log "Installation summary saved to: $info_file"
}

# Main execution
main() {
    log "Starting Nextcloud installation..."
    
    check_root
    check_prerequisites
    download_nextcloud
    set_permissions
    install_nextcloud
    configure_nextcloud
    setup_background_jobs
    configure_apps
    save_install_info
    
    log "✓ Nextcloud installation completed successfully!"
    echo ""
    info "Admin credentials saved to: /root/nextcloud-admin-credentials.txt"
    info "Installation summary: /root/nextcloud-install-summary.txt"
    echo ""
    info "Next step: Run 04_onlyoffice_install.sh"
    echo ""
    info "Log file: $LOG_FILE"
}

# Run main function
main "$@"
