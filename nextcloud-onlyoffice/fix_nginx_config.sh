#!/bin/bash

# Fix nginx configuration for Nextcloud + OnlyOffice
# This creates the correct nginx config matching the tutorial

echo "Fixing nginx configuration..."

# Restore backup first
cp /etc/nginx/sites-available/nextcloud.backup /etc/nginx/sites-available/nextcloud

# Create the corrected config file
cat > /etc/nginx/sites-available/nextcloud << 'NGINX_EOF'
# HTTP redirect to HTTPS  
server {
    listen 80;
    listen [::]:80;
    server_name www.bedfordfallsbbbl.org;
    return 301 https://$host$request_uri;
}

# Main server block
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name www.bedfordfallsbbbl.org;

    ssl_certificate /etc/letsencrypt/live/www.bedfordfallsbbbl.org/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/www.bedfordfallsbbbl.org/privkey.pem;

    client_max_body_size 0;
    underscores_in_headers on;

    # OnlyOffice proxy
    location /onlyoffice/ {
        proxy_pass http://127.0.0.1:82/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Main Nextcloud proxy (changed from ~ to / to avoid conflicts)
    location / {
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        add_header Front-End-Https on;
        proxy_headers_hash_max_size 512;
        proxy_headers_hash_bucket_size 64;
        proxy_buffering off;
        proxy_redirect off;
        proxy_max_temp_file_size 0;
        proxy_pass http://127.0.0.1:8080;
    }
}
NGINX_EOF

echo "Testing nginx configuration..."
if nginx -t; then
    echo "Configuration is valid. Reloading nginx..."
    systemctl reload nginx
    echo "✅ nginx configuration fixed and reloaded"
else
    echo "❌ Configuration test failed. Restoring backup..."
    cp /etc/nginx/sites-available/nextcloud.backup /etc/nginx/sites-available/nextcloud
    systemctl reload nginx
    echo "Backup restored"
fi

echo "Current nginx config:"
echo "==================="
cat /etc/nginx/sites-available/nextcloud