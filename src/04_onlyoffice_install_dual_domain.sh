#!/bin/bash

# OnlyOffice Installation Script for 2-Domain Setup
# This script installs OnlyOffice for onlyoffice.DOMAIN.com with its own internal nginx

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
    
    OO_DB_NAME=$(grep "db_name:" /etc/nextcloud-onlyoffice/params.yaml | tail -1 | cut -d'"' -f2)
    OO_DB_USER=$(grep "db_user:" /etc/nextcloud-onlyoffice/params.yaml | tail -1 | cut -d'"' -f2)
    OO_DB_PASSWORD=$(grep "db_password:" /etc/nextcloud-onlyoffice/params.yaml | tail -1 | cut -d'"' -f2)
    
    JWT_SECRET=$(grep "secret:" /etc/nextcloud-onlyoffice/params.yaml | cut -d'"' -f2)
    
    success "Configuration loaded"
}

# Display banner
show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                   2-DOMAIN ONLYOFFICE INSTALLATION                          ║
║              Installing OnlyOffice for onlyoffice.DOMAIN.com                ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo ""
    info "Installing OnlyOffice for:"
    info "  • Domain: $ONLYOFFICE_DOMAIN"
    info "  • Database: $OO_DB_NAME (PostgreSQL)"
    info "  • Architecture: Internal nginx + main nginx front-end"
    echo ""
}

# Add OnlyOffice repository
add_onlyoffice_repo() {
    header "Adding OnlyOffice Repository"
    
    log "Adding OnlyOffice repository..."
    
    # Add GPG key
    wget -O - https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE | apt-key add -
    
    # Add repository
    echo "deb https://download.onlyoffice.com/repo/debian squeeze main" | tee /etc/apt/sources.list.d/onlyoffice.list
    
    # Update package lists
    apt update
    
    success "OnlyOffice repository added"
}

# Install OnlyOffice Document Server
install_onlyoffice() {
    header "Installing OnlyOffice Document Server"
    
    log "Installing OnlyOffice Document Server..."
    
    # Install OnlyOffice Document Server
    apt install -y onlyoffice-documentserver
    
    success "OnlyOffice Document Server installed"
}

# Configure OnlyOffice
configure_onlyoffice() {
    header "Configuring OnlyOffice"
    
    log "Configuring OnlyOffice Document Server..."
    
    # Create OnlyOffice configuration directory
    mkdir -p /etc/onlyoffice/documentserver
    
    # Configure local.json
    cat > /etc/onlyoffice/documentserver/local.json << EOF
{
  "services": {
    "CoAuthoring": {
      "sql": {
        "type": "postgres",
        "dbHost": "localhost",
        "dbPort": "5432",
        "dbName": "$OO_DB_NAME",
        "dbUser": "$OO_DB_USER",
        "dbPass": "$OO_DB_PASSWORD"
      },
      "redis": {
        "host": "localhost",
        "port": "6379"
      },
      "secret": {
        "inbox": {
          "string": "$JWT_SECRET"
        },
        "outbox": {
          "string": "$JWT_SECRET"
        }
      }
    }
  },
  "rabbitmq": {
    "url": "amqp://guest:guest@localhost"
  }
}
EOF
    
    # Set permissions
    chown -R ds:ds /etc/onlyoffice/documentserver
    chmod 600 /etc/onlyoffice/documentserver/local.json
    
    success "OnlyOffice configured"
}

# Configure OnlyOffice internal nginx
configure_onlyoffice_nginx() {
    header "Configuring OnlyOffice Internal Nginx"
    
    log "Configuring OnlyOffice internal nginx..."
    
    # OnlyOffice comes with its own nginx configuration
    # We need to modify it to work with our dual-domain setup
    
    local nginx_conf="/etc/onlyoffice/documentserver/nginx/ds.conf"
    
    if [[ -f "$nginx_conf" ]]; then
        # Backup original configuration
        cp "$nginx_conf" "$nginx_conf.backup"
        
        # Modify nginx configuration for internal use
        cat > "$nginx_conf" << 'EOF'
upstream backend {
    server 127.0.0.1:8080;
}

upstream converter {
    server 127.0.0.1:8080;
}

upstream docservice {
    server 127.0.0.1:8080;
}

upstream example {
    server 127.0.0.1:8080;
}

map $http_host $this_host {
    "" $host;
    default $http_host;
}

map $http_x_forwarded_proto $the_scheme {
    default $http_x_forwarded_proto;
    "" $scheme;
}

map $http_x_forwarded_host $the_host {
    default $http_x_forwarded_host;
    "" $this_host;
}

map $http_upgrade $proxy_connection {
    default upgrade;
    "" close;
}

proxy_cache_path /var/cache/nginx/onlyoffice-documentserver levels=1:2 keys_zone=onlyoffice_cache:10m max_size=3g inactive=120m use_temp_path=off;

server {
    listen 127.0.0.1:8080;
    server_name _;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    
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
    
    # OnlyOffice Document Server
    location / {
        proxy_pass http://docservice;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $proxy_connection;
        proxy_set_header X-Forwarded-Host $the_host;
        proxy_set_header X-Forwarded-Proto $the_scheme;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $http_host;
        proxy_cache onlyoffice_cache;
        proxy_cache_valid 200 302 10m;
        proxy_cache_valid 404 1m;
        proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
        proxy_cache_lock on;
        proxy_cache_lock_timeout 5s;
    }
    
    # Health check
    location /healthcheck {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
    
    # Static files
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg)$ {
        proxy_pass http://docservice;
        proxy_set_header Host $http_host;
        proxy_cache onlyoffice_cache;
        proxy_cache_valid 200 1d;
        expires 1d;
        add_header Cache-Control "public, immutable";
    }
}
EOF
    fi
    
    success "OnlyOffice internal nginx configured"
}

# Configure main nginx for OnlyOffice
configure_main_nginx() {
    header "Configuring Main Nginx for OnlyOffice"
    
    log "Creating main nginx configuration for $ONLYOFFICE_DOMAIN..."
    
    # Create nginx configuration for OnlyOffice
    cat > "/etc/nginx/sites-available/$ONLYOFFICE_DOMAIN" << EOF
# OnlyOffice configuration for $ONLYOFFICE_DOMAIN
server {
    listen 80;
    listen [::]:80;
    server_name $ONLYOFFICE_DOMAIN;
    
    # Redirect HTTP to HTTPS (will be enabled after SSL setup)
    # return 301 https://\$server_name\$request_uri;
    
    # Temporary HTTP configuration for initial setup
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
    
    # Enable the site
    ln -sf "/etc/nginx/sites-available/$ONLYOFFICE_DOMAIN" "/etc/nginx/sites-enabled/"
    
    # Test nginx configuration
    nginx -t
    
    # Reload nginx
    systemctl reload nginx
    
    success "Main nginx configured for OnlyOffice"
}

# Start OnlyOffice services
start_onlyoffice_services() {
    header "Starting OnlyOffice Services"
    
    log "Starting OnlyOffice Document Server services..."
    
    # Start OnlyOffice services
    systemctl start ds-docservice
    systemctl start ds-converter
    systemctl start ds-metrics
    
    # Enable services
    systemctl enable ds-docservice
    systemctl enable ds-converter
    systemctl enable ds-metrics
    
    # Wait for services to start
    sleep 10
    
    # Check if services are running
    local services=("ds-docservice" "ds-converter" "ds-metrics")
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            success "$service is running"
        else
            warning "$service is not running, attempting to start..."
            systemctl start "$service"
            sleep 5
            if systemctl is-active --quiet "$service"; then
                success "$service started successfully"
            else
                error "$service failed to start"
            fi
        fi
    done
}

# Configure JWT secret
configure_jwt() {
    header "Configuring JWT Secret"
    
    log "Configuring JWT secret for OnlyOffice..."
    
    # Update OnlyOffice configuration with JWT secret
    local local_json="/etc/onlyoffice/documentserver/local.json"
    
    if [[ -f "$local_json" ]]; then
        # Update JWT secret in configuration
        sed -i "s/\"string\": \"[^\"]*\"/\"string\": \"$JWT_SECRET\"/g" "$local_json"
        
        # Restart OnlyOffice services
        systemctl restart ds-docservice
        systemctl restart ds-converter
        systemctl restart ds-metrics
        
        success "JWT secret configured"
    else
        error "OnlyOffice configuration file not found"
        return 1
    fi
}

# Test OnlyOffice installation
test_installation() {
    header "Testing OnlyOffice Installation"
    
    log "Testing OnlyOffice installation..."
    
    # Test internal nginx
    local internal_response=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:8080/healthcheck" || echo "000")
    
    if [[ "$internal_response" == "200" ]]; then
        success "OnlyOffice internal nginx is working"
    else
        warning "OnlyOffice internal nginx may not be ready yet (HTTP $internal_response)"
    fi
    
    # Test main nginx proxy
    local main_response=$(curl -s -o /dev/null -w "%{http_code}" "http://$ONLYOFFICE_DOMAIN/healthcheck" || echo "000")
    
    if [[ "$main_response" == "200" ]]; then
        success "OnlyOffice main nginx proxy is working"
    else
        warning "OnlyOffice main nginx proxy may not be ready yet (HTTP $main_response)"
        info "This is normal if SSL certificates haven't been set up yet"
    fi
    
    # Test OnlyOffice API
    local api_response=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:8080/healthcheck" || echo "000")
    
    if [[ "$api_response" == "200" ]]; then
        success "OnlyOffice API is responding"
    else
        warning "OnlyOffice API may not be ready yet (HTTP $api_response)"
    fi
}

# Create backup script
create_backup_script() {
    header "Creating Backup Script"
    
    cat > /usr/local/bin/backup-onlyoffice.sh << 'EOF'
#!/bin/bash
# OnlyOffice backup script

BACKUP_DIR="/var/backups/onlyoffice"
DATE=$(date +%Y%m%d_%H%M%S)
CONFIG_DIR="/etc/onlyoffice"

mkdir -p "$BACKUP_DIR"

# Backup OnlyOffice configuration
tar -czf "$BACKUP_DIR/onlyoffice-config-$DATE.tar.gz" -C /etc onlyoffice

# Keep only last 7 days of backups
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +7 -delete

echo "OnlyOffice backup completed: $DATE"
EOF
    
    chmod +x /usr/local/bin/backup-onlyoffice.sh
    
    # Add to daily backup
    echo "/usr/local/bin/backup-onlyoffice.sh" >> /etc/cron.daily/backup-databases
    
    success "Backup script created"
}

# Save installation info
save_installation_info() {
    header "Saving Installation Information"
    
    cat > /root/onlyoffice_installation_info.txt << EOF
# OnlyOffice Installation Information
# Generated on: $(date)

## Access Information
URL: http://$ONLYOFFICE_DOMAIN (will be https:// after SSL setup)
Internal URL: http://127.0.0.1:8080
Health Check: http://$ONLYOFFICE_DOMAIN/healthcheck

## Configuration
Config Directory: /etc/onlyoffice/documentserver
Config File: /etc/onlyoffice/documentserver/local.json
Internal Nginx: /etc/onlyoffice/documentserver/nginx/ds.conf
Main Nginx: /etc/nginx/sites-available/$ONLYOFFICE_DOMAIN

## Database Information
Database: $OO_DB_NAME
Username: $OO_DB_USER
Password: $OO_DB_PASSWORD
Host: localhost
Port: 5432

## JWT Configuration
Secret: $JWT_SECRET

## Services
- ds-docservice: Document service
- ds-converter: Document converter
- ds-metrics: Metrics service

## Backup Scripts
OnlyOffice: /usr/local/bin/backup-onlyoffice.sh
Database: /usr/local/bin/backup-postgresql.sh

## Next Steps
1. Run: ./05_nginx_config_dual_domain.sh
2. Run: ./06_ssl_setup_dual_domain.sh
3. Run: ./07_integration_config_dual_domain.sh
EOF
    
    chmod 600 /root/onlyoffice_installation_info.txt
    success "Installation information saved"
}

# Final verification
verify_installation() {
    header "Verifying OnlyOffice Installation"
    
    local issues=0
    
    # Check if OnlyOffice is installed
    if command -v ds-docservice >/dev/null 2>&1; then
        success "OnlyOffice Document Server installed"
    else
        error "OnlyOffice Document Server not found"
        ((issues++))
    fi
    
    # Check configuration file
    if [[ -f "/etc/onlyoffice/documentserver/local.json" ]]; then
        success "OnlyOffice configuration created"
    else
        error "OnlyOffice configuration missing"
        ((issues++))
    fi
    
    # Check nginx configuration
    if [[ -f "/etc/nginx/sites-available/$ONLYOFFICE_DOMAIN" ]]; then
        success "Main nginx configuration created"
    else
        error "Main nginx configuration missing"
        ((issues++))
    fi
    
    # Check if site is enabled
    if [[ -L "/etc/nginx/sites-enabled/$ONLYOFFICE_DOMAIN" ]]; then
        success "Main nginx site enabled"
    else
        error "Main nginx site not enabled"
        ((issues++))
    fi
    
    # Check services
    local services=("ds-docservice" "ds-converter" "ds-metrics")
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            success "$service is running"
        else
            warning "$service is not running"
            ((issues++))
        fi
    done
    
    if [[ $issues -eq 0 ]]; then
        success "OnlyOffice installation completed successfully!"
        echo ""
        info "OnlyOffice is available at: http://$ONLYOFFICE_DOMAIN"
        info "Internal OnlyOffice is available at: http://127.0.0.1:8080"
        info "Installation info saved to: /root/onlyoffice_installation_info.txt"
        echo ""
        info "Next steps:"
        info "  1. Run: ./05_nginx_config_dual_domain.sh"
        info "  2. Run: ./06_ssl_setup_dual_domain.sh"
        info "  3. Run: ./07_integration_config_dual_domain.sh"
    else
        error "OnlyOffice installation completed with $issues issues"
        exit 1
    fi
}

# Main execution
main() {
    check_root
    load_config
    show_banner
    add_onlyoffice_repo
    install_onlyoffice
    configure_onlyoffice
    configure_onlyoffice_nginx
    configure_main_nginx
    start_onlyoffice_services
    configure_jwt
    test_installation
    create_backup_script
    save_installation_info
    verify_installation
}

# Run main function
main "$@"
