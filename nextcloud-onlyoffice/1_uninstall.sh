#!/bin/bash

# Uninstall Step 1: Remove System Packages (Updated for Dual Database)

set -e

echo "=== Uninstalling Step 1: System Packages ==="
echo "This will remove nginx, MariaDB, PostgreSQL, PHP and related packages"
echo ""

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

read -p "This will remove all installed packages. Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo "Stopping services..."
systemctl stop nginx mariadb postgresql php8.3-fpm 2>/dev/null || true

echo "Disabling services..."
systemctl disable nginx mariadb postgresql php8.3-fpm 2>/dev/null || true

echo "Removing packages..."
apt remove -y \
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
    ssl-cert

echo "Cleaning up configuration files..."
apt purge -y nginx mariadb-server postgresql postgresql-contrib php8.3-*

echo "Removing leftover directories..."
rm -rf /var/www/html
rm -rf /etc/nginx/sites-*
rm -rf /var/lib/mysql 2>/dev/null || true
rm -rf /var/lib/postgresql 2>/dev/null || true
rm -rf /etc/postgresql 2>/dev/null || true

echo "Running autoremove..."
apt autoremove -y

echo ""
echo "Step 1 packages removed!"
echo "System is back to clean state."