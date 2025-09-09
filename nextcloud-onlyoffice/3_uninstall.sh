#!/bin/bash

# Uninstall Step 3: Remove Nextcloud Installation

set -e

echo "=== Uninstalling Step 3: Nextcloud Files ==="
echo "This will remove Nextcloud installation and data"
echo ""

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

INSTALL_DIR="/var/www/nextcloud"

if [ ! -d "$INSTALL_DIR" ]; then
    echo "Nextcloud not found at $INSTALL_DIR"
    echo "Nothing to remove."
else
    echo "Found Nextcloud at: $INSTALL_DIR"
    
    read -p "This will DELETE all Nextcloud files and data. Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
    
    echo "Removing Nextcloud directory..."
    rm -rf "$INSTALL_DIR"
    echo "Nextcloud files removed."
fi

# Restore PHP configuration
PHP_INI="/etc/php/8.3/fpm/php.ini"
PHP_BACKUP=$(ls $PHP_INI.backup.* 2>/dev/null | head -1)

if [ -f "$PHP_BACKUP" ]; then
    echo "Restoring original PHP configuration..."
    cp "$PHP_BACKUP" "$PHP_INI"
    systemctl restart php8.3-fpm
    echo "PHP configuration restored from: $PHP_BACKUP"
    
    # Remove backup files
    rm -f $PHP_INI.backup.*
else
    echo "No PHP backup found, leaving current configuration."
fi

echo "Removing info files..."
rm -f /root/nextcloud-install-info.txt

echo ""
echo "✓ Step 3 Nextcloud removed!"
echo "Files deleted: $INSTALL_DIR"
echo "PHP configuration restored"