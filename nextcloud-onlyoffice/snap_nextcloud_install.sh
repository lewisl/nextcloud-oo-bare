#!/bin/bash

# Snap-Based Nextcloud + OnlyOffice Installation
# Simple alternative to the multi-step installation scripts
# Uses Nextcloud snap + OnlyOffice snap + nginx reverse proxy

set -e

echo "=== Snap-Based Nextcloud + OnlyOffice Installation ==="
echo "This installs:"
echo "- Nextcloud (snap) with internal database"
echo "- OnlyOffice Document Server (snap)"
echo "- nginx (apt) as reverse proxy"
echo "- Let's Encrypt SSL certificates"
echo ""

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

# Get domain information
read -p "Enter your domain name (e.g., nextcloud.example.com): " DOMAIN_NAME
read -p "Enter your email for Let's Encrypt: " LETSENCRYPT_EMAIL

if [[ -z "$DOMAIN_NAME" || -z "$LETSENCRYPT_EMAIL" ]]; then
    echo "Error: Domain name and email are required"
    exit 1
fi

echo ""
echo "Configuration:"
echo "Domain: $DOMAIN_NAME"
echo "Email: $LETSENCRYPT_EMAIL"
echo ""

read -p "Continue with installation? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "=== Step 1: Installing System Packages ==="
apt update
apt install -y nginx snapd ssl-cert curl wget ufw

# Configure firewall to block all unused ports
echo "Configuring firewall (blocking all except SSH and HTTP/HTTPS)..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp    # HTTP (for Let's Encrypt and redirects)
ufw allow 443/tcp   # HTTPS (main access)
ufw --force enable

echo "Firewall configured - only SSH, HTTP, and HTTPS allowed"

echo ""
echo "=== Step 2: Installing Snap Core ==="
source /etc/profile.d/apps-bin-path.sh 2>/dev/null || true
snap install core
snap refresh core

echo ""
echo "=== Step 3: Installing Nextcloud Snap ==="
snap install nextcloud

# Configure Nextcloud to run on non-standard ports (nginx will proxy)
echo "Configuring Nextcloud ports..."
snap set nextcloud ports.http=8080
# Note: No HTTPS port needed - nginx handles SSL termination

# Get admin credentials
echo ""
read -p "Enter Nextcloud admin username: " NC_ADMIN_USER
read -s -p "Enter Nextcloud admin password: " NC_ADMIN_PASS
echo

if [[ -z "$NC_ADMIN_USER" || -z "$NC_ADMIN_PASS" ]]; then
    echo "Error: Admin username and password are required"
    exit 1
fi

# why do we need this
echo "Setting up Nextcloud admin user..."
nextcloud.manual-install "$NC_ADMIN_USER" "$NC_ADMIN_PASS"

# Configure Nextcloud for HTTPS proxy: these commands won't work until nextcloud is minimally setup and can run
echo "Configuring Nextcloud for reverse proxy..."
nextcloud.occ config:system:set overwriteprotocol --value="https"
nextcloud.occ config:system:set trusted_domains 1 --value="$DOMAIN_NAME"

echo ""
echo "=== Step 4: Installing OnlyOffice Document Server Snap ==="
snap install onlyoffice-ds

# Configure OnlyOffice to run on port 82 (HTTP only)
echo "Configuring OnlyOffice port..."
snap set onlyoffice-ds onlyoffice.ds-port=82

# Ensure OnlyOffice runs HTTP only (no SSL certificates)
echo "Ensuring OnlyOffice runs in HTTP mode..."
rm -f /var/snap/onlyoffice-ds/current/var/www/onlyoffice/Data/certs/* 2>/dev/null || true

# Get JWT secret for later use
JWT_SECRET=$(snap get onlyoffice-ds onlyoffice.jwt-secret)

echo ""
echo "=== Step 5: Configuring nginx Reverse Proxy ==="

# Remove default nginx site
rm -f /etc/nginx/sites-enabled/default

# Create nginx configuration
cat > /etc/nginx/sites-available/nextcloud << EOF
# HTTP redirect to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN_NAME;
    return 301 https://\$server_name\$request_uri;
}

# Main Nextcloud HTTPS server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN_NAME;

    # Temporary self-signed SSL (will be replaced by Let's Encrypt)
    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;

    # Large file uploads
    client_max_body_size 10G;
    client_body_buffer_size 400M;

    # OnlyOffice Document Server proxy
    location /onlyoffice/ {
        proxy_pass http://127.0.0.1:82/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support for collaborative editing
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts for long document operations
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        client_max_body_size 100M;
    }

    # Main Nextcloud proxy
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Headers for Nextcloud
        add_header Front-End-Https on;
        proxy_headers_hash_max_size 512;
        proxy_headers_hash_bucket_size 64;
        proxy_buffering off;
        proxy_redirect off;
        proxy_max_temp_file_size 0;
        
        # Large file uploads
        client_max_body_size 10G;
        proxy_request_buffering off;
    }
}
EOF

# Enable the site
ln -sf /etc/nginx/sites-available/nextcloud /etc/nginx/sites-enabled/

# Test nginx configuration
echo "Testing nginx configuration..."
if nginx -t; then
    systemctl restart nginx
    echo "✅ nginx configured and started"
else
    echo "❌ nginx configuration failed"
    exit 1
fi

echo ""
echo "=== Step 6: Installing Let's Encrypt SSL ==="

# Install certbot
apt install -y certbot python3-certbot-nginx

echo "Obtaining SSL certificate for $DOMAIN_NAME..."
if certbot --nginx -d "$DOMAIN_NAME" --email "$LETSENCRYPT_EMAIL" --agree-tos --non-interactive --redirect; then
    echo "✅ SSL certificate obtained successfully"
else
    echo "❌ SSL certificate generation failed!"
    echo "Check:"
    echo "- Domain $DOMAIN_NAME resolves to this server"
    echo "- Ports 80/443 are accessible from internet"
    echo "- No firewall blocking access"
    exit 1
fi

echo ""
echo "=== Step 7: Installing OnlyOffice App in Nextcloud ==="

echo "Installing OnlyOffice connector app..."
nextcloud.occ app:install onlyoffice

echo "Configuring OnlyOffice integration..."
nextcloud.occ config:app:set onlyoffice DocumentServerUrl --value="https://$DOMAIN_NAME/onlyoffice/"
nextcloud.occ config:app:set onlyoffice jwt_secret --value="$JWT_SECRET"
nextcloud.occ config:app:set onlyoffice jwt_header --value="AuthorizationJwt"

# Enable OnlyOffice app
nextcloud.occ app:enable onlyoffice

echo ""
echo "=== Step 8: Final Configuration ==="

# Create info file
cat > /root/snap-nextcloud-info.txt << EOL
Snap-Based Nextcloud + OnlyOffice Installation
==============================================
Date: $(date)

Nextcloud Configuration:
- URL: https://$DOMAIN_NAME
- Admin User: $NC_ADMIN_USER
- Internal HTTP: http://127.0.0.1:8080
- Data Directory: /var/snap/nextcloud/common/nextcloud/data/

OnlyOffice Configuration:
- Internal URL: http://127.0.0.1:82
- External URL: https://$DOMAIN_NAME/onlyoffice/
- JWT Secret: $JWT_SECRET

nginx Configuration:
- Config File: /etc/nginx/sites-available/nextcloud
- SSL Certificate: Managed by Let's Encrypt
- Auto-renewal: Configured via certbot

Snap Management:
- Nextcloud: snap info nextcloud
- OnlyOffice: snap info onlyoffice-ds
- Logs: snap logs nextcloud, snap logs onlyoffice-ds

Useful Commands:
- Nextcloud CLI: nextcloud.occ
- Backup: nextcloud.export /backup/location
- Restore: nextcloud.import /backup/location
- Update: snap refresh nextcloud onlyoffice-ds

Service Status:
- Nextcloud: $(snap list nextcloud --color=never | tail -n +2)
- OnlyOffice: $(snap list onlyoffice-ds --color=never | tail -n +2)
- nginx: $(systemctl is-active nginx)

Next Steps:
1. Access Nextcloud at https://$DOMAIN_NAME
2. Log in with admin credentials
3. Test document editing functionality
4. Configure additional users and settings
EOL

echo ""
echo "=============================================="
echo "✅ INSTALLATION COMPLETE!"
echo "=============================================="
echo ""
echo "Your Nextcloud server is ready at:"
echo "🌐 https://$DOMAIN_NAME"
echo ""
echo "Admin Login:"
echo "👤 Username: $NC_ADMIN_USER"
echo "🔐 Password: [as entered]"
echo ""
echo "OnlyOffice Document Server:"
echo "📄 Integrated and ready for collaborative editing"
echo ""
echo "Configuration saved to: /root/snap-nextcloud-info.txt"
echo ""
echo "🔧 Maintenance Commands:"
echo "  - Update: snap refresh nextcloud onlyoffice-ds"
echo "  - Backup: nextcloud.export /backup/path"
echo "  - Logs: snap logs nextcloud"
echo "  - Status: snap list"
echo ""
echo "🎉 Enjoy your new Nextcloud server with OnlyOffice!"