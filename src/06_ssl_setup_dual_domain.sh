#!/bin/bash

# SSL Setup Script for 2-Domain Setup
# This script sets up Let's Encrypt SSL certificates for both domains

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

# Show usage
show_usage() {
    echo "Usage: $0 [email]"
    echo ""
    echo "Arguments:"
    echo "  email    Email address for Let's Encrypt certificate notifications"
    echo "           If not provided, will use admin_email from params.yaml"
    echo ""
    echo "Examples:"
    echo "  $0 admin@example.com"
    echo "  $0  # Uses email from params.yaml"
    echo ""
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
    
    # Get email from command line parameter or YAML
    if [[ -n "${1:-}" ]]; then
        ADMIN_EMAIL="$1"
        log "Using email from command line: $ADMIN_EMAIL"
    else
        ADMIN_EMAIL=$(grep "admin_email:" /etc/nextcloud-onlyoffice/params.yaml | cut -d'"' -f2)
        log "Using email from YAML: $ADMIN_EMAIL"
    fi
    
    success "Configuration loaded"
}

# Display banner
show_banner() {
    # clear  # Commented out to avoid terminal issues
    echo -e "${CYAN}${BOLD}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                   2-DOMAIN SSL SETUP                                         ║
║              Let's Encrypt certificates for both domains                     ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo ""
    info "Setting up SSL certificates for:"
    info "  • Nextcloud: $NEXTCLOUD_DOMAIN"
    info "  • OnlyOffice: $ONLYOFFICE_DOMAIN"
    info "  • Admin Email: $ADMIN_EMAIL"
    echo ""
}

# Check domain resolution
check_domain_resolution() {
    header "Checking Domain Resolution"
    
    local domains=("$NEXTCLOUD_DOMAIN" "$ONLYOFFICE_DOMAIN")
    local issues=0
    
    for domain in "${domains[@]}"; do
        log "Checking $domain..."
        
        # Get the IP address the domain resolves to
        local domain_ip=$(dig +short "$domain" | head -1)
        local server_ip=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || echo "unknown")
        
        if [[ -z "$domain_ip" ]]; then
            error "$domain does not resolve to any IP address"
            ((issues++))
        elif [[ "$domain_ip" != "$server_ip" ]]; then
            warning "$domain resolves to $domain_ip but server IP is $server_ip"
            warning "This may cause SSL certificate issues"
        else
            success "$domain resolves correctly to $domain_ip"
        fi
    done
    
    if [[ $issues -gt 0 ]]; then
        error "Domain resolution issues found. Please fix DNS before continuing."
        exit 1
    fi
}

# Create temporary HTTP configurations
create_temp_http_configs() {
    header "Creating Temporary HTTP Configurations"
    
    log "Creating temporary HTTP configurations for SSL challenge..."
    
    # Create temporary Nextcloud HTTP config
    cat > "/etc/nginx/sites-available/${NEXTCLOUD_DOMAIN}-temp" << EOF
# Temporary HTTP configuration for $NEXTCLOUD_DOMAIN (SSL challenge)
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
# Temporary HTTP configuration for $ONLYOFFICE_DOMAIN (SSL challenge)
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
    
    # Disable any existing SSL configurations
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

# Obtain SSL certificates
obtain_ssl_certificates() {
    header "Obtaining SSL Certificates"
    
    log "Obtaining SSL certificates for both domains..."
    
    # Obtain certificate for Nextcloud domain
    log "Obtaining certificate for $NEXTCLOUD_DOMAIN..."
    certbot certonly --nginx \
        --non-interactive \
        --agree-tos \
        --email "$ADMIN_EMAIL" \
        --domains "$NEXTCLOUD_DOMAIN"
    
    # Obtain certificate for OnlyOffice domain
    log "Obtaining certificate for $ONLYOFFICE_DOMAIN..."
    certbot certonly --nginx \
        --non-interactive \
        --agree-tos \
        --email "$ADMIN_EMAIL" \
        --domains "$ONLYOFFICE_DOMAIN"
    
    success "SSL certificates obtained"
}

# Create SSL nginx configurations
create_ssl_configs() {
    header "Creating SSL Nginx Configurations"
    
    log "Creating SSL configurations for both domains..."
    
    # Create Nextcloud SSL configuration
    cat > "/etc/nginx/sites-available/$NEXTCLOUD_DOMAIN" << EOF
# Nextcloud SSL configuration for $NEXTCLOUD_DOMAIN
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
    
    # SSL configuration
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
    
    # Create OnlyOffice SSL configuration
    cat > "/etc/nginx/sites-available/$ONLYOFFICE_DOMAIN" << EOF
# OnlyOffice SSL configuration for $ONLYOFFICE_DOMAIN
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
    
    # SSL configuration
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
    
    success "SSL configurations created"
}

# Enable SSL configurations
enable_ssl_configs() {
    header "Enabling SSL Configurations"
    
    log "Enabling SSL configurations..."
    
    # Remove temporary configurations
    rm -f "/etc/nginx/sites-enabled/${NEXTCLOUD_DOMAIN}-temp"
    rm -f "/etc/nginx/sites-enabled/${ONLYOFFICE_DOMAIN}-temp"
    
    # Enable SSL configurations
    ln -sf "/etc/nginx/sites-available/$NEXTCLOUD_DOMAIN" "/etc/nginx/sites-enabled/"
    ln -sf "/etc/nginx/sites-available/$ONLYOFFICE_DOMAIN" "/etc/nginx/sites-enabled/"
    
    # Test nginx configuration
    nginx -t
    
    # Reload nginx
    systemctl reload nginx
    
    success "SSL configurations enabled"
}

# Set up certificate renewal
setup_certificate_renewal() {
    header "Setting up Certificate Renewal"
    
    log "Setting up automatic certificate renewal..."
    
    # Test certificate renewal
    certbot renew --dry-run
    
    # Create renewal script
    cat > /usr/local/bin/renew-ssl-certificates.sh << 'EOF'
#!/bin/bash
# SSL certificate renewal script

# Renew certificates
certbot renew --quiet

# Reload nginx if certificates were renewed
if systemctl is-active --quiet nginx; then
    systemctl reload nginx
fi

echo "SSL certificate renewal completed: $(date)"
EOF
    
    chmod +x /usr/local/bin/renew-ssl-certificates.sh
    
    # Add to crontab (run twice daily)
    (crontab -l 2>/dev/null; echo "0 12,0 * * * /usr/local/bin/renew-ssl-certificates.sh") | crontab -
    
    success "Certificate renewal configured"
}

# Test SSL configurations
test_ssl_configs() {
    header "Testing SSL Configurations"
    
    log "Testing SSL configurations..."
    
    # Test nginx configuration
    if nginx -t; then
        success "Nginx configuration is valid"
    else
        error "Nginx configuration is invalid"
        return 1
    fi
    
    # Test HTTPS access
    local nextcloud_response=$(curl -s -o /dev/null -w "%{http_code}" "https://$NEXTCLOUD_DOMAIN" || echo "000")
    local onlyoffice_response=$(curl -s -o /dev/null -w "%{http_code}" "https://$ONLYOFFICE_DOMAIN" || echo "000")
    
    if [[ "$nextcloud_response" == "200" ]]; then
        success "Nextcloud HTTPS is working: https://$NEXTCLOUD_DOMAIN"
    else
        warning "Nextcloud HTTPS may not be ready yet (HTTP $nextcloud_response)"
    fi
    
    if [[ "$onlyoffice_response" == "200" ]]; then
        success "OnlyOffice HTTPS is working: https://$ONLYOFFICE_DOMAIN"
    else
        warning "OnlyOffice HTTPS may not be ready yet (HTTP $onlyoffice_response)"
    fi
    
    # Test HTTP to HTTPS redirect
    local nextcloud_redirect=$(curl -s -o /dev/null -w "%{http_code}" "http://$NEXTCLOUD_DOMAIN" || echo "000")
    local onlyoffice_redirect=$(curl -s -o /dev/null -w "%{http_code}" "http://$ONLYOFFICE_DOMAIN" || echo "000")
    
    if [[ "$nextcloud_redirect" == "301" ]]; then
        success "Nextcloud HTTP to HTTPS redirect is working"
    else
        warning "Nextcloud HTTP to HTTPS redirect may not be working (HTTP $nextcloud_redirect)"
    fi
    
    if [[ "$onlyoffice_redirect" == "301" ]]; then
        success "OnlyOffice HTTP to HTTPS redirect is working"
    else
        warning "OnlyOffice HTTP to HTTPS redirect may not be working (HTTP $onlyoffice_redirect)"
    fi
}

# Save SSL information
save_ssl_info() {
    header "Saving SSL Information"
    
    cat > /root/ssl_setup_info.txt << EOF
# SSL Setup Information
# Generated on: $(date)

## Domains
Nextcloud: https://$NEXTCLOUD_DOMAIN
OnlyOffice: https://$ONLYOFFICE_DOMAIN

## Certificate Locations
Nextcloud: /etc/letsencrypt/live/$NEXTCLOUD_DOMAIN/
OnlyOffice: /etc/letsencrypt/live/$ONLYOFFICE_DOMAIN/

## Nginx Configurations
Nextcloud: /etc/nginx/sites-available/$NEXTCLOUD_DOMAIN
OnlyOffice: /etc/nginx/sites-available/$ONLYOFFICE_DOMAIN

## Renewal
Script: /usr/local/bin/renew-ssl-certificates.sh
Cron: 0 12,0 * * * /usr/local/bin/renew-ssl-certificates.sh
Test: certbot renew --dry-run

## Next Steps
1. Run: ./07_integration_config_dual_domain.sh
2. Test document editing functionality
3. Configure OnlyOffice app in Nextcloud

## Troubleshooting
- Check certificates: certbot certificates
- Renew manually: certbot renew
- Test renewal: certbot renew --dry-run
- Check nginx: nginx -t
- Reload nginx: systemctl reload nginx
EOF
    
    chmod 600 /root/ssl_setup_info.txt
    success "SSL information saved"
}

# Final verification
verify_ssl_setup() {
    header "Verifying SSL Setup"
    
    local issues=0
    
    # Check if certificates exist
    if [[ -f "/etc/letsencrypt/live/$NEXTCLOUD_DOMAIN/fullchain.pem" ]]; then
        success "Nextcloud SSL certificate exists"
    else
        error "Nextcloud SSL certificate missing"
        ((issues++))
    fi
    
    if [[ -f "/etc/letsencrypt/live/$ONLYOFFICE_DOMAIN/fullchain.pem" ]]; then
        success "OnlyOffice SSL certificate exists"
    else
        error "OnlyOffice SSL certificate missing"
        ((issues++))
    fi
    
    # Check nginx configurations
    if [[ -f "/etc/nginx/sites-available/$NEXTCLOUD_DOMAIN" ]]; then
        success "Nextcloud nginx configuration exists"
    else
        error "Nextcloud nginx configuration missing"
        ((issues++))
    fi
    
    if [[ -f "/etc/nginx/sites-available/$ONLYOFFICE_DOMAIN" ]]; then
        success "OnlyOffice nginx configuration exists"
    else
        error "OnlyOffice nginx configuration missing"
        ((issues++))
    fi
    
    # Check if sites are enabled
    if [[ -L "/etc/nginx/sites-enabled/$NEXTCLOUD_DOMAIN" ]]; then
        success "Nextcloud nginx site is enabled"
    else
        error "Nextcloud nginx site is not enabled"
        ((issues++))
    fi
    
    if [[ -L "/etc/nginx/sites-enabled/$ONLYOFFICE_DOMAIN" ]]; then
        success "OnlyOffice nginx site is enabled"
    else
        error "OnlyOffice nginx site is not enabled"
        ((issues++))
    fi
    
    if [[ $issues -eq 0 ]]; then
        success "SSL setup completed successfully!"
        echo ""
        info "Your sites are now available at:"
        info "  • Nextcloud: https://$NEXTCLOUD_DOMAIN"
        info "  • OnlyOffice: https://$ONLYOFFICE_DOMAIN"
        echo ""
        info "Next steps:"
        info "  1. Run: ./07_integration_config_dual_domain.sh"
        info "  2. Test document editing functionality"
    else
        error "SSL setup completed with $issues issues"
        exit 1
    fi
}

# Main execution
main() {
    # Check for help option
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        show_usage
        exit 0
    fi
    
    check_root
    load_config "$@"
    show_banner
    check_domain_resolution
    create_temp_http_configs
    enable_temp_configs
    obtain_ssl_certificates
    create_ssl_configs
    enable_ssl_configs
    setup_certificate_renewal
    test_ssl_configs
    save_ssl_info
    verify_ssl_setup
}

# Run main function
main "$@"
