#!/bin/bash

# Uninstall Step 4: Remove Nginx Configuration

set -e

echo "=== Uninstalling Step 4: Nginx Configuration ==="
echo "This will remove Nextcloud nginx configuration and stop nginx"
echo "Note: This does NOT remove nginx package (that's handled by step 1)"
echo ""

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

read -p "This will remove nginx configuration for Nextcloud. Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo "Stopping nginx..."
systemctl stop nginx 2>/dev/null || true

echo "Disabling nginx..."
systemctl disable nginx 2>/dev/null || true

echo "Removing Nextcloud site configuration..."
rm -f /etc/nginx/sites-enabled/nextcloud
rm -f /etc/nginx/sites-available/nextcloud*

echo "Restoring nginx default site..."
if [ -f "/etc/nginx/sites-available/default" ]; then
    ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
    echo "✓ Default nginx site restored"
else
    echo "! Default nginx site not found - creating basic one..."
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
fi

echo "Testing nginx configuration..."
if nginx -t; then
    echo "✓ Nginx configuration valid"
    echo "Note: Nginx stopped and disabled - won't start automatically"
    echo "Run 'systemctl start nginx' if you want to start it with default config"
else
    echo "! Nginx configuration test failed - may need manual cleanup"
fi

echo "Removing nginx info files..."
rm -f /root/nextcloud-nginx-info.txt

# Check what's using ports 80/443
echo ""
echo "Port status after cleanup:"
netstat -tlnp | grep -E ":80|:443" || echo "Ports 80/443 are free"

echo ""
echo "✓ Step 4 nginx configuration removed!"
echo "Nginx package still installed (use 01-uninstall.sh to remove)"
echo "Default nginx configuration restored"
echo "Service stopped and disabled"