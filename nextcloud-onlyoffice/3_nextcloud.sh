#!/bin/bash

# Step 3: Nextcloud Installation
# Downloads and installs Nextcloud files only

set -e

echo "=== Step 3: Nextcloud Installation ==="
echo "This downloads and installs Nextcloud files"
echo "Location: /var/www/nextcloud/"
echo ""

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

# Check prerequisites
if [ ! -f /root/nextcloud-db-credentials.txt ]; then
    echo "Error: Database not set up. Run 02-database-setup.sh first."
    exit 1
fi

if ! command -v php &> /dev/null; then
    echo "Error: PHP not installed. Run 01-system-prep.sh first."
    exit 1
fi

INSTALL_DIR="/var/www/nextcloud"

# Check if already installed
if [ -d "$INSTALL_DIR" ]; then
    echo "Warning: $INSTALL_DIR already exists!"
    read -p "Remove and reinstall? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$INSTALL_DIR"
        echo "Removed existing installation."
    else
        echo "Cancelled."
        exit 0
    fi
fi

echo "Creating web directory..."
mkdir -p /var/www

echo "Downloading Nextcloud..."
cd /var/www
wget -O nextcloud.tar.bz2 https://download.nextcloud.com/server/releases/latest.tar.bz2

echo "Extracting Nextcloud..."
tar -xjf nextcloud.tar.bz2

echo "Setting permissions..."
chown -R www-data:www-data nextcloud
chmod -R 755 nextcloud

echo "Cleaning up..."
rm nextcloud.tar.bz2

# Configure PHP for Nextcloud
echo "Configuring PHP..."
PHP_INI="/etc/php/8.3/fpm/php.ini"
if [ -f "$PHP_INI" ]; then
    # Backup original
    cp "$PHP_INI" "$PHP_INI.backup.$(date +%s)"
    
    # Update settings
    sed -i 's/memory_limit = 128M/memory_limit = 512M/' "$PHP_INI"
    sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 1G/' "$PHP_INI"
    sed -i 's/post_max_size = 8M/post_max_size = 1G/' "$PHP_INI"
    sed -i 's/max_execution_time = 30/max_execution_time = 300/' "$PHP_INI"
    
    echo "Restarting PHP-FPM..."
    systemctl restart php8.3-fpm
    
    echo "PHP configured for Nextcloud."
else
    echo "Warning: PHP config file not found at $PHP_INI"
fi

# Save installation info
cat > /root/nextcloud-install-info.txt << EOL
Nextcloud Installation Info
===========================
Installation Date: $(date)
Install Directory: $INSTALL_DIR
Version: $(cat $INSTALL_DIR/version.php | grep OC_VersionString | cut -d"'" -f4 2>/dev/null || echo "Unknown")

Key Directories:
- Main: $INSTALL_DIR/
- Config: $INSTALL_DIR/config/
- Data: $INSTALL_DIR/data/ (will be created during setup)
- Apps: $INSTALL_DIR/apps/
- Encryption Classes: $INSTALL_DIR/lib/private/Encryption/

Files modified:
- $PHP_INI (backed up as $PHP_INI.backup.*)

Next Steps:
1. Run 04-nginx-config.sh to configure web server
2. Access https://your-server-ip to complete setup
3. Use database credentials from /root/nextcloud-db-credentials.txt
EOL

echo ""
echo "✓ Step 3 Complete!"
echo "Nextcloud installed to: $INSTALL_DIR"
echo "Version: $(cat $INSTALL_DIR/version.php | grep OC_VersionString | cut -d"'" -f4 2>/dev/null || echo "Unknown")"
echo "Install info saved to: /root/nextcloud-install-info.txt"
echo ""
echo "Directory structure:"
echo "├── $INSTALL_DIR/"
echo "├── $INSTALL_DIR/config/"
echo "├── $INSTALL_DIR/lib/private/Encryption/"
echo "└── $INSTALL_DIR/apps/"
echo ""
echo "Next: Run 04-nginx-config.sh"