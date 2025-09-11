#!/bin/bash

# Nextcloud + OnlyOffice Bare Metal Installation
# Step 2: Database Setup
# 
# This script configures databases for Nextcloud and OnlyOffice:
# - MariaDB for Nextcloud (recommended)
# - PostgreSQL for OnlyOffice Document Server (required)
# - Secure database configurations
# - Create users and databases with proper permissions

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/nextcloud-install.log"

# Database configuration
NEXTCLOUD_DB_NAME="nextcloud"
NEXTCLOUD_DB_USER="nextcloud"
ONLYOFFICE_DB_NAME="onlyoffice"
ONLYOFFICE_DB_USER="onlyoffice"

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

# Generate secure random password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
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
    
    # Check if MariaDB is installed and running
    if ! systemctl is-active --quiet mariadb; then
        error "MariaDB is not running. Please run 01_system_prep.sh first."
    fi
    
    # Check if PostgreSQL is installed
    if ! command -v psql &> /dev/null; then
        error "PostgreSQL is not installed. Please run 01_system_prep.sh first."
    fi
    
    log "Prerequisites check passed"
}

# Secure MariaDB installation
secure_mariadb() {
    log "Securing MariaDB installation..."
    
    # Generate root password
    local mysql_root_password=$(generate_password)
    
    # Set root password and secure installation
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$mysql_root_password';"
    mysql -u root -p"$mysql_root_password" -e "DELETE FROM mysql.user WHERE User='';"
    mysql -u root -p"$mysql_root_password" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    mysql -u root -p"$mysql_root_password" -e "DROP DATABASE IF EXISTS test;"
    mysql -u root -p"$mysql_root_password" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
    mysql -u root -p"$mysql_root_password" -e "FLUSH PRIVILEGES;"
    
    # Save root credentials
    cat > /root/.my.cnf << EOF
[client]
user=root
password=$mysql_root_password
EOF
    chmod 600 /root/.my.cnf
    
    log "MariaDB secured with root password"
}

# Setup Nextcloud database
setup_nextcloud_database() {
    log "Setting up Nextcloud database..."
    
    # Generate password for Nextcloud user
    local nextcloud_password=$(generate_password)
    
    # Create database and user
    mysql -e "CREATE DATABASE IF NOT EXISTS \`$NEXTCLOUD_DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
    mysql -e "CREATE USER IF NOT EXISTS '$NEXTCLOUD_DB_USER'@'localhost' IDENTIFIED BY '$nextcloud_password';"
    mysql -e "ALTER USER '$NEXTCLOUD_DB_USER'@'localhost' IDENTIFIED BY '$nextcloud_password';"
    mysql -e "GRANT ALL PRIVILEGES ON \`$NEXTCLOUD_DB_NAME\`.* TO '$NEXTCLOUD_DB_USER'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    
    # Save credentials
    cat > /root/nextcloud-db-credentials.txt << EOF
Nextcloud Database Credentials
=============================
Database Type: MariaDB/MySQL
Host: localhost
Database: $NEXTCLOUD_DB_NAME
Username: $NEXTCLOUD_DB_USER
Password: $nextcloud_password

Connection String for Nextcloud:
Database host: localhost
Database name: $NEXTCLOUD_DB_NAME
Database user: $NEXTCLOUD_DB_USER
Database password: $nextcloud_password
EOF
    chmod 600 /root/nextcloud-db-credentials.txt
    
    log "Nextcloud database created successfully"
}

# Setup PostgreSQL for OnlyOffice
setup_postgresql() {
    log "Setting up PostgreSQL for OnlyOffice..."
    
    # Start PostgreSQL if not running
    systemctl start postgresql
    systemctl enable postgresql
    
    # Generate password for OnlyOffice user
    local onlyoffice_password=$(generate_password)
    
    # Create user and database
    sudo -u postgres psql -c "CREATE USER $ONLYOFFICE_DB_USER WITH PASSWORD '$onlyoffice_password';" || true
    sudo -u postgres psql -c "CREATE DATABASE $ONLYOFFICE_DB_NAME OWNER $ONLYOFFICE_DB_USER;" || true
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $ONLYOFFICE_DB_NAME TO $ONLYOFFICE_DB_USER;" || true
    
    # Configure PostgreSQL for local connections
    local pg_version=$(sudo -u postgres psql -t -c "SELECT version();" | grep -oP '\d+\.\d+' | head -1)
    local pg_config_dir="/etc/postgresql/$pg_version/main"
    
    if [[ -d "$pg_config_dir" ]]; then
        # Backup original configurations
        cp "$pg_config_dir/postgresql.conf" "$pg_config_dir/postgresql.conf.backup.$(date +%s)"
        cp "$pg_config_dir/pg_hba.conf" "$pg_config_dir/pg_hba.conf.backup.$(date +%s)"
        
        # Configure PostgreSQL
        sed -i "s/#listen_addresses = 'localhost'/listen_addresses = 'localhost'/" "$pg_config_dir/postgresql.conf"
        sed -i "s/#port = 5432/port = 5432/" "$pg_config_dir/postgresql.conf"
        
        # Add authentication rule for OnlyOffice user
        if ! grep -q "$ONLYOFFICE_DB_USER" "$pg_config_dir/pg_hba.conf"; then
            echo "local   $ONLYOFFICE_DB_NAME   $ONLYOFFICE_DB_USER   md5" >> "$pg_config_dir/pg_hba.conf"
        fi
        
        # Restart PostgreSQL
        systemctl restart postgresql
    fi
    
    # Save credentials
    cat > /root/onlyoffice-db-credentials.txt << EOF
OnlyOffice Database Credentials
==============================
Database Type: PostgreSQL
Host: localhost
Port: 5432
Database: $ONLYOFFICE_DB_NAME
Username: $ONLYOFFICE_DB_USER
Password: $onlyoffice_password

Connection String for OnlyOffice:
postgresql://$ONLYOFFICE_DB_USER:$onlyoffice_password@localhost:5432/$ONLYOFFICE_DB_NAME
EOF
    chmod 600 /root/onlyoffice-db-credentials.txt
    
    log "PostgreSQL configured for OnlyOffice"
}

# Configure Redis
configure_redis() {
    log "Configuring Redis..."
    
    # Backup original configuration
    cp /etc/redis/redis.conf /etc/redis/redis.conf.backup.$(date +%s)
    
    # Configure Redis for Nextcloud
    sed -i 's/# maxmemory <bytes>/maxmemory 256mb/' /etc/redis/redis.conf
    sed -i 's/# maxmemory-policy noeviction/maxmemory-policy allkeys-lru/' /etc/redis/redis.conf
    
    # Enable Unix socket for better performance
    sed -i 's/# unixsocket \/var\/run\/redis\/redis-server.sock/unixsocket \/var\/run\/redis\/redis-server.sock/' /etc/redis/redis.conf
    sed -i 's/# unixsocketperm 700/unixsocketperm 770/' /etc/redis/redis.conf
    
    # Add www-data to redis group for socket access
    usermod -a -G redis www-data
    
    # Restart Redis
    systemctl restart redis-server
    systemctl enable redis-server
    
    log "Redis configured successfully"
}

# Test database connections
test_connections() {
    log "Testing database connections..."
    
    # Test MariaDB connection
    if mysql -e "SELECT 1;" &> /dev/null; then
        log "✓ MariaDB connection successful"
    else
        error "✗ MariaDB connection failed"
    fi
    
    # Test Nextcloud database
    local nc_password=$(grep "Password:" /root/nextcloud-db-credentials.txt | cut -d' ' -f2)
    if mysql -u "$NEXTCLOUD_DB_USER" -p"$nc_password" -e "SELECT 1;" &> /dev/null; then
        log "✓ Nextcloud database connection successful"
    else
        error "✗ Nextcloud database connection failed"
    fi
    
    # Test PostgreSQL connection
    if sudo -u postgres psql -c "SELECT 1;" &> /dev/null; then
        log "✓ PostgreSQL connection successful"
    else
        error "✗ PostgreSQL connection failed"
    fi
    
    # Test Redis connection
    if redis-cli ping | grep -q PONG; then
        log "✓ Redis connection successful"
    else
        error "✗ Redis connection failed"
    fi
}

# Save installation summary
save_install_info() {
    local info_file="/root/database-setup-summary.txt"
    
    cat > "$info_file" << EOF
Database Setup Summary
=====================
Date: $(date)

Databases Configured:
1. MariaDB (for Nextcloud)
   - Database: $NEXTCLOUD_DB_NAME
   - User: $NEXTCLOUD_DB_USER
   - Credentials: /root/nextcloud-db-credentials.txt

2. PostgreSQL (for OnlyOffice)
   - Database: $ONLYOFFICE_DB_NAME
   - User: $ONLYOFFICE_DB_USER
   - Credentials: /root/onlyoffice-db-credentials.txt

3. Redis (for caching)
   - Socket: /var/run/redis/redis-server.sock
   - Memory limit: 256MB

Security:
- MariaDB root password set and saved to /root/.my.cnf
- Anonymous users removed
- Test database removed
- Remote root access disabled
- PostgreSQL configured for local connections only

Next Steps:
1. Run 03_nextcloud_install.sh to install Nextcloud
2. Use credentials from /root/nextcloud-db-credentials.txt during setup

Log File: $LOG_FILE
EOF

    log "Database setup summary saved to: $info_file"
}

# Main execution
main() {
    log "Starting database setup for Nextcloud + OnlyOffice..."
    
    check_root
    check_prerequisites
    secure_mariadb
    setup_nextcloud_database
    setup_postgresql
    configure_redis
    test_connections
    save_install_info
    
    log "✓ Database setup completed successfully!"
    echo ""
    info "Credentials saved to:"
    info "  - Nextcloud: /root/nextcloud-db-credentials.txt"
    info "  - OnlyOffice: /root/onlyoffice-db-credentials.txt"
    info "  - MariaDB root: /root/.my.cnf"
    echo ""
    info "Next step: Run 03_nextcloud_install.sh"
    echo ""
    info "Log file: $LOG_FILE"
}

# Run main function
main "$@"
