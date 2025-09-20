#!/bin/bash

# Quick fix script to generate and set database passwords

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== Fixing Database Passwords ==="
echo ""

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

# Check if params.yaml exists
if [[ ! -f "/etc/nextcloud-onlyoffice/params.yaml" ]]; then
    echo "Error: Configuration file not found at /etc/nextcloud-onlyoffice/params.yaml"
    exit 1
fi

# Backup the current file
cp /etc/nextcloud-onlyoffice/params.yaml /etc/nextcloud-onlyoffice/params.yaml.backup
echo "Backed up current params.yaml to params.yaml.backup"

# Generate passwords
nc_db_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
oo_db_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
jwt_secret=$(openssl rand -base64 64 | tr -d "=+/" | cut -c1-40)

echo "Generated new passwords:"
echo "  Nextcloud DB: $nc_db_password"
echo "  OnlyOffice DB: $oo_db_password"
echo "  JWT Secret: ${jwt_secret:0:20}..."

# Update configuration file with proper YAML structure
# Update Nextcloud password (first occurrence)
sed -i "0,/db_password: \"\"/s//db_password: \"$nc_db_password\"/" /etc/nextcloud-onlyoffice/params.yaml

# Update OnlyOffice password (second occurrence) 
sed -i "/^onlyoffice:/,/^jwt:/ s/db_password: \"\"/db_password: \"$oo_db_password\"/" /etc/nextcloud-onlyoffice/params.yaml

# Update JWT secret
sed -i "s/secret: \"\"/secret: \"$jwt_secret\"/" /etc/nextcloud-onlyoffice/params.yaml

echo ""
echo -e "${GREEN}✓${NC} Passwords updated in /etc/nextcloud-onlyoffice/params.yaml"

# Verify the updates
echo ""
echo "Verification:"
nc_check=$(sed -n '/^nextcloud:/,/^onlyoffice:/{/db_password:/p}' /etc/nextcloud-onlyoffice/params.yaml | cut -d'"' -f2)
oo_check=$(sed -n '/^onlyoffice:/,/^jwt:/{/db_password:/p}' /etc/nextcloud-onlyoffice/params.yaml | cut -d'"' -f2)
jwt_check=$(grep "secret:" /etc/nextcloud-onlyoffice/params.yaml | cut -d'"' -f2)

if [[ -n "$nc_check" ]]; then
    echo -e "${GREEN}✓${NC} Nextcloud password set"
else
    echo -e "${YELLOW}⚠${NC} Nextcloud password may not be set correctly"
fi

if [[ -n "$oo_check" ]]; then
    echo -e "${GREEN}✓${NC} OnlyOffice password set"
else
    echo -e "${YELLOW}⚠${NC} OnlyOffice password may not be set correctly"
fi

if [[ -n "$jwt_check" ]]; then
    echo -e "${GREEN}✓${NC} JWT secret set"
else
    echo -e "${YELLOW}⚠${NC} JWT secret may not be set correctly"
fi

echo ""
echo "You can now run:"
echo "  sudo /srv/collab/src/02_database_setup_dual_domain.sh"
echo ""
echo "The script should run without password prompts."
