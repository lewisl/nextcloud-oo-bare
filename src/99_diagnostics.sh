#!/bin/bash

# Nextcloud + OnlyOffice Diagnostics and Troubleshooting
# 
# This script provides comprehensive diagnostics for the installation:
# - Checks all services and their status
# - Validates configuration files
# - Tests connectivity and integration
# - Provides troubleshooting recommendations
# - Generates diagnostic reports

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/nextcloud-diagnostics.log"
NEXTCLOUD_WEB_DIR="/var/www/nextcloud"
ONLYOFFICE_PORT="8080"

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
    echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[⚠]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[ℹ]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"
}

header() {
    echo -e "${CYAN}${BOLD}$1${NC}" | tee -a "$LOG_FILE"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script should be run as root for complete diagnostics"
        warning "Some checks may be limited"
    fi
}

# Display banner
show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                    Nextcloud + OnlyOffice Diagnostics                       ║
║                         System Health Check                                 ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo ""
}

# Check system information
check_system_info() {
    header "System Information"
    echo ""
    
    info "Operating System: $(lsb_release -d | cut -f2 2>/dev/null || echo "Unknown")"
    info "Kernel: $(uname -r)"
    info "Architecture: $(uname -m)"
    info "Uptime: $(uptime -p 2>/dev/null || uptime)"
    info "Load Average: $(uptime | awk -F'load average:' '{print $2}')"
    
    # Memory information
    local mem_info=$(free -h | grep Mem)
    local mem_total=$(echo "$mem_info" | awk '{print $2}')
    local mem_used=$(echo "$mem_info" | awk '{print $3}')
    local mem_free=$(echo "$mem_info" | awk '{print $4}')
    info "Memory: $mem_used used / $mem_total total ($mem_free free)"
    
    # Disk space
    local disk_info=$(df -h / | tail -1)
    local disk_used=$(echo "$disk_info" | awk '{print $3}')
    local disk_total=$(echo "$disk_info" | awk '{print $2}')
    local disk_free=$(echo "$disk_info" | awk '{print $4}')
    local disk_percent=$(echo "$disk_info" | awk '{print $5}')
    info "Disk Space: $disk_used used / $disk_total total ($disk_free free, $disk_percent used)"
    
    echo ""
}

# Check service status
check_services() {
    header "Service Status"
    echo ""
    
    local services=(
        "nginx"
        "php8.3-fpm:php-fpm"
        "mariadb:mysql"
        "postgresql"
        "redis-server:redis"
        "onlyoffice-documentserver:onlyoffice"
        "fail2ban"
        "ufw"
    )
    
    for service_info in "${services[@]}"; do
        local service_name="${service_info%%:*}"
        local display_name="${service_info##*:}"
        [[ "$display_name" == "$service_name" ]] && display_name="$service_name"
        
        if systemctl is-active --quiet "$service_name" 2>/dev/null; then
            success "$display_name is running"
        elif systemctl list-unit-files | grep -q "^$service_name"; then
            error "$display_name is not running"
        else
            warning "$display_name is not installed"
        fi
    done
    
    echo ""
}

# Check network connectivity
check_network() {
    header "Network Connectivity"
    echo ""
    
    # Check if ports are listening
    local ports=(
        "80:HTTP"
        "443:HTTPS"
        "3306:MySQL"
        "5432:PostgreSQL"
        "6379:Redis"
        "$ONLYOFFICE_PORT:OnlyOffice"
    )
    
    for port_info in "${ports[@]}"; do
        local port="${port_info%%:*}"
        local service="${port_info##*:}"
        
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            success "$service (port $port) is listening"
        else
            warning "$service (port $port) is not listening"
        fi
    done
    
    # Check external connectivity
    if curl -s --connect-timeout 5 google.com > /dev/null; then
        success "External internet connectivity working"
    else
        error "External internet connectivity failed"
    fi
    
    echo ""
}

# Check Nextcloud status
check_nextcloud() {
    header "Nextcloud Status"
    echo ""
    
    if [[ ! -d "$NEXTCLOUD_WEB_DIR" ]]; then
        error "Nextcloud directory not found: $NEXTCLOUD_WEB_DIR"
        return
    fi
    
    # Check if Nextcloud is installed
    if [[ -f "$NEXTCLOUD_WEB_DIR/config/config.php" ]]; then
        success "Nextcloud configuration found"
        
        # Get Nextcloud version
        local version=$(grep "version" "$NEXTCLOUD_WEB_DIR/version.php" | cut -d"'" -f4 2>/dev/null || echo "Unknown")
        info "Nextcloud version: $version"
        
        # Check occ status
        if cd "$NEXTCLOUD_WEB_DIR" && sudo -u www-data php occ status --no-warnings 2>/dev/null; then
            success "Nextcloud OCC status check passed"
        else
            error "Nextcloud OCC status check failed"
        fi
        
        # Check database connection
        if cd "$NEXTCLOUD_WEB_DIR" && sudo -u www-data php occ db:convert-filecache-bigint --no-interaction --dry-run 2>/dev/null >/dev/null; then
            success "Database connection working"
        else
            error "Database connection failed"
        fi
        
    else
        error "Nextcloud not configured (config.php missing)"
    fi
    
    echo ""
}

# Check OnlyOffice status
check_onlyoffice() {
    header "OnlyOffice Document Server Status"
    echo ""
    
    # Check if OnlyOffice is installed
    if systemctl list-unit-files | grep -q onlyoffice-documentserver; then
        success "OnlyOffice Document Server is installed"
        
        # Check service status
        if systemctl is-active --quiet onlyoffice-documentserver; then
            success "OnlyOffice service is running"
            
            # Check healthcheck
            if curl -s "http://127.0.0.1:$ONLYOFFICE_PORT/healthcheck" | grep -q "true"; then
                success "OnlyOffice healthcheck passed"
            else
                error "OnlyOffice healthcheck failed"
            fi
            
            # Check discovery endpoint
            if curl -s "http://127.0.0.1:$ONLYOFFICE_PORT/hosting/discovery" | grep -q "wopi-discovery"; then
                success "OnlyOffice discovery endpoint working"
            else
                warning "OnlyOffice discovery endpoint not responding"
            fi
            
        else
            error "OnlyOffice service is not running"
        fi
        
    else
        error "OnlyOffice Document Server is not installed"
    fi
    
    echo ""
}

# Check SSL certificates
check_ssl() {
    header "SSL Certificate Status"
    echo ""
    
    # Find domain from nginx config
    local domain=""
    if [[ -f /root/ssl-setup-summary.txt ]]; then
        domain=$(grep "Domain:" /root/ssl-setup-summary.txt | cut -d' ' -f2)
    fi
    
    if [[ -z "$domain" ]]; then
        warning "Domain not found in SSL setup summary"
        return
    fi
    
    local cert_path="/etc/letsencrypt/live/$domain/fullchain.pem"
    
    if [[ -f "$cert_path" ]]; then
        success "SSL certificate found for $domain"
        
        # Check certificate expiry
        local expiry_date=$(openssl x509 -enddate -noout -in "$cert_path" | cut -d= -f2)
        local expiry_epoch=$(date -d "$expiry_date" +%s)
        local current_epoch=$(date +%s)
        local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
        
        if [[ $days_until_expiry -gt 30 ]]; then
            success "Certificate expires in $days_until_expiry days ($expiry_date)"
        elif [[ $days_until_expiry -gt 7 ]]; then
            warning "Certificate expires in $days_until_expiry days ($expiry_date)"
        else
            error "Certificate expires in $days_until_expiry days ($expiry_date) - RENEWAL NEEDED"
        fi
        
        # Test HTTPS access
        if curl -s -I "https://$domain/" | grep -q "HTTP/"; then
            success "HTTPS access working"
        else
            error "HTTPS access failed"
        fi
        
    else
        error "SSL certificate not found for $domain"
    fi
    
    echo ""
}

# Check integration
check_integration() {
    header "Nextcloud-OnlyOffice Integration"
    echo ""
    
    if [[ ! -d "$NEXTCLOUD_WEB_DIR" ]]; then
        error "Nextcloud not found"
        return
    fi
    
    cd "$NEXTCLOUD_WEB_DIR"
    
    # Check if OnlyOffice app is installed
    if sudo -u www-data php occ app:list | grep -q "onlyoffice"; then
        success "OnlyOffice app is installed"
        
        # Check if app is enabled
        if sudo -u www-data php occ app:list | grep -A1 "onlyoffice" | grep -q "enabled"; then
            success "OnlyOffice app is enabled"
            
            # Check configuration
            local doc_server_url=$(sudo -u www-data php occ config:app:get onlyoffice DocumentServerUrl 2>/dev/null || echo "")
            local internal_url=$(sudo -u www-data php occ config:app:get onlyoffice DocumentServerInternalUrl 2>/dev/null || echo "")
            local jwt_secret=$(sudo -u www-data php occ config:app:get onlyoffice jwt_secret 2>/dev/null || echo "")
            
            if [[ -n "$doc_server_url" ]]; then
                success "Document Server URL configured: $doc_server_url"
            else
                error "Document Server URL not configured"
            fi
            
            if [[ -n "$internal_url" ]]; then
                success "Internal URL configured: $internal_url"
            else
                warning "Internal URL not configured"
            fi
            
            if [[ -n "$jwt_secret" ]]; then
                success "JWT secret configured"
            else
                warning "JWT secret not configured"
            fi
            
        else
            error "OnlyOffice app is not enabled"
        fi
        
    else
        error "OnlyOffice app is not installed"
    fi
    
    echo ""
}

# Check file permissions
check_permissions() {
    header "File Permissions"
    echo ""
    
    if [[ -d "$NEXTCLOUD_WEB_DIR" ]]; then
        local web_owner=$(stat -c '%U:%G' "$NEXTCLOUD_WEB_DIR")
        if [[ "$web_owner" == "www-data:www-data" ]]; then
            success "Nextcloud web directory ownership correct"
        else
            error "Nextcloud web directory ownership incorrect: $web_owner (should be www-data:www-data)"
        fi
    fi
    
    if [[ -d "/srv/nextcloud-data" ]]; then
        local data_owner=$(stat -c '%U:%G' "/srv/nextcloud-data")
        if [[ "$data_owner" == "www-data:www-data" ]]; then
            success "Nextcloud data directory ownership correct"
        else
            error "Nextcloud data directory ownership incorrect: $data_owner (should be www-data:www-data)"
        fi
    fi
    
    # Check config file permissions
    if [[ -f "$NEXTCLOUD_WEB_DIR/config/config.php" ]]; then
        local config_perms=$(stat -c '%a' "$NEXTCLOUD_WEB_DIR/config/config.php")
        if [[ "$config_perms" == "640" || "$config_perms" == "644" ]]; then
            success "Config file permissions correct ($config_perms)"
        else
            warning "Config file permissions: $config_perms (recommended: 640)"
        fi
    fi
    
    echo ""
}

# Check logs for errors
check_logs() {
    header "Recent Log Errors"
    echo ""
    
    # Nginx errors
    if [[ -f /var/log/nginx/error.log ]]; then
        local nginx_errors=$(tail -50 /var/log/nginx/error.log | grep -i error | wc -l)
        if [[ $nginx_errors -eq 0 ]]; then
            success "No recent nginx errors"
        else
            warning "$nginx_errors recent nginx errors found"
            info "Check: tail -f /var/log/nginx/error.log"
        fi
    fi
    
    # PHP errors
    local php_version=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
    if [[ -f "/var/log/php$php_version-fpm.log" ]]; then
        local php_errors=$(tail -50 "/var/log/php$php_version-fpm.log" | grep -i error | wc -l)
        if [[ $php_errors -eq 0 ]]; then
            success "No recent PHP-FPM errors"
        else
            warning "$php_errors recent PHP-FPM errors found"
            info "Check: tail -f /var/log/php$php_version-fpm.log"
        fi
    fi
    
    # Nextcloud logs
    if [[ -f "$NEXTCLOUD_WEB_DIR/data/nextcloud.log" ]]; then
        local nc_errors=$(tail -50 "$NEXTCLOUD_WEB_DIR/data/nextcloud.log" | grep -i error | wc -l)
        if [[ $nc_errors -eq 0 ]]; then
            success "No recent Nextcloud errors"
        else
            warning "$nc_errors recent Nextcloud errors found"
            info "Check: tail -f $NEXTCLOUD_WEB_DIR/data/nextcloud.log"
        fi
    fi
    
    echo ""
}

# Generate diagnostic report
generate_report() {
    local report_file="/root/nextcloud-diagnostics-$(date +%Y%m%d-%H%M%S).txt"
    
    header "Generating Diagnostic Report"
    
    {
        echo "Nextcloud + OnlyOffice Diagnostic Report"
        echo "========================================"
        echo "Generated: $(date)"
        echo ""
        
        echo "System Information:"
        echo "- OS: $(lsb_release -d | cut -f2 2>/dev/null || echo "Unknown")"
        echo "- Kernel: $(uname -r)"
        echo "- Uptime: $(uptime -p 2>/dev/null || uptime)"
        echo "- Load: $(uptime | awk -F'load average:' '{print $2}')"
        echo ""
        
        echo "Service Status:"
        systemctl is-active nginx && echo "✓ Nginx" || echo "✗ Nginx"
        systemctl is-active php*-fpm && echo "✓ PHP-FPM" || echo "✗ PHP-FPM"
        systemctl is-active mariadb && echo "✓ MariaDB" || echo "✗ MariaDB"
        systemctl is-active postgresql && echo "✓ PostgreSQL" || echo "✗ PostgreSQL"
        systemctl is-active redis-server && echo "✓ Redis" || echo "✗ Redis"
        systemctl is-active onlyoffice-documentserver && echo "✓ OnlyOffice" || echo "✗ OnlyOffice"
        echo ""
        
        echo "Network Ports:"
        netstat -tuln 2>/dev/null | grep -E ":(80|443|3306|5432|6379|$ONLYOFFICE_PORT) " || echo "No listening ports found"
        echo ""
        
        echo "Disk Usage:"
        df -h
        echo ""
        
        echo "Memory Usage:"
        free -h
        echo ""
        
        if [[ -d "$NEXTCLOUD_WEB_DIR" ]]; then
            echo "Nextcloud Status:"
            cd "$NEXTCLOUD_WEB_DIR" && sudo -u www-data php occ status --no-warnings 2>/dev/null || echo "OCC status failed"
            echo ""
        fi
        
        echo "Recent Errors:"
        echo "Nginx errors (last 10):"
        tail -10 /var/log/nginx/error.log 2>/dev/null | grep -i error || echo "No nginx errors"
        echo ""
        
    } > "$report_file"
    
    success "Diagnostic report saved: $report_file"
    echo ""
}

# Provide troubleshooting recommendations
show_recommendations() {
    header "Troubleshooting Recommendations"
    echo ""
    
    info "Common Issues and Solutions:"
    echo ""
    
    echo "1. OnlyOffice not working:"
    echo "   - Check service: systemctl status onlyoffice-documentserver"
    echo "   - Check logs: journalctl -u onlyoffice-documentserver"
    echo "   - Test healthcheck: curl http://127.0.0.1:$ONLYOFFICE_PORT/healthcheck"
    echo ""
    
    echo "2. SSL certificate issues:"
    echo "   - Renew certificate: certbot renew"
    echo "   - Check expiry: certbot certificates"
    echo "   - Test renewal: certbot renew --dry-run"
    echo ""
    
    echo "3. Nextcloud performance issues:"
    echo "   - Check memory usage: free -h"
    echo "   - Check disk space: df -h"
    echo "   - Optimize database: sudo -u www-data php occ db:add-missing-indices"
    echo ""
    
    echo "4. Integration problems:"
    echo "   - Check app status: sudo -u www-data php occ app:list | grep onlyoffice"
    echo "   - Verify JWT secret matches between Nextcloud and OnlyOffice"
    echo "   - Test internal connectivity: curl http://127.0.0.1:$ONLYOFFICE_PORT/"
    echo ""
    
    echo "5. File permission issues:"
    echo "   - Fix ownership: chown -R www-data:www-data /var/www/nextcloud /srv/nextcloud-data"
    echo "   - Fix permissions: find /var/www/nextcloud -type f -exec chmod 640 {} \\;"
    echo "   - Fix directories: find /var/www/nextcloud -type d -exec chmod 750 {} \\;"
    echo ""
}

# Main execution
main() {
    show_banner
    check_root
    
    check_system_info
    check_services
    check_network
    check_nextcloud
    check_onlyoffice
    check_ssl
    check_integration
    check_permissions
    check_logs
    
    generate_report
    show_recommendations
    
    header "Diagnostic Complete"
    info "For detailed logs, check: $LOG_FILE"
    echo ""
}

# Run main function
main "$@"
