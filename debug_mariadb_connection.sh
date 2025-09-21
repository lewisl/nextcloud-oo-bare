#!/bin/bash

# Debug MariaDB connection issues

echo "=== MariaDB Connection Debug ==="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root (use sudo)${NC}" 
   exit 1
fi

# Load configuration like the main script does
if [[ ! -f "/etc/nextcloud-onlyoffice/params.yaml" ]]; then
    echo -e "${RED}Configuration file not found at /etc/nextcloud-onlyoffice/params.yaml${NC}"
    exit 1
fi

# Extract Nextcloud database values (same method as main script)
NC_DB_NAME=$(sed -n '/^nextcloud:/,/^onlyoffice:/{/db_name:/p}' /etc/nextcloud-onlyoffice/params.yaml | cut -d'"' -f2)
NC_DB_USER=$(sed -n '/^nextcloud:/,/^onlyoffice:/{/db_user:/p}' /etc/nextcloud-onlyoffice/params.yaml | cut -d'"' -f2)
NC_DB_PASSWORD=$(sed -n '/^nextcloud:/,/^onlyoffice:/{/db_password:/p}' /etc/nextcloud-onlyoffice/params.yaml | cut -d'"' -f2)

echo "Configuration loaded:"
echo "  Database: '$NC_DB_NAME'"
echo "  User: '$NC_DB_USER'"
echo "  Password length: ${#NC_DB_PASSWORD} characters"
echo ""

# Test 1: Check if MariaDB is running
echo "1. Checking MariaDB service..."
if systemctl is-active --quiet mariadb; then
    echo -e "${GREEN}✓${NC} MariaDB is running"
else
    echo -e "${RED}✗${NC} MariaDB is not running"
    exit 1
fi

# Test 2: Check root access
echo ""
echo "2. Testing root access..."
if mysql -u root -e "SELECT 1;" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Root access works"
else
    echo -e "${RED}✗${NC} Root access failed"
    exit 1
fi

# Test 3: Check if database exists
echo ""
echo "3. Checking if database '$NC_DB_NAME' exists..."
if mysql -u root -e "USE \`$NC_DB_NAME\`;" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Database '$NC_DB_NAME' exists"
else
    echo -e "${RED}✗${NC} Database '$NC_DB_NAME' does not exist"
    echo "Creating database..."
    mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`$NC_DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
    if mysql -u root -e "USE \`$NC_DB_NAME\`;" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Database created successfully"
    else
        echo -e "${RED}✗${NC} Failed to create database"
        exit 1
    fi
fi

# Test 4: Check if user exists
echo ""
echo "4. Checking if user '$NC_DB_USER' exists..."
if mysql -u root -e "SELECT User FROM mysql.user WHERE User='$NC_DB_USER';" | grep -q "$NC_DB_USER"; then
    echo -e "${GREEN}✓${NC} User '$NC_DB_USER' exists"
else
    echo -e "${RED}✗${NC} User '$NC_DB_USER' does not exist"
    echo "Creating user..."
    mysql -u root -e "CREATE USER '$NC_DB_USER'@'localhost' IDENTIFIED BY '$NC_DB_PASSWORD';"
    if mysql -u root -e "SELECT User FROM mysql.user WHERE User='$NC_DB_USER';" | grep -q "$NC_DB_USER"; then
        echo -e "${GREEN}✓${NC} User created successfully"
    else
        echo -e "${RED}✗${NC} Failed to create user"
        exit 1
    fi
fi

# Test 5: Check user privileges
echo ""
echo "5. Checking user privileges..."
mysql -u root -e "GRANT ALL PRIVILEGES ON \`$NC_DB_NAME\`.* TO '$NC_DB_USER'@'localhost';"
mysql -u root -e "FLUSH PRIVILEGES;"
echo -e "${GREEN}✓${NC} Privileges granted"

# Test 6: Test user connection with password
echo ""
echo "6. Testing user connection..."
echo "Command: mysql -u '$NC_DB_USER' -p'***' -e \"USE \\\`$NC_DB_NAME\\\`; SELECT 1;\""

if mysql -u "$NC_DB_USER" -p"$NC_DB_PASSWORD" -e "USE \`$NC_DB_NAME\`; SELECT 1;" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} User connection successful!"
else
    echo -e "${RED}✗${NC} User connection failed"
    
    # Try to debug further
    echo ""
    echo "Debugging connection failure..."
    
    # Check if password is correct by trying to change it
    echo "Resetting user password..."
    mysql -u root -e "ALTER USER '$NC_DB_USER'@'localhost' IDENTIFIED BY '$NC_DB_PASSWORD';"
    mysql -u root -e "FLUSH PRIVILEGES;"
    
    # Try connection again
    if mysql -u "$NC_DB_USER" -p"$NC_DB_PASSWORD" -e "USE \`$NC_DB_NAME\`; SELECT 1;" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Connection works after password reset"
    else
        echo -e "${RED}✗${NC} Connection still fails"
        
        # Show detailed error
        echo ""
        echo "Detailed error output:"
        mysql -u "$NC_DB_USER" -p"$NC_DB_PASSWORD" -e "USE \`$NC_DB_NAME\`; SELECT 1;" 2>&1 || true
        
        # Check user details
        echo ""
        echo "User details from mysql.user table:"
        mysql -u root -e "SELECT User, Host, plugin, authentication_string FROM mysql.user WHERE User='$NC_DB_USER';"
    fi
fi

echo ""
echo "=== Summary ==="
echo "If all tests pass, the MariaDB connection should work."
echo "If tests fail, check the error messages above."
