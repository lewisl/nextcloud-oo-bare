#!/bin/bash

# System Preparation Script for 2-Domain Nextcloud + OnlyOffice Setup
# This script prepares the system for a dual-domain deployment:
# - Nextcloud: docs.DOMAIN.com
# - OnlyOffice: onlyoffice.DOMAIN.com

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

# Display banner
show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                   2-DOMAIN SYSTEM PREPARATION                                ║
║              Nextcloud + OnlyOffice Dual Domain Setup                       ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo ""
    info "This script will prepare your system for:"
    info "  • Nextcloud on docs.DOMAIN.com"
    info "  • OnlyOffice on onlyoffice.DOMAIN.com"
    info "  • Each with their own nginx configuration"
    echo ""
}

# Get domain information
get_domain_info() {
    header "Domain Configuration"
    
    read -p "Enter your base domain (e.g., test-collab-site.com): " BASE_DOMAIN
    read -p "Enter admin email for SSL certificates: " ADMIN_EMAIL
    
    # Validate domain format
    if [[ ! "$BASE_DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]*\.[a-zA-Z]{2,}$ ]]; then
        error "Invalid domain format. Please use format like 'example.com'"
        exit 1
    fi
    
    # Set derived domains
    NEXTCLOUD_DOMAIN="docs.$BASE_DOMAIN"
    ONLYOFFICE_DOMAIN="onlyoffice.$BASE_DOMAIN"
    
    info "Nextcloud will be available at: https://$NEXTCLOUD_DOMAIN"
    info "OnlyOffice will be available at: https://$ONLYOFFICE_DOMAIN"
    
    # Save configuration
    mkdir -p /etc/nextcloud-onlyoffice
    cat > /etc/nextcloud-onlyoffice/params.yaml << EOF
deployment:
  base_domain: "$BASE_DOMAIN"
  nextcloud_domain: "$NEXTCLOUD_DOMAIN"
  onlyoffice_domain: "$ONLYOFFICE_DOMAIN"
  admin_email: "$ADMIN_EMAIL"

nextcloud:
  db_name: "nextcloud"
  db_user: "ncuser"
  db_password: ""

onlyoffice:
  db_name: "onlyoffice"
  db_user: "oouser"
  db_password: ""

jwt:
  secret: ""
EOF
    
    chmod 600 /etc/nextcloud-onlyoffice/params.yaml
    success "Configuration saved to /etc/nextcloud-onlyoffice/params.yaml"
}

# Update system
update_system() {
    header "Updating System Packages"
    
    log "Updating package lists..."
    apt update
    
    log "Upgrading system packages..."
    apt upgrade -y
    
    success "System updated"
}

# Install required packages
install_packages() {
    header "Installing Required Packages"
    
    # Essential packages
    local packages=(
        "curl"
        "wget"
        "gnupg"
        "lsb-release"
        "ca-certificates"
        "software-properties-common"
        "apt-transport-https"
        "unzip"
        "htop"
        "nano"
        "vim"
        "ufw"
        "fail2ban"
    )
    
    log "Installing essential packages..."
    apt install -y "${packages[@]}"
    
    # Web server and PHP
    log "Installing web server and PHP..."
    apt install -y nginx
    
    # PHP 8.3 with required extensions
    apt install -y php8.3-fpm php8.3-cli php8.3-common php8.3-mysql php8.3-pgsql \
        php8.3-zip php8.3-gd php8.3-mbstring php8.3-curl php8.3-xml php8.3-bcmath \
        php8.3-intl php8.3-imagick php8.3-apcu php8.3-redis php8.3-opcache
    
    # Databases
    log "Installing databases..."
    apt install -y mariadb-server postgresql postgresql-contrib
    
    # Redis for caching
    apt install -y redis-server
    
    # SSL certificates
    apt install -y certbot python3-certbot-nginx
    
    success "All packages installed"
}

# Configure firewall
configure_firewall() {
    header "Configuring Firewall"
    
    log "Configuring UFW firewall..."
    
    # Reset firewall
    ufw --force reset
    
    # Default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH
    ufw allow ssh
    
    # Allow HTTP and HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    # Enable firewall
    ufw --force enable
    
    success "Firewall configured"
}

# Configure fail2ban
configure_fail2ban() {
    header "Configuring Fail2ban"
    
    log "Configuring fail2ban for nginx..."
    
    # Create nginx jail
    cat > /etc/fail2ban/jail.d/nginx.conf << 'EOF'
[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log

[nginx-limit-req]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 10
EOF
    
    # Start and enable fail2ban
    systemctl enable fail2ban
    systemctl start fail2ban
    
    success "Fail2ban configured"
}

# Configure PHP
configure_php() {
    header "Configuring PHP"
    
    log "Configuring PHP settings..."
    
    # PHP-FPM configuration
    local php_ini="/etc/php/8.3/fpm/php.ini"
    local php_cli="/etc/php/8.3/cli/php.ini"
    
    # Common PHP settings
    for ini_file in "$php_ini" "$php_cli"; do
        if [[ -f "$ini_file" ]]; then
            # Memory and execution limits
            sed -i 's/memory_limit = .*/memory_limit = 512M/' "$ini_file"
            sed -i 's/max_execution_time = .*/max_execution_time = 300/' "$ini_file"
            sed -i 's/max_input_time = .*/max_input_time = 300/' "$ini_file"
            
            # File upload settings
            sed -i 's/upload_max_filesize = .*/upload_max_filesize = 10G/' "$ini_file"
            sed -i 's/post_max_size = .*/post_max_size = 10G/' "$ini_file"
            sed -i 's/max_file_uploads = .*/max_file_uploads = 200/' "$ini_file"
            
            # Session settings
            sed -i 's/session.gc_maxlifetime = .*/session.gc_maxlifetime = 3600/' "$ini_file"
            
            # OPcache settings
            sed -i 's/opcache.enable=.*/opcache.enable=1/' "$ini_file"
            sed -i 's/opcache.memory_consumption=.*/opcache.memory_consumption=128/' "$ini_file"
            sed -i 's/opcache.max_accelerated_files=.*/opcache.max_accelerated_files=10000/' "$ini_file"
        fi
    done
    
    # PHP-FPM pool configuration
    local pool_conf="/etc/php/8.3/fpm/pool.d/www.conf"
    if [[ -f "$pool_conf" ]]; then
        # Increase limits
        sed -i 's/pm.max_children = .*/pm.max_children = 50/' "$pool_conf"
        sed -i 's/pm.start_servers = .*/pm.start_servers = 5/' "$pool_conf"
        sed -i 's/pm.min_spare_servers = .*/pm.min_spare_servers = 5/' "$pool_conf"
        sed -i 's/pm.max_spare_servers = .*/pm.max_spare_servers = 35/' "$pool_conf"
    fi
    
    # Enable APCu module
    phpenmod apcu
    
    # Restart PHP-FPM
    systemctl restart php8.3-fpm
    systemctl enable php8.3-fpm
    
    success "PHP configured"
}

# Configure nginx
configure_nginx() {
    header "Configuring Nginx"
    
    log "Configuring nginx for dual domain setup..."
    
    # Remove default nginx configuration
    rm -f /etc/nginx/sites-enabled/default
    
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
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
    
    # Rate limiting
    limit_req_zone $binary_remote_addr zone=login:10m rate=10r/m;
    limit_req_zone $binary_remote_addr zone=api:10m rate=1r/s;
    
    # Include site configurations
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF
    
    # Test nginx configuration
    nginx -t
    
    # Start and enable nginx
    systemctl restart nginx
    systemctl enable nginx
    
    success "Nginx configured"
}

# Configure databases
configure_databases() {
    header "Configuring Databases"
    
    # Configure MariaDB
    log "Configuring MariaDB..."
    systemctl start mariadb
    systemctl enable mariadb
    
    # Secure MariaDB installation
    mysql -u root -e "DELETE FROM mysql.user WHERE User='';"
    mysql -u root -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    mysql -u root -e "DROP DATABASE IF EXISTS test;"
    mysql -u root -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
    mysql -u root -e "FLUSH PRIVILEGES;"
    
    # Configure PostgreSQL
    log "Configuring PostgreSQL..."
    systemctl start postgresql
    systemctl enable postgresql
    
    # Configure Redis
    log "Configuring Redis..."
    systemctl start redis-server
    systemctl enable redis-server
    
    # Configure Redis for unix socket
    log "Configuring Redis for unix socket..."
    sed -i 's/# unixsocket \/run\/redis\/redis-server.sock/unixsocket \/run\/redis\/redis-server.sock/' /etc/redis/redis.conf
    sed -i 's/# unixsocketperm 700/unixsocketperm 770/' /etc/redis/redis.conf
    
    # Add www-data to redis group
    usermod -a -G redis www-data
    
    # Restart Redis to apply configuration
    systemctl restart redis-server
    
    success "Databases configured"
}

# Generate secrets
generate_secrets() {
    header "Generating Secrets"
    
    log "Generating random passwords and secrets..."
    
    # Generate passwords
    local nc_db_password=$(openssl rand -base64 32)
    local oo_db_password=$(openssl rand -base64 32)
    local jwt_secret=$(openssl rand -base64 64)
    
    # Update configuration file with proper YAML structure
    # Update Nextcloud password (first occurrence)
    sed -i "0,/db_password: \"\"/s//db_password: \"$nc_db_password\"/" /etc/nextcloud-onlyoffice/params.yaml
    
    # Update OnlyOffice password (second occurrence) 
    # Use a more specific pattern to target the right section
    sed -i "/^onlyoffice:/,/^jwt:/ s/db_password: \"\"/db_password: \"$oo_db_password\"/" /etc/nextcloud-onlyoffice/params.yaml
    
    # Update JWT secret
    sed -i "s/secret: \"\"/secret: \"$jwt_secret\"/" /etc/nextcloud-onlyoffice/params.yaml
    
    success "Secrets generated and saved"
}

# Final verification
verify_installation() {
    header "Verifying Installation"
    
    local issues=0
    
    # Check services
    local services=("nginx" "php8.3-fpm" "mariadb" "postgresql" "redis-server" "fail2ban")
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            success "$service is running"
        else
            error "$service is not running"
            ((issues++))
        fi
    done
    
    # Check configuration file
    if [[ -f "/etc/nextcloud-onlyoffice/params.yaml" ]]; then
        success "Configuration file created"
    else
        error "Configuration file missing"
        ((issues++))
    fi
    
    if [[ $issues -eq 0 ]]; then
        success "System preparation completed successfully!"
        echo ""
        info "Next steps:"
        info "  1. Run: ./02_database_setup_dual_domain.sh"
        info "  2. Run: ./03_nextcloud_install_dual_domain.sh"
        info "  3. Run: ./04_onlyoffice_install_dual_domain.sh"
        info "  4. Run: ./05_nginx_config_dual_domain.sh"
        info "  5. Run: ./06_ssl_setup_dual_domain.sh"
        info "  6. Run: ./07_integration_config_dual_domain.sh"
    else
        error "Installation completed with $issues issues"
        exit 1
    fi
}

# Main execution
main() {
    check_root
    show_banner
    get_domain_info
    update_system
    install_packages
    configure_firewall
    configure_fail2ban
    configure_php
    configure_nginx
    configure_databases
    generate_secrets
    verify_installation
}

# Run main function
main "$@"
