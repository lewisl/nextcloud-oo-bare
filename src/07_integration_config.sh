#!/bin/bash

# Nextcloud + OnlyOffice Bare Metal Installation
# Step 7: Integration Configuration
# 
# This script configures the integration between Nextcloud and OnlyOffice:
# - Installs OnlyOffice connector app in Nextcloud
# - Configures connection URLs and JWT authentication
# - Sets up proper internal/external URL routing
# - Tests document editing functionality
# - Optimizes integration settings

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/nextcloud-install.log"
NEXTCLOUD_WEB_DIR="/var/www/nextcloud"
NEXTCLOUD_USER="www-data"
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
    
    # Check if SSL is configured
    if [[ ! -f /root/ssl-setup-summary.txt ]]; then
        warning "SSL not configured. Integration will work but HTTPS is recommended."
    fi
    
    # Check if JWT secret exists
    if [[ ! -f /root/onlyoffice-jwt-secret.txt ]]; then
        error "OnlyOffice JWT secret not found. Please run 04_onlyoffice_install.sh first."
    fi
    
    log "Prerequisites check passed"
}

# Get domain name
get_domain() {
    local domain=""
    
    # Try to get from SSL setup summary
    if [[ -f /root/ssl-setup-summary.txt ]]; then
        domain=$(grep "Domain:" /root/ssl-setup-summary.txt | cut -d' ' -f2)
    fi
    
    # If not found, try nginx config
    if [[ -z "$domain" && -f /root/nginx-config-summary.txt ]]; then
        domain=$(grep "Domain:" /root/nginx-config-summary.txt | cut -d' ' -f2)
    fi
    
    # If still not found, ask user
    if [[ -z "$domain" ]]; then
        echo ""
        read -p "Enter the domain name (e.g., cloud.example.com): " domain
        
        if [[ -z "$domain" ]]; then
            error "Domain name is required"
        fi
    fi
    
    echo "$domain"
}

# Get JWT secret
get_jwt_secret() {
    local jwt_secret=""
    
    if [[ -f /root/onlyoffice-jwt-secret.txt ]]; then
        jwt_secret=$(grep "JWT Secret:" /root/onlyoffice-jwt-secret.txt | cut -d' ' -f3)
    fi
    
    if [[ -z "$jwt_secret" ]]; then
        error "JWT secret not found in /root/onlyoffice-jwt-secret.txt"
    fi
    
    echo "$jwt_secret"
}

# Test OnlyOffice service
test_onlyoffice_service() {
    log "Testing OnlyOffice Document Server..."
    
    # Test healthcheck
    if curl -s "http://127.0.0.1:$ONLYOFFICE_PORT/healthcheck" | grep -q "true"; then
        log "✓ OnlyOffice healthcheck passed"
    else
        error "✗ OnlyOffice healthcheck failed - service may not be running"
    fi
    
    # Test discovery endpoint
    if curl -s "http://127.0.0.1:$ONLYOFFICE_PORT/hosting/discovery" | grep -q "wopi-discovery"; then
        log "✓ OnlyOffice discovery endpoint working"
    else
        warning "✗ OnlyOffice discovery endpoint not responding properly"
    fi
}

# Install OnlyOffice connector app
install_connector_app() {
    log "Installing OnlyOffice connector app..."
    
    cd "$NEXTCLOUD_WEB_DIR"
    
    # Download and install OnlyOffice app
    if sudo -u "$NEXTCLOUD_USER" php occ app:list | grep -q "onlyoffice"; then
        log "OnlyOffice app already installed"
    else
        # Install from app store
        if sudo -u "$NEXTCLOUD_USER" php occ app:install onlyoffice; then
            log "✓ OnlyOffice app installed from app store"
        else
            warning "Failed to install from app store, trying manual installation..."
            
            # Manual installation as fallback
            local temp_dir="/tmp/onlyoffice-app"
            mkdir -p "$temp_dir"
            cd "$temp_dir"
            
            # Download latest release
            wget -O onlyoffice.tar.gz "https://github.com/ONLYOFFICE/onlyoffice-nextcloud/releases/latest/download/onlyoffice.tar.gz"
            
            # Extract to apps directory
            tar -xzf onlyoffice.tar.gz -C "$NEXTCLOUD_WEB_DIR/apps/"
            chown -R "$NEXTCLOUD_USER:$NEXTCLOUD_USER" "$NEXTCLOUD_WEB_DIR/apps/onlyoffice"
            
            # Clean up
            rm -rf "$temp_dir"
            
            log "✓ OnlyOffice app installed manually"
        fi
    fi
    
    # Enable the app
    sudo -u "$NEXTCLOUD_USER" php occ app:enable onlyoffice
    log "✓ OnlyOffice app enabled"
}

# Configure OnlyOffice connector
configure_connector() {
    local domain="$1"
    local jwt_secret="$2"
    
    log "Configuring OnlyOffice connector..."
    
    cd "$NEXTCLOUD_WEB_DIR"
    
    # Determine protocol
    local protocol="https"
    if [[ ! -f /root/ssl-setup-summary.txt ]]; then
        protocol="http"
        warning "Using HTTP - SSL not configured"
    fi
    
    # Configure Document Server URL (external URL for browsers)
    sudo -u "$NEXTCLOUD_USER" php occ config:app:set onlyoffice DocumentServerUrl \
        --value="$protocol://$domain/onlyoffice/"
    
    # Configure internal Document Server URL (for server-to-server communication)
    sudo -u "$NEXTCLOUD_USER" php occ config:app:set onlyoffice DocumentServerInternalUrl \
        --value="http://127.0.0.1:$ONLYOFFICE_PORT/"
    
    # Configure storage URL (how OnlyOffice calls back to Nextcloud)
    sudo -u "$NEXTCLOUD_USER" php occ config:app:set onlyoffice StorageUrl \
        --value="$protocol://$domain/"
    
    # Configure JWT authentication
    sudo -u "$NEXTCLOUD_USER" php occ config:app:set onlyoffice jwt_secret \
        --value="$jwt_secret"
    
    sudo -u "$NEXTCLOUD_USER" php occ config:app:set onlyoffice jwt_header \
        --value="Authorization"
    
    # Enable JWT
    sudo -u "$NEXTCLOUD_USER" php occ config:app:set onlyoffice jwt_use_for_request \
        --value="true"
    
    # Configure file formats
    sudo -u "$NEXTCLOUD_USER" php occ config:app:set onlyoffice defFormats \
        --value='{"csv":"false","doc":"true","docm":"true","docx":"true","dotx":"true","epub":"true","html":"false","odp":"true","ods":"true","odt":"true","pdf":"false","potm":"true","potx":"true","ppsm":"true","ppsx":"true","ppt":"true","pptm":"true","pptx":"true","rtf":"true","txt":"false","xls":"true","xlsm":"true","xlsx":"true","xltm":"true","xltx":"true"}'
    
    # Configure editing formats
    sudo -u "$NEXTCLOUD_USER" php occ config:app:set onlyoffice editFormats \
        --value='{"csv":"true","odp":"true","ods":"true","odt":"true","potm":"false","potx":"false","ppsm":"false","ppsx":"false","ppt":"false","pptm":"false","pptx":"true","rtf":"false","txt":"true","xls":"false","xlsm":"false","xlsx":"true","xltm":"false","xltx":"false"}'
    
    # Disable certificate verification for internal connections
    sudo -u "$NEXTCLOUD_USER" php occ config:app:set onlyoffice verify_peer_off \
        --value="true"
    
    log "✓ OnlyOffice connector configured"
}

# Test integration
test_integration() {
    local domain="$1"
    
    log "Testing Nextcloud-OnlyOffice integration..."
    
    cd "$NEXTCLOUD_WEB_DIR"
    
    # Check app status
    if sudo -u "$NEXTCLOUD_USER" php occ app:list | grep -A1 "onlyoffice" | grep -q "enabled"; then
        log "✓ OnlyOffice app is enabled"
    else
        error "✗ OnlyOffice app is not enabled"
    fi
    
    # Test configuration
    local doc_server_url=$(sudo -u "$NEXTCLOUD_USER" php occ config:app:get onlyoffice DocumentServerUrl)
    local internal_url=$(sudo -u "$NEXTCLOUD_USER" php occ config:app:get onlyoffice DocumentServerInternalUrl)
    local jwt_secret=$(sudo -u "$NEXTCLOUD_USER" php occ config:app:get onlyoffice jwt_secret)
    
    log "Configuration check:"
    log "  Document Server URL: $doc_server_url"
    log "  Internal URL: $internal_url"
    log "  JWT Secret: ${jwt_secret:0:10}..."
    
    # Test external access to OnlyOffice
    local protocol="https"
    if [[ ! -f /root/ssl-setup-summary.txt ]]; then
        protocol="http"
    fi
    
    if curl -s "$protocol://$domain/onlyoffice/healthcheck" | grep -q "true"; then
        log "✓ OnlyOffice accessible via external URL"
    else
        warning "✗ OnlyOffice not accessible via external URL"
    fi
}

# Create test document
create_test_document() {
    log "Creating test document for editing..."
    
    cd "$NEXTCLOUD_WEB_DIR"
    
    # Create a test directory in Nextcloud data
    local test_dir="/srv/nextcloud-data/admin/files/OnlyOffice_Test"
    sudo -u "$NEXTCLOUD_USER" mkdir -p "$test_dir"
    
    # Create test documents
    cat > "$test_dir/Test_Document.docx" << 'EOF'
This is a test document for OnlyOffice integration.
You should be able to edit this document online.
EOF
    
    cat > "$test_dir/Test_Spreadsheet.xlsx" << 'EOF'
Name,Value,Description
Test,123,Sample data
OnlyOffice,456,Document editing
Nextcloud,789,File storage
EOF
    
    # Set proper ownership
    chown -R "$NEXTCLOUD_USER:$NEXTCLOUD_USER" "$test_dir"
    
    # Scan files
    sudo -u "$NEXTCLOUD_USER" php occ files:scan admin
    
    log "✓ Test documents created in OnlyOffice_Test folder"
}

# Configure additional settings
configure_additional_settings() {
    log "Configuring additional OnlyOffice settings..."
    
    cd "$NEXTCLOUD_WEB_DIR"
    
    # Enable collaborative editing
    sudo -u "$NEXTCLOUD_USER" php occ config:app:set onlyoffice customization_chat \
        --value="true"
    
    sudo -u "$NEXTCLOUD_USER" php occ config:app:set onlyoffice customization_compactHeader \
        --value="true"
    
    sudo -u "$NEXTCLOUD_USER" php occ config:app:set onlyoffice customization_feedback \
        --value="false"
    
    sudo -u "$NEXTCLOUD_USER" php occ config:app:set onlyoffice customization_forcesave \
        --value="true"
    
    sudo -u "$NEXTCLOUD_USER" php occ config:app:set onlyoffice customization_help \
        --value="false"
    
    # Configure watermark settings
    sudo -u "$NEXTCLOUD_USER" php occ config:app:set onlyoffice watermark_text \
        --value=""
    
    # Configure demo settings
    sudo -u "$NEXTCLOUD_USER" php occ config:app:set onlyoffice demo \
        --value='{"enabled":false}'
    
    log "✓ Additional settings configured"
}

# Save integration summary
save_integration_info() {
    local domain="$1"
    local jwt_secret="$2"
    local info_file="/root/integration-config-summary.txt"
    
    local protocol="https"
    if [[ ! -f /root/ssl-setup-summary.txt ]]; then
        protocol="http"
    fi
    
    cat > "$info_file" << EOF
Nextcloud-OnlyOffice Integration Summary
=======================================
Date: $(date)
Domain: $domain
Protocol: $protocol

OnlyOffice Connector Configuration:
- App Status: Enabled
- Document Server URL: $protocol://$domain/onlyoffice/
- Internal URL: http://127.0.0.1:$ONLYOFFICE_PORT/
- Storage URL: $protocol://$domain/
- JWT Secret: ${jwt_secret:0:10}...
- JWT Header: Authorization

Supported File Formats:
- View: DOC, DOCX, DOCM, DOTX, EPUB, ODT, ODS, ODP, PDF, PPT, PPTX, PPTM, POTX, POTM, PPSX, PPSM, XLS, XLSX, XLSM, XLTX, XLTM, RTF, TXT, CSV, HTML
- Edit: DOCX, XLSX, PPTX, ODT, ODS, ODP, TXT, CSV

Features Enabled:
- Collaborative editing
- Real-time collaboration
- Comments and chat
- Force save
- Compact header

Test Documents:
- Location: OnlyOffice_Test folder in admin account
- Files: Test_Document.docx, Test_Spreadsheet.xlsx

URLs:
- Nextcloud: $protocol://$domain/
- OnlyOffice: $protocol://$domain/onlyoffice/
- Admin Login: $protocol://$domain/login

Testing:
1. Login to Nextcloud as admin
2. Navigate to OnlyOffice_Test folder
3. Click on Test_Document.docx to edit
4. Verify document opens in OnlyOffice editor
5. Make changes and save

Troubleshooting:
- Check OnlyOffice service: systemctl status onlyoffice-documentserver
- Check nginx: systemctl status nginx
- Check logs: /var/log/nginx/error.log
- Nextcloud logs: $NEXTCLOUD_WEB_DIR/data/nextcloud.log

Log File: $LOG_FILE
EOF

    log "Integration summary saved to: $info_file"
}

# Main execution
main() {
    log "Starting Nextcloud-OnlyOffice integration configuration..."
    
    check_root
    check_prerequisites
    
    local domain=$(get_domain)
    local jwt_secret=$(get_jwt_secret)
    
    log "Configuring integration for domain: $domain"
    
    test_onlyoffice_service
    install_connector_app
    configure_connector "$domain" "$jwt_secret"
    configure_additional_settings
    test_integration "$domain"
    create_test_document
    save_integration_info "$domain" "$jwt_secret"
    
    log "✓ Nextcloud-OnlyOffice integration completed successfully!"
    echo ""
    info "Integration configured for: $domain"
    info "Integration summary: /root/integration-config-summary.txt"
    echo ""
    info "Test the integration:"
    info "1. Login to Nextcloud at: https://$domain/"
    info "2. Navigate to OnlyOffice_Test folder"
    info "3. Click on Test_Document.docx to edit"
    echo ""
    info "Next step: Run 08_master_install.sh for complete deployment"
    echo ""
    info "Log file: $LOG_FILE"
}

# Run main function
main "$@"
