#!/bin/bash

# Nextcloud + OnlyOffice Bare Metal Installation
# Master Installation Script
# 
# This script orchestrates the complete installation of Nextcloud + OnlyOffice:
# - Runs all installation steps in correct order
# - Provides error handling and rollback capabilities
# - Validates each step before proceeding
# - Creates comprehensive installation report
# - Supports resume from failed steps

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/nextcloud-install.log"
STATE_FILE="/root/nextcloud-install-state.txt"

# Installation steps
declare -a INSTALL_STEPS=(
    "01_system_prep.sh"
    "02_database_setup.sh"
    "03_nextcloud_install.sh"
    "04_onlyoffice_install.sh"
    "05_nginx_config.sh"
    "06_ssl_setup.sh"
    "07_integration_config.sh"
)

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

header() {
    echo -e "${CYAN}${BOLD}$1${NC}" | tee -a "$LOG_FILE"
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
║                    Nextcloud + OnlyOffice Installation                      ║
║                           Bare Metal Deployment                             ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo ""
    info "This script will install and configure:"
    info "  • Nextcloud (latest version)"
    info "  • OnlyOffice Document Server"
    info "  • Nginx reverse proxy"
    info "  • SSL certificates (Let's Encrypt)"
    info "  • Complete integration"
    echo ""
    warning "This installation will:"
    warning "  • Modify system packages and configuration"
    warning "  • Configure firewall rules"
    warning "  • Set up databases (MariaDB + PostgreSQL)"
    warning "  • Configure web server"
    echo ""
}

# Get installation parameters
get_installation_params() {
    header "Installation Configuration"
    echo ""
    
    # Domain name
    read -p "Enter your domain name (e.g., cloud.example.com): " DOMAIN
    if [[ -z "$DOMAIN" ]]; then
        error "Domain name is required"
        exit 1
    fi
    
    # Email for SSL
    read -p "Enter email for SSL certificates: " EMAIL
    if [[ -z "$EMAIL" ]]; then
        error "Email is required for SSL certificates"
        exit 1
    fi
    
    # Confirm installation
    echo ""
    info "Installation Summary:"
    info "  Domain: $DOMAIN"
    info "  Email: $EMAIL"
    info "  Installation directory: /var/www/nextcloud"
    info "  Data directory: /srv/nextcloud-data"
    echo ""
    
    read -p "Proceed with installation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Installation cancelled"
        exit 0
    fi
    
    # Save parameters
    cat > /root/install-params.txt << EOF
DOMAIN=$DOMAIN
EMAIL=$EMAIL
INSTALL_DATE=$(date)
EOF
}

# Load installation state
load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        source "$STATE_FILE"
        info "Resuming installation from step: ${CURRENT_STEP:-1}"
    else
        CURRENT_STEP=1
        echo "CURRENT_STEP=1" > "$STATE_FILE"
    fi
}

# Save installation state
save_state() {
    local step=$1
    echo "CURRENT_STEP=$step" > "$STATE_FILE"
}

# Check if step was completed
is_step_completed() {
    local step_num=$1
    local step_name="${INSTALL_STEPS[$((step_num-1))]}"
    
    case $step_num in
        1) [[ -f /root/nextcloud-system-prep.txt ]] ;;
        2) [[ -f /root/database-setup-summary.txt ]] ;;
        3) [[ -f /root/nextcloud-install-summary.txt ]] ;;
        4) [[ -f /root/onlyoffice-install-summary.txt ]] ;;
        5) [[ -f /root/nginx-config-summary.txt ]] ;;
        6) [[ -f /root/ssl-setup-summary.txt ]] ;;
        7) [[ -f /root/integration-config-summary.txt ]] ;;
        *) false ;;
    esac
}

# Run installation step
run_step() {
    local step_num=$1
    local step_script="${INSTALL_STEPS[$((step_num-1))]}"
    local step_name=$(echo "$step_script" | sed 's/[0-9]*_//; s/\.sh//; s/_/ /g' | sed 's/\b\w/\U&/g')
    
    header "Step $step_num: $step_name"
    echo ""
    
    # Check if already completed
    if is_step_completed "$step_num"; then
        success "Step $step_num already completed, skipping..."
        return 0
    fi
    
    # Run the step
    local script_path="$SCRIPT_DIR/$step_script"
    
    if [[ ! -f "$script_path" ]]; then
        error "Step script not found: $script_path"
        return 1
    fi
    
    if [[ ! -x "$script_path" ]]; then
        chmod +x "$script_path"
    fi
    
    info "Running: $step_script"
    
    if "$script_path"; then
        success "Step $step_num completed successfully"
        save_state $((step_num + 1))
        return 0
    else
        error "Step $step_num failed"
        return 1
    fi
}

# Rollback installation
rollback_installation() {
    header "Rolling Back Installation"
    warning "This will attempt to undo changes made during installation"
    echo ""
    
    read -p "Are you sure you want to rollback? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Rollback cancelled"
        return
    fi
    
    # Stop services
    systemctl stop nginx || true
    systemctl stop onlyoffice-documentserver || true
    systemctl stop php*-fpm || true
    
    # Remove installations
    rm -rf /var/www/nextcloud
    rm -rf /srv/nextcloud-data
    rm -rf /etc/nginx/sites-available/$(cat /root/install-params.txt | grep DOMAIN | cut -d= -f2) || true
    rm -rf /etc/nginx/sites-enabled/$(cat /root/install-params.txt | grep DOMAIN | cut -d= -f2) || true
    
    # Remove OnlyOffice
    apt remove --purge -y onlyoffice-documentserver || true
    
    # Remove state files
    rm -f "$STATE_FILE"
    rm -f /root/install-params.txt
    rm -f /root/*-summary.txt
    rm -f /root/*-credentials.txt
    
    warning "Rollback completed. Some system packages and configurations may remain."
}

# Generate final report
generate_report() {
    local report_file="/root/nextcloud-installation-report.txt"
    local domain=$(grep DOMAIN /root/install-params.txt | cut -d= -f2)
    
    header "Generating Installation Report"
    
    cat > "$report_file" << EOF
Nextcloud + OnlyOffice Installation Report
==========================================
Installation Date: $(date)
Domain: $domain
Installation Method: Bare Metal (No Docker/Containers)

System Information:
- OS: $(lsb_release -d | cut -f2)
- Kernel: $(uname -r)
- Architecture: $(uname -m)
- Memory: $(free -h | grep Mem | awk '{print $2}')
- Disk: $(df -h / | tail -1 | awk '{print $2}')

Installed Components:
✓ Nextcloud $(cat /var/www/nextcloud/version.php | grep OC_VersionString | cut -d"'" -f4 2>/dev/null || echo "Unknown")
✓ OnlyOffice Document Server
✓ Nginx Web Server
✓ MariaDB Database (Nextcloud)
✓ PostgreSQL Database (OnlyOffice)
✓ Redis Cache
✓ SSL Certificate (Let's Encrypt)
✓ PHP $(php -v | head -n1 | cut -d' ' -f2)

Access Information:
- Nextcloud URL: https://$domain/
- OnlyOffice URL: https://$domain/onlyoffice/
- Admin Credentials: /root/nextcloud-admin-credentials.txt

Key Directories:
- Web Root: /var/www/nextcloud/
- Data Directory: /srv/nextcloud-data/
- Config: /var/www/nextcloud/config/config.php
- Nginx Config: /etc/nginx/sites-available/$domain
- OnlyOffice Config: /etc/onlyoffice/documentserver/

Service Status:
$(systemctl is-active nginx && echo "✓ Nginx: Running" || echo "✗ Nginx: Not Running")
$(systemctl is-active php*-fpm && echo "✓ PHP-FPM: Running" || echo "✗ PHP-FPM: Not Running")
$(systemctl is-active mariadb && echo "✓ MariaDB: Running" || echo "✗ MariaDB: Not Running")
$(systemctl is-active postgresql && echo "✓ PostgreSQL: Running" || echo "✗ PostgreSQL: Not Running")
$(systemctl is-active redis-server && echo "✓ Redis: Running" || echo "✗ Redis: Not Running")
$(systemctl is-active onlyoffice-documentserver && echo "✓ OnlyOffice: Running" || echo "✗ OnlyOffice: Not Running")

Security Features:
✓ UFW Firewall enabled
✓ Fail2ban configured
✓ SSL/TLS encryption
✓ Security headers configured
✓ JWT authentication for OnlyOffice

Maintenance Commands:
- Update Nextcloud: sudo -u www-data php /var/www/nextcloud/occ upgrade
- Restart services: systemctl restart nginx php*-fpm onlyoffice-documentserver
- Check logs: tail -f /var/log/nginx/error.log
- Renew SSL: certbot renew

Backup Locations:
- Database credentials: /root/*-credentials.txt
- Configuration summaries: /root/*-summary.txt
- Installation log: $LOG_FILE

Next Steps:
1. Login to Nextcloud at https://$domain/
2. Complete initial setup wizard
3. Test document editing in OnlyOffice_Test folder
4. Configure additional users and settings
5. Set up regular backups

Support:
- Nextcloud Documentation: https://docs.nextcloud.com/
- OnlyOffice Documentation: https://helpcenter.onlyoffice.com/
- Installation Log: $LOG_FILE
EOF

    success "Installation report generated: $report_file"
}

# Main installation process
main() {
    check_root
    show_banner
    
    # Check for resume
    if [[ -f "$STATE_FILE" ]]; then
        echo ""
        warning "Previous installation detected"
        read -p "Resume installation? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            load_state
        else
            read -p "Start fresh installation? This will remove previous state (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -f "$STATE_FILE"
                CURRENT_STEP=1
            else
                info "Installation cancelled"
                exit 0
            fi
        fi
    else
        get_installation_params
        CURRENT_STEP=1
    fi
    
    # Run installation steps
    local total_steps=${#INSTALL_STEPS[@]}
    
    for ((i=CURRENT_STEP; i<=total_steps; i++)); do
        echo ""
        if ! run_step "$i"; then
            error "Installation failed at step $i"
            echo ""
            warning "Options:"
            warning "1. Check logs: $LOG_FILE"
            warning "2. Fix the issue and run this script again to resume"
            warning "3. Run rollback: $0 --rollback"
            exit 1
        fi
        
        # Brief pause between steps
        sleep 2
    done
    
    # Generate final report
    echo ""
    generate_report
    
    # Success message
    echo ""
    header "Installation Completed Successfully!"
    echo ""
    local domain=$(grep DOMAIN /root/install-params.txt | cut -d= -f2)
    success "Nextcloud + OnlyOffice is now ready!"
    success "Access your installation at: https://$domain/"
    echo ""
    info "Installation report: /root/nextcloud-installation-report.txt"
    info "Admin credentials: /root/nextcloud-admin-credentials.txt"
    info "Installation log: $LOG_FILE"
    echo ""
    info "Test document editing:"
    info "1. Login to Nextcloud"
    info "2. Navigate to OnlyOffice_Test folder"
    info "3. Click on Test_Document.docx"
    echo ""
    
    # Clean up state file
    rm -f "$STATE_FILE"
}

# Handle command line arguments
case "${1:-}" in
    --rollback)
        check_root
        rollback_installation
        ;;
    --help|-h)
        echo "Usage: $0 [--rollback] [--help]"
        echo ""
        echo "Options:"
        echo "  --rollback    Rollback the installation"
        echo "  --help        Show this help message"
        ;;
    *)
        main "$@"
        ;;
esac
