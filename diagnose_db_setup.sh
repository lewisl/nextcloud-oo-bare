#!/bin/bash

# Diagnostic script for database setup issues

echo "=== Database Setup Diagnostics ==="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root (use sudo)${NC}" 
   exit 1
fi

echo "1. Checking MariaDB status..."
if systemctl is-active --quiet mariadb; then
    echo -e "${GREEN}✓${NC} MariaDB is running"
else
    echo -e "${RED}✗${NC} MariaDB is not running"
fi

echo ""
echo "2. Checking PostgreSQL status..."
if systemctl is-active --quiet postgresql; then
    echo -e "${GREEN}✓${NC} PostgreSQL is running"
    # Check PostgreSQL version
    sudo -u postgres psql --version
else
    echo -e "${RED}✗${NC} PostgreSQL is not running"
    echo "   Checking if PostgreSQL is installed..."
    if command -v psql &> /dev/null; then
        echo "   PostgreSQL is installed but not running"
        echo "   Trying to start it..."
        systemctl start postgresql
        if systemctl is-active --quiet postgresql; then
            echo -e "   ${GREEN}✓${NC} PostgreSQL started successfully"
        else
            echo -e "   ${RED}✗${NC} Failed to start PostgreSQL"
            echo "   Checking status:"
            systemctl status postgresql --no-pager
        fi
    else
        echo -e "   ${RED}✗${NC} PostgreSQL is not installed"
    fi
fi

echo ""
echo "3. Checking params.yaml configuration..."
if [[ -f "/etc/nextcloud-onlyoffice/params.yaml" ]]; then
    echo -e "${GREEN}✓${NC} Configuration file exists"
    
    # Check passwords
    NC_PASS=$(sed -n '/^nextcloud:/,/^onlyoffice:/{/db_password:/p}' /etc/nextcloud-onlyoffice/params.yaml | cut -d'"' -f2)
    OO_PASS=$(sed -n '/^onlyoffice:/,/^jwt:/{/db_password:/p}' /etc/nextcloud-onlyoffice/params.yaml | cut -d'"' -f2)
    
    if [[ -n "$NC_PASS" ]]; then
        echo -e "${GREEN}✓${NC} Nextcloud password is set (length: ${#NC_PASS})"
    else
        echo -e "${RED}✗${NC} Nextcloud password is empty"
    fi
    
    if [[ -n "$OO_PASS" ]]; then
        echo -e "${GREEN}✓${NC} OnlyOffice password is set (length: ${#OO_PASS})"
    else
        echo -e "${RED}✗${NC} OnlyOffice password is empty"
    fi
else
    echo -e "${RED}✗${NC} Configuration file not found"
fi

echo ""
echo "4. Testing MariaDB root access..."
if mysql -u root -e "SELECT 1;" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} MariaDB root access works without password"
else
    echo -e "${RED}✗${NC} MariaDB root access failed"
fi

echo ""
echo "5. Testing PostgreSQL access..."
if sudo -u postgres psql -c "SELECT 1;" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} PostgreSQL postgres user access works"
else
    echo -e "${RED}✗${NC} PostgreSQL postgres user access failed"
fi

echo ""
echo "6. Checking existing databases..."
echo "   MariaDB databases:"
mysql -u root -e "SHOW DATABASES;" 2>/dev/null | grep -E "(nextcloud|ncdb)" || echo "   No Nextcloud database found"

echo ""
echo "   PostgreSQL databases:"
sudo -u postgres psql -l 2>/dev/null | grep -E "(onlyoffice|oodb)" || echo "   No OnlyOffice database found"

echo ""
echo "7. Checking for error conditions that might stop the script..."
echo "   Script uses 'set -euo pipefail' which means it will exit on:"
echo "   - Any command that returns non-zero status"
echo "   - Use of undefined variables"
echo "   - Pipeline failures"

echo ""
echo -e "${YELLOW}Recommendations:${NC}"
echo "1. If passwords are empty, run: sudo /srv/collab/fix_passwords.sh"
echo "2. If PostgreSQL is not running, check: sudo journalctl -u postgresql -n 50"
echo "3. Run the script with debug output: bash -x /srv/collab/src/02_database_setup_dual_domain.sh"
echo "4. Or add 'set -x' after the shebang in the script for verbose output"
