#!/bin/bash

# Test password generation and retrieval

echo "=== Testing Password Generation and Retrieval ==="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check current params.yaml
echo "Current params.yaml passwords:"
echo "------------------------------"
echo "Nextcloud password: '$(sed -n '/^nextcloud:/,/^onlyoffice:/{/db_password:/p}' /etc/nextcloud-onlyoffice/params.yaml | cut -d'"' -f2)'"
echo "OnlyOffice password: '$(sed -n '/^onlyoffice:/,/^jwt:/{/db_password:/p}' /etc/nextcloud-onlyoffice/params.yaml | cut -d'"' -f2)'"
echo ""

# Test password generation
echo "Testing password generation..."
echo "------------------------------"

# Generate test passwords
test_nc_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
test_oo_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

echo "Generated test passwords:"
echo "  Nextcloud: $test_nc_password"
echo "  OnlyOffice: $test_oo_password"
echo ""

# Create a test YAML file
cat > /tmp/test_params.yaml << 'EOF'
deployment:
  base_domain: "test.com"
  nextcloud_domain: "docs.test.com"
  onlyoffice_domain: "office.test.com"
  admin_email: "admin@test.com"

nextcloud:
  db_name: "nextcloud"
  db_user: "ncuser"
  db_password: ""

onlyoffice:
  db_name: "onlyoffice"
  db_user: "oouser"
  db_password: ""

jwt:
  secret: ""
EOF

echo "Testing sed commands for updating passwords..."
echo "------------------------------"

# Test the fixed sed commands
sed -i "0,/db_password: \"\"/s//db_password: \"$test_nc_password\"/" /tmp/test_params.yaml
sed -i "/^onlyoffice:/,/^jwt:/ s/db_password: \"\"/db_password: \"$test_oo_password\"/" /tmp/test_params.yaml

# Verify the updates
echo "After sed commands:"
nc_pass_check=$(sed -n '/^nextcloud:/,/^onlyoffice:/{/db_password:/p}' /tmp/test_params.yaml | cut -d'"' -f2)
oo_pass_check=$(sed -n '/^onlyoffice:/,/^jwt:/{/db_password:/p}' /tmp/test_params.yaml | cut -d'"' -f2)

if [[ "$nc_pass_check" == "$test_nc_password" ]]; then
    echo -e "${GREEN}✓${NC} Nextcloud password updated correctly"
else
    echo -e "${RED}✗${NC} Nextcloud password update failed"
    echo "  Expected: $test_nc_password"
    echo "  Got: $nc_pass_check"
fi

if [[ "$oo_pass_check" == "$test_oo_password" ]]; then
    echo -e "${GREEN}✓${NC} OnlyOffice password updated correctly"
else
    echo -e "${RED}✗${NC} OnlyOffice password update failed"
    echo "  Expected: $test_oo_password"
    echo "  Got: $oo_pass_check"
fi

echo ""
echo "Test YAML file content:"
echo "------------------------------"
cat /tmp/test_params.yaml

# Cleanup
rm -f /tmp/test_params.yaml

echo ""
echo -e "${YELLOW}To fix the actual params.yaml file, you can run:${NC}"
echo "sudo /srv/collab/src/01_system_prep_dual_domain.sh"
echo "Or manually run the generate_secrets function from that script"
