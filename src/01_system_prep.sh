#!/bin/bash

# Nextcloud + OnlyOffice Bare Metal Installation
# Step 1: System Preparation and Basic Packages
# 
# This script prepares a fresh Ubuntu/Debian system for Nextcloud and OnlyOffice installation
# - Installs required packages
# - Configures basic security
# - Sets up users and directories
# - Configures firewall

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/nextcloud-install.log"
NEXTCLOUD_USER="www-data"
NEXTCLOUD_DATA_DIR="/srv/nextcloud-data"
NEXTCLOUD_WEB_DIR="/var/www/nextcloud"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
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

# Check OS compatibility
check_os() {
    if [[ ! -f /etc/os-release ]]; then
        error "Cannot determine OS version"
    fi
    
    source /etc/os-release
    
    case "$ID" in
        ubuntu)
            if [[ "${VERSION_ID}" < "20.04" ]]; then
                error "Ubuntu 20.04 or later required"
            fi
            ;;
        debian)
            if [[ "${VERSION_ID}" < "11" ]]; then
                error "Debian 11 or later required"
            fi
            ;;
        *)
            error "Unsupported OS: $ID. This script supports Ubuntu 20.04+ and Debian 11+"
            ;;
    esac
    
    log "OS check passed: $PRETTY_NAME"
}

# Update system packages
update_system() {
    log "Updating system packages..."

    # Check for running apt processes and wait
    local max_wait=60
    local wait_count=0
    while pgrep -x apt > /dev/null || pgrep -x apt-get > /dev/null || pgrep -x dpkg > /dev/null; do
        if [[ $wait_count -ge $max_wait ]]; then
            warning "Killing stuck apt processes..."
            pkill -f apt || true
            pkill -f dpkg || true
            rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock || true
            dpkg --configure -a || true
            break
        fi
        warning "Waiting for existing package manager processes to complete... ($wait_count/$max_wait)"
        sleep 5
        ((wait_count += 5))
    done

    # Fix any broken packages first
    dpkg --configure -a || true
    apt --fix-broken install -y || true

    apt update
    apt upgrade -y
    apt autoremove -y
    log "System update completed"
}

# Install core packages
install_packages() {
    log "Installing core packages..."
    
    # Web server and PHP
    local php_packages=(
        "nginx"
        "php-fpm"
        "php-cli"
        "php-mysql"
        "php-pgsql"
        "php-xml"
        "php-gd"
        "php-curl"
        "php-mbstring"
        "php-intl"
        "php-bcmath"
        "php-gmp"
        "php-zip"
        "php-bz2"
        "php-imagick"
        "php-redis"
        "php-apcu"
    )
    
    # Database servers
    local db_packages=(
        "mariadb-server"
        "postgresql"
        "postgresql-contrib"
        "redis-server"
    )
    
    # System tools
    local system_packages=(
        "unzip"
        "wget"
        "curl"
        "ssl-cert"
        "certbot"
        "python3-certbot-nginx"
        "ufw"
        "fail2ban"
        "htop"
        "tree"
        "jq"
        "git"
    )
    
    # Install all packages
    apt install -y "${php_packages[@]}" "${db_packages[@]}" "${system_packages[@]}"
    
    log "Core packages installed successfully"
}

# Configure firewall
configure_firewall() {
    log "Configuring UFW firewall..."
    
    # Reset UFW to defaults
    ufw --force reset
    
    # Default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH (be careful not to lock yourself out)
    ufw allow ssh
    
    # Allow HTTP and HTTPS
    ufw allow 'Nginx Full'
    
    # Enable firewall
    ufw --force enable
    
    log "Firewall configured and enabled"
}

# Configure fail2ban
configure_fail2ban() {
    log "Configuring fail2ban..."
    
    # Create local jail configuration
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
backend = %(sshd_backend)s

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log

[nginx-noscript]
enabled = true
port = http,https
filter = nginx-noscript
logpath = /var/log/nginx/access.log
maxretry = 6

[nginx-badbots]
enabled = true
port = http,https
filter = nginx-badbots
logpath = /var/log/nginx/access.log
maxretry = 2

[nginx-noproxy]
enabled = true
port = http,https
filter = nginx-noproxy
logpath = /var/log/nginx/access.log
maxretry = 2
EOF

    systemctl enable fail2ban
    systemctl restart fail2ban
    
    log "Fail2ban configured and started"
}

# Create directories and set permissions
setup_directories() {
    log "Setting up directories..."
    
    # Create Nextcloud data directory
    mkdir -p "$NEXTCLOUD_DATA_DIR"
    chown "$NEXTCLOUD_USER:$NEXTCLOUD_USER" "$NEXTCLOUD_DATA_DIR"
    chmod 750 "$NEXTCLOUD_DATA_DIR"
    
    # Create web directory
    mkdir -p "$(dirname "$NEXTCLOUD_WEB_DIR")"
    
    # Create log directory for our scripts
    mkdir -p /var/log/nextcloud-install
    
    log "Directories created and configured"
}

# Configure PHP for Nextcloud
configure_php() {
    log "Configuring PHP for Nextcloud..."
    
    # Detect PHP version
    local php_version=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
    local php_ini="/etc/php/$php_version/fpm/php.ini"
    local php_pool="/etc/php/$php_version/fpm/pool.d/www.conf"
    
    if [[ ! -f "$php_ini" ]]; then
        error "PHP configuration file not found: $php_ini"
    fi
    
    # Backup original configuration
    cp "$php_ini" "$php_ini.backup.$(date +%s)"
    
    # Update PHP settings for Nextcloud
    sed -i 's/memory_limit = .*/memory_limit = 512M/' "$php_ini"
    sed -i 's/upload_max_filesize = .*/upload_max_filesize = 1G/' "$php_ini"
    sed -i 's/post_max_size = .*/post_max_size = 1G/' "$php_ini"
    sed -i 's/max_execution_time = .*/max_execution_time = 3600/' "$php_ini"
    sed -i 's/max_input_time = .*/max_input_time = 3600/' "$php_ini"
    sed -i 's/;date.timezone.*/date.timezone = UTC/' "$php_ini"
    sed -i 's/;opcache.enable=.*/opcache.enable=1/' "$php_ini"
    sed -i 's/;opcache.memory_consumption=.*/opcache.memory_consumption=128/' "$php_ini"
    sed -i 's/;opcache.interned_strings_buffer=.*/opcache.interned_strings_buffer=8/' "$php_ini"
    sed -i 's/;opcache.max_accelerated_files=.*/opcache.max_accelerated_files=10000/' "$php_ini"
    sed -i 's/;opcache.revalidate_freq=.*/opcache.revalidate_freq=1/' "$php_ini"
    sed -i 's/;opcache.save_comments=.*/opcache.save_comments=1/' "$php_ini"
    
    # Configure PHP-FPM pool
    cp "$php_pool" "$php_pool.backup.$(date +%s)"
    
    # Update pool settings
    sed -i 's/pm.max_children = .*/pm.max_children = 120/' "$php_pool"
    sed -i 's/pm.start_servers = .*/pm.start_servers = 12/' "$php_pool"
    sed -i 's/pm.min_spare_servers = .*/pm.min_spare_servers = 6/' "$php_pool"
    sed -i 's/pm.max_spare_servers = .*/pm.max_spare_servers = 18/' "$php_pool"
    
    # Enable and restart PHP-FPM
    systemctl enable "php$php_version-fpm"
    systemctl restart "php$php_version-fpm"
    
    log "PHP configured for Nextcloud (version $php_version)"
}

# Enable and start services
enable_services() {
    log "Enabling and starting services..."
    
    local services=(
        "nginx"
        "mariadb"
        "postgresql"
        "redis-server"
    )
    
    for service in "${services[@]}"; do
        systemctl enable "$service"
        systemctl start "$service"
        
        if systemctl is-active --quiet "$service"; then
            log "✓ $service is running"
        else
            warning "⚠ $service failed to start"
        fi
    done
}

# Save installation info
save_install_info() {
    local info_file="/root/nextcloud-system-prep.txt"
    
    cat > "$info_file" << EOF
Nextcloud + OnlyOffice System Preparation
========================================
Date: $(date)
OS: $(lsb_release -d | cut -f2)
PHP Version: $(php -v | head -n1)

Directories Created:
- Nextcloud Data: $NEXTCLOUD_DATA_DIR
- Web Root: $NEXTCLOUD_WEB_DIR (to be created)
- Logs: /var/log/nextcloud-install/

Services Enabled:
- nginx
- php-fpm
- mariadb
- postgresql
- redis-server
- fail2ban
- ufw (firewall)

Next Steps:
1. Run 02_database_setup.sh to configure databases
2. Run 03_nextcloud_install.sh to install Nextcloud
3. Run 04_onlyoffice_install.sh to install OnlyOffice
4. Run 05_nginx_config.sh to configure web server
5. Run 06_ssl_setup.sh to configure SSL certificates

Configuration Files Modified:
- $(find /etc/php -name "php.ini.backup.*" | head -1 | sed 's/.backup.*//')
- $(find /etc/php -name "www.conf.backup.*" | head -1 | sed 's/.backup.*//')
- /etc/fail2ban/jail.local (created)

Log File: $LOG_FILE
EOF

    log "Installation info saved to: $info_file"
}

# Main execution
main() {
    log "Starting Nextcloud + OnlyOffice system preparation..."
    
    check_root
    check_os
    update_system
    install_packages
    setup_directories
    configure_php
    configure_firewall
    configure_fail2ban
    enable_services
    save_install_info
    
    log "✓ System preparation completed successfully!"
    echo ""
    info "Next step: Run 02_database_setup.sh to configure databases"
    echo ""
    info "Log file: $LOG_FILE"
    info "Installation info: /root/nextcloud-system-prep.txt"
}

# Run main function
main "$@"
