#!/bin/bash

# Step 2: Database Setup - FIXED VERSION
# Creates Nextcloud database and user with proper error handling

set -e

echo "=== Step 2: Database Setup (FIXED) ==="
echo "This creates the Nextcloud database and user"
echo ""

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

# Check if mariadb is installed
if ! command -v mysql &> /dev/null; then
    echo "Error: MariaDB not installed. Run step1_system_prep.sh first."
    exit 1
fi

echo "Starting MariaDB..."
systemctl start mariadb

# Check if MariaDB is actually running
if ! systemctl is-active --quiet mariadb; then
    echo "Error: MariaDB failed to start. Checking status..."
    systemctl status mariadb
    exit 1
fi

# Secure MariaDB installation first if this is a fresh install
echo "Checking MariaDB security status..."
if mysql -u root -e "SELECT 1;" 2>/dev/null; then
    echo "MariaDB root access working without password - this is expected on fresh install"
    
    # Set up basic security
    echo "Setting up MariaDB security..."
    mysql -u root << 'MYSQL_SECURE'
-- Remove anonymous users
DELETE FROM mysql.user WHERE User='';
-- Remove remote root access (keep only localhost)
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
-- Remove test database
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
-- Reload privilege tables
FLUSH PRIVILEGES;
MYSQL_SECURE
    
    echo "MariaDB basic security applied"
else
    echo "MariaDB root requires password or has authentication issues"
    echo "This is normal if MariaDB was previously configured"
fi

# Generate random passwords
DB_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-20)
echo "Generated Nextcloud database password: $DB_PASSWORD"

echo "Creating Nextcloud database and user..."

# Create database and user with proper error handling
mysql -u root << MYSQL_COMMANDS || {
    echo "Database setup failed. Trying to diagnose..."
    echo "MariaDB status:"
    systemctl status mariadb --no-pager
    echo ""
    echo "MariaDB logs:"
    journalctl -u mariadb -n 20 --no-pager
    exit 1
}

-- Create database with proper charset
CREATE DATABASE IF NOT EXISTS nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

-- Create user with modern authentication
CREATE USER IF NOT EXISTS 'nextcloud'@'localhost' IDENTIFIED BY '$DB_PASSWORD';

-- Grant all privileges on nextcloud database
GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'localhost';

-- Apply changes
FLUSH PRIVILEGES;

-- Test the new user can connect
SELECT 'Database setup completed successfully' as Status;

MYSQL_COMMANDS

# Test the new credentials
echo "Testing database connection..."
if mysql -u nextcloud -p"$DB_PASSWORD" -e "SELECT 'Connection test successful' AS result;" nextcloud; then
    echo "✓ Database connection test passed"
else
    echo "✗ Database connection test failed"
    echo "This might indicate a problem with the user creation"
    exit 1
fi

# Save credentials with more detail
cat > /root/nextcloud-db-credentials.txt << EOL
Nextcloud Database Credentials
==============================
Created: $(date)
Host: localhost
Database: nextcloud
Username: nextcloud
Password: $DB_PASSWORD

Connection Test Command:
mysql -u nextcloud -p'$DB_PASSWORD' nextcloud

MariaDB Service Status: $(systemctl is-active mariadb)
MariaDB Version: $(mysql --version)

Notes:
- Database uses utf8mb4 charset for full Unicode support
- User 'nextcloud'@'localhost' has ALL privileges on 'nextcloud' database
- Connection tested and verified working
EOL

chmod 600 /root/nextcloud-db-credentials.txt

echo ""
echo "✓ Step 2 Complete!"
echo "Database 'nextcloud' created with user 'nextcloud'"
echo "Credentials saved to: /root/nextcloud-db-credentials.txt (secure permissions)"
echo ""
echo "Verification commands:"
echo "- Test connection: mysql -u nextcloud -p'$DB_PASSWORD' nextcloud"
echo "- Check database: mysql -u nextcloud -p'$DB_PASSWORD' -e 'SHOW DATABASES;'"
echo "- View tables: mysql -u nextcloud -p'$DB_PASSWORD' -e 'USE nextcloud; SHOW TABLES;'"
echo ""
echo "Next: Run step3_nextcloud.sh"