#!/bin/bash

# Master Uninstall Script
# Removes everything in proper reverse order

set -e

echo "=== Complete Nextcloud Uninstallation ==="
echo "This will remove EVERYTHING installed by the setup scripts:"
echo "- OnlyOffice (Step 6)"
echo "- Let's Encrypt SSL (Step 5)" 
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
if [ -f "6_uninstall.sh" ]; then
    echo "Step 6: Removing OnlyOffice..."
    ./6_uninstall.sh || echo "OnlyOffice removal failed or not installed"
else
    echo "Step 6: OnlyOffice uninstall script not found, manual cleanup..."
    # Manual cleanup
    systemctl stop ds-docservice ds-converter ds-metrics 2>/dev/null || true
    
    # Force remove broken package
    dpkg --remove --force-remove-reinstreq onlyoffice-documentserver 2>/dev/null || true
    dpkg --purge --force-all onlyoffice-documentserver 2>/dev/null || true
    
    # Nuclear option if still stuck
    if dpkg -l | grep -q onlyoffice-documentserver; then
        sed -i '/^Package: onlyoffice-documentserver$/,/^$/d' /var/lib/dpkg/status
        rm -f /var/lib/dpkg/info/onlyoffice-documentserver.*
    fi
    
    apt remove -y onlyoffice-documentserver 2>/dev/null || true
    rm -f /etc/apt/sources.list.d/onlyoffice.list
    rm -f /usr/share/keyrings/onlyoffice.gpg
    rm -rf /etc/onlyoffice /var/log/onlyoffice /var/lib/onlyoffice 2>/dev/null || true
fi

echo ""

# Step 5: Let's Encrypt SSL
if [ -f "5_uninstall.sh" ]; then
    echo "Step 5: Removing Let's Encrypt SSL..."
    ./5_uninstall.sh || echo "Let's Encrypt removal failed"
else
    echo "Step 5: Let's Encrypt uninstall script not found, manual cleanup..."
    rm -f /etc/cron.d/letsencrypt_renewal
    rm -f /usr/local/bin/renew_letsencrypt.sh
    apt remove -y certbot python3-certbot-nginx 2>/dev/null || true
    rm -rf /etc/letsencrypt 2>/dev/null || true
fi

echo ""

# Step 4: Nginx configuration
if [ -f "4_uninstall.sh" ]; then
    echo "Step 4: Removing Nginx configuration..."
    ./4_uninstall.sh || echo "Nginx cleanup failed"
else
    echo "Step 4: Nginx uninstall script not found, manual cleanup..."
    systemctl stop nginx 2>/dev/null || true
    rm -f /etc/nginx/sites-enabled/nextcloud
    rm -f /etc/nginx/sites-available/nextcloud*
    rm -f /root/nextcloud_nginx_info.txt
fi

echo ""

# Step 3: Nextcloud files
if [ -f "3_uninstall.sh" ]; then
    echo "Step 3: Removing Nextcloud files..."
    ./3_uninstall.sh || echo "Nextcloud file removal failed"
else
    echo "Step 3: Nextcloud uninstall script not found, manual cleanup..."
    rm -rf /var/www/nextcloud
    rm -f /root/nextcloud_install_info.txt
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
if [ -f "2_uninstall.sh" ]; then
    echo "Step 2: Removing databases..."
    ./2_uninstall.sh || echo "Database removal failed"
else
    echo "Step 2: Database uninstall script not found, manual cleanup..."
    # Clean MariaDB
    mysql -e "DROP DATABASE IF EXISTS nextcloud;" 2>/dev/null || true
    mysql -e "DROP USER IF EXISTS 'nextcloud'@'localhost';" 2>/dev/null || true
    # Clean PostgreSQL
    sudo -u postgres psql -c "DROP DATABASE IF EXISTS onlyoffice;" 2>/dev/null || true
    sudo -u postgres psql -c "DROP USER IF EXISTS onlyoffice;" 2>/dev/null || true
    rm -f /root/nextcloud_db_credentials.txt
fi

echo ""

# Step 1: System packages
if [ -f "1_uninstall.sh" ]; then
    echo "Step 1: Removing system packages..."
    ./1_uninstall.sh || echo "Package removal failed"
else
    echo "Step 1: Package uninstall script not found, manual cleanup..."
    systemctl stop nginx mariadb postgresql php8.3-fpm 2>/dev/null || true
    systemctl disable nginx mariadb postgresql php8.3-fpm 2>/dev/null || true
    apt remove -y nginx mariadb-server postgresql postgresql-contrib php8.3-* ssl-cert 2>/dev/null || true
    apt purge -y nginx mariadb-server postgresql postgresql-contrib php8.3-* 2>/dev/null || true
    rm -rf /var/lib/mysql /var/lib/postgresql /etc/nginx 2>/dev/null || true
fi

echo ""
echo "Final cleanup..."
apt autoremove -y 2>/dev/null || true
apt autoclean 2>/dev/null || true

# Remove any remaining info files
rm -f /root/nextcloud_*_info.txt
rm -f /root/nextcloud_*_credentials.txt
rm -f /root/letsencrypt_info.txt
rm -f /root/onlyoffice_info.txt

echo ""
echo "======================================"
echo "COMPLETE UNINSTALLATION FINISHED!"
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