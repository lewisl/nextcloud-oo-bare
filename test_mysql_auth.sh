#!/bin/bash

# Test MariaDB authentication

echo "Testing MariaDB root authentication..."

# Test 1: Try without specifying user (this likely causes the password prompt)
echo "Test 1: mysql -e \"SELECT 1;\""
mysql -e "SELECT 1;" 2>&1 && echo "SUCCESS: No password needed" || echo "FAILED: Password required"

echo ""

# Test 2: Try with -u root
echo "Test 2: mysql -u root -e \"SELECT 1;\""
mysql -u root -e "SELECT 1;" 2>&1 && echo "SUCCESS: Root access works" || echo "FAILED: Root access failed"

echo ""

# Test 3: Check current root user configuration
echo "Test 3: Checking root user configuration in mysql.user table:"
mysql -u root -e "SELECT User, Host, plugin, authentication_string FROM mysql.user WHERE User='root';" 2>&1

echo ""
echo "If Test 1 fails but Test 2 succeeds, the issue is that mysql needs -u root specified."
echo "If both fail, there's an authentication issue with the root user."
