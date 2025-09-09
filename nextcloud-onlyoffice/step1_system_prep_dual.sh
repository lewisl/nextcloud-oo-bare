#!/bin/bash

# Step 1: System Preparation with Dual Database Support
# Installs nginx, MariaDB, PostgreSQL, PHP, and basic tools

set -e

echo "=== Step 1: System Preparation (Dual Database) ==="
echo "This installs: nginx, mariadb, postgresql, PHP, basic tools"
echo "No configuration changes, just package installation"
echo ""

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

echo "Updating package lists..."
apt update

echo "Installing core packages..."
apt install -y \
    nginx \
    mariadb-server \
    postgresql \
    postgresql-contrib \
    php8.3-fpm \
    php8.3-mysql \
    php8.3-pgsql \
    php8.3-xml \
    php8.3-gd \
    php8.3-curl \
    php8.3-mbstring \
    php8.3-intl \
    php8.3-bcmath \
    php8.3-zip \
    php8.3-bz2 \
    unzip \
    wget \
    curl \
    ssl-cert

echo "Enabling services (but not starting/configuring yet)..."
systemctl enable nginx mariadb postgresql php8.3-fpm

echo ""
echo "✓ Step 1 Complete!"
echo "Installed packages with BOTH MariaDB and PostgreSQL"
echo "Services enabled but not configured."
echo ""
echo "Database support:"
echo "- MariaDB: For Nextcloud"
echo "- PostgreSQL: For OnlyOffice"
echo "- PHP extensions: mysql + pgsql"
echo ""
echo "Next: Run step2_database_dual.sh"