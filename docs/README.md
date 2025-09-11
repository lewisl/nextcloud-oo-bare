# Nextcloud + OnlyOffice Bare Metal Installation

A comprehensive toolkit for installing Nextcloud with OnlyOffice Document Server on bare metal servers without Docker or containers.

## Overview

This project provides automated installation scripts for deploying a production-ready Nextcloud instance with integrated OnlyOffice Document Server. The installation is designed to replicate the functionality of containerized solutions like Cloudron while providing direct access to the underlying PHP code for customization.

## Key Features

- **Bare Metal Installation**: No Docker, containers, or snap packages
- **Single Domain Setup**: Both Nextcloud and OnlyOffice served from one domain
- **Automated SSL**: Let's Encrypt certificates with automatic renewal
- **Security Hardened**: Firewall, fail2ban, security headers, and JWT authentication
- **Performance Optimized**: Redis caching, PHP OPcache, nginx optimization
- **Comprehensive Logging**: Detailed installation and diagnostic logs
- **Rollback Support**: Ability to undo installation if needed

## Architecture

```
Internet → Nginx (SSL Termination) → {
    / → Nextcloud (PHP-FPM)
    /onlyoffice/ → OnlyOffice Document Server (localhost:8080)
}

Databases:
- MariaDB (Nextcloud data)
- PostgreSQL (OnlyOffice data)
- Redis (Caching)
```

## Requirements

### System Requirements
- **OS**: Ubuntu 20.04+ or Debian 11+
- **RAM**: 4GB minimum, 8GB recommended
- **CPU**: 2 cores minimum, 4 cores recommended
- **Storage**: 20GB minimum, 100GB+ recommended
- **Network**: Public IP address with domain name

### Prerequisites
- Root access to the server
- Domain name pointing to the server
- Email address for SSL certificates
- Basic familiarity with Linux command line

## Quick Start

### 1. Download the Installation Scripts

```bash
# Clone or download the scripts to your server
git clone <repository-url> /opt/nextcloud-install
cd /opt/nextcloud-install
chmod +x src/*.sh
```

### 2. Run the Master Installation Script

```bash
sudo ./src/00_master_install.sh
```

The script will:
1. Prompt for your domain name and email
2. Install all required packages
3. Configure databases and services
4. Install Nextcloud and OnlyOffice
5. Configure nginx and SSL certificates
6. Set up the integration
7. Generate a comprehensive report

### 3. Access Your Installation

After successful installation:
- **Nextcloud**: `https://yourdomain.com/`
- **OnlyOffice**: `https://yourdomain.com/onlyoffice/`
- **Admin credentials**: Check `/root/nextcloud-admin-credentials.txt`

## Installation Scripts

### Core Installation Scripts

| Script | Purpose | Description |
|--------|---------|-------------|
| `00_master_install.sh` | Master orchestrator | Runs all installation steps in order |
| `01_system_prep.sh` | System preparation | Installs packages, configures firewall |
| `02_database_setup.sh` | Database configuration | Sets up MariaDB and PostgreSQL |
| `03_nextcloud_install.sh` | Nextcloud installation | Downloads and configures Nextcloud |
| `04_onlyoffice_install.sh` | OnlyOffice installation | Installs Document Server |
| `05_nginx_config.sh` | Web server setup | Configures nginx reverse proxy |
| `06_ssl_setup.sh` | SSL certificates | Sets up Let's Encrypt certificates |
| `07_integration_config.sh` | Integration setup | Connects Nextcloud with OnlyOffice |

### Utility Scripts

| Script | Purpose | Description |
|--------|---------|-------------|
| `99_diagnostics.sh` | System diagnostics | Health checks and troubleshooting |

## Manual Installation

If you prefer to run each step manually:

```bash
cd /opt/nextcloud-install/src

# Step 1: Prepare the system
sudo ./01_system_prep.sh

# Step 2: Configure databases
sudo ./02_database_setup.sh

# Step 3: Install Nextcloud
sudo ./03_nextcloud_install.sh

# Step 4: Install OnlyOffice
sudo ./04_onlyoffice_install.sh

# Step 5: Configure nginx
sudo ./05_nginx_config.sh

# Step 6: Set up SSL
sudo ./06_ssl_setup.sh

# Step 7: Configure integration
sudo ./07_integration_config.sh
```

## Configuration Files

### Important Locations

- **Nextcloud**: `/var/www/nextcloud/`
- **Nextcloud Data**: `/srv/nextcloud-data/`
- **Nextcloud Config**: `/var/www/nextcloud/config/config.php`
- **Nginx Config**: `/etc/nginx/sites-available/yourdomain.com`
- **OnlyOffice Config**: `/etc/onlyoffice/documentserver/local.json`
- **SSL Certificates**: `/etc/letsencrypt/live/yourdomain.com/`

### Credentials and Summaries

After installation, check these files for important information:
- `/root/nextcloud-admin-credentials.txt` - Admin login details
- `/root/nextcloud-db-credentials.txt` - Database credentials
- `/root/onlyoffice-jwt-secret.txt` - JWT authentication secret
- `/root/nextcloud-installation-report.txt` - Complete installation summary

## Customization for Encryption

This installation provides direct access to Nextcloud's PHP code, enabling custom encryption implementations:

### Key Locations for Encryption Hooks

- **Encryption Classes**: `/var/www/nextcloud/lib/private/Encryption/`
- **File Handling**: `/var/www/nextcloud/lib/private/Files/`
- **OnlyOffice Integration**: `/var/www/nextcloud/apps/onlyoffice/`

### Example: Custom Key Management

```php
// Custom encryption key retrieval
// File: /var/www/nextcloud/lib/private/Encryption/Keys/Storage.php

public function getFileKey($path, $keyId, $encryptionModuleId) {
    // Custom logic to retrieve encryption keys from remote server
    $remoteKey = $this->fetchKeyFromRemoteServer($path, $keyId);
    return $remoteKey ?: parent::getFileKey($path, $keyId, $encryptionModuleId);
}
```

## Maintenance

### Regular Tasks

```bash
# Update Nextcloud
sudo -u www-data php /var/www/nextcloud/occ upgrade

# Renew SSL certificates (automatic via cron)
sudo certbot renew

# Check system health
sudo ./src/99_diagnostics.sh

# Backup databases
sudo mysqldump nextcloud > nextcloud-backup-$(date +%Y%m%d).sql
sudo -u postgres pg_dump onlyoffice > onlyoffice-backup-$(date +%Y%m%d).sql
```

### Service Management

```bash
# Restart all services
sudo systemctl restart nginx php*-fpm mariadb postgresql redis-server onlyoffice-documentserver

# Check service status
sudo systemctl status nginx php*-fpm mariadb postgresql redis-server onlyoffice-documentserver

# View logs
sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/nextcloud-install.log
sudo journalctl -u onlyoffice-documentserver -f
```

## Troubleshooting

### Common Issues

1. **OnlyOffice not loading documents**
   - Check JWT secret matches between Nextcloud and OnlyOffice
   - Verify OnlyOffice service is running: `systemctl status onlyoffice-documentserver`
   - Test healthcheck: `curl http://127.0.0.1:8080/healthcheck`

2. **SSL certificate issues**
   - Renew manually: `sudo certbot renew`
   - Check DNS resolution: `dig yourdomain.com`
   - Verify nginx configuration: `sudo nginx -t`

3. **Performance issues**
   - Check memory usage: `free -h`
   - Monitor disk space: `df -h`
   - Optimize database: `sudo -u www-data php /var/www/nextcloud/occ db:add-missing-indices`

### Diagnostic Tools

Run comprehensive diagnostics:
```bash
sudo ./src/99_diagnostics.sh
```

This will check:
- Service status
- Network connectivity
- SSL certificates
- Integration configuration
- File permissions
- Recent errors

## Security Considerations

### Implemented Security Features

- **Firewall**: UFW configured to allow only necessary ports
- **Fail2ban**: Protection against brute force attacks
- **SSL/TLS**: Strong cipher suites and HSTS headers
- **JWT Authentication**: Secure communication between Nextcloud and OnlyOffice
- **File Permissions**: Proper ownership and permissions for all files
- **Security Headers**: XSS protection, content type options, frame options

### Additional Security Recommendations

1. **Regular Updates**: Keep all packages updated
2. **Backup Strategy**: Implement regular automated backups
3. **Monitoring**: Set up log monitoring and alerting
4. **Access Control**: Use strong passwords and consider 2FA
5. **Network Security**: Consider VPN access for admin functions

## Support and Documentation

### Log Files
- **Installation**: `/var/log/nextcloud-install.log`
- **Nginx**: `/var/log/nginx/error.log`
- **Nextcloud**: `/var/www/nextcloud/data/nextcloud.log`
- **OnlyOffice**: `journalctl -u onlyoffice-documentserver`

### Official Documentation
- [Nextcloud Admin Manual](https://docs.nextcloud.com/server/latest/admin_manual/)
- [OnlyOffice Documentation](https://helpcenter.onlyoffice.com/)
- [Nginx Documentation](https://nginx.org/en/docs/)

### Getting Help

1. Check the diagnostic output: `sudo ./src/99_diagnostics.sh`
2. Review installation logs: `/var/log/nextcloud-install.log`
3. Consult the troubleshooting section above
4. Check official documentation for specific components

## License

This project is provided as-is for educational and deployment purposes. Please ensure compliance with the licenses of all included software components (Nextcloud, OnlyOffice, etc.).
