#!/bin/bash

# Uninstall Step 2: Remove Database

set -e

echo "=== Uninstalling Step 2: Database ==="
echo "This will remove the Nextcloud database and user"
echo ""

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

read -p "This will DELETE the Nextcloud database and all data. Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

if command -v mysql &> /dev/null; then
    echo "Removing Nextcloud database and user..."
    mysql -e "DROP DATABASE IF EXISTS nextcloud;" 2>/dev/null || true
    mysql -e "DROP USER IF EXISTS 'nextcloud'@'localhost';" 2>/dev/null || true
    mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true
    echo "Database and user removed."
else
    echo "MariaDB not found, skipping database cleanup."
fi

echo "Removing credential files..."
rm -f /root/nextcloud-db-credentials.txt

echo ""
echo "✓ Step 2 database removed!"