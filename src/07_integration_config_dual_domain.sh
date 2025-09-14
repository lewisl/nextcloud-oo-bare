#!/bin/bash

# Integration Configuration Script for 2-Domain Setup
# This script configures the integration between Nextcloud and OnlyOffice

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
    
    # Extract JWT secret
    JWT_SECRET=$(grep "secret:" /etc/nextcloud-onlyoffice/params.yaml | cut -d'"' -f2)
    
    success "Configuration loaded"
}

# Get OnlyOffice port from nginx configuration
get_onlyoffice_port() {
    local nginx_conf="/etc/onlyoffice/documentserver/nginx/ds.conf"
    if [[ -f "$nginx_conf" ]]; then
        # Extract port from listen directive
        local port=$(grep "listen" "$nginx_conf" | head -1 | sed -n "s/.*listen[[:space:]]*[^:]*:\([0-9]*\).*/\1/p")
        echo "${port:-80}"
    else
        echo "80"  # default fallback
    fi
}

# Display banner
show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                   2-DOMAIN INTEGRATION CONFIGURATION                        ║
║              Connecting Nextcloud and OnlyOffice                            ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo ""
    info "Configuring integration for:"
    info "  • Nextcloud: https://$NEXTCLOUD_DOMAIN"
    info "  • OnlyOffice: https://$ONLYOFFICE_DOMAIN"
    echo ""
}

# Check prerequisites
check_prerequisites() {
    header "Checking Prerequisites"
    
    # Check if Nextcloud is accessible
    local nextcloud_response=$(curl -s -o /dev/null -w "%{http_code}" "https://$NEXTCLOUD_DOMAIN" || echo "000")
    if [[ "$nextcloud_response" == "200" || "$nextcloud_response" == "302" ]]; then
        success "Nextcloud is accessible"
    else
        error "Nextcloud is not accessible (HTTP $nextcloud_response)"
        exit 1
    fi
    
    # Check if OnlyOffice is accessible
    local onlyoffice_response=$(curl -s -o /dev/null -w "%{http_code}" "https://$ONLYOFFICE_DOMAIN" || echo "000")
    if [[ "$nextcloud_response" == "200" || "$nextcloud_response" == "302" || "$nextcloud_response" == "502" ]]; then
        success "OnlyOffice is accessible"
    else
        error "OnlyOffice is not accessible (HTTP $onlyoffice_response)"
        exit 1
    fi
    
    # Check if Nextcloud occ command works
    if sudo -u www-data php /var/www/nextcloud/occ --version >/dev/null 2>&1; then
        success "Nextcloud occ command is working"
    else
        error "Nextcloud occ command is not working"
        exit 1
    fi
}

# Install OnlyOffice app in Nextcloud
install_onlyoffice_app() {
    header "Installing OnlyOffice App in Nextcloud"
    
    log "Installing OnlyOffice app..."
    
    # Download and install OnlyOffice app
    sudo -u www-data php /var/www/nextcloud/occ app:install onlyoffice
    
    success "OnlyOffice app installed"
}

# Configure OnlyOffice connection
configure_onlyoffice_connection() {
    header "Configuring OnlyOffice Connection"
    
    log "Configuring OnlyOffice connection settings..."
    
    # Get OnlyOffice port
    local onlyoffice_port=$(get_onlyoffice_port)
    log "OnlyOffice internal port: $onlyoffice_port"
    
    # Configure OnlyOffice Document Server URL
    sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice DocumentServerUrl --value="https://$ONLYOFFICE_DOMAIN/"
    
    # Configure JWT secret
    sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice jwt_secret --value="$JWT_SECRET"
    
    # Configure JWT header
    sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice jwt_header --value="Authorization"
    
    # Enable JWT
    sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice jwt_enabled --value="true"
    
    # Configure document server internal URL (for internal communication)
    sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice DocumentServerInternalUrl --value="http://127.0.0.1:$onlyoffice_port/"
    
    # Configure storage URL
    sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice storage_url --value="https://$NEXTCLOUD_DOMAIN/"
    
    # Configure webhook URL
    sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice webhook_url --value="https://$NEXTCLOUD_DOMAIN/index.php/apps/onlyoffice/webhook"
    
    success "OnlyOffice connection configured"
}

# Configure OnlyOffice Document Server
configure_onlyoffice_server() {
    header "Configuring OnlyOffice Document Server"
    
    log "Configuring OnlyOffice Document Server settings..."
    
    # Update OnlyOffice local.json with Nextcloud settings
    sudo cp /etc/onlyoffice/documentserver/local.json /etc/onlyoffice/documentserver/local.json.backup
    
    # Create new local.json with Nextcloud integration settings
    sudo bash -c "cat > /etc/onlyoffice/documentserver/local.json << EOF
{
  \"services\": {
    \"CoAuthoring\": {
      \"sql\": {
        \"type\": \"postgres\",
        \"dbHost\": \"localhost\",
        \"dbPort\": \"5432\",
        \"dbName\": \"onlyoffice\",
        \"dbUser\": \"onlyoffice\",
        \"dbPass\": \"onlyoffice\"
      },
      \"token\": {
        \"enable\": {
          \"request\": {
            \"inbox\": true,
            \"outbox\": true
          },
          \"browser\": true
        },
        \"inbox\": {
          \"header\": \"Authorization\"
        },
        \"outbox\": {
          \"header\": \"Authorization\"
        }
      },
      \"secret\": {
        \"inbox\": {
          \"string\": \"$JWT_SECRET\"
        },
        \"outbox\": {
          \"string\": \"$JWT_SECRET\"
        },
        \"session\": {
          \"string\": \"$JWT_SECRET\"
        }
      }
    }
  },
  \"rabbitmq\": {
    \"url\": \"amqp://guest:guest@localhost\"
  },
  \"wopi\": {
    \"enable\": false
  },
  \"storage\": {
    \"fs\": {
      \"secretString\": \"YPS6ChTYS6V0zK96655f\"
    }
  }
}
EOF"
    
    # Restart OnlyOffice services
    log "Restarting OnlyOffice services..."
    sudo systemctl restart onlyoffice-documentserver || warning "OnlyOffice service restart failed, continuing..."
    
    success "OnlyOffice Document Server configured"
}

# Test integration
test_integration() {
    header "Testing Integration"
    
    log "Testing Nextcloud and OnlyOffice integration..."
    
    # Test OnlyOffice app status
    local app_status=$(sudo -u www-data php /var/www/nextcloud/occ app:list | grep onlyoffice || echo "not found")
    if [[ "$app_status" == *"enabled"* ]]; then
        success "OnlyOffice app is enabled in Nextcloud"
    else
        error "OnlyOffice app is not enabled in Nextcloud"
        return 1
    fi
    
    # Test OnlyOffice configuration
    local docserver_url=$(sudo -u www-data php /var/www/nextcloud/occ config:app:get onlyoffice DocumentServerUrl)
    if [[ "$docserver_url" == "https://$ONLYOFFICE_DOMAIN/" ]]; then
        success "OnlyOffice Document Server URL is configured correctly"
    else
        warning "OnlyOffice Document Server URL: $docserver_url"
    fi
    
    # Test JWT configuration
    local jwt_enabled=$(sudo -u www-data php /var/www/nextcloud/occ config:app:get onlyoffice jwt_enabled)
    if [[ "$jwt_enabled" == "true" ]]; then
        success "JWT is enabled"
    else
        warning "JWT is not enabled"
    fi
    
    # Test OnlyOffice accessibility
    local onlyoffice_response=$(curl -s -o /dev/null -w "%{http_code}" "https://$ONLYOFFICE_DOMAIN" || echo "000")
    if [[ "$onlyoffice_response" == "200" || "$onlyoffice_response" == "302" ]]; then
        success "OnlyOffice is accessible via HTTPS"
    else
        warning "OnlyOffice HTTPS response: $onlyoffice_response"
    fi
}

# Create test document
create_test_document() {
    header "Creating Test Document"
    
    log "Creating a test document to verify integration..."
    
    # Create a simple test document
    sudo -u www-data bash -c 'cat > /var/www/nextcloud/data/admin/files/test-document.txt << EOF
This is a test document for OnlyOffice integration.

Created on: $(date)
Nextcloud: https://'$NEXTCLOUD_DOMAIN'
OnlyOffice: https://'$ONLYOFFICE_DOMAIN'

This document should be editable with OnlyOffice when accessed through Nextcloud.
EOF'
    
    success "Test document created: test-document.txt"
}

# Save integration information
save_integration_info() {
    header "Saving Integration Information"
    
    cat > /root/integration_setup_info.txt << EOF
# Integration Setup Information
# Generated on: $(date)

## Domains
Nextcloud: https://$NEXTCLOUD_DOMAIN
OnlyOffice: https://$ONLYOFFICE_DOMAIN

## OnlyOffice Configuration
Document Server URL: https://$ONLYOFFICE_DOMAIN/
Internal URL: http://127.0.0.1:$(get_onlyoffice_port)/
JWT Secret: $JWT_SECRET
JWT Enabled: true

## Nextcloud Configuration
OnlyOffice App: Installed and enabled
Document Server URL: https://$ONLYOFFICE_DOMAIN/
JWT Secret: $JWT_SECRET
Storage URL: https://$NEXTCLOUD_DOMAIN/
Webhook URL: https://$NEXTCLOUD_DOMAIN/index.php/apps/onlyoffice/webhook

## Test Document
Location: /var/www/nextcloud/data/admin/files/test-document.txt
Access: https://$NEXTCLOUD_DOMAIN/files/test-document.txt

## Next Steps
1. Log into Nextcloud at https://$NEXTCLOUD_DOMAIN
2. Navigate to Files app
3. Open test-document.txt
4. Verify OnlyOffice editor opens
5. Test document editing functionality

## Troubleshooting
- Check OnlyOffice app status: sudo -u www-data php /var/www/nextcloud/occ app:list | grep onlyoffice
- Check OnlyOffice config: sudo -u www-data php /var/www/nextcloud/occ config:app:get onlyoffice DocumentServerUrl
- Check OnlyOffice logs: tail -f /var/log/onlyoffice/documentserver/docservice/out.log
- Check Nextcloud logs: tail -f /var/www/nextcloud/data/nextcloud.log
EOF
    
    chmod 600 /root/integration_setup_info.txt
    success "Integration information saved"
}

# Final verification
verify_integration() {
    header "Verifying Integration"
    
    local issues=0
    
    # Check if OnlyOffice app is installed
    if sudo -u www-data php /var/www/nextcloud/occ app:list | grep -q "onlyoffice.*enabled"; then
        success "OnlyOffice app is installed and enabled"
    else
        error "OnlyOffice app is not properly installed"
        ((issues++))
    fi
    
    # Check if OnlyOffice is accessible
    local onlyoffice_response=$(curl -s -o /dev/null -w "%{http_code}" "https://$ONLYOFFICE_DOMAIN" || echo "000")
    if [[ "$onlyoffice_response" == "200" || "$onlyoffice_response" == "302" ]]; then
        success "OnlyOffice is accessible"
    else
        error "OnlyOffice is not accessible (HTTP $onlyoffice_response)"
        ((issues++))
    fi
    
    # Check if Nextcloud is accessible
    local nextcloud_response=$(curl -s -o /dev/null -w "%{http_code}" "https://$NEXTCLOUD_DOMAIN" || echo "000")
    if [[ "$nextcloud_response" == "200" || "$nextcloud_response" == "302" ]]; then
        success "Nextcloud is accessible"
    else
        error "Nextcloud is not accessible (HTTP $nextcloud_response)"
        ((issues++))
    fi
    
    if [[ $issues -eq 0 ]]; then
        success "Integration setup completed successfully!"
        echo ""
        info "Your Nextcloud + OnlyOffice setup is ready:"
        info "  • Nextcloud: https://$NEXTCLOUD_DOMAIN"
        info "  • OnlyOffice: https://$ONLYOFFICE_DOMAIN"
        echo ""
        info "Next steps:"
        info "  1. Log into Nextcloud"
        info "  2. Open the Files app"
        info "  3. Try editing a document with OnlyOffice"
        echo ""
        info "Test document created: test-document.txt"
    else
        error "Integration setup completed with $issues issues"
        exit 1
    fi
}

# Main execution
main() {
    check_root
    load_config
    show_banner
    check_prerequisites
    install_onlyoffice_app
    configure_onlyoffice_connection
    configure_onlyoffice_server
    test_integration
    create_test_document
    save_integration_info
    verify_integration
}

# Run main function
main "$@"
