#!/bin/bash

# Fix database setup after PostgreSQL cluster creation

set -e

echo "=== Fixing Database Setup ==="

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

# Generate new passwords
NEXTCLOUD_DB_PASSWORD=$(openssl rand -base64 24)
ONLYOFFICE_DB_PASSWORD=$(openssl rand -base64 24)

echo "Generated new database passwords:"
echo "  Nextcloud (MariaDB): $NEXTCLOUD_DB_PASSWORD"
echo "  OnlyOffice (PostgreSQL): $ONLYOFFICE_DB_PASSWORD"

echo ""
echo "=== Fixing MariaDB for Nextcloud ==="

# Reset nextcloud user password in MariaDB
mysql -e "ALTER USER 'nextcloud'@'localhost' IDENTIFIED BY '$NEXTCLOUD_DB_PASSWORD';"
mysql -e "FLUSH PRIVILEGES;"

echo "MariaDB password updated for user 'nextcloud'"

echo ""
echo "=== Configuring PostgreSQL for OnlyOffice ==="

# Create OnlyOffice user and database in PostgreSQL
sudo -u postgres psql -c "CREATE USER onlyoffice WITH PASSWORD '$ONLYOFFICE_DB_PASSWORD';" 2>/dev/null || {
    echo "OnlyOffice user already exists. Updating password..."
    sudo -u postgres psql -c "ALTER USER onlyoffice WITH PASSWORD '$ONLYOFFICE_DB_PASSWORD';"
}

sudo -u postgres psql -c "CREATE DATABASE onlyoffice OWNER onlyoffice;" 2>/dev/null || {
    echo "OnlyOffice database already exists."
}

sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE onlyoffice TO onlyoffice;"

echo "PostgreSQL configured: database 'onlyoffice' with user 'onlyoffice'"

echo ""
echo "=== Testing database connections ==="

# Test MariaDB connection
if mysql -u nextcloud -p$NEXTCLOUD_DB_PASSWORD -e "SELECT 1;" nextcloud >/dev/null 2>&1; then
    echo "MariaDB connection test: SUCCESS"
else
    echo "MariaDB connection test: FAILED"
    exit 1
fi

# Test PostgreSQL connection
if PGPASSWORD=$ONLYOFFICE_DB_PASSWORD psql -h localhost -U onlyoffice -d onlyoffice -c "SELECT 1;" >/dev/null 2>&1; then
    echo "PostgreSQL connection test: SUCCESS"
else
    echo "PostgreSQL connection test: FAILED"
    exit 1
fi

# Save credentials
cat > /root/nextcloud_db_credentials.txt << EOL
Database Credentials for Nextcloud + OnlyOffice Setup
=====================================================

Nextcloud Database (MariaDB)
----------------------------
Host: localhost
Database: nextcloud
Username: nextcloud
Password: $NEXTCLOUD_DB_PASSWORD
Connection test: mysql -u nextcloud -p nextcloud

OnlyOffice Database (PostgreSQL)
---------------------------------
Host: localhost
Database: onlyoffice
Username: onlyoffice
Password: $ONLYOFFICE_DB_PASSWORD
Connection test: PGPASSWORD='$ONLYOFFICE_DB_PASSWORD' psql -h localhost -U onlyoffice -d onlyoffice

System Information
------------------
MariaDB Status: $(systemctl is-active mariadb)
PostgreSQL Status: $(systemctl is-active postgresql)
PostgreSQL Cluster: $(pg_lsclusters | grep main)
Created: $(date)

Notes:
- MariaDB runs on port 3306
- PostgreSQL runs on port 5432
- Both databases can run simultaneously
- PostgreSQL cluster was manually created and started
EOL

echo ""
echo "Database Setup Fixed!"
echo "Both database systems configured:"
echo "MariaDB: nextcloud database ready"  
echo "PostgreSQL: onlyoffice database ready"
echo "Credentials saved to: /root/nextcloud_db_credentials.txt"
echo ""
echo "Database status:"
echo "- MariaDB: $(systemctl is-active mariadb)"
echo "- PostgreSQL: $(systemctl is-active postgresql)"
echo "- PostgreSQL Cluster: $(pg_lsclusters | grep main | awk '{print $4}')"
echo ""
echo "Next: Run 3_nextcloud.sh"
