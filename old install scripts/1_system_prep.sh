#!/bin/bash

# Step 1: System Preparation and Basic Packages
# Installs MariaDB for Nextcloud + PostgreSQL for OnlyOffice

set -e

echo "=== Step 1: System Preparation ==="
echo "This installs: nginx, MariaDB, PostgreSQL, PHP, basic tools"
echo "Dual database setup: MariaDB for Nextcloud, PostgreSQL for OnlyOffice"
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
    php8.3-fmp \
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
echo "Step 1 Complete!"
echo "Installed packages:"
echo "  MariaDB (for Nextcloud)"
echo "  PostgreSQL (for OnlyOffice)"
echo "  Nginx, PHP, and supporting tools"
echo ""
echo "Services enabled but not configured."
echo ""
echo "Next: Run 2_database.sh"