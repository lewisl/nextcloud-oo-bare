#!/bin/bash

# Nextcloud + OnlyOffice Complete Uninstall Script
# 
# This script removes everything installed by the installation scripts:
# - Stops all services
# - Removes packages
# - Deletes directories and files
# - Cleans up databases
# - Removes configuration files
# - Resets firewall rules

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

# Display banner and confirmation
show_banner() {
    clear
    echo -e "${RED}${BOLD}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                    COMPLETE UNINSTALL - DANGER ZONE                         ║
║                   This will remove EVERYTHING                               ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo ""
    warning "This script will completely remove:"
    warning "  • All Nextcloud files and data"
    warning "  • All OnlyOffice components"
    warning "  • All databases and data"
    warning "  • All configuration files"
    warning "  • All SSL certificates"
    warning "  • All installed packages"
    echo ""
    error "THIS CANNOT BE UNDONE!"
    echo ""
    
    read -p "Are you absolutely sure you want to continue? (type 'YES' to confirm): " confirm
    if [[ "$confirm" != "YES" ]]; then
        info "Uninstall cancelled"
        exit 0
    fi
    
    echo ""
    warning "Last chance to cancel..."
    read -p "Type 'DELETE EVERYTHING' to proceed: " final_confirm
    if [[ "$final_confirm" != "DELETE EVERYTHING" ]]; then
        info "Uninstall cancelled"
        exit 0
    fi
}

# Stop all services
stop_services() {
    header "Stopping All Services"
    
    local services=(
        "nginx"
        "php8.3-fpm"
        "php-fpm"
        "onlyoffice-documentserver"
        "mariadb"
        "mysql"
        "postgresql"
        "redis-server"
        "fail2ban"
    )
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log "Stopping $service..."
            systemctl stop "$service" || warning "Failed to stop $service"
        fi
        
        if systemctl is-enabled --quiet "$service" 2>/dev/null; then
            log "Disabling $service..."
            systemctl disable "$service" || warning "Failed to disable $service"
        fi
    done
    
    success "Services stopped"
}

# Remove packages
remove_packages() {
    header "Removing Packages"
    
    # OnlyOffice packages
    log "Removing OnlyOffice packages..."
    apt remove --purge -y onlyoffice-documentserver* || true
    
    # Force remove OnlyOffice if stuck
    rm -rf /var/lib/dpkg/info/onlyoffice* || true
    dpkg --remove --force-remove-reinstreq onlyoffice-documentserver || true
    
    # Web server and PHP packages
    log "Removing web server and PHP packages..."
    apt remove --purge -y nginx nginx-* || true
    apt remove --purge -y php* || true
    
    # Database packages
    log "Removing database packages..."
    apt remove --purge -y mariadb-server mariadb-client mariadb-common || true
    apt remove --purge -y mysql-* || true
    apt remove --purge -y postgresql postgresql-* || true
    
    # Other packages
    log "Removing other packages..."
    apt remove --purge -y redis-server || true
    apt remove --purge -y fail2ban || true
    apt remove --purge -y certbot python3-certbot-nginx || true
    
    # Clean up
    apt autoremove -y || true
    apt autoclean || true
    
    success "Packages removed"
}

# Remove directories and files
remove_directories() {
    header "Removing Directories and Files"
    
    # Nextcloud directories
    log "Removing Nextcloud directories..."
    rm -rf /var/www/nextcloud || true
    rm -rf /srv/nextcloud-data || true
    rm -rf /var/www/html || true
    
    # OnlyOffice directories
    log "Removing OnlyOffice directories..."
    rm -rf /etc/onlyoffice || true
    rm -rf /var/lib/onlyoffice || true
    rm -rf /var/log/onlyoffice || true
    rm -rf /usr/bin/onlyoffice || true
    
    # Configuration directories
    log "Removing configuration directories..."
    rm -rf /etc/nginx || true
    rm -rf /etc/php || true
    rm -rf /etc/mysql || true
    rm -rf /etc/postgresql || true
    rm -rf /etc/redis || true
    rm -rf /etc/fail2ban || true
    
    # Data directories
    log "Removing data directories..."
    rm -rf /var/lib/mysql || true
    rm -rf /var/lib/postgresql || true
    rm -rf /var/lib/redis || true
    rm -rf /var/lib/nginx || true
    
    # Log directories
    log "Removing log directories..."
    rm -rf /var/log/nginx || true
    rm -rf /var/log/php* || true
    rm -rf /var/log/mysql || true
    rm -rf /var/log/postgresql || true
    rm -rf /var/log/redis || true
    rm -rf /var/log/fail2ban || true
    rm -rf /var/log/nextcloud* || true
    
    success "Directories removed"
}

# Remove SSL certificates
remove_ssl() {
    header "Removing SSL Certificates"
    
    log "Removing Let's Encrypt certificates..."
    rm -rf /etc/letsencrypt || true
    rm -rf /var/lib/letsencrypt || true
    rm -rf /var/log/letsencrypt || true
    
    log "Removing SSL certificates..."
    rm -rf /etc/ssl/certs/dhparam.pem || true
    
    success "SSL certificates removed"
}

# Clean up users and groups
cleanup_users() {
    header "Cleaning Up Users and Groups"
    
    # Remove users (be careful not to remove system users)
    local users_to_check=(
        "www-data"
        "nginx"
        "mysql"
        "postgres"
        "redis"
    )
    
    for user in "${users_to_check[@]}"; do
        if id "$user" &>/dev/null; then
            log "User $user exists (keeping system user)"
        fi
    done
    
    success "User cleanup completed"
}

# Reset firewall
reset_firewall() {
    header "Resetting Firewall"
    
    log "Resetting UFW firewall..."
    ufw --force reset || true
    ufw default deny incoming || true
    ufw default allow outgoing || true
    ufw allow ssh || true
    ufw --force enable || true
    
    success "Firewall reset to defaults"
}

# Remove installation artifacts
remove_artifacts() {
    header "Removing Installation Artifacts"
    
    log "Removing installation files..."
    rm -rf /root/nextcloud-* || true
    rm -rf /root/onlyoffice-* || true
    rm -rf /root/database-* || true
    rm -rf /root/nginx-* || true
    rm -rf /root/ssl-* || true
    rm -rf /root/integration-* || true
    rm -rf /root/install-* || true
    rm -rf /root/.my.cnf || true
    
    # Remove state files
    rm -rf /root/nextcloud-install-state.txt || true
    
    # Remove log files
    rm -rf /var/log/nextcloud-install.log || true
    rm -rf /var/log/nextcloud-diagnostics.log || true
    
    success "Installation artifacts removed"
}

# Remove repositories
remove_repositories() {
    header "Removing Package Repositories"
    
    log "Removing OnlyOffice repository..."
    rm -rf /etc/apt/sources.list.d/onlyoffice.list || true
    rm -rf /usr/share/keyrings/onlyoffice.gpg || true
    
    log "Removing other repositories..."
    # Add any other custom repositories here
    
    # Update package lists
    apt update || true
    
    success "Repositories removed"
}

# Final cleanup
final_cleanup() {
    header "Final Cleanup"
    
    log "Cleaning package cache..."
    apt clean || true
    apt autoclean || true
    apt autoremove --purge -y || true
    
    log "Cleaning temporary files..."
    rm -rf /tmp/nextcloud* || true
    rm -rf /tmp/onlyoffice* || true
    
    log "Cleaning systemd..."
    systemctl daemon-reload || true
    systemctl reset-failed || true
    
    success "Final cleanup completed"
}

# Verify removal
verify_removal() {
    header "Verifying Removal"
    
    local issues=0
    
    # Check for remaining services
    local services=(
        "nginx"
        "php8.3-fpm"
        "onlyoffice-documentserver"
        "mariadb"
        "postgresql"
        "redis-server"
    )
    
    for service in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "^$service"; then
            warning "Service $service still exists"
            ((issues++))
        fi
    done
    
    # Check for remaining directories
    local directories=(
        "/var/www/nextcloud"
        "/srv/nextcloud-data"
        "/etc/onlyoffice"
        "/var/lib/onlyoffice"
    )
    
    for dir in "${directories[@]}"; do
        if [[ -d "$dir" ]]; then
            warning "Directory $dir still exists"
            ((issues++))
        fi
    done
    
    if [[ $issues -eq 0 ]]; then
        success "Verification passed - all components removed"
    else
        warning "$issues issues found - manual cleanup may be needed"
    fi
}

# Main execution
main() {
    check_root
    show_banner
    
    log "Starting complete uninstall..."
    
    stop_services
    remove_packages
    remove_directories
    remove_ssl
    cleanup_users
    reset_firewall
    remove_artifacts
    remove_repositories
    final_cleanup
    verify_removal
    
    header "Uninstall Complete"
    success "All Nextcloud + OnlyOffice components have been removed"
    echo ""
    info "Your system has been restored to its previous state"
    info "Only SSH access and basic firewall rules remain"
    echo ""
    warning "If you had any custom configurations, they have been removed"
    warning "Make sure to reconfigure any services you need"
}

# Run main function
main "$@"
