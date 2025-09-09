#!/bin/bash

# Step 2: Dual Database Setup 
# MariaDB for Nextcloud, PostgreSQL for OnlyOffice

set -e

echo "=== Step 2: Dual Database Setup ==="
echo "Setting up MariaDB for Nextcloud AND PostgreSQL for OnlyOffice"
echo ""

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

# Check if MariaDB is installed and running (from step 1)
if ! command -v mysql &> /dev/null; then
    echo "Error: MariaDB not installed. Run step1_system_prep.sh first."
    exit 1
fi

if ! systemctl is-active --quiet mariadb; then
    echo "Starting MariaDB..."
    systemctl start mariadb
fi

# Install PostgreSQL alongside MariaDB
echo "Installing PostgreSQL for OnlyOffice..."
apt update
apt install -y postgresql postgresql-contrib php8.3-pgsql

echo "Starting PostgreSQL..."
systemctl start postgresql
systemctl enable postgresql

# Generate passwords for both databases
NEXTCLOUD_DB_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-20)
ONLYOFFICE_DB_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-20)

echo "Generated passwords for both databases"

echo ""
echo "=== Setting up MariaDB for Nextcloud ==="
mysql -u root << MYSQL_SETUP
CREATE DATABASE IF NOT EXISTS nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS 'nextcloud'@'localhost' IDENTIFIED BY '$NEXTCLOUD_DB_PASSWORD';
GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SETUP

# Test MariaDB connection
echo "Testing Nextcloud MariaDB connection..."
if mysql -u nextcloud -p"$NEXTCLOUD_DB_PASSWORD" -e "SELECT 'Nextcloud DB OK' AS status;" nextcloud; then
    echo "✓ Nextcloud MariaDB connection working"
else
    echo "✗ Nextcloud MariaDB connection failed"
    exit 1
fi

echo ""
echo "=== Setting up PostgreSQL for OnlyOffice ==="
sudo -u postgres psql << POSTGRES_SETUP
CREATE USER onlyoffice WITH PASSWORD '$ONLYOFFICE_DB_PASSWORD';
CREATE DATABASE onlyoffice 
    WITH OWNER onlyoffice 
    ENCODING 'UTF8' 
    LC_COLLATE='en_US.UTF-8' 
    LC_CTYPE='en_US.UTF-8' 
    TEMPLATE=template0;
GRANT ALL PRIVILEGES ON DATABASE onlyoffice TO onlyoffice;
\c onlyoffice
GRANT ALL ON SCHEMA public TO onlyoffice;
GRANT CREATE ON SCHEMA public TO onlyoffice;
POSTGRES_SETUP

# Test PostgreSQL connection  
echo "Testing OnlyOffice PostgreSQL connection..."
if PGPASSWORD="$ONLYOFFICE_DB_PASSWORD" psql -h localhost -U onlyoffice -d onlyoffice -c "SELECT 'OnlyOffice DB OK' AS status;"; then
    echo "✓ OnlyOffice PostgreSQL connection working"
else
    echo "✗ OnlyOffice PostgreSQL connection failed"
    exit 1
fi

# Save credentials for both databases
cat > /root/nextcloud-db-credentials.txt << EOL
Dual Database Credentials
========================
Created: $(date)

NEXTCLOUD DATABASE (MariaDB)
============================
Host: localhost
Port: 3306
Database: nextcloud
Username: nextcloud
Password: $NEXTCLOUD_DB_PASSWORD

Test: mysql -u nextcloud -p'$NEXTCLOUD_DB_PASSWORD' nextcloud

ONLYOFFICE DATABASE (PostgreSQL)  
================================
Host: localhost
Port: 5432
Database: onlyoffice
Username: onlyoffice
Password: $ONLYOFFICE_DB_PASSWORD

Test: PGPASSWORD='$ONLYOFFICE_DB_PASSWORD' psql -h localhost -U onlyoffice -d onlyoffice

SERVICE STATUS
==============
MariaDB: $(systemctl is-active mariadb)
PostgreSQL: $(systemctl is-active postgresql)

PORTS IN USE
============
MariaDB: 3306
PostgreSQL: 5432
EOL

chmod 600 /root/nextcloud-db-credentials.txt

echo ""
echo "✓ Step 2 Complete!"
echo "✓ MariaDB configured for Nextcloud"
echo "✓ PostgreSQL configured for OnlyOffice"  
echo "✓ Both databases running simultaneously"
echo ""
echo "Credentials saved to: /root/nextcloud-db-credentials.txt"
echo ""
echo "Verification:"
echo "- MariaDB: $(systemctl is-active mariadb) on port 3306"
echo "- PostgreSQL: $(systemctl is-active postgresql) on port 5432"
echo ""
echo "Next: Run step3_nextcloud.sh"