#!/bin/bash

# Nginx Configuration Script for 2-Domain Setup
# This script configures the main nginx to handle both domains with proper SSL

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
    
    success "Configuration loaded"
}

# Display banner
show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                   2-DOMAIN NGINX CONFIGURATION                              ║
║              Configuring main nginx for both domains                        ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo ""
    info "Configuring main nginx for:"
    info "  • Nextcloud: $NEXTCLOUD_DOMAIN"
    info "  • OnlyOffice: $ONLYOFFICE_DOMAIN"
    info "  • Architecture: Main nginx front-end with SSL termination"
    echo ""
}

# Create main nginx configuration
create_main_nginx_config() {
    header "Creating Main Nginx Configuration"
    
    log "Creating main nginx configuration for dual domain setup..."
    
    # Create main nginx configuration
    cat > /etc/nginx/nginx.conf << 'EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    # Basic Settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;
    
    # File upload size
    client_max_body_size 10G;
    client_body_timeout 60s;
    client_header_timeout 60s;
    
    # MIME types
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;
    
    # Security headers (will be applied per server block)
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    
    # Rate limiting
    limit_req_zone $binary_remote_addr zone=login:10m rate=10r/m;
    limit_req_zone $binary_remote_addr zone=api:10m rate=1r/s;
    limit_req_zone $binary_remote_addr zone=onlyoffice:10m rate=5r/s;
    
    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_stapling on;
    ssl_stapling_verify on;
    
    # Include site configurations
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF
    
    success "Main nginx configuration created"
}

# Update Nextcloud nginx configuration
update_nextcloud_config() {
    header "Updating Nextcloud Nginx Configuration"
    
    log "Updating Nextcloud configuration for SSL..."
    
    # Update Nextcloud nginx configuration
    cat > "/etc/nginx/sites-available/$NEXTCLOUD_DOMAIN" << EOF
# Nextcloud configuration for $NEXTCLOUD_DOMAIN
server {
    listen 80;
    listen [::]:80;
    server_name $NEXTCLOUD_DOMAIN;
    
    # Redirect HTTP to HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $NEXTCLOUD_DOMAIN;
    
    # SSL configuration (will be updated by SSL setup script)
    ssl_certificate /etc/letsencrypt/live/$NEXTCLOUD_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$NEXTCLOUD_DOMAIN/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/$NEXTCLOUD_DOMAIN/chain.pem;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
    add_header Strict-Transport-Security "max-age=63072000" always;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_comp_level 4;
    gzip_min_length 256;
    gzip_proxied expired no-cache no-store private no_last_modified no_etag auth;
    gzip_types application/atom+xml application/javascript application/json application/ld+json application/manifest+json application/rss+xml application/vnd.geo+json application/vnd.ms-fontobject application/x-font-ttf application/x-web-app-manifest+json application/xhtml+xml application/xml font/opentype image/bmp image/svg+xml image/x-icon text/cache-manifest text/css text/plain text/vcard text/vnd.rim.location.xloc text/vtt text/x-component text/x-cross-domain-policy;
    
    # Root directory
    root /var/www/nextcloud;
    index index.php index.html;
    
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
    
    success "Nextcloud nginx configuration updated"
}

# Update OnlyOffice nginx configuration
update_onlyoffice_config() {
    header "Updating OnlyOffice Nginx Configuration"
    
    log "Updating OnlyOffice configuration for SSL..."
    
    # Update OnlyOffice nginx configuration
    cat > "/etc/nginx/sites-available/$ONLYOFFICE_DOMAIN" << EOF
# OnlyOffice configuration for $ONLYOFFICE_DOMAIN
server {
    listen 80;
    listen [::]:80;
    server_name $ONLYOFFICE_DOMAIN;
    
    # Redirect HTTP to HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $ONLYOFFICE_DOMAIN;
    
    # SSL configuration (will be updated by SSL setup script)
    ssl_certificate /etc/letsencrypt/live/$ONLYOFFICE_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$ONLYOFFICE_DOMAIN/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/$ONLYOFFICE_DOMAIN/chain.pem;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Strict-Transport-Security "max-age=63072000" always;
    
    # Rate limiting for OnlyOffice
    limit_req zone=onlyoffice burst=10 nodelay;
    
    # Proxy to OnlyOffice internal nginx
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$server_name;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # File upload size
        client_max_body_size 100M;
        
        # Buffering
        proxy_buffering off;
        proxy_request_buffering off;
    }
    
    # Health check
    location /healthcheck {
        proxy_pass http://127.0.0.1:8080/healthcheck;
        access_log off;
    }
    
    # Static files caching
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg)\$ {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_cache_valid 200 1d;
        expires 1d;
        add_header Cache-Control "public, immutable";
    }
}
EOF
    
    success "OnlyOffice nginx configuration updated"
}

# Create temporary HTTP configurations
create_temp_http_configs() {
    header "Creating Temporary HTTP Configurations"
    
    log "Creating temporary HTTP configurations for initial setup..."
    
    # Create temporary Nextcloud HTTP config
    cat > "/etc/nginx/sites-available/${NEXTCLOUD_DOMAIN}-temp" << EOF
# Temporary HTTP configuration for $NEXTCLOUD_DOMAIN
server {
    listen 80;
    listen [::]:80;
    server_name $NEXTCLOUD_DOMAIN;
    
    root /var/www/nextcloud;
    index index.php index.html;
    
    # Basic security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
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
        fastcgi_param modHeadersAvailable true;
        fastcgi_param front_controller_active true;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_intercept_errors on;
        fastcgi_request_buffering off;
    }
    
    # Serve static files
    location ~* \.(?:css|js|woff2?|svg|gif|map)\$ {
        try_files \$uri /index.php?\$args;
        add_header Cache-Control "public, max-age=15778463";
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
    
    # Create temporary OnlyOffice HTTP config
    cat > "/etc/nginx/sites-available/${ONLYOFFICE_DOMAIN}-temp" << EOF
# Temporary HTTP configuration for $ONLYOFFICE_DOMAIN
server {
    listen 80;
    listen [::]:80;
    server_name $ONLYOFFICE_DOMAIN;
    
    # Proxy to OnlyOffice internal nginx
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$server_name;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # File upload size
        client_max_body_size 100M;
    }
    
    # Health check
    location /healthcheck {
        proxy_pass http://127.0.0.1:8080/healthcheck;
        access_log off;
    }
}
EOF
    
    success "Temporary HTTP configurations created"
}

# Enable temporary configurations
enable_temp_configs() {
    header "Enabling Temporary Configurations"
    
    log "Enabling temporary HTTP configurations..."
    
    # Disable SSL configurations temporarily
    rm -f "/etc/nginx/sites-enabled/$NEXTCLOUD_DOMAIN"
    rm -f "/etc/nginx/sites-enabled/$ONLYOFFICE_DOMAIN"
    
    # Enable temporary HTTP configurations
    ln -sf "/etc/nginx/sites-available/${NEXTCLOUD_DOMAIN}-temp" "/etc/nginx/sites-enabled/"
    ln -sf "/etc/nginx/sites-available/${ONLYOFFICE_DOMAIN}-temp" "/etc/nginx/sites-enabled/"
    
    # Test nginx configuration
    nginx -t
    
    # Reload nginx
    systemctl reload nginx
    
    success "Temporary configurations enabled"
}

# Test nginx configurations
test_nginx_configs() {
    header "Testing Nginx Configurations"
    
    log "Testing nginx configurations..."
    
    # Test nginx syntax
    if nginx -t; then
        success "Nginx configuration syntax is valid"
    else
        error "Nginx configuration syntax is invalid"
        return 1
    fi
    
    # Test if nginx is running
    if systemctl is-active --quiet nginx; then
        success "Nginx is running"
    else
        error "Nginx is not running"
        return 1
    fi
    
    # Test domain accessibility (HTTP only for now)
    local nextcloud_response=$(curl -s -o /dev/null -w "%{http_code}" "http://$NEXTCLOUD_DOMAIN" || echo "000")
    local onlyoffice_response=$(curl -s -o /dev/null -w "%{http_code}" "http://$ONLYOFFICE_DOMAIN" || echo "000")
    
    if [[ "$nextcloud_response" == "200" ]]; then
        success "Nextcloud is accessible at http://$NEXTCLOUD_DOMAIN"
    else
        warning "Nextcloud may not be accessible yet (HTTP $nextcloud_response)"
    fi
    
    if [[ "$onlyoffice_response" == "200" ]]; then
        success "OnlyOffice is accessible at http://$ONLYOFFICE_DOMAIN"
    else
        warning "OnlyOffice may not be accessible yet (HTTP $onlyoffice_response)"
    fi
}

# Create nginx management script
create_nginx_management_script() {
    header "Creating Nginx Management Script"
    
    cat > /usr/local/bin/nginx-dual-domain.sh << EOF
#!/bin/bash
# Nginx management script for dual domain setup

case "\$1" in
    "enable-ssl")
        echo "Enabling SSL configurations..."
        rm -f /etc/nginx/sites-enabled/*-temp
        ln -sf /etc/nginx/sites-available/$NEXTCLOUD_DOMAIN /etc/nginx/sites-enabled/
        ln -sf /etc/nginx/sites-available/$ONLYOFFICE_DOMAIN /etc/nginx/sites-enabled/
        nginx -t && systemctl reload nginx
        echo "SSL configurations enabled"
        ;;
    "disable-ssl")
        echo "Enabling HTTP configurations..."
        rm -f /etc/nginx/sites-enabled/$NEXTCLOUD_DOMAIN
        rm -f /etc/nginx/sites-enabled/$ONLYOFFICE_DOMAIN
        ln -sf /etc/nginx/sites-available/${NEXTCLOUD_DOMAIN}-temp /etc/nginx/sites-enabled/
        ln -sf /etc/nginx/sites-available/${ONLYOFFICE_DOMAIN}-temp /etc/nginx/sites-enabled/
        nginx -t && systemctl reload nginx
        echo "HTTP configurations enabled"
        ;;
    "test")
        nginx -t
        ;;
    "reload")
        systemctl reload nginx
        ;;
    *)
        echo "Usage: \$0 {enable-ssl|disable-ssl|test|reload}"
        exit 1
        ;;
esac
EOF
    
    chmod +x /usr/local/bin/nginx-dual-domain.sh
    
    success "Nginx management script created"
}

# Save configuration info
save_config_info() {
    header "Saving Configuration Information"
    
    cat > /root/nginx_config_info.txt << EOF
# Nginx Configuration Information
# Generated on: $(date)

## Domains
Nextcloud: $NEXTCLOUD_DOMAIN
OnlyOffice: $ONLYOFFICE_DOMAIN

## Configuration Files
Main Config: /etc/nginx/nginx.conf
Nextcloud SSL: /etc/nginx/sites-available/$NEXTCLOUD_DOMAIN
OnlyOffice SSL: /etc/nginx/sites-available/$ONLYOFFICE_DOMAIN
Nextcloud HTTP: /etc/nginx/sites-available/${NEXTCLOUD_DOMAIN}-temp
OnlyOffice HTTP: /etc/nginx/sites-available/${ONLYOFFICE_DOMAIN}-temp

## Management Script
/usr/local/bin/nginx-dual-domain.sh

## Commands
Enable SSL: nginx-dual-domain.sh enable-ssl
Disable SSL: nginx-dual-domain.sh disable-ssl
Test Config: nginx-dual-domain.sh test
Reload: nginx-dual-domain.sh reload

## Current Status
- HTTP configurations are enabled
- SSL configurations are ready but disabled
- Run SSL setup script to enable HTTPS

## Next Steps
1. Run: ./06_ssl_setup_dual_domain.sh
2. Run: ./07_integration_config_dual_domain.sh
EOF
    
    chmod 600 /root/nginx_config_info.txt
    success "Configuration information saved"
}

# Final verification
verify_configuration() {
    header "Verifying Nginx Configuration"
    
    local issues=0
    
    # Check if nginx is running
    if systemctl is-active --quiet nginx; then
        success "Nginx is running"
    else
        error "Nginx is not running"
        ((issues++))
    fi
    
    # Check configuration files
    local configs=(
        "/etc/nginx/sites-available/$NEXTCLOUD_DOMAIN"
        "/etc/nginx/sites-available/$ONLYOFFICE_DOMAIN"
        "/etc/nginx/sites-available/${NEXTCLOUD_DOMAIN}-temp"
        "/etc/nginx/sites-available/${ONLYOFFICE_DOMAIN}-temp"
    )
    
    for config in "${configs[@]}"; do
        if [[ -f "$config" ]]; then
            success "Configuration file exists: $(basename "$config")"
        else
            error "Configuration file missing: $(basename "$config")"
            ((issues++))
        fi
    done
    
    # Check if temporary configs are enabled
    if [[ -L "/etc/nginx/sites-enabled/${NEXTCLOUD_DOMAIN}-temp" ]] && [[ -L "/etc/nginx/sites-enabled/${ONLYOFFICE_DOMAIN}-temp" ]]; then
        success "Temporary HTTP configurations are enabled"
    else
        error "Temporary HTTP configurations are not enabled"
        ((issues++))
    fi
    
    if [[ $issues -eq 0 ]]; then
        success "Nginx configuration completed successfully!"
        echo ""
        info "Current status:"
        info "  • HTTP configurations are enabled"
        info "  • SSL configurations are ready but disabled"
        info "  • Nextcloud: http://$NEXTCLOUD_DOMAIN"
        info "  • OnlyOffice: http://$ONLYOFFICE_DOMAIN"
        echo ""
        info "Next steps:"
        info "  1. Run: ./06_ssl_setup_dual_domain.sh"
        info "  2. Run: ./07_integration_config_dual_domain.sh"
    else
        error "Nginx configuration completed with $issues issues"
        exit 1
    fi
}

# Main execution
main() {
    check_root
    load_config
    show_banner
    create_main_nginx_config
    update_nextcloud_config
    update_onlyoffice_config
    create_temp_http_configs
    enable_temp_configs
    test_nginx_configs
    create_nginx_management_script
    save_config_info
    verify_configuration
}

# Run main function
main "$@"
