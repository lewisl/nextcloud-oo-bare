#!/bin/bash

# Force Clean OnlyOffice Broken Package State
# Fixes the dpkg broken package state that's preventing clean uninstall

set -e

echo "=== Force Cleaning OnlyOffice Broken Package State ==="
echo "This fixes the dpkg error preventing clean removal"
echo ""

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

echo "Step 1: Creating missing file that's causing removal script to fail..."
# The error shows it's looking for /etc/nginx/conf.d/ds.conf
mkdir -p /etc/nginx/conf.d
touch /etc/nginx/conf.d/ds.conf
echo "# Dummy file to fix OnlyOffice removal" > /etc/nginx/conf.d/ds.conf

echo "Step 2: Trying normal package removal again..."
if dpkg --remove onlyoffice-documentserver; then
    echo "✅ OnlyOffice removed successfully"
else
    echo "Normal removal still failed, using force methods..."
    
    echo "Step 3: Force removing with all dpkg options..."
    dpkg --remove --force-remove-reinstreq --force-depends onlyoffice-documentserver 2>/dev/null || true
    
    echo "Step 4: Nuclear option - editing dpkg database directly..."
    # Remove from dpkg status database
    sed -i '/^Package: onlyoffice-documentserver$/,/^$/d' /var/lib/dpkg/status
    
    # Remove package files list
    rm -f /var/lib/dpkg/info/onlyoffice-documentserver.*
    
    echo "✅ OnlyOffice forcibly removed from dpkg database"
fi

echo "Step 5: Cleaning up OnlyOffice files manually..."
rm -rf /etc/onlyoffice 2>/dev/null || true
rm -rf /var/www/onlyoffice 2>/dev/null || true
rm -rf /var/log/onlyoffice 2>/dev/null || true
rm -rf /var/lib/onlyoffice 2>/dev/null || true
rm -rf /usr/share/onlyoffice 2>/dev/null || true

echo "Step 6: Removing OnlyOffice repository..."
rm -f /etc/apt/sources.list.d/onlyoffice.list
rm -f /usr/share/keyrings/onlyoffice.gpg

echo "Step 7: Cleaning up remaining nginx files..."
rm -f /etc/nginx/conf.d/ds.conf
rmdir /etc/nginx/conf.d 2>/dev/null || true

echo "Step 8: Fixing broken dependencies..."
apt --fix-broken install -y

echo "Step 9: Final cleanup..."
apt autoremove -y
apt autoclean

echo ""
echo "✅ OnlyOffice completely removed!"
echo "Checking dpkg status..."
if dpkg -l | grep -i onlyoffice; then
    echo "⚠️  OnlyOffice packages still found - may need manual intervention"
else
    echo "✅ No OnlyOffice packages found in dpkg database"
fi

echo ""
echo "System should now be clean for fresh installation with PostgreSQL approach!"