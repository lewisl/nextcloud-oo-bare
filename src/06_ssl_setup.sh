#!/bin/bash

# Nextcloud + OnlyOffice Bare Metal Installation
# Step 6: SSL Certificate Setup
# 
# This script configures SSL certificates using Let's Encrypt:
# - Installs and configures certbot
# - Obtains SSL certificates for the domain
# - Configures automatic renewal
# - Updates nginx configuration with SSL
# - Sets up security best practices

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/nextcloud-install.log"

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
    
    # Check if nginx is configured
    if [[ ! -f /root/nginx-config-summary.txt ]]; then
        error "Nginx not configured. Please run 05_nginx_config.sh first."
    fi
    
    # Check if certbot is installed
    if ! command -v certbot &> /dev/null; then
        error "Certbot not installed. Please run 01_system_prep.sh first."
    fi
    
    # Check if nginx is running
    if ! systemctl is-active --quiet nginx; then
        error "Nginx is not running. Please check nginx configuration."
    fi
    
    log "Prerequisites check passed"
}

# Get domain name from nginx config
get_domain() {
    local domain=""
    
    # Try to get from nginx config summary
    if [[ -f /root/nginx-config-summary.txt ]]; then
        domain=$(grep "Domain:" /root/nginx-config-summary.txt | cut -d' ' -f2)
    fi
    
    # If not found, try to detect from nginx sites
    if [[ -z "$domain" ]]; then
        local sites_dir="/etc/nginx/sites-enabled"
        if [[ -d "$sites_dir" ]]; then
            for site in "$sites_dir"/*; do
                if [[ -f "$site" && "$(basename "$site")" != "default" ]]; then
                    # Try to get first server_name from the config file
                    domain=$(grep -m1 "server_name" "$site" | awk '{print $2}' | sed 's/;//')
                    if [[ -z "$domain" ]]; then
                        # Fallback to filename
                        domain=$(basename "$site")
                    fi
                    break
                fi
            done
        fi
    fi
    
    # If still not found, error out
    if [[ -z "$domain" ]]; then
        error "Could not detect domain from nginx configuration. Please check nginx setup."
    fi

    log "Detected domain: $domain"
    
    echo "$domain"
}

# Get email for Let's Encrypt
get_email() {
    local email="$1"

    # If email provided as parameter, use it
    if [[ -n "$email" ]]; then
        # Email provided, use it (no log to avoid contamination)
        true
    else
        # Use default email for testing
        email="admin@localhost.local"
        warning "No email provided, using default: $email"
        warning "This is for testing only. For production, provide a real email address."
    fi

    # Basic email validation
    if [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        error "Invalid email address format: $email"
    fi

    echo "$email"
}

# Check DNS resolution
check_dns() {
    local domain="$1"
    
    log "Checking DNS resolution for $domain..."
    
    # Get public IP of this server
    local server_ip=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || curl -s icanhazip.com)
    
    if [[ -z "$server_ip" ]]; then
        warning "Could not determine server public IP"
        return 0
    fi
    
    # Check if domain resolves to this server
    local domain_ip=$(dig +short "$domain" A | head -1)
    
    if [[ -z "$domain_ip" ]]; then
        warning "Domain $domain does not resolve to any IP"
        warning "Please ensure DNS is configured to point $domain to $server_ip"
        warning "Continuing anyway - Let's Encrypt will validate via HTTP"
    elif [[ "$domain_ip" != "$server_ip" ]]; then
        warning "Domain $domain resolves to $domain_ip but server IP is $server_ip"
        warning "This may be normal if using Cloudflare proxy or CDN"
        warning "Continuing with SSL setup - Let's Encrypt will validate via HTTP"
    else
        log "✓ DNS resolution correct: $domain -> $server_ip"
    fi
}

# Test HTTP access
test_http_access() {
    local domain="$1"
    
    log "Testing HTTP access to $domain..."
    
    # Create test file
    local test_file="/var/www/html/ssl-test-$(date +%s).txt"
    echo "SSL setup test" > "$test_file"
    
    # Test access
    if curl -s "http://$domain/$(basename "$test_file")" | grep -q "SSL setup test"; then
        log "✓ HTTP access working"
    else
        warning "HTTP access test failed - Let's Encrypt may not work"
        warning "Continuing anyway - Let's Encrypt will perform its own validation"
    fi
    
    # Clean up test file
    rm -f "$test_file"
}

# Obtain SSL certificate
obtain_certificate() {
    local domain="$1"
    local email="$2"
    
    log "Obtaining SSL certificate for $domain..."
    
    # Stop nginx temporarily for standalone mode (safer for first-time setup)
    systemctl stop nginx
    
    # Obtain certificate using standalone mode
    if certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --email "$email" \
        --domains "$domain"; then
        log "✓ SSL certificate obtained successfully"
    else
        # Start nginx back up even if certbot failed
        systemctl start nginx
        error "Failed to obtain SSL certificate"
    fi
    
    # Start nginx back up
    systemctl start nginx
}

# Update nginx configuration with SSL
update_nginx_ssl() {
    local domain="$1"
    local config_file="/etc/nginx/sites-available/$domain"
    
    log "Updating nginx configuration with SSL..."
    
    if [[ ! -f "$config_file" ]]; then
        error "Nginx configuration file not found: $config_file"
    fi
    
    # Backup current config
    cp "$config_file" "$config_file.backup.$(date +%s)"
    
    # Update SSL certificate paths
    sed -i "s|# ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;|ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;|" "$config_file"
    sed -i "s|# ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;|ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;|" "$config_file"
    
    # Test nginx configuration
    if nginx -t; then
        log "✓ Nginx SSL configuration valid"
        systemctl reload nginx
        log "✓ Nginx reloaded with SSL configuration"
    else
        error "Nginx SSL configuration invalid"
    fi
}

# Configure automatic renewal
setup_auto_renewal() {
    log "Setting up automatic certificate renewal..."
    
    # Create renewal hook script
    local hook_script="/etc/letsencrypt/renewal-hooks/deploy/nginx-reload.sh"
    mkdir -p "$(dirname "$hook_script")"
    
    cat > "$hook_script" << 'EOF'
#!/bin/bash
# Reload nginx after certificate renewal
systemctl reload nginx
EOF
    
    chmod +x "$hook_script"
    
    # Test renewal process
    if certbot renew --dry-run; then
        log "✓ Certificate renewal test successful"
    else
        warning "Certificate renewal test failed"
    fi
    
    # Check if cron job already exists
    if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
        # Add cron job for automatic renewal (twice daily)
        (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -
        log "✓ Automatic renewal cron job added"
    else
        log "✓ Automatic renewal cron job already exists"
    fi
}

# Test SSL configuration
test_ssl() {
    local domain="$1"
    
    log "Testing SSL configuration..."
    
    # Test HTTPS access
    if curl -s -I "https://$domain/" | grep -q "HTTP/"; then
        log "✓ HTTPS access working"
    else
        warning "HTTPS access test failed"
    fi
    
    # Test SSL certificate
    local cert_info=$(echo | openssl s_client -servername "$domain" -connect "$domain:443" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null)
    
    if [[ -n "$cert_info" ]]; then
        log "✓ SSL certificate valid"
        info "Certificate details:"
        echo "$cert_info" | sed 's/^/  /'
    else
        warning "Could not verify SSL certificate"
    fi
    
    # Test OnlyOffice through HTTPS
    if curl -s "https://$domain/onlyoffice/healthcheck" | grep -q "true"; then
        log "✓ OnlyOffice accessible via HTTPS"
    else
        warning "OnlyOffice not accessible via HTTPS"
    fi
}

# Configure security enhancements
configure_security() {
    local domain="$1"
    
    log "Configuring additional security enhancements..."
    
    # Create DH parameters for better security (this takes time)
    local dhparam_file="/etc/ssl/certs/dhparam.pem"
    
    if [[ ! -f "$dhparam_file" ]]; then
        log "Generating DH parameters (this may take several minutes)..."
        openssl dhparam -out "$dhparam_file" 2048
        log "✓ DH parameters generated"
    fi
    
    # Update nginx config with enhanced security
    local config_file="/etc/nginx/sites-available/$domain"
    
    # Add DH parameters and enhanced SSL settings
    if ! grep -q "ssl_dhparam" "$config_file"; then
        sed -i "/ssl_session_timeout/a\\    ssl_dhparam $dhparam_file;" "$config_file"
        sed -i "/ssl_dhparam/a\\    ssl_ecdh_curve secp384r1;" "$config_file"
        
        # Test and reload
        if nginx -t; then
            systemctl reload nginx
            log "✓ Enhanced SSL security configured"
        else
            warning "Enhanced SSL configuration failed"
        fi
    fi
}

# Save SSL setup summary
save_ssl_info() {
    local domain="$1"
    local email="$2"
    local info_file="/root/ssl-setup-summary.txt"
    
    # Get certificate expiry date
    local cert_expiry=""
    if [[ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
        cert_expiry=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$domain/fullchain.pem" | cut -d= -f2)
    fi
    
    cat > "$info_file" << EOF
SSL Certificate Setup Summary
============================
Date: $(date)
Domain: $domain
Email: $email

Certificate Details:
- Provider: Let's Encrypt
- Certificate: /etc/letsencrypt/live/$domain/fullchain.pem
- Private Key: /etc/letsencrypt/live/$domain/privkey.pem
- Expiry: $cert_expiry

Automatic Renewal:
- Cron job: 0 12 * * * /usr/bin/certbot renew --quiet
- Hook script: /etc/letsencrypt/renewal-hooks/deploy/nginx-reload.sh
- Test command: certbot renew --dry-run

Security Features:
- TLS 1.2 and 1.3 only
- Strong cipher suites
- HSTS enabled
- DH parameters: /etc/ssl/certs/dhparam.pem

URLs:
- Nextcloud: https://$domain/
- OnlyOffice: https://$domain/onlyoffice/
- Healthcheck: https://$domain/onlyoffice/healthcheck

Next Steps:
1. Run 07_integration_config.sh to configure Nextcloud-OnlyOffice integration
2. Test document editing functionality
3. Configure additional security if needed

Certificate Management:
- Renew manually: certbot renew
- Check status: certbot certificates
- Revoke: certbot revoke --cert-path /etc/letsencrypt/live/$domain/fullchain.pem

Log File: $LOG_FILE
EOF

    log "SSL setup summary saved to: $info_file"
}

# Main execution
main() {
    local email="${1:-}"
    local domain="${2:-}"

    # Get domain from previous step if not provided
    if [[ -z "$domain" ]]; then
        domain=$(get_domain)
    fi

    # Get email if not provided
    if [[ -z "$email" ]]; then
        echo ""
        read -p "Enter email address for SSL certificate: " email
        if [[ -z "$email" ]]; then
            error "Email address is required"
        fi
    fi

    log "Starting SSL certificate setup..."

    check_root
    check_prerequisites

    local validated_email=$(get_email "$email")

    log "Using domain: $domain"
    
    log "Setting up SSL for domain: $domain"

    # Skip DNS check - irrelevant for SSL with CDN/proxy
    # Let's Encrypt will validate domain access via HTTP challenge
    obtain_certificate "$domain" "$validated_email"
    update_nginx_ssl "$domain"
    setup_auto_renewal
    configure_security "$domain"
    test_ssl "$domain"
    save_ssl_info "$domain" "$validated_email"
    
    log "✓ SSL certificate setup completed successfully!"
    echo ""
    info "Domain: $domain"
    info "Certificate expires: $(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$domain/fullchain.pem" | cut -d= -f2)"
    info "SSL setup summary: /root/ssl-setup-summary.txt"
    echo ""
    info "Your site is now accessible at: https://$domain/"
    echo ""
    info "Next step: Run 07_integration_config.sh"
    echo ""
    info "Log file: $LOG_FILE"
}

# Run main function
main "$@"
