#!/bin/bash

# Uninstall Step 5: Remove Let's Encrypt SSL

set -e

echo "=== Uninstalling Step 5: Let's Encrypt SSL ==="
echo "This will remove SSL certificates and revert to self-signed"
echo ""

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

read -p "This will remove SSL certificates and revert nginx config. Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Get domain from letsencrypt info if available
DOMAIN_NAME=""
if [ -f "/root/letsencrypt-info.txt" ]; then
    DOMAIN_NAME=$(grep "^Domain:" /root/letsencrypt-info.txt | cut -d' ' -f2)
    echo "Found domain: $DOMAIN_NAME"
fi

echo "Stopping renewal cron job..."
rm -f /etc/cron.d/letsencrypt-renewal

echo "Removing renewal script..."
rm -f /usr/local/bin/renew-letsencrypt.sh

if [ -n "$DOMAIN_NAME" ] && [ -d "/etc/letsencrypt/live/$DOMAIN_NAME" ]; then
    echo "Removing Let's Encrypt certificates for $DOMAIN_NAME..."
    certbot delete --cert-name "$DOMAIN_NAME" --non-interactive 2>/dev/null || true
    
    # Clean up any remaining certificate files
    rm -rf "/etc/letsencrypt/live/$DOMAIN_NAME" 2>/dev/null || true
    rm -rf "/etc/letsencrypt/archive/$DOMAIN_NAME" 2>/dev/null || true
    rm -rf "/etc/letsencrypt/renewal/$DOMAIN_NAME.conf" 2>/dev/null || true
else
    echo "No domain found or certificates don't exist, skipping certificate removal..."
fi

echo "Restoring original nginx configuration..."
NGINX_BACKUP=$(ls /etc/nginx/sites-available/nextcloud.backup.* 2>/dev/null | tail -1)

if [ -f "$NGINX_BACKUP" ]; then
    echo "Restoring from backup: $NGINX_BACKUP"
    cp "$NGINX_BACKUP" /etc/nginx/sites-available/nextcloud
    
    # Remove all backup files
    rm -f /etc/nginx/sites-available/nextcloud.backup.*
    
    echo "Testing restored nginx configuration..."
    if nginx -t; then
        systemctl reload nginx
        echo "✓ Nginx configuration restored and reloaded"
    else
        echo "✗ Nginx configuration test failed!"
        echo "Manual intervention required."
        exit 1
    fi
else
    echo "No nginx backup found. Creating new self-signed config..."
    
    # Recreate basic self-signed configuration
    sed -i 's/server_name .*/server_name _;/' /etc/nginx/sites-available/nextcloud
    sed -i 's|ssl_certificate .*|ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;|' /etc/nginx/sites-available/nextcloud
    sed -i 's|ssl_certificate_key .*|ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;|' /etc/nginx/sites-available/nextcloud
    
    nginx -t && systemctl reload nginx
fi

echo "Removing certbot..."
apt remove -y certbot python3-certbot-nginx
apt autoremove -y

echo "Cleaning up info files..."
rm -f /root/letsencrypt-info.txt
rm -f /var/log/letsencrypt-renewal.log

# Clean up any remaining letsencrypt files
rm -rf /etc/letsencrypt 2>/dev/null || true

echo ""
echo "✓ Step 5 Let's Encrypt removed!"
echo "Reverted to self-signed SSL certificates"
echo "Access via: https://server-ip (will show security warning)"
echo ""
echo "If you had a domain configured, update DNS or use IP address"