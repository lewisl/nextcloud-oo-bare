#!/bin/bash

# Uninstall Step 2: Remove Both Databases (Updated for Dual Database)

set -e

echo "=== Uninstalling Step 2: Databases ==="
echo "This will remove both MariaDB and PostgreSQL databases and users"
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

echo "Removing MariaDB database and user..."
if command -v mysql &> /dev/null; then
    mysql -e "DROP DATABASE IF EXISTS nextcloud;" 2>/dev/null || true
    mysql -e "DROP USER IF EXISTS 'nextcloud'@'localhost';" 2>/dev/null || true
    mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true
    echo "MariaDB Nextcloud database and user removed."
else
    echo "MariaDB not found, skipping MariaDB cleanup."
fi

echo "Removing PostgreSQL database and user..."
if command -v psql &> /dev/null; then
    sudo -u postgres psql -c "DROP DATABASE IF EXISTS onlyoffice;" 2>/dev/null || true
    sudo -u postgres psql -c "DROP USER IF EXISTS onlyoffice;" 2>/dev/null || true
    echo "PostgreSQL OnlyOffice database and user removed."
else
    echo "PostgreSQL not found, skipping PostgreSQL cleanup."
fi

echo "Removing credential files..."
rm -f /root/nextcloud_db_credentials.txt
rm -f /root/nextcloud-db-credentials.txt

echo ""
echo "Step 2 databases removed!"
echo "Both MariaDB and PostgreSQL databases cleaned up."