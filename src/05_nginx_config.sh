#!/bin/bash

# Nextcloud + OnlyOffice Bare Metal Installation
# Step 5: Nginx Configuration
# 
# This script configures nginx as a single entry point for both Nextcloud and OnlyOffice:
# - Creates optimized nginx configuration for Nextcloud
# - Adds OnlyOffice reverse proxy under /onlyoffice/ path
# - Configures SSL-ready setup
# - Optimizes for performance and security
# - Sets up proper headers and caching

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/nextcloud-install.log"
NEXTCLOUD_WEB_DIR="/var/www/nextcloud"
ONLYOFFICE_PORT="8080"

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

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Nextcloud is installed
    if [[ ! -d "$NEXTCLOUD_WEB_DIR" ]]; then
        error "Nextcloud not found. Please run 03_nextcloud_install.sh first."
    fi
    
    # Check if OnlyOffice is installed
    if [[ ! -f /root/onlyoffice-install-summary.txt ]]; then
        error "OnlyOffice not installed. Please run 04_onlyoffice_install.sh first."
    fi
    
    # Check if nginx is installed
    if ! command -v nginx &> /dev/null; then
        error "Nginx not installed. Please run 01_system_prep.sh first."
    fi
    
    log "Prerequisites check passed"
}

# Get domain name
get_domain() {
    local domain=""
    
    # Try to get from Nextcloud config
    if [[ -f "$NEXTCLOUD_WEB_DIR/config/config.php" ]]; then
        domain=$(grep -oP "(?<=')https?://[^/]+" "$NEXTCLOUD_WEB_DIR/config/config.php" | head -1 | sed 's|https\?://||')
    fi
    
    # If not found, try existing nginx config
    if [[ -z "$domain" && -f /etc/nginx/sites-enabled/test-collab-site.com ]]; then
        domain="test-collab-site.com"
    fi
    
    # If still not found, use localhost as default for testing
    if [[ -z "$domain" ]]; then
        echo ""
        read -p "Enter the domain name for your site (or press Enter for localhost): " domain
        
        if [[ -z "$domain" ]]; then
            domain="localhost"
            info "Using localhost as domain (can be changed later)"
        fi
    fi
    
    echo "$domain"
}

# Detect PHP version
detect_php_version() {
    local php_version=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
    echo "$php_version"
}

# Create nginx configuration
create_nginx_config() {
    local domain="$1"
    local php_version="$2"
    local config_file="/etc/nginx/sites-available/$domain"
    
    log "Creating nginx configuration for $domain..."
    
    # Backup existing config if it exists
    if [[ -f "$config_file" ]]; then
        cp "$config_file" "$config_file.backup.$(date +%s)"
        log "Backed up existing configuration"
    fi
    
    # Create the nginx configuration
    cat > "$config_file" << EOF
# WebSocket upgrade mapping
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

# HTTP server - redirect to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name $domain;
    
    # ACME challenge for Let's Encrypt
    location ^~ /.well-known/acme-challenge/ {
        root /var/www/html;
        allow all;
    }
    
    # Redirect all other traffic to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# HTTPS server - Main configuration
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $domain;
    
    # SSL configuration (certificates will be added by certbot)
    # ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    
    # SSL security settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header Referrer-Policy "no-referrer" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Robots-Tag "none" always;
    add_header X-Download-Options "noopen" always;
    add_header X-Permitted-Cross-Domain-Policies "none" always;
    
    # Nextcloud root directory
    root $NEXTCLOUD_WEB_DIR;
    index index.php index.html /index.php\$request_uri;
    
    # Maximum file upload size
    client_max_body_size 512M;
    client_body_timeout 300s;
    fastcgi_buffers 64 4K;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_comp_level 4;
    gzip_min_length 256;
    gzip_proxied expired no-cache no-store private no_last_modified no_etag auth;
    gzip_types application/atom+xml application/javascript application/json application/ld+json application/manifest+json application/rss+xml application/vnd.geo+json application/vnd.ms-fontobject application/x-font-ttf application/x-web-app-manifest+json application/xhtml+xml application/xml font/opentype image/bmp image/svg+xml image/x-icon text/cache-manifest text/css text/plain text/vcard text/vnd.rim.location.xloc text/vtt text/x-component text/x-cross-domain-policy;
    
    # Well-known redirects for CalDAV/CardDAV
    location = /.well-known/carddav {
        return 301 \$scheme://\$host:\$server_port/remote.php/dav;
    }
    location = /.well-known/caldav {
        return 301 \$scheme://\$host:\$server_port/remote.php/dav;
    }
    location = /.well-known/webfinger {
        return 301 \$scheme://\$host:\$server_port/index.php/.well-known/webfinger;
    }
    location = /.well-known/nodeinfo {
        return 301 \$scheme://\$host:\$server_port/index.php/.well-known/nodeinfo;
    }
    
    # Deny access to sensitive directories
    location ~ ^/(?:build|tests|config|lib|3rdparty|templates|data)(?:\$|/)  { return 404; }
    location ~ ^/(?:\.|autotest|occ|issue|indie|db_|console)                { return 404; }
    
    # Main Nextcloud location
    location / {
        try_files \$uri \$uri/ /index.php\$request_uri;
    }
    
    # PHP handler
    location ~ \.php(?:\$|/) {
        # Split path info for PHP
        fastcgi_split_path_info ^(.+?\.php)(/.*)$;
        set \$path_info \$fastcgi_path_info;
        
        try_files \$fastcgi_script_name =404;
        
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$path_info;
        fastcgi_param modHeadersAvailable true;
        fastcgi_param front_controller_active true;
        
        fastcgi_pass unix:/run/php/php$php_version-fpm.sock;
        fastcgi_intercept_errors on;
        fastcgi_request_buffering off;
        fastcgi_read_timeout 120;
        fastcgi_send_timeout 120;
    }
    
    # Static files caching
    location ~ \.(?:css|js|mjs|svg|gif|png|jpg|jpeg|ico|woff2?)$ {
        try_files \$uri /index.php\$request_uri;
        expires 6M;
        access_log off;
        add_header Cache-Control "public, immutable";
    }
    
    # OnlyOffice Document Server reverse proxy
    location ^~ /onlyoffice/ {
        proxy_pass http://127.0.0.1:$ONLYOFFICE_PORT/;
        proxy_http_version 1.1;
        
        # WebSocket support for collaborative editing
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        
        # Standard proxy headers
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host/onlyoffice;
        
        # Timeouts for large documents
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffer settings
        proxy_buffering off;
        proxy_request_buffering off;
        client_max_body_size 100M;
        
        # Security
        proxy_set_header X-Forwarded-Prefix "";
        proxy_redirect off;
    }
    
    # OnlyOffice healthcheck endpoint
    location = /onlyoffice/healthcheck {
        proxy_pass http://127.0.0.1:$ONLYOFFICE_PORT/healthcheck;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        access_log off;
    }
}
EOF

    log "Nginx configuration created: $config_file"
}

# Enable site and test configuration
enable_site() {
    local domain="$1"
    local config_file="/etc/nginx/sites-available/$domain"
    local enabled_file="/etc/nginx/sites-enabled/$domain"
    
    log "Enabling nginx site..."
    
    # Remove default site if it exists
    if [[ -f /etc/nginx/sites-enabled/default ]]; then
        rm -f /etc/nginx/sites-enabled/default
        log "Removed default nginx site"
    fi
    
    # Enable the new site
    ln -sf "$config_file" "$enabled_file"
    
    # Test nginx configuration
    if nginx -t; then
        log "✓ Nginx configuration test passed"
    else
        error "✗ Nginx configuration test failed"
    fi
    
    # Reload nginx
    systemctl reload nginx
    
    if systemctl is-active --quiet nginx; then
        log "✓ Nginx reloaded successfully"
    else
        error "✗ Nginx failed to reload"
    fi
}

# Create nginx snippets for reusability
create_nginx_snippets() {
    log "Creating nginx snippets..."
    
    local snippets_dir="/etc/nginx/snippets"
    mkdir -p "$snippets_dir"
    
    # OnlyOffice proxy headers snippet
    cat > "$snippets_dir/onlyoffice-proxy.conf" << 'EOF'
# OnlyOffice proxy headers
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Host $host;

proxy_http_version 1.1;
proxy_read_timeout 3600;
proxy_connect_timeout 60;
proxy_send_timeout 60;

# WebSocket support
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection $connection_upgrade;
EOF

    # Security headers snippet
    cat > "$snippets_dir/security-headers.conf" << 'EOF'
# Security headers
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
add_header Referrer-Policy "no-referrer" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header X-Robots-Tag "none" always;
add_header X-Download-Options "noopen" always;
add_header X-Permitted-Cross-Domain-Policies "none" always;
EOF

    log "Nginx snippets created"
}

# Save configuration summary
save_config_info() {
    local domain="$1"
    local php_version="$2"
    local info_file="/root/nginx-config-summary.txt"
    
    cat > "$info_file" << EOF
Nginx Configuration Summary
==========================
Date: $(date)
Domain: $domain
PHP Version: $php_version

Configuration Files:
- Main config: /etc/nginx/sites-available/$domain
- Enabled: /etc/nginx/sites-enabled/$domain
- Snippets: /etc/nginx/snippets/

Features Configured:
- HTTP to HTTPS redirect
- SSL-ready configuration (certificates need to be added)
- Nextcloud optimized settings
- OnlyOffice reverse proxy at /onlyoffice/
- WebSocket support for collaborative editing
- Security headers
- Static file caching
- Gzip compression

URLs:
- Nextcloud: https://$domain/
- OnlyOffice: https://$domain/onlyoffice/
- Healthcheck: https://$domain/onlyoffice/healthcheck

Next Steps:
1. Run 06_ssl_setup.sh to configure SSL certificates
2. Run 07_integration_config.sh to connect Nextcloud with OnlyOffice
3. Test the complete setup

Service Management:
- Test config: nginx -t
- Reload: systemctl reload nginx
- Restart: systemctl restart nginx
- Status: systemctl status nginx

Log Files:
- Access: /var/log/nginx/access.log
- Error: /var/log/nginx/error.log
- Install: $LOG_FILE
EOF

    log "Configuration summary saved to: $info_file"
}

# Main execution
main() {
    log "Starting nginx configuration..."
    
    check_root
    check_prerequisites
    
    local domain=$(get_domain)
    local php_version=$(detect_php_version)
    
    log "Configuring nginx for domain: $domain (PHP $php_version)"
    
    create_nginx_snippets
    create_nginx_config "$domain" "$php_version"
    enable_site "$domain"
    save_config_info "$domain" "$php_version"
    
    log "✓ Nginx configuration completed successfully!"
    echo ""
    info "Domain configured: $domain"
    info "Configuration summary: /root/nginx-config-summary.txt"
    echo ""
    info "Next step: Run 06_ssl_setup.sh to configure SSL certificates"
    echo ""
    info "Log file: $LOG_FILE"
}

# Run main function
main "$@"
