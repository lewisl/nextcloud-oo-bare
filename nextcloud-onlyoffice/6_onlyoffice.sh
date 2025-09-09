#!/bin/bash

# Step 6: OnlyOffice Document Server Installation with PostgreSQL
# Installs OnlyOffice Document Server using PostgreSQL (no MariaDB conflicts)

set -e

echo "=== Step 6: OnlyOffice Document Server Installation ==="
echo "This installs OnlyOffice Document Server with PostgreSQL backend"
echo "No conflicts with MariaDB (used by Nextcloud)"
echo ""

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

# Check prerequisites
if [ ! -f "/etc/nginx/sites-available/nextcloud" ]; then
    echo "Error: Nextcloud nginx not configured. Run previous steps first."
    exit 1
fi

if ! systemctl is-active --quiet nginx; then
    echo "Error: Nginx is not running."
    exit 1
fi

if ! systemctl is-active --quiet postgresql; then
    echo "Error: PostgreSQL is not running. Check 2_database.sh."
    exit 1
fi

# Get domain info if available (for OnlyOffice URL)
DOMAIN_NAME=""
if [ -f "/root/letsencrypt_info.txt" ]; then
    DOMAIN_NAME=$(grep "^Domains:" /root/letsencrypt_info.txt | cut -d' ' -f2 2>/dev/null || echo "")
fi

if [ -z "$DOMAIN_NAME" ]; then
    SERVER_IP=$(curl -s ifconfig.me)
    DOMAIN_NAME="$SERVER_IP"
    echo "Using server IP: $DOMAIN_NAME"
else
    echo "Using domain: $DOMAIN_NAME"
fi

# Read PostgreSQL credentials from step 2
if [ ! -f "/root/nextcloud_db_credentials.txt" ]; then
    echo "Error: Database credentials not found. Run 2_database.sh first."
    exit 1
fi

echo "Found PostgreSQL credentials from step 2"

ONLYOFFICE_DB_PASSWORD=$(grep -A 10 "OnlyOffice Database (PostgreSQL)" /root/nextcloud_db_credentials.txt | grep "Password:" | cut -d' ' -f2)

if [ -z "$ONLYOFFICE_DB_PASSWORD" ]; then
    echo "Error: Could not read OnlyOffice PostgreSQL password from credentials file."
    echo "Expected format in /root/nextcloud_db_credentials.txt:"
    echo "OnlyOffice Database (PostgreSQL)"
    echo "Password: xxxxxxxxx"
    exit 1
fi

# Test PostgreSQL connection
echo "Testing PostgreSQL connection..."
if PGPASSWORD=$ONLYOFFICE_DB_PASSWORD psql -h localhost -U onlyoffice -d onlyoffice -c "SELECT 1;" > /dev/null 2>&1; then
    echo "PostgreSQL connection verified"
else
    echo "Cannot connect to PostgreSQL with OnlyOffice credentials"
    exit 1
fi

echo ""
echo "Step 1: Installing prerequisite packages..."
apt update
apt install -y \
    apt-transport-https \
    ca-certificates \
    gnupg \
    wget \
    curl \
    fontconfig \
    fonts-dejavu-core \
    fonts-liberation

echo ""
echo "Step 2: Adding OnlyOffice repository..."

# Add OnlyOffice GPG key
echo "Adding OnlyOffice GPG key..."
wget -qO- https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE | gpg --dearmor > /usr/share/keyrings/onlyoffice.gpg

# Add repository
echo "Adding OnlyOffice repository..."
echo "deb [signed-by=/usr/share/keyrings/onlyoffice.gpg] https://download.onlyoffice.com/repo/debian squeeze main" > /etc/apt/sources.list.d/onlyoffice.list

# Update package lists
apt update

echo ""
echo "Step 3: Pre-configuring OnlyOffice with debconf..."
echo "Setting up debconf configuration for PostgreSQL..."

# CRITICAL: Configure OnlyOffice to use PostgreSQL, not MySQL
echo "onlyoffice-documentserver onlyoffice-documentserver/db-type select pgsql" | debconf-set-selections
echo "onlyoffice-documentserver onlyoffice-documentserver/db-host string localhost" | debconf-set-selections
echo "onlyoffice-documentserver onlyoffice-documentserver/db-port string 5432" | debconf-set-selections
echo "onlyoffice-documentserver onlyoffice-documentserver/db-name string onlyoffice" | debconf-set-selections
echo "onlyoffice-documentserver onlyoffice-documentserver/db-user string onlyoffice" | debconf-set-selections
echo "onlyoffice-documentserver onlyoffice-documentserver/db-password password $ONLYOFFICE_DB_PASSWORD" | debconf-set-selections

# PostgreSQL-specific debconf settings
echo "onlyoffice-documentserver onlyoffice-documentserver/pgsql/admin-user string postgres" | debconf-set-selections
echo "onlyoffice-documentserver onlyoffice-documentserver/pgsql/admin-password password " | debconf-set-selections

echo "Debconf pre-configuration complete"

echo ""
echo "Step 4: Installing OnlyOffice Document Server..."
echo "Installing onlyoffice-documentserver package..."

# Install with non-interactive mode to use our debconf settings
export DEBIAN_FRONTEND=noninteractive

if apt install -y onlyoffice-documentserver; then
    echo "OnlyOffice installed successfully"
else
    echo "OnlyOffice installation failed!"
    echo ""
    echo "Debug information:"
    echo "- PostgreSQL status: $(systemctl is-active postgresql)"
    echo "- Database connection test:"
    PGPASSWORD=$ONLYOFFICE_DB_PASSWORD psql -h localhost -U onlyoffice -d onlyoffice -c "SELECT version();" || echo "Database connection failed"
    echo ""
    echo "Check OnlyOffice logs: /var/log/onlyoffice/documentserver/"
    exit 1
fi

echo ""
echo "Step 5: Configuring OnlyOffice..."

# Configure OnlyOffice to run on port 8081 (avoid conflicts with nginx)
ONLYOFFICE_CONFIG="/etc/onlyoffice/documentserver/default.json"

if [ -f "$ONLYOFFICE_CONFIG" ]; then
    echo "Backing up OnlyOffice configuration..."
    cp "$ONLYOFFICE_CONFIG" "$ONLYOFFICE_CONFIG.backup.$(date +%s)"
    
    echo "Configuring OnlyOffice to use port 8081..."
    # Change port from 80 to 8081
    sed -i 's/"port": 80/"port": 8081/' "$ONLYOFFICE_CONFIG"
    sed -i 's/"port":80/"port":8081/' "$ONLYOFFICE_CONFIG"
else
    echo "Warning: OnlyOffice config file not found at expected location"
fi

# Generate JWT secret for security
JWT_SECRET=$(openssl rand -base64 32)
echo "Generated JWT secret: $JWT_SECRET"

# Configure JWT in OnlyOffice
ONLYOFFICE_LOCAL_JSON="/etc/onlyoffice/documentserver/local.json"
cat > "$ONLYOFFICE_LOCAL_JSON" << EOF
{
  "services": {
    "CoAuthoring": {
      "secret": {
        "inbox": {
          "string": "$JWT_SECRET"
        },
        "outbox": {
          "string": "$JWT_SECRET"
        },
        "session": {
          "string": "$JWT_SECRET"
        }
      }
    }
  }
}
EOF

echo ""
echo "Step 6: Starting OnlyOffice services..."
systemctl enable ds-docservice ds-converter ds-metrics
systemctl restart ds-docservice ds-converter ds-metrics

# Don't start ds-example (we don't want the portal)
systemctl stop ds-example 2>/dev/null || true
systemctl disable ds-example 2>/dev/null || true

# Wait for services to start
sleep 15

echo ""
echo "Step 7: Testing OnlyOffice services..."

# Test OnlyOffice services
echo -n "Document Service: "
if systemctl is-active --quiet ds-docservice; then
    echo "Running"
else
    echo "Failed"
    systemctl status ds-docservice --no-pager -l
fi

echo -n "Converter Service: "
if systemctl is-active --quiet ds-converter; then
    echo "Running"
else
    echo "Failed"
fi

echo -n "Metrics Service: "
if systemctl is-active --quiet ds-metrics; then
    echo "Running"
else
    echo "Failed"
fi

# Test OnlyOffice direct access
echo -n "OnlyOffice direct access (port 8081): "
if curl -s http://127.0.0.1:8081/healthcheck > /dev/null 2>&1; then
    echo "Working"
else
    echo "Failed"
    echo "Checking service status..."
    systemctl status ds-docservice --no-pager -l
fi

echo ""
echo "Step 8: Updating nginx configuration for OnlyOffice..."

# Backup current nginx config
cp /etc/nginx/sites-available/nextcloud /etc/nginx/sites-available/nextcloud.backup.$(date +%s)

# Add OnlyOffice location to nginx config if not already present
if ! grep -q "location /onlyoffice/" /etc/nginx/sites-available/nextcloud; then
    echo "Adding OnlyOffice proxy configuration to nginx..."
    
    # Insert OnlyOffice location block before the main location block
    sed -i '/# Main location/i \
    # OnlyOffice Document Server\
    location /onlyoffice/ {\
        proxy_pass http://127.0.0.1:8081/;\
        proxy_http_version 1.1;\
        proxy_set_header Upgrade $http_upgrade;\
        proxy_set_header Connection "upgrade";\
        proxy_set_header Host $host;\
        proxy_set_header X-Real-IP $remote_addr;\
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\
        proxy_set_header X-Forwarded-Proto $scheme;\
        proxy_read_timeout 3600s;\
        proxy_send_timeout 3600s;\
        client_max_body_size 100M;\
    }\
\
' /etc/nginx/sites-available/nextcloud
else
    echo "OnlyOffice configuration already exists in nginx"
fi

echo "Testing nginx configuration..."
if nginx -t; then
    systemctl reload nginx
    echo "Nginx configuration updated and reloaded"
else
    echo "Nginx configuration test failed!"
    echo "Restoring previous configuration..."
    BACKUP=$(ls /etc/nginx/sites-available/nextcloud.backup.* | tail -1)
    cp "$BACKUP" /etc/nginx/sites-available/nextcloud
    systemctl reload nginx
    exit 1
fi

# Test OnlyOffice through nginx proxy
echo -n "OnlyOffice via nginx proxy: "
if curl -s -k https://$DOMAIN_NAME/onlyoffice/healthcheck > /dev/null 2>&1; then
    echo "Working"
else
    echo "Failed (may be normal if using IP address without proper SSL)"
fi

# Save configuration info
cat > /root/onlyoffice_info.txt << EOL
OnlyOffice Document Server Configuration
=======================================
Date: $(date)
Database: PostgreSQL (no MariaDB conflicts)

Service Information:
- Port: 8081 (internal)
- JWT Secret: $JWT_SECRET
- Configuration: $ONLYOFFICE_CONFIG
- Local config: $ONLYOFFICE_LOCAL_JSON

Database Connection:
- Type: PostgreSQL
- Host: localhost
- Port: 5432
- Database: onlyoffice
- User: onlyoffice
- Password: $ONLYOFFICE_DB_PASSWORD

URLs:
- Direct access: http://127.0.0.1:8081/
- Via nginx: https://$DOMAIN_NAME/onlyoffice/
- Health check: https://$DOMAIN_NAME/onlyoffice/healthcheck

Services Status:
- Document Service: $(systemctl is-active ds-docservice)
- Converter: $(systemctl is-active ds-converter)  
- Metrics: $(systemctl is-active ds-metrics)
- Example Portal: $(systemctl is-active ds-example 2>/dev/null || echo "disabled")

Nginx Configuration:
- File: /etc/nginx/sites-available/nextcloud
- Backup: /etc/nginx/sites-available/nextcloud.backup.*
- Proxy: /onlyoffice/ -> http://127.0.0.1:8081/

Nextcloud Integration Steps:
1. Access Nextcloud: https://$DOMAIN_NAME
2. Go to Apps -> Office & text
3. Install "ONLYOFFICE" app
4. Go to Settings -> Administration -> ONLYOFFICE
5. Enter these settings:
   - Document Server URL: https://$DOMAIN_NAME/onlyoffice/
   - Secret key (JWT): $JWT_SECRET
   - Enable: "Restrict access to editors to registered users"

Log Files:
- Document Service: /var/log/onlyoffice/documentserver/docservice/out.log
- Converter: /var/log/onlyoffice/documentserver/converter/out.log
- Metrics: /var/log/onlyoffice/documentserver/metrics/out.log

Manual Commands:
- Restart services: systemctl restart ds-docservice ds-converter ds-metrics
- Check status: systemctl status ds-docservice
- Test connection: curl http://127.0.0.1:8081/healthcheck
- Database test: PGPASSWORD='$ONLYOFFICE_DB_PASSWORD' psql -h localhost -U onlyoffice -d onlyoffice -c 'SELECT version();'
EOL

echo ""
echo "Step 6 Complete!"
echo "OnlyOffice Document Server installed with PostgreSQL"
echo ""
echo "Configuration saved to: /root/onlyoffice_info.txt"
echo ""
echo "=== NEXTCLOUD + ONLYOFFICE SETUP COMPLETE! ==="
echo ""
echo "Final steps:"
echo "1. Access Nextcloud: https://$DOMAIN_NAME"
echo "2. Complete Nextcloud initial setup if not done"
echo "3. Install OnlyOffice app in Nextcloud:"
echo "   - Go to Apps -> Office & text"
echo "   - Install 'ONLYOFFICE'"
echo "4. Configure OnlyOffice integration:"
echo "   - Settings -> Administration -> ONLYOFFICE"
echo "   - Document Server URL: https://$DOMAIN_NAME/onlyoffice/"
echo "   - Secret key: $JWT_SECRET"
echo ""
echo "Your Nextcloud installation is ready for encryption modifications!"
echo "Encryption classes located at: /var/www/nextcloud/lib/private/Encryption/"