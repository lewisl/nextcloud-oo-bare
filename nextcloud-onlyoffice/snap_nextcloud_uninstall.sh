#!/bin/bash

# Snap-Based Nextcloud + OnlyOffice Uninstallation
# Completely removes the snap-based installation

set -e

echo "=== Snap-Based Nextcloud + OnlyOffice Uninstallation ==="
echo "This will completely remove:"
echo "- Nextcloud snap and all data"
echo "- OnlyOffice Document Server snap"
echo "- nginx configuration"
echo "- SSL certificates"
echo "- Firewall rules"
echo ""
echo "WARNING: This will DELETE ALL NEXTCLOUD DATA!"
echo ""

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

read -p "This will DELETE EVERYTHING. Type 'DELETE' to confirm: " -r
if [[ $REPLY != "DELETE" ]]; then
    echo "Cancelled - you must type 'DELETE' exactly to confirm."
    exit 0
fi

echo ""
echo "Starting complete removal..."

echo ""
echo "=== Step 1: Stopping Services ==="
systemctl stop nginx 2>/dev/null || true

echo ""
echo "=== Step 2: Removing Snap Packages ==="
echo "Removing OnlyOffice Document Server..."
snap remove onlyoffice-ds 2>/dev/null || echo "OnlyOffice snap not found"

echo "Removing Nextcloud (this will delete all data)..."
snap remove nextcloud 2>/dev/null || echo "Nextcloud snap not found"

echo ""
echo "=== Step 3: Removing nginx Configuration ==="
echo "Removing site configurations..."
rm -f /etc/nginx/sites-enabled/nextcloud
rm -f /etc/nginx/sites-available/nextcloud

echo "Restoring default nginx site..."
if [ -f "/etc/nginx/sites-available/default" ]; then
    ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
    echo "Default site restored"
else
    echo "Creating basic default site..."
    cat > /etc/nginx/sites-available/default << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    root /var/www/html;
    index index.html index.htm index.nginx-debian.html;
    
    server_name _;
    
    location / {
        try_files $uri $uri/ =404;
    }
}
EOF
    ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
    echo "Basic default site created"
fi

echo ""
echo "=== Step 4: Removing SSL Certificates ==="
if command -v certbot &> /dev/null; then
    echo "Removing Let's Encrypt certificates..."
    
    # List certificates and remove them
    CERTS=$(certbot certificates 2>/dev/null | grep "Certificate Name:" | awk '{print $3}' || true)
    
    for cert in $CERTS; do
        if [ -n "$cert" ]; then
            echo "Removing certificate: $cert"
            certbot delete --cert-name "$cert" --non-interactive 2>/dev/null || true
        fi
    done
    
    echo "Removing certbot..."
    apt remove -y certbot python3-certbot-nginx 2>/dev/null || true
    apt autoremove -y 2>/dev/null || true
else
    echo "Certbot not installed, skipping certificate removal"
fi

# Clean up any remaining letsencrypt files
rm -rf /etc/letsencrypt 2>/dev/null || true

echo ""
echo "=== Step 5: Testing nginx Configuration ==="
echo "Testing nginx configuration..."
if nginx -t; then
    systemctl start nginx
    echo "nginx restarted with default configuration"
else
    echo "nginx configuration error - manual intervention needed"
fi

echo ""
echo "=== Step 6: Resetting Firewall ==="
echo "Resetting firewall to default state..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw --force enable
echo "Firewall reset - only SSH allowed"

echo ""
echo "=== Step 7: Cleaning Up Files ==="
echo "Removing info and backup files..."
rm -f /root/snap-nextcloud-info.txt
rm -f /root/snap-nextcloud-install.log

# Remove any snap data directories that might remain
rm -rf /var/snap/nextcloud 2>/dev/null || true
rm -rf /var/snap/onlyoffice-ds 2>/dev/null || true

echo ""
echo "=== Step 8: Final Cleanup ==="
echo "Running system cleanup..."
apt autoremove -y 2>/dev/null || true
apt autoclean 2>/dev/null || true

# Verify removals
echo ""
echo "Verification:"
echo "Snap packages:"
snap list 2>/dev/null | grep -E "(nextcloud|onlyoffice)" || echo "  No Nextcloud or OnlyOffice snaps found ✓"

echo "nginx sites:"
ls -la /etc/nginx/sites-enabled/ | grep -v default || echo "  Only default site enabled ✓"

echo "SSL certificates:"
ls -la /etc/letsencrypt/live/ 2>/dev/null || echo "  No SSL certificates found ✓"

echo "Firewall status:"
ufw status | head -5

echo ""
echo "=============================================="
echo "✅ COMPLETE REMOVAL FINISHED!"
echo "=============================================="
echo ""
echo "System returned to clean state:"
echo "- All snap packages removed"
echo "- All data deleted"
echo "- nginx restored to default"
echo "- SSL certificates removed"
echo "- Firewall reset to SSH-only"
echo ""
echo "The system is now ready for a fresh installation."
echo ""
echo "Note: If you want to completely remove nginx as well:"
echo "  apt remove --purge nginx nginx-common"
echo "  apt autoremove"