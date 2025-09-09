#!/bin/bash

# Nextcloud + OnlyOffice Snap Setup Script
# Configures both snaps to work together via nginx reverse proxy

set -e

echo "=== Nextcloud + OnlyOffice Snap Setup ==="
echo "This script configures:"
echo "- Nextcloud snap on port 8080"  
echo "- OnlyOffice snap on port 8081"
echo "- Nginx reverse proxy on ports 80/443"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

echo "Step 1: Installing snaps (if not already installed)..."
snap install nextcloud || echo "Nextcloud already installed"
snap install onlyoffice-ds || echo "OnlyOffice already installed"

echo "Step 2: Stopping conflicting services..."
systemctl stop nginx 2>/dev/null || echo "nginx not running"
systemctl stop apache2 2>/dev/null || echo "apache2 not running" 
systemctl stop httpd 2>/dev/null || echo "httpd not running"

echo "Step 3: Configuring snap ports..."
# Configure Nextcloud for port 8080/8443
snap set nextcloud ports.http=8080 ports.https=8443

# Configure OnlyOffice for port 8081/8444  
snap set onlyoffice-ds onlyoffice.ds-port=8081 onlyoffice.ds-ssl-port=8444

echo "Step 4: Waiting for snaps to restart with new ports..."
sleep 10

echo "Step 5: Installing and configuring nginx..."
apt update
apt install -y nginx

# Create nginx configuration
cat > /etc/nginx/sites-available/nextcloud-onlyoffice << 'EOL'
# Remove default nginx page
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 301 https://$server_name$request_uri;
}

# Nextcloud main site
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name _;

    # SSL configuration (you'll need to add your own certificates)
    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;
    
    # SSL settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # Nextcloud proxy
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $server_name;
        proxy_set_header X-Forwarded-Port $server_port;
        
        # Nextcloud specific headers
        proxy_max_temp_file_size 0;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Handle large file uploads
        client_max_body_size 10G;
        proxy_max_temp_file_size 2048m;
    }

    # OnlyOffice Document Server
    location /onlyoffice/ {
        proxy_pass http://127.0.0.1:8081/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $server_name;
        
        # OnlyOffice specific settings
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Handle large document operations
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        client_max_body_size 100M;
    }
}
EOL

# Enable the site
ln -sf /etc/nginx/sites-available/nextcloud-onlyoffice /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

echo "Step 6: Testing nginx configuration..."
nginx -t

echo "Step 7: Starting nginx..."
systemctl enable nginx
systemctl start nginx

echo "Step 8: Checking service status..."
echo ""
echo "=== Service Status ==="
echo -n "Nextcloud snap: "
if curl -s http://127.0.0.1:8080 > /dev/null; then
    echo "✓ Running on port 8080"
else
    echo "✗ Not responding on port 8080"
fi

echo -n "OnlyOffice snap: "
if curl -s http://127.0.0.1:8081 > /dev/null; then
    echo "✓ Running on port 8081"  
else
    echo "✗ Not responding on port 8081"
fi

echo -n "Nginx proxy: "
if curl -s -k https://127.0.0.1 > /dev/null; then
    echo "✓ Running on port 443"
else
    echo "✗ Not responding on port 443"
fi

echo ""
echo "=== Port Status ==="
netstat -tlnp | grep -E ":80|:443|:8080|:8081" | head -10

echo ""
echo "=== Setup Complete! ==="
echo ""
echo "Next steps:"
echo "1. Access Nextcloud at: https://your-server-ip"
echo "2. Complete Nextcloud initial setup"
echo "3. Configure OnlyOffice integration:"
echo "   - Go to Settings → Administration → OnlyOffice"
echo "   - Set Document Server URL to: https://your-server-ip/onlyoffice/"
echo "   - Set Secret Key (JWT): $(snap get onlyoffice-ds onlyoffice.jwt-secret 2>/dev/null | cut -d' ' -f2 || echo 'Check with: sudo snap get onlyoffice-ds onlyoffice.jwt-secret')"
echo ""
echo "4. For production use, replace the self-signed SSL certificates with proper ones"
echo ""

# Save configuration info for later reference
cat > /root/nextcloud-onlyoffice-info.txt << EOL
Nextcloud + OnlyOffice Configuration
===================================

Setup Date: $(date)

Service URLs:
- Nextcloud (direct): http://localhost:8080
- OnlyOffice (direct): http://localhost:8081  
- Public access: https://your-server-ip

OnlyOffice Integration Settings:
- Document Server URL: https://your-server-ip/onlyoffice/
- JWT Secret: $(snap get onlyoffice-ds onlyoffice.jwt-secret 2>/dev/null | cut -d' ' -f2 || echo 'Check with: sudo snap get onlyoffice-ds onlyoffice.jwt-secret')

Configuration Files:
- Nginx config: /etc/nginx/sites-available/nextcloud-onlyoffice
- This info: /root/nextcloud-onlyoffice-info.txt

Useful Commands:
- Check snap settings: sudo snap get nextcloud && sudo snap get onlyoffice-ds  
- Restart services: systemctl restart nginx
- View logs: journalctl -u snap.nextcloud* -f
- View OnlyOffice logs: journalctl -u snap.onlyoffice-ds* -f
EOL

echo "Configuration details saved to: /root/nextcloud-onlyoffice-info.txt"