#!/bin/bash

# Step 1: System Preparation and Basic Packages
# Installs core system packages including both MariaDB and PostgreSQL

set -e

echo "=== Step 1: System Preparation ==="
echo "This installs: nginx, mariadb, postgresql, PHP, basic tools"
echo "MariaDB for Nextcloud, PostgreSQL for OnlyOffice"
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
echo "✅ Step 1 Complete!"
echo "Installed packages including both database systems:"
echo "- MariaDB: For Nextcloud"
echo "- PostgreSQL: For OnlyOffice Document Server"
echo "Services enabled but not configured."
echo ""
echo "Next: Run step2_database_setup.sh"