#!/bin/bash

# Step 4: Nginx Configuration
# Configures nginx for Nextcloud only

set -e

echo "=== Step 4: Nginx Configuration ==="
echo "This configures nginx to serve Nextcloud"
echo ""

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

# Check prerequisites
if [ ! -d "/var/www/nextcloud" ]; then
    echo "Error: Nextcloud not installed. Run 03-nextcloud-install.sh first."
    exit 1
fi

if ! command -v nginx &> /dev/null; then
    echo "Error: Nginx not installed. Run 01-system-prep.sh first."
    exit 1
fi

# Get server IP
SERVER_IP=$(curl -s ifconfig.me || echo "YOUR_SERVER_IP")
echo "Detected server IP: $SERVER_IP"

NGINX_SITE="/etc/nginx/sites-available/nextcloud"
NGINX_ENABLED="/etc/nginx/sites-enabled/nextcloud"

echo "Creating nginx configuration..."

# Backup existing config if it exists
if [ -f "$NGINX_SITE" ]; then
    cp "$NGINX_SITE" "$NGINX_SITE.backup.$(date +%s)"
fi

# Create the nginx configuration
cat > "$NGINX_SITE" << 'EOF'
upstream php-handler {
    server unix:/var/run/php/php8.3-fpm.sock;
}

# Redirect HTTP to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name _;
    return 301 https://$server_name$request_uri;
}

# Main Nextcloud server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name _;

    # SSL Configuration
    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;

    # Nextcloud root
    root /var/www/nextcloud;
    index index.php index.html;

    # File upload limits
    client_max_body_size 10G;
    client_body_buffer_size 400M;

    # Security - block access to sensitive files
    location ~ ^/(?:build|tests|config|lib|3rdparty|templates|data)(?:$|/) { 
        return 404; 
    }
    location ~ ^/(?:\.|autotest|occ|issue|indie|db_|console) { 
        return 404; 
    }

    # Well-known URLs
    location = /.well-known/carddav {
        return 301 $scheme://$host/remote.php/dav;
    }
    location = /.well-known/caldav {
        return 301 $scheme://$host/remote.php/dav;
    }

    # Main location
    location / {
        rewrite ^ /index.php;
    }

    # PHP handler
    location ~ \.php(?:$|/) {
        rewrite ^(.*.php)(/.*)$ $1 last;

        include fastcgi_params;
        fastcgi_split_path_info ^(.+\.php)(/.*)$;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
        fastcgi_param HTTPS on;
        fastcgi_param modHeadersAvailable true;
        fastcgi_param front_controller_active true;
        fastcgi_pass php-handler;
        fastcgi_intercept_errors on;
        fastcgi_request_buffering off;
        fastcgi_read_timeout 300;
    }

    # Static files
    location ~ \.(?:css|js|svg|gif|png|html|ttf|woff|woff2|ico|jpg|jpeg)$ {
        try_files $uri /index.php$request_uri;
        expires 6M;
        access_log off;
    }
}
EOF

echo "Enabling Nextcloud site..."
# Remove default site
rm -f /etc/nginx/sites-enabled/default

# Enable our site
ln -sf "$NGINX_SITE" "$NGINX_ENABLED"

echo "Testing nginx configuration..."
if nginx -t; then
    echo "Configuration valid!"
else
    echo "Configuration test failed!"
    exit 1
fi

echo "Starting nginx..."
systemctl start nginx
systemctl enable nginx

# Test if services are running
echo "Testing services..."
if systemctl is-active --quiet nginx; then
    echo "✓ Nginx is running"
else
    echo "✗ Nginx failed to start"
    systemctl status nginx
    exit 1
fi

if systemctl is-active --quiet php8.3-fpm; then
    echo "✓ PHP-FPM is running"
else
    echo "✗ PHP-FPM not running"
    systemctl status php8.3-fpm
    exit 1
fi

# Save configuration info
cat > /root/nextcloud-nginx-info.txt << EOL
Nginx Configuration Info
========================
Date: $(date)
Configuration file: $NGINX_SITE
Enabled site: $NGINX_ENABLED
Server IP: $SERVER_IP

Access URLs:
- HTTP: http://$SERVER_IP (redirects to HTTPS)
- HTTPS: https://$SERVER_IP

SSL Certificate:
- Certificate: /etc/ssl/certs/ssl-cert-snakeoil.pem
- Key: /etc/ssl/private/ssl-cert-snakeoil.key
- Type: Self-signed (replace with real cert for production)

Services Status:
- Nginx: $(systemctl is-active nginx)
- PHP-FPM: $(systemctl is-active php8.3-fpm)
- MariaDB: $(systemctl is-active mariadb)

Next Steps:
1. Access https://$SERVER_IP in browser
2. Complete Nextcloud setup with database credentials
3. Run 05-onlyoffice-install.sh for document editing
EOL

echo ""
echo "✓ Step 4 Complete!"
echo "Nginx configured and running"
echo "Access Nextcloud at: https://$SERVER_IP"
echo ""
echo "Configuration saved to: /root/nextcloud-nginx-info.txt"
echo ""
echo "Next: Run 05-onlyoffice-install.sh"