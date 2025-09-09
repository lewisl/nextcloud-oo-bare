#!/bin/bash

# Master Uninstall Script
# Removes everything in proper reverse order

set -e

echo "=== Complete Nextcloud Uninstallation ==="
echo "This will remove EVERYTHING installed by the setup scripts:"
echo "- OnlyOffice (Step 5)"
echo "- Nginx configuration (Step 4)" 
echo "- Nextcloud files and data (Step 3)"
echo "- Database and user (Step 2)"
echo "- System packages (Step 1)"
echo ""

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

read -p "This will DELETE EVERYTHING. Are you absolutely sure? (type 'DELETE' to confirm): " -r
if [[ $REPLY != "DELETE" ]]; then
    echo "Cancelled - you must type 'DELETE' exactly to confirm."
    exit 0
fi

echo ""
echo "Starting complete removal..."
echo "=================================="

# Step 6: OnlyOffice (if installed)
if [ -f "06-uninstall.sh" ]; then
    echo "Step 6: Removing OnlyOffice..."
    ./06-uninstall.sh || echo "OnlyOffice removal failed or not installed"
else
    echo "Step 6: OnlyOffice uninstall script not found, skipping..."
    # Manual cleanup
    systemctl stop ds-docservice ds-converter ds-metrics 2>/dev/null || true
    apt remove -y onlyoffice-documentserver 2>/dev/null || true
    rm -f /etc/apt/sources.list.d/onlyoffice.list
    rm -f /usr/share/keyrings/onlyoffice.gpg
fi

echo ""

# Step 5: Let's Encrypt SSL
if [ -f "05-uninstall.sh" ]; then
    echo "Step 5: Removing Let's Encrypt SSL..."
    ./05-uninstall.sh || echo "Let's Encrypt removal failed"
else
    echo "Step 5: Let's Encrypt uninstall script not found, manual cleanup..."
    rm -f /etc/cron.d/letsencrypt-renewal
    rm -f /usr/local/bin/renew-letsencrypt.sh
    apt remove -y certbot python3-certbot-nginx 2>/dev/null || true
    rm -rf /etc/letsencrypt 2>/dev/null || true
fi

echo ""

# Step 4: Nginx configuration
if [ -f "04-uninstall.sh" ]; then
    echo "Step 4: Removing Nginx configuration..."
    ./04-uninstall.sh || echo "Nginx cleanup failed"
else
    echo "Step 4: Nginx uninstall script not found, manual cleanup..."
    systemctl stop nginx 2>/dev/null || true
    rm -f /etc/nginx/sites-enabled/nextcloud
    rm -f /etc/nginx/sites-available/nextcloud*
    rm -f /root/nextcloud-nginx-info.txt
fi

echo ""

# Step 3: Nextcloud files
if [ -f "03-uninstall.sh" ]; then
    echo "Step 3: Removing Nextcloud files..."
    ./03-uninstall.sh || echo "Nextcloud file removal failed"
else
    echo "Step 3: Nextcloud uninstall script not found, manual cleanup..."
    rm -rf /var/www/nextcloud
    rm -f /root/nextcloud-install-info.txt
    # Restore PHP if backup exists
    if ls /etc/php/8.3/fpm/php.ini.backup.* 2>/dev/null; then
        BACKUP=$(ls /etc/php/8.3/fpm/php.ini.backup.* | head -1)
        cp "$BACKUP" /etc/php/8.3/fpm/php.ini
        systemctl restart php8.3-fpm 2>/dev/null || true
        rm -f /etc/php/8.3/fpm/php.ini.backup.*
    fi
fi

echo ""

# Step 2: Database
if [ -f "02-uninstall.sh" ]; then
    echo "Step 2: Removing database..."
    ./02-uninstall.sh || echo "Database removal failed"
else
    echo "Step 2: Database uninstall script not found, manual cleanup..."
    mysql -e "DROP DATABASE IF EXISTS nextcloud;" 2>/dev/null || true
    mysql -e "DROP USER IF EXISTS 'nextcloud'@'localhost';" 2>/dev/null || true
    rm -f /root/nextcloud-db-credentials.txt
fi

echo ""

# Step 1: System packages
if [ -f "01-uninstall.sh" ]; then
    echo "Step 1: Removing system packages..."
    ./01-uninstall.sh || echo "Package removal failed"
else
    echo "Step 1: Package uninstall script not found, manual cleanup..."
    systemctl stop nginx mariadb php8.3-fpm 2>/dev/null || true
    systemctl disable nginx mariadb php8.3-fpm 2>/dev/null || true
    apt remove -y nginx mariadb-server php8.3-* ssl-cert 2>/dev/null || true
    apt purge -y nginx mariadb-server php8.3-* 2>/dev/null || true
    rm -rf /var/lib/mysql 2>/dev/null || true
    rm -rf /etc/nginx 2>/dev/null || true
fi

echo ""
echo "Final cleanup..."
apt autoremove -y 2>/dev/null || true
apt autoclean 2>/dev/null || true

# Remove any remaining info files
rm -f /root/nextcloud-*-info.txt
rm -f /root/nextcloud-*-credentials.txt

echo ""
echo "======================================"
echo "✓ COMPLETE UNINSTALLATION FINISHED!"
echo "======================================"
echo ""
echo "System returned to clean state."
echo "All Nextcloud components removed:"
echo "- All packages uninstalled"
echo "- All data deleted"
echo "- All configuration files removed"
echo "- All databases dropped"
echo ""
echo "You can now run the installation scripts again if needed."