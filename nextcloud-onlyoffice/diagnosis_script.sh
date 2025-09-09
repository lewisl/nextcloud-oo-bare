#!/bin/bash

# Installation Diagnosis Script
# Run this to check system status and diagnose issues

echo "=== Nextcloud Installation Diagnosis ==="
echo "Date: $(date)"
echo "User: $(whoami)"
echo "System: $(uname -a)"
echo ""

echo "=== Step 1: System Packages Check ==="
echo "Checking if required packages are installed..."

packages=("nginx" "mariadb-server" "php8.3-fpm" "php8.3-mysql" "curl" "wget" "unzip")
for package in "${packages[@]}"; do
    if dpkg -l | grep -q "^ii  $package "; then
        echo "✓ $package: Installed"
    else
        echo "✗ $package: NOT INSTALLED"
    fi
done

echo ""
echo "=== Step 2: Services Status Check ==="
services=("nginx" "mariadb" "php8.3-fpm")
for service in "${services[@]}"; do
    if systemctl is-active --quiet "$service"; then
        echo "✓ $service: Running"
    elif systemctl is-enabled --quiet "$service"; then
        echo "⚠ $service: Enabled but not running"
    else
        echo "✗ $service: Not running and not enabled"
    fi
done

echo ""
echo "=== Step 3: MariaDB Specific Checks ==="
if command -v mysql &> /dev/null; then
    echo "✓ MySQL client available"
    
    echo "MariaDB version: $(mysql --version)"
    
    echo "Testing MariaDB root connection..."
    if mysql -u root -e "SELECT 'Root connection works' AS status;" 2>/dev/null; then
        echo "✓ Root connection: Working (no password)"
    elif mysql -u root -p"" -e "SELECT 'Root connection works' AS status;" 2>/dev/null; then
        echo "✓ Root connection: Working (empty password)"
    else
        echo "⚠ Root connection: Requires password or failing"
        echo "This might be normal if MariaDB was previously secured"
    fi
    
    echo "MariaDB service status:"
    systemctl status mariadb --no-pager -l | head -10
    
    echo ""
    echo "MariaDB process check:"
    ps aux | grep -i mysql | grep -v grep || echo "No MariaDB processes found"
    
    echo ""
    echo "MariaDB socket check:"
    if [ -S /var/run/mysqld/mysqld.sock ]; then
        echo "✓ MariaDB socket exists: /var/run/mysqld/mysqld.sock"
        ls -la /var/run/mysqld/mysqld.sock
    else
        echo "✗ MariaDB socket not found"
        ls -la /var/run/mysqld/ 2>/dev/null || echo "Socket directory doesn't exist"
    fi
    
    echo ""
    echo "MariaDB port check:"
    if netstat -tlnp | grep -q ":3306"; then
        echo "✓ MariaDB listening on port 3306:"
        netstat -tlnp | grep ":3306"
    else
        echo "✗ MariaDB not listening on port 3306"
    fi
    
else
    echo "✗ MySQL client not available"
fi

echo ""
echo "=== Step 4: File System Checks ==="
echo "Checking key directories and files..."

# Check if previous installation attempts left files
if [ -d "/var/www/nextcloud" ]; then
    echo "⚠ /var/www/nextcloud exists (previous installation?)"
    ls -la /var/www/nextcloud/ | head -5
else
    echo "✓ /var/www/nextcloud: Clean (not present)"
fi

# Check nginx config
if [ -f "/etc/nginx/sites-available/nextcloud" ]; then
    echo "⚠ Nginx nextcloud config exists"
else
    echo "✓ Nginx nextcloud config: Clean (not present)"
fi

# Check for credential files
if [ -f "/root/nextcloud-db-credentials.txt" ]; then
    echo "⚠ Database credentials file exists:"
    echo "  Created: $(stat -c %y /root/nextcloud-db-credentials.txt)"
    if grep -q "Password:" /root/nextcloud-db-credentials.txt; then
        echo "  Contains password information"
    fi
else
    echo "✓ No previous credential files"
fi

echo ""
echo "=== Step 5: Network & Connectivity ==="
echo "Server IP: $(curl -s ifconfig.me 2>/dev/null || echo "Unable to detect")"
echo ""
echo "Port status:"
netstat -tlnp | grep -E ":80|:443|:3306" || echo "No web or database services listening"

echo ""
echo "=== Step 6: Recent Logs ==="
echo "Recent MariaDB logs:"
journalctl -u mariadb -n 10 --no-pager 2>/dev/null || echo "No MariaDB logs available"

echo ""
echo "Recent system errors:"
journalctl -p err -n 5 --no-pager 2>/dev/null || echo "No recent errors found"

echo ""
echo "=== Step 7: Disk Space ==="
df -h / /var /tmp

echo ""
echo "=== Step 8: Memory Usage ==="
free -h

echo ""
echo "=== Diagnosis Complete ==="
echo ""
echo "Common issues and solutions:"
echo "1. If MariaDB isn't running: sudo systemctl start mariadb"
echo "2. If packages missing: sudo apt update && sudo apt install [package]"
echo "3. If permission denied: Make sure you're running as root (sudo)"
echo "4. If MariaDB root access fails: Try 'sudo mysql' instead of 'mysql'"
echo "5. If disk full: Clean up space in / or /var partitions"
echo ""
echo "Next steps:"
echo "- Fix any ✗ issues shown above"
echo "- Re-run the failing step"
echo "- If step 2 still fails, check MariaDB logs: journalctl -u mariadb -f"