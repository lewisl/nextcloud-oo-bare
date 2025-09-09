#!/bin/bash

# Step 2 Uninstall: Remove Both MariaDB and PostgreSQL Databases

set -e

echo "=== Uninstalling Step 2: Both Databases ==="
echo "This will remove databases and users from BOTH MariaDB and PostgreSQL"
echo ""

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

read -p "This will DELETE both Nextcloud and OnlyOffice databases. Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "=== Cleaning MariaDB (Nextcloud) ==="
if command -v mysql &> /dev/null && systemctl is-active --quiet mariadb; then
    echo "Removing Nextcloud database and user from MariaDB..."
    mysql -u root << MYSQL_CLEANUP 2>/dev/null || true
DROP DATABASE IF EXISTS nextcloud;
DROP USER IF EXISTS 'nextcloud'@'localhost';
FLUSH PRIVILEGES;
MYSQL_CLEANUP
    echo "✓ MariaDB cleanup completed"
else
    echo "MariaDB not running or not found, skipping MariaDB cleanup"
fi

echo ""
echo "=== Cleaning PostgreSQL (OnlyOffice) ==="
if command -v psql &> /dev/null && systemctl is-active --quiet postgresql; then
    echo "Removing OnlyOffice database and user from PostgreSQL..."
    sudo -u postgres psql << POSTGRES_CLEANUP 2>/dev/null || true
DROP DATABASE IF EXISTS onlyoffice;
DROP USER IF EXISTS onlyoffice;
POSTGRES_CLEANUP
    echo "✓ PostgreSQL cleanup completed"
else
    echo "PostgreSQL not running or not found, skipping PostgreSQL cleanup"
fi

echo ""
echo "=== Removing Credential Files ==="
rm -f /root/nextcloud-db-credentials.txt
echo "✓ Credential files removed"

echo ""
echo "=== Service Status After Cleanup ==="
if systemctl is-active --quiet mariadb; then
    echo "MariaDB: Still running (ready for fresh setup)"
else
    echo "MariaDB: Stopped or not installed"
fi

if systemctl is-active --quiet postgresql; then
    echo "PostgreSQL: Still running (ready for fresh setup)"
else
    echo "PostgreSQL: Stopped or not installed"
fi

echo ""
echo "✓ Step 2 databases cleaned!"
echo "Both Nextcloud (MariaDB) and OnlyOffice (PostgreSQL) databases removed"
echo "Services left running for fresh database setup"