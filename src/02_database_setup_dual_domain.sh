#!/bin/bash

# Database Setup Script for 2-Domain Nextcloud + OnlyOffice Setup
# This script sets up MariaDB for Nextcloud and PostgreSQL for OnlyOffice

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
    
    NC_DB_NAME=$(grep "db_name:" /etc/nextcloud-onlyoffice/params.yaml | head -1 | cut -d'"' -f2)
    NC_DB_USER=$(grep "db_user:" /etc/nextcloud-onlyoffice/params.yaml | head -1 | cut -d'"' -f2)
    NC_DB_PASSWORD=$(grep "db_password:" /etc/nextcloud-onlyoffice/params.yaml | head -1 | cut -d'"' -f2)
    
    OO_DB_NAME=$(grep "db_name:" /etc/nextcloud-onlyoffice/params.yaml | tail -1 | cut -d'"' -f2)
    OO_DB_USER=$(grep "db_user:" /etc/nextcloud-onlyoffice/params.yaml | tail -1 | cut -d'"' -f2)
    OO_DB_PASSWORD=$(grep "db_password:" /etc/nextcloud-onlyoffice/params.yaml | tail -1 | cut -d'"' -f2)
    
    success "Configuration loaded"
}

# Display banner
show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                   2-DOMAIN DATABASE SETUP                                    ║
║              MariaDB (Nextcloud) + PostgreSQL (OnlyOffice)                  ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo ""
    info "Setting up databases for:"
    info "  • Nextcloud: $NEXTCLOUD_DOMAIN (MariaDB)"
    info "  • OnlyOffice: $ONLYOFFICE_DOMAIN (PostgreSQL)"
    echo ""
}

# Setup MariaDB for Nextcloud
setup_mariadb() {
    header "Setting up MariaDB for Nextcloud"
    
    log "Starting MariaDB service..."
    systemctl start mariadb
    systemctl enable mariadb
    
    # Wait for MariaDB to be ready
    log "Waiting for MariaDB to be ready..."
    local max_attempts=30
    local attempt=0
    
    while ! mysql -e "SELECT 1;" >/dev/null 2>&1; do
        ((attempt++))
        if [[ $attempt -ge $max_attempts ]]; then
            error "MariaDB failed to start after $max_attempts attempts"
            exit 1
        fi
        sleep 2
    done
    
    success "MariaDB is ready"
    
    # Create Nextcloud database and user
    log "Creating Nextcloud database and user..."
    
    mysql -e "CREATE DATABASE IF NOT EXISTS \`$NC_DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
    mysql -e "CREATE USER IF NOT EXISTS '$NC_DB_USER'@'localhost' IDENTIFIED BY '$NC_DB_PASSWORD';"
    mysql -e "GRANT ALL PRIVILEGES ON \`$NC_DB_NAME\`.* TO '$NC_DB_USER'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    
    # Test database connection
    mysql -u "$NC_DB_USER" -p"$NC_DB_PASSWORD" -e "USE \`$NC_DB_NAME\`; SELECT 1;" >/dev/null 2>&1
    
    success "MariaDB setup completed"
}

# Setup PostgreSQL for OnlyOffice
setup_postgresql() {
    header "Setting up PostgreSQL for OnlyOffice"
    
    log "Starting PostgreSQL service..."
    systemctl start postgresql
    systemctl enable postgresql
    
    # Wait for PostgreSQL to be ready
    log "Waiting for PostgreSQL to be ready..."
    local max_attempts=30
    local attempt=0
    
    while ! sudo -u postgres psql -c "SELECT 1;" >/dev/null 2>&1; do
        ((attempt++))
        if [[ $attempt -ge $max_attempts ]]; then
            error "PostgreSQL failed to start after $max_attempts attempts"
            exit 1
        fi
        sleep 2
    done
    
    success "PostgreSQL is ready"
    
    # Create OnlyOffice database and user (using OnlyOffice defaults)
    log "Creating OnlyOffice database and user..."
    
    sudo -u postgres psql -c "CREATE DATABASE onlyoffice;"
    sudo -u postgres psql -c "CREATE USER onlyoffice WITH PASSWORD 'onlyoffice';"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE onlyoffice TO onlyoffice;"
    sudo -u postgres psql -c "ALTER USER onlyoffice CREATEDB;"
    
    # Test database connection
    PGPASSWORD="onlyoffice" psql -h localhost -U "onlyoffice" -d "onlyoffice" -c "SELECT 1;" >/dev/null 2>&1
    
    success "PostgreSQL setup completed"
}

# Configure database security
configure_database_security() {
    header "Configuring Database Security"
    
    # MariaDB security
    log "Configuring MariaDB security..."
    
    # Create MariaDB configuration for better security
    cat > /etc/mysql/mariadb.conf.d/50-nextcloud.cnf << 'EOF'
[mysqld]
# Security settings
bind-address = 127.0.0.1
skip-networking = false
local-infile = 0

# Performance settings
innodb_buffer_pool_size = 256M
innodb_log_file_size = 64M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT

# Character set
character-set-server = utf8mb4
collation-server = utf8mb4_general_ci

# Query cache
query_cache_type = 1
query_cache_size = 32M
query_cache_limit = 2M

# Logging
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 2
EOF
    
    # PostgreSQL security
    log "Configuring PostgreSQL security..."
    
    # Configure PostgreSQL for local connections only
    local pg_hba="/etc/postgresql/16/main/pg_hba.conf"
    if [[ -f "$pg_hba" ]]; then
        # Backup original
        cp "$pg_hba" "$pg_hba.backup"
        
        # Configure for local connections only
        cat > "$pg_hba" << 'EOF'
# PostgreSQL Client Authentication Configuration File
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# "local" is for Unix domain socket connections only
local   all             postgres                                peer
local   all             all                                     peer

# IPv4 local connections:
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5

# IPv6 local connections:
host    all             all             ::1/128                 md5
EOF
    fi
    
    # Restart services to apply configuration
    systemctl restart mariadb
    systemctl restart postgresql
    
    success "Database security configured"
}

# Create database backup scripts
create_backup_scripts() {
    header "Creating Database Backup Scripts"
    
    # MariaDB backup script
    cat > /usr/local/bin/backup-mariadb.sh << 'EOF'
#!/bin/bash
# MariaDB backup script

BACKUP_DIR="/var/backups/mariadb"
DATE=$(date +%Y%m%d_%H%M%S)
DB_NAME="nextcloud"

mkdir -p "$BACKUP_DIR"

# Create backup
mysqldump --single-transaction --routines --triggers "$DB_NAME" > "$BACKUP_DIR/${DB_NAME}_$DATE.sql"

# Compress backup
gzip "$BACKUP_DIR/${DB_NAME}_$DATE.sql"

# Keep only last 7 days of backups
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +7 -delete

echo "MariaDB backup completed: ${DB_NAME}_$DATE.sql.gz"
EOF
    
    # PostgreSQL backup script
    cat > /usr/local/bin/backup-postgresql.sh << 'EOF'
#!/bin/bash
# PostgreSQL backup script

BACKUP_DIR="/var/backups/postgresql"
DATE=$(date +%Y%m%d_%H%M%S)
DB_NAME="onlyoffice"

mkdir -p "$BACKUP_DIR"

# Create backup
sudo -u postgres pg_dump "$DB_NAME" > "$BACKUP_DIR/${DB_NAME}_$DATE.sql"

# Compress backup
gzip "$BACKUP_DIR/${DB_NAME}_$DATE.sql"

# Keep only last 7 days of backups
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +7 -delete

echo "PostgreSQL backup completed: ${DB_NAME}_$DATE.sql.gz"
EOF
    
    # Make scripts executable
    chmod +x /usr/local/bin/backup-mariadb.sh
    chmod +x /usr/local/bin/backup-postgresql.sh
    
    # Create daily backup cron job
    cat > /etc/cron.daily/backup-databases << 'EOF'
#!/bin/bash
/usr/local/bin/backup-mariadb.sh
/usr/local/bin/backup-postgresql.sh
EOF
    
    chmod +x /etc/cron.daily/backup-databases
    
    success "Backup scripts created"
}

# Test database connections
test_connections() {
    header "Testing Database Connections"
    
    # Test MariaDB connection
    log "Testing MariaDB connection..."
    if mysql -u "$NC_DB_USER" -p"$NC_DB_PASSWORD" -e "USE \`$NC_DB_NAME\`; SELECT 'MariaDB connection successful' as status;" 2>/dev/null; then
        success "MariaDB connection test passed"
    else
        error "MariaDB connection test failed"
        return 1
    fi
    
    # Test PostgreSQL connection
    log "Testing PostgreSQL connection..."
    if PGPASSWORD="$OO_DB_PASSWORD" psql -h localhost -U "$OO_DB_USER" -d "$OO_DB_NAME" -c "SELECT 'PostgreSQL connection successful' as status;" >/dev/null 2>&1; then
        success "PostgreSQL connection test passed"
    else
        error "PostgreSQL connection test failed"
        return 1
    fi
}

# Save database credentials
save_credentials() {
    header "Saving Database Credentials"
    
    # Create credentials file
    cat > /root/database_credentials.txt << EOF
# Database Credentials for 2-Domain Setup
# Generated on: $(date)

## Nextcloud (MariaDB)
Database: $NC_DB_NAME
Username: $NC_DB_USER
Password: $NC_DB_PASSWORD
Host: localhost
Port: 3306

## OnlyOffice (PostgreSQL)
Database: $OO_DB_NAME
Username: $OO_DB_USER
Password: $OO_DB_PASSWORD
Host: localhost
Port: 5432

## Domains
Nextcloud: https://$NEXTCLOUD_DOMAIN
OnlyOffice: https://$ONLYOFFICE_DOMAIN

## Backup Scripts
MariaDB: /usr/local/bin/backup-mariadb.sh
PostgreSQL: /usr/local/bin/backup-postgresql.sh
Daily backups: /etc/cron.daily/backup-databases
EOF
    
    chmod 600 /root/database_credentials.txt
    success "Database credentials saved to /root/database_credentials.txt"
}

# Final verification
verify_setup() {
    header "Verifying Database Setup"
    
    local issues=0
    
    # Check MariaDB service
    if systemctl is-active --quiet mariadb; then
        success "MariaDB service is running"
    else
        error "MariaDB service is not running"
        ((issues++))
    fi
    
    # Check PostgreSQL service
    if systemctl is-active --quiet postgresql; then
        success "PostgreSQL service is running"
    else
        error "PostgreSQL service is not running"
        ((issues++))
    fi
    
    # Test database connections
    if test_connections; then
        success "Database connections verified"
    else
        error "Database connection tests failed"
        ((issues++))
    fi
    
    if [[ $issues -eq 0 ]]; then
        success "Database setup completed successfully!"
        echo ""
        info "Next steps:"
        info "  1. Run: ./03_nextcloud_install_dual_domain.sh"
        info "  2. Run: ./04_onlyoffice_install_dual_domain.sh"
        info "  3. Run: ./05_nginx_config_dual_domain.sh"
        info "  4. Run: ./06_ssl_setup_dual_domain.sh"
        info "  5. Run: ./07_integration_config_dual_domain.sh"
    else
        error "Database setup completed with $issues issues"
        exit 1
    fi
}

# Main execution
main() {
    check_root
    load_config
    show_banner
    setup_mariadb
    setup_postgresql
    configure_database_security
    create_backup_scripts
    test_connections
    save_credentials
    verify_setup
}

# Run main function
main "$@"
