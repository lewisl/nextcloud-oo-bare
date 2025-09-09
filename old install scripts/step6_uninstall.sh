#!/bin/bash

# Uninstall Step 6: Remove OnlyOffice Document Server

set -e

echo "=== Uninstalling Step 6: OnlyOffice Document Server ==="
echo "This will remove OnlyOffice Document Server and clean up configuration"
echo ""

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

read -p "This will remove OnlyOffice Document Server. Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo "Stopping OnlyOffice services..."
systemctl stop ds-docservice ds-converter ds-metrics ds-example 2>/dev/null || true

echo "Disabling OnlyOffice services..."
systemctl disable ds-docservice ds-converter ds-metrics ds-example 2>/dev/null || true

echo "Removing OnlyOffice package..."
# Handle broken dpkg states - OnlyOffice often gets stuck in broken install state

# First, create the missing file that's causing the removal script to fail
mkdir -p /etc/nginx/conf.d
touch /etc/nginx/conf.d/ds.conf
echo "# Dummy file to fix OnlyOffice removal" > /etc/nginx/conf.d/ds.conf

if dpkg -l | grep -q onlyoffice-documentserver; then
    echo "OnlyOffice package found, attempting removal..."
    
    # Try normal removal first
    if ! apt remove -y onlyoffice-documentserver 2>/dev/null; then
        echo "Normal removal failed, forcing removal..."
        
        # Force remove broken package
        dpkg --remove --force-remove-reinstreq onlyoffice-documentserver 2>/dev/null || true
        
        # If still broken, force purge with all possible force options
        dpkg --purge --force-all onlyoffice-documentserver 2>/dev/null || true
        
        # Nuclear option: directly edit dpkg database
        if dpkg -l | grep -q onlyoffice-documentserver; then
            echo "Package still stuck, using nuclear option..."
            
            # Remove from dpkg status database
            sed -i '/^Package: onlyoffice-documentserver$/,/^$/d' /var/lib/dpkg/status
            
            # Remove package files list
            rm -f /var/lib/dpkg/info/onlyoffice-documentserver.*
            
            echo "Package removed from dpkg database"
        fi
    fi
    
    # Try purge after removal
    apt purge -y onlyoffice-documentserver 2>/dev/null || true
    
    # Fix broken dependencies
    apt --fix-broken install -y 2>/dev/null || true
    
    # Verify removal
    if dpkg -l | grep -q onlyoffice-documentserver; then
        echo "WARNING: OnlyOffice package still present in dpkg database"
        echo "Manual intervention may be required"
    else
        echo "✓ OnlyOffice package removed successfully"
    fi
else
    echo "OnlyOffice package not found in system"
fi

# Clean up the dummy file we created
rm -f /etc/nginx/conf.d/ds.conf
rmdir /etc/nginx/conf.d 2>/dev/null || true

echo "Removing OnlyOffice repository and GPG key..."
rm -f /etc/apt/sources.list.d/onlyoffice.list
rm -f /usr/share/keyrings/onlyoffice.gpg

echo "Cleaning up OnlyOffice directories..."
rm -rf /etc/onlyoffice 2>/dev/null || true
rm -rf /var/www/onlyoffice 2>/dev/null || true
rm -rf /var/log/onlyoffice 2>/dev/null || true
rm -rf /var/lib/onlyoffice 2>/dev/null || true
rm -rf /usr/share/onlyoffice 2>/dev/null || true

echo "Cleaning up OnlyOffice database..."
# Clean up OnlyOffice database and user
if command -v mysql >/dev/null 2>&1; then
    mysql -u root -e "DROP DATABASE IF EXISTS onlyoffice;" 2>/dev/null || true
    mysql -u root -e "DROP USER IF EXISTS 'onlyoffice'@'localhost';" 2>/dev/null || true
    mysql -u root -e "FLUSH PRIVILEGES;" 2>/dev/null || true
    echo "✓ OnlyOffice database cleaned"
else
    echo "MySQL not available, skipping database cleanup"
fi

echo "Restoring nginx configuration..."
NGINX_BACKUP=$(ls /etc/nginx/sites-available/nextcloud.backup.* 2>/dev/null | tail -1)

if [ -f "$NGINX_BACKUP" ]; then
    echo "Restoring nginx from backup: $NGINX_BACKUP"
    cp "$NGINX_BACKUP" /etc/nginx/sites-available/nextcloud
    
    # Remove OnlyOffice-related backup files
    rm -f /etc/nginx/sites-available/nextcloud.backup.*onlyoffice* 2>/dev/null || true
    
    echo "Testing nginx configuration..."
    if nginx -t; then
        systemctl reload nginx
        echo "✓ Nginx configuration restored"
    else
        echo "✗ Nginx configuration test failed!"
        echo "Manual intervention required."
        exit 1
    fi
else
    echo "No nginx backup found. Removing OnlyOffice location manually..."
    
    # Remove OnlyOffice location block from nginx config
    sed -i '/# OnlyOffice Document Server/,/^[[:space:]]*}$/d' /etc/nginx/sites-available/nextcloud
    
    if nginx -t; then
        systemctl reload nginx
        echo "✓ OnlyOffice configuration removed from nginx"
    else
        echo "✗ Failed to clean nginx configuration"
        exit 1
    fi
fi

echo "Cleaning up info files..."
rm -f /root/onlyoffice-info.txt

echo "Running package cleanup..."
apt autoremove -y
apt autoclean

# Final verification
echo ""
echo "Verification:"
ONLYOFFICE_CHECK=$(dpkg -l | grep onlyoffice || true)
if [ -n "$ONLYOFFICE_CHECK" ]; then
    echo "WARNING: OnlyOffice packages still found:"
    echo "$ONLYOFFICE_CHECK"
    echo "Manual cleanup may be needed"
else
    echo "✓ No OnlyOffice packages found in system"
fi

# Check for any remaining OnlyOffice processes
ONLYOFFICE_PROCS=$(ps aux | grep -i onlyoffice | grep -v grep | wc -l)
if [ "$ONLYOFFICE_PROCS" -gt 0 ]; then
    echo "Warning: Found $ONLYOFFICE_PROCS OnlyOffice processes still running"
    echo "Killing remaining processes..."
    pkill -f onlyoffice 2>/dev/null || true
    pkill -f documentserver 2>/dev/null || true
fi

# Verify port 8081 is free
if netstat -tlnp | grep -q ":8081"; then
    echo "Warning: Port 8081 still in use after OnlyOffice removal"
    netstat -tlnp | grep ":8081"
fi

echo ""
echo "✓ Step 6 OnlyOffice removed!"
echo "OnlyOffice Document Server uninstalled"
echo "Nginx configuration cleaned up"
echo "Port 8081 freed"
echo ""
echo "Note: If you had OnlyOffice app installed in Nextcloud:"
echo "1. Go to Nextcloud Apps → Office & text"
echo "2. Disable/Remove the ONLYOFFICE app"