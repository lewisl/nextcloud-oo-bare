# Nextcloud + OnlyOffice Deployment Guide

## Overview

This repository contains scripts for deploying Nextcloud with OnlyOffice Document Server on a bare metal Ubuntu server. The scripts are designed to be run individually for better control and reliability.

## Prerequisites

### Server Requirements
- Ubuntu 22.04 LTS or later
- Minimum 4GB RAM, 8GB recommended
- 20GB+ available disk space
- Root access or sudo privileges

### Domain Requirements
- A registered domain name
- DNS A records pointing to your server's IPv4 address
- If using Cloudflare: Ensure proxy is enabled and SSL/TLS mode is set appropriately

### Required Information
Before starting, gather:
- **Domain name**: e.g., `cloud.example.com`
- **Email address**: For Let's Encrypt SSL certificates
- **Server IPv4 address**: Your server's public IP

## Installation Process

### Step 1: System Preparation
```bash
./01_system_prep.sh
```
**What it does:**
- Updates system packages
- Installs nginx, PHP 8.3 with all required modules
- Installs MariaDB and PostgreSQL
- Configures Redis, Fail2ban, UFW firewall
- Verifies all PHP modules are loaded

**Verification:**
- All services should be running: `nginx`, `mariadb`, `postgresql`, `redis-server`
- PHP modules verified: `posix`, `SimpleXML`, `mysqli`, etc.

### Step 2: Database Setup
```bash
./02_database_setup.sh
```
**What it does:**
- Secures MariaDB installation
- Creates `nextcloud` database and user
- Creates `onlyoffice` PostgreSQL database and user
- Generates secure passwords
- Saves credentials to `/root/nextcloud-db-credentials.txt` and `/root/onlyoffice-db-credentials.txt`

**Verification:**
- Databases exist: `SHOW DATABASES;` (MariaDB), `\l` (PostgreSQL)
- Connection tests pass

### Step 3: Nextcloud Installation
```bash
./03_nextcloud_install.sh
```
**What it does:**
- Downloads latest Nextcloud
- Installs via command line
- Configures database connection
- Sets up Redis caching
- Creates admin account with secure password
- Saves credentials to `/root/nextcloud-admin-credentials.txt`

**Verification:**
- Nextcloud files in `/var/www/nextcloud`
- Admin credentials saved
- Database connection working

### Step 4: Basic Nginx Configuration
**Manual step** - Create basic HTTP configuration:
```bash
# Create nginx config for your domain
cat > /etc/nginx/sites-available/yourdomain.com << 'EOF'
server {
    listen 80;
    server_name yourdomain.com www.yourdomain.com;
    
    root /var/www/nextcloud;
    index index.php index.html;
    
    client_max_body_size 512M;
    fastcgi_buffers 64 4K;
    
    location /.well-known/acme-challenge { }
    
    location / {
        try_files $uri $uri/ /index.php$request_uri;
    }
    
    location ~ ^\/(?:build|tests|config|lib|3rdparty|templates|data)\/ {
        deny all;
    }
    
    location ~ ^\/(?:\.|autotest|occ|issue|indie|db_|console) {
        deny all;
    }
    
    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.*)$;
        try_files $fastcgi_script_name =404;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
    }
}
EOF

# Enable site
ln -sf /etc/nginx/sites-available/yourdomain.com /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx
```

**Update Nextcloud trusted domains:**
```bash
cd /var/www/nextcloud
sudo -u www-data php occ config:system:set trusted_domains 0 --value='yourdomain.com'
sudo -u www-data php occ config:system:set trusted_domains 1 --value='www.yourdomain.com'
sudo -u www-data php occ config:system:set overwrite.cli.url --value='https://yourdomain.com/'
```

### Step 5: SSL Certificate Setup
```bash
./06_ssl_setup.sh your-email@domain.com yourdomain.com
```
**What it does:**
- Installs certbot
- Obtains Let's Encrypt SSL certificate
- Updates nginx configuration for HTTPS
- Sets up automatic renewal
- Configures security headers

**Parameters:**
- `your-email@domain.com`: Email for Let's Encrypt notifications
- `yourdomain.com`: Your domain name

**Cloudflare Users:**
- Ensure your domain's DNS records point to your server
- Cloudflare proxy (orange cloud) can remain enabled
- Set Cloudflare SSL/TLS mode to "Full (strict)" after SSL setup

**Verification:**
- Certificate files in `/etc/letsencrypt/live/yourdomain.com/`
- HTTPS access working: `https://yourdomain.com/`
- SSL test passes

### Step 6: OnlyOffice Document Server (Optional)
```bash
./04_onlyoffice_install.sh
```
**What it does:**
- Installs OnlyOffice Document Server
- Configures PostgreSQL connection
- Starts OnlyOffice services
- Runs on port 8000 (localhost only)

**Verification:**
- Services running: `ds-docservice`, `ds-converter`, `ds-metrics`
- Health check: `curl http://localhost:8000/healthcheck`

### Step 7: Integration Configuration (Optional)
```bash
./07_integration_config.sh
```
**What it does:**
- Installs OnlyOffice app in Nextcloud
- Configures connection between Nextcloud and OnlyOffice
- Updates nginx to proxy OnlyOffice requests
- Tests integration

## Post-Installation

### Access Your Installation
- **URL**: `https://yourdomain.com/`
- **Admin credentials**: Check `/root/nextcloud-admin-credentials.txt`

### Important Files
- **Nextcloud admin credentials**: `/root/nextcloud-admin-credentials.txt`
- **Database credentials**: `/root/nextcloud-db-credentials.txt`, `/root/onlyoffice-db-credentials.txt`
- **SSL certificate info**: `/root/ssl-setup-summary.txt`
- **Installation logs**: `/var/log/nextcloud-install.log`

### Security Considerations
- Change default admin password after first login
- Review firewall rules: `ufw status`
- Monitor fail2ban: `fail2ban-client status`
- Keep system updated: `apt update && apt upgrade`

## Troubleshooting

### Common Issues

**1. SSL Certificate Fails with Cloudflare**
- Verify DNS records point to your server IP
- Check Cloudflare SSL/TLS mode
- Ensure `.well-known/acme-challenge` is accessible

**2. Nextcloud Shows "Trusted Domain" Error**
```bash
cd /var/www/nextcloud
sudo -u www-data php occ config:system:set trusted_domains 0 --value='yourdomain.com'
```

**3. OnlyOffice Connection Issues**
- Verify services: `systemctl status ds-docservice`
- Check logs: `journalctl -u ds-docservice`
- Test health: `curl http://localhost:8000/healthcheck`

**4. PHP Module Missing**
```bash
# Check loaded modules
php -m | grep module_name

# Install missing module
apt install php8.3-module-name
systemctl restart php8.3-fpm
```

### Log Files
- **Installation**: `/var/log/nextcloud-install.log`
- **Nginx**: `/var/log/nginx/error.log`
- **PHP**: `/var/log/php8.3-fpm.log`
- **OnlyOffice**: `journalctl -u ds-docservice`

## Script Parameters Reference

| Script | Parameters | Example |
|--------|------------|---------|
| `01_system_prep.sh` | None | `./01_system_prep.sh` |
| `02_database_setup.sh` | None | `./02_database_setup.sh` |
| `03_nextcloud_install.sh` | None | `./03_nextcloud_install.sh` |
| `04_onlyoffice_install.sh` | None | `./04_onlyoffice_install.sh` |
| `06_ssl_setup.sh` | `<email> <domain>` | `./06_ssl_setup.sh admin@example.com cloud.example.com` |
| `07_integration_config.sh` | None | `./07_integration_config.sh` |

## Development Notes

### Design Principles
- **Individual script execution**: Each script can be run independently
- **Parameter-based**: No auto-detection that requires external access
- **Verification built-in**: Each script verifies its own success
- **Idempotent**: Scripts can be re-run safely
- **Logging**: All actions logged to `/var/log/nextcloud-install.log`

### Testing
- Test each script individually before proceeding
- Verify services after each step
- Check log files for errors
- Test web access at each stage
