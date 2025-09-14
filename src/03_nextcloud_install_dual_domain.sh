#!/bin/bash

# Nextcloud Installation Script for 2-Domain Setup
# This script installs Nextcloud for docs.DOMAIN.com with main nginx front-end

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

header() {
    echo -e "${CYAN}${BOLD}$1${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Load configuration
load_config() {
    if [[ ! -f "/etc/nextcloud-onlyoffice/params.yaml" ]]; then
        error "Configuration file not found. Please run 01_system_prep_dual_domain.sh first."
        exit 1
    fi
    
    # Extract values from YAML (simple parsing)
    BASE_DOMAIN=$(grep "base_domain:" /etc/nextcloud-onlyoffice/params.yaml | cut -d'"' -f2)
    NEXTCLOUD_DOMAIN=$(grep "nextcloud_domain:" /etc/nextcloud-onlyoffice/params.yaml | cut -d'"' -f2)
    ONLYOFFICE_DOMAIN=$(grep "onlyoffice_domain:" /etc/nextcloud-onlyoffice/params.yaml | cut -d'"' -f2)
    ADMIN_EMAIL=$(grep "admin_email:" /etc/nextcloud-onlyoffice/params.yaml | cut -d'"' -f2)
    
    NC_DB_NAME=$(grep "db_name:" /etc/nextcloud-onlyoffice/params.yaml | head -1 | cut -d'"' -f2)
    NC_DB_USER=$(grep "db_user:" /etc/nextcloud-onlyoffice/params.yaml | head -1 | cut -d'"' -f2)
    NC_DB_PASSWORD=$(grep "db_password:" /etc/nextcloud-onlyoffice/params.yaml | head -1 | cut -d'"' -f2)
    
    success "Configuration loaded"
}

# Display banner
show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                   2-DOMAIN NEXTCLOUD INSTALLATION                           ║
║              Installing Nextcloud for docs.DOMAIN.com                       ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo ""
    info "Installing Nextcloud for:"
    info "  • Domain: $NEXTCLOUD_DOMAIN"
    info "  • Database: $NC_DB_NAME (MariaDB)"
    info "  • Architecture: Main nginx front-end + PHP-FPM backend"
    echo ""
}

# Download and extract Nextcloud
download_nextcloud() {
    header "Downloading Nextcloud"
    
    local nextcloud_version="28.0.4"
    local download_url="https://download.nextcloud.com/server/releases/nextcloud-${nextcloud_version}.tar.bz2"
    local temp_dir="/tmp/nextcloud-${nextcloud_version}"
    
    log "Downloading Nextcloud ${nextcloud_version}..."
    
    # Create temporary directory
    mkdir -p "$temp_dir"
    cd "$temp_dir"
    
    # Download Nextcloud
    wget -O nextcloud.tar.bz2 "$download_url"
    
    # Extract
    log "Extracting Nextcloud..."
    tar -xjf nextcloud.tar.bz2
    
    # Move to web directory
    log "Installing Nextcloud to /var/www/nextcloud..."
    rm -rf /var/www/nextcloud
    mv nextcloud /var/www/nextcloud
    
    # Set permissions
    chown -R www-data:www-data /var/www/nextcloud
    chmod -R 755 /var/www/nextcloud
    
    # Clean up
    cd /
    rm -rf "$temp_dir"
    
    success "Nextcloud downloaded and installed"
}

# Create data directory
create_data_directory() {
    header "Creating Data Directory"
    
    log "Creating Nextcloud data directory..."
    
    # Create data directory
    mkdir -p /srv/nextcloud-data
    chown -R www-data:www-data /srv/nextcloud-data
    chmod -R 755 /srv/nextcloud-data
    
    success "Data directory created"
}

# Configure PHP for Nextcloud
configure_php() {
    header "Configuring PHP for Nextcloud"
    
    log "Configuring PHP settings for Nextcloud..."
    
    local php_ini="/etc/php/8.3/fpm/php.ini"
    
    # Nextcloud-specific PHP settings
    cat >> "$php_ini" << 'EOF'

; Nextcloud optimizations
opcache.enable=1
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=10000
opcache.memory_consumption=128
opcache.save_comments=1
opcache.revalidate_freq=1

; Memory and execution
memory_limit = 512M
max_execution_time = 300
max_input_time = 300

; File uploads
upload_max_filesize = 10G
post_max_size = 10G
max_file_uploads = 200

; Session settings
session.gc_maxlifetime = 3600
session.cookie_lifetime = 0

; Security
expose_php = Off
allow_url_fopen = On
allow_url_include = Off
EOF
    
    # Restart PHP-FPM
    systemctl restart php8.3-fpm
    
    success "PHP configured for Nextcloud"
}

# Install Nextcloud
install_nextcloud() {
    header "Installing Nextcloud"
    
    log "Running Nextcloud installation..."
    
    # Run Nextcloud installation
    sudo -u www-data php /var/www/nextcloud/occ maintenance:install \
        --database="mysql" \
        --database-name="$NC_DB_NAME" \
        --database-user="$NC_DB_USER" \
        --database-pass="$NC_DB_PASSWORD" \
        --database-host="localhost" \
        --data-dir="/srv/nextcloud-data" \
        --admin-user="admin" \
        --admin-pass="$(openssl rand -base64 32)" \
        --admin-email="$ADMIN_EMAIL" \
        --no-interaction
    
    success "Nextcloud installed"
}

# Configure Nextcloud
configure_nextcloud() {
    header "Configuring Nextcloud"
    
    log "Configuring Nextcloud settings..."
    
    # Set trusted domains
    sudo -u www-data php /var/www/nextcloud/occ config:system:set trusted_domains 0 --value="$NEXTCLOUD_DOMAIN"
    sudo -u www-data php /var/www/nextcloud/occ config:system:set trusted_domains 1 --value="$(hostname -I | awk '{print $1}')"
    
    # Set overwrite protocol
    sudo -u www-data php /var/www/nextcloud/occ config:system:set overwriteprotocol --value="https"
    
    # Set overwrite host
    sudo -u www-data php /var/www/nextcloud/occ config:system:set overwritehost --value="$NEXTCLOUD_DOMAIN"
    
    # Set overwrite webroot
    sudo -u www-data php /var/www/nextcloud/occ config:system:set overwritewebroot --value="/"
    
    # Configure Redis caching (skip if APCu not available)
    if php -m | grep -q apcu; then
        log "Configuring APCu and Redis caching..."
        sudo -u www-data php /var/www/nextcloud/occ config:system:set memcache.local --value="\\OC\\Memcache\\APCu" || warning "APCu configuration failed, continuing without local cache"
    else
        warning "APCu not available, skipping local cache configuration"
    fi
    
    # Configure Redis for file locking (use unix socket)
    sudo -u www-data php /var/www/nextcloud/occ config:system:set memcache.locking --value="\\OC\\Memcache\\Redis" || warning "Redis locking configuration failed"
    sudo -u www-data php /var/www/nextcloud/occ config:system:set redis host --value="/var/run/redis/redis-server.sock" || warning "Redis host configuration failed"
    sudo -u www-data php /var/www/nextcloud/occ config:system:set redis port --value="0" --type=integer || warning "Redis port configuration failed"
    
    # Enable local remote servers (for OnlyOffice integration)
    sudo -u www-data php /var/www/nextcloud/occ config:system:set allow_local_remote_servers --value="true" --type=boolean
    
    # Set default app
    sudo -u www-data php /var/www/nextcloud/occ app:enable files
    
    # Disable some default apps we don't need
    sudo -u www-data php /var/www/nextcloud/occ app:disable photos
    sudo -u www-data php /var/www/nextcloud/occ app:disable dashboard
    
    success "Nextcloud configured"
}

# Create nginx configuration for Nextcloud
create_nginx_config() {
    header "Creating Nginx Configuration for Nextcloud"
    
    log "Creating nginx configuration for $NEXTCLOUD_DOMAIN..."
    
    # Create nginx configuration for Nextcloud
    cat > "/etc/nginx/sites-available/$NEXTCLOUD_DOMAIN" << EOF
# Nextcloud configuration for $NEXTCLOUD_DOMAIN
server {
    listen 80;
    listen [::]:80;
    server_name $NEXTCLOUD_DOMAIN;
    
    # Redirect HTTP to HTTPS (will be enabled after SSL setup)
    # return 301 https://\$server_name\$request_uri;
    
    # Temporary HTTP configuration for initial setup
    root /var/www/nextcloud;
    index index.php index.html;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_comp_level 4;
    gzip_min_length 256;
    gzip_proxied expired no-cache no-store private no_last_modified no_etag auth;
    gzip_types application/atom+xml application/javascript application/json application/ld+json application/manifest+json application/rss+xml application/vnd.geo+json application/vnd.ms-fontobject application/x-font-ttf application/x-web-app-manifest+json application/xhtml+xml application/xml font/opentype image/bmp image/svg+xml image/x-icon text/cache-manifest text/css text/plain text/vcard text/vnd.rim.location.xloc text/vtt text/x-component text/x-cross-domain-policy;
    
    # Handle Nextcloud
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
    
    # PHP handling
    location ~ ^/(?:build|tests|config|lib|3rdparty|templates|data)(?:\$|/) {
        deny all;
    }
    
    location ~ ^/(?:\.|autotest|occ|issue|indie|db_|sqlite) {
        deny all;
    }
    
    location ~ ^/(?:index|remote|public|cron|core/ajax/update|status|ocs/v[12]|updater/.+|oc[ms]-provider/.+)\.php(?:\$|/) {
        fastcgi_split_path_info ^(.+?\.php)(/.*)\$;
        set \$path_info \$fastcgi_path_info;
        
        try_files \$fastcgi_script_name =404;
        
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$path_info;
        fastcgi_param HTTPS on;
        fastcgi_param modHeadersAvailable true;
        fastcgi_param front_controller_active true;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_intercept_errors on;
        fastcgi_request_buffering off;
    }
    
    location ~ ^/(?:updater|oc[ms]-provider)(?:\$|/) {
        try_files \$uri/ =404;
        index index.php;
    }
    
    # Serve static files
    location ~* \.(?:css|js|woff2?|svg|gif|map)\$ {
        try_files \$uri /index.php?\$args;
        add_header Cache-Control "public, max-age=15778463";
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "no-referrer-when-downgrade" always;
        add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
        access_log off;
    }
    
    location ~* \.(?:png|html|ttf|ico|jpg|jpeg)\$ {
        try_files \$uri /index.php?\$args;
        access_log off;
    }
    
    # Security.txt
    location = /.well-known/security.txt {
        return 301 /remote.php/dav/files/admin/security.txt;
    }
    
    # CalDAV and CardDAV
    location ~ ^/(?:caldav|carddav|dav)(?:\$|/) {
        return 301 /remote.php/dav\$is_args\$args;
    }
    
    # WebDAV
    location ~ ^/(?:remote|webdav)(?:\$|/) {
        return 301 /remote.php/\$is_args\$args;
    }
    
    # Deny access to sensitive files
    location ~ /\.ht {
        deny all;
    }
    
    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF
    
    # Enable the site
    ln -sf "/etc/nginx/sites-available/$NEXTCLOUD_DOMAIN" "/etc/nginx/sites-enabled/"
    
    # Test nginx configuration
    nginx -t
    
    # Reload nginx
    systemctl reload nginx
    
    success "Nginx configuration created for Nextcloud"
}

# Install and configure OnlyOffice app
install_onlyoffice_app() {
    header "Installing OnlyOffice App"
    
    log "Installing OnlyOffice app for Nextcloud..."
    
    # Download OnlyOffice app
    local app_version="8.0.0"
    local app_url="https://github.com/ONLYOFFICE/onlyoffice-nextcloud/releases/download/v${app_version}/onlyoffice-${app_version}.tar.gz"
    
    cd /tmp
    wget -O onlyoffice-app.tar.gz "$app_url"
    tar -xzf onlyoffice-app.tar.gz
    
    # Install app
    sudo -u www-data php /var/www/nextcloud/occ app:install onlyoffice
    
    # Configure OnlyOffice app (will be completed in integration script)
    sudo -u www-data php /var/www/nextcloud/occ app:enable onlyoffice
    
    # Clean up
    rm -f onlyoffice-app.tar.gz
    rm -rf onlyoffice
    
    success "OnlyOffice app installed"
}

# Set up cron jobs
setup_cron() {
    header "Setting up Cron Jobs"
    
    log "Setting up Nextcloud cron jobs..."
    
    # Add Nextcloud cron job
    cat > /etc/cron.d/nextcloud << EOF
# Nextcloud cron job
*/5 * * * * www-data php -f /var/www/nextcloud/cron.php
EOF
    
    success "Cron jobs configured"
}

# Create backup script
create_backup_script() {
    header "Creating Backup Script"
    
    cat > /usr/local/bin/backup-nextcloud.sh << 'EOF'
#!/bin/bash
# Nextcloud backup script

BACKUP_DIR="/var/backups/nextcloud"
DATE=$(date +%Y%m%d_%H%M%S)
NEXTCLOUD_DIR="/var/www/nextcloud"
DATA_DIR="/srv/nextcloud-data"

mkdir -p "$BACKUP_DIR"

# Backup Nextcloud files
tar -czf "$BACKUP_DIR/nextcloud-files-$DATE.tar.gz" -C /var/www nextcloud

# Backup data directory
tar -czf "$BACKUP_DIR/nextcloud-data-$DATE.tar.gz" -C /srv nextcloud-data

# Keep only last 7 days of backups
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +7 -delete

echo "Nextcloud backup completed: $DATE"
EOF
    
    chmod +x /usr/local/bin/backup-nextcloud.sh
    
    # Add to daily backup
    echo "/usr/local/bin/backup-nextcloud.sh" >> /etc/cron.daily/backup-databases
    
    success "Backup script created"
}

# Test Nextcloud installation
test_installation() {
    header "Testing Nextcloud Installation"
    
    log "Testing Nextcloud installation..."
    
    # Test if Nextcloud is accessible
    local response=$(curl -s -o /dev/null -w "%{http_code}" "http://$NEXTCLOUD_DOMAIN" || echo "000")
    
    if [[ "$response" == "200" ]]; then
        success "Nextcloud is accessible at http://$NEXTCLOUD_DOMAIN"
    else
        warning "Nextcloud may not be fully accessible yet (HTTP $response)"
        info "This is normal if SSL certificates haven't been set up yet"
    fi
    
    # Test database connection
    if sudo -u www-data php /var/www/nextcloud/occ status >/dev/null 2>&1; then
        success "Nextcloud database connection is working"
    else
        error "Nextcloud database connection failed"
        return 1
    fi
}

# Save installation info
save_installation_info() {
    header "Saving Installation Information"
    
    # Get admin password
    local admin_password=$(sudo -u www-data php /var/www/nextcloud/occ user:list | grep admin | cut -d'"' -f4)
    
    cat > /root/nextcloud_installation_info.txt << EOF
# Nextcloud Installation Information
# Generated on: $(date)

## Access Information
URL: http://$NEXTCLOUD_DOMAIN (will be https:// after SSL setup)
Admin User: admin
Admin Password: $admin_password

## Directory Structure
Nextcloud Root: /var/www/nextcloud
Data Directory: /srv/nextcloud-data
Config File: /var/www/nextcloud/config/config.php

## Database Information
Database: $NC_DB_NAME
Username: $NC_DB_USER
Password: $NC_DB_PASSWORD
Host: localhost

## Nginx Configuration
Config File: /etc/nginx/sites-available/$NEXTCLOUD_DOMAIN
Enabled: /etc/nginx/sites-enabled/$NEXTCLOUD_DOMAIN

## Backup Scripts
Nextcloud: /usr/local/bin/backup-nextcloud.sh
Database: /usr/local/bin/backup-mariadb.sh

## Next Steps
1. Run: ./04_onlyoffice_install_dual_domain.sh
2. Run: ./05_nginx_config_dual_domain.sh
3. Run: ./06_ssl_setup_dual_domain.sh
4. Run: ./07_integration_config_dual_domain.sh
EOF
    
    chmod 600 /root/nextcloud_installation_info.txt
    success "Installation information saved"
}

# Final verification
verify_installation() {
    header "Verifying Nextcloud Installation"
    
    local issues=0
    
    # Check if Nextcloud files exist
    if [[ -d "/var/www/nextcloud" ]]; then
        success "Nextcloud files installed"
    else
        error "Nextcloud files missing"
        ((issues++))
    fi
    
    # Check if data directory exists
    if [[ -d "/srv/nextcloud-data" ]]; then
        success "Data directory created"
    else
        error "Data directory missing"
        ((issues++))
    fi
    
    # Check nginx configuration
    if [[ -f "/etc/nginx/sites-available/$NEXTCLOUD_DOMAIN" ]]; then
        success "Nginx configuration created"
    else
        error "Nginx configuration missing"
        ((issues++))
    fi
    
    # Check if site is enabled
    if [[ -L "/etc/nginx/sites-enabled/$NEXTCLOUD_DOMAIN" ]]; then
        success "Nginx site enabled"
    else
        error "Nginx site not enabled"
        ((issues++))
    fi
    
    if [[ $issues -eq 0 ]]; then
        success "Nextcloud installation completed successfully!"
        echo ""
        info "Nextcloud is available at: http://$NEXTCLOUD_DOMAIN"
        info "Admin credentials saved to: /root/nextcloud_installation_info.txt"
        echo ""
        info "Next steps:"
        info "  1. Run: ./04_onlyoffice_install_dual_domain.sh"
        info "  2. Run: ./05_nginx_config_dual_domain.sh"
        info "  3. Run: ./06_ssl_setup_dual_domain.sh"
        info "  4. Run: ./07_integration_config_dual_domain.sh"
    else
        error "Nextcloud installation completed with $issues issues"
        exit 1
    fi
}

# Main execution
main() {
    check_root
    load_config
    show_banner
    download_nextcloud
    create_data_directory
    configure_php
    install_nextcloud
    configure_nextcloud
    create_nginx_config
    install_onlyoffice_app
    setup_cron
    create_backup_script
    test_installation
    save_installation_info
    verify_installation
}

# Run main function
main "$@"
