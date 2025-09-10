# Quick Start Guide

Get Nextcloud + OnlyOffice running in under 30 minutes!

## Prerequisites Checklist

Before starting, ensure you have:

- [ ] **Fresh Ubuntu 20.04+ or Debian 11+ server**
- [ ] **Root access** (sudo privileges)
- [ ] **Domain name** pointing to your server's IP
- [ ] **Email address** for SSL certificates
- [ ] **Minimum 4GB RAM, 2 CPU cores, 20GB storage**

## Step 1: Prepare Your Server

### Update the system
```bash
sudo apt update && sudo apt upgrade -y
```

### Download the installation scripts
```bash
# Option A: If you have git
git clone <repository-url> /opt/nextcloud-install

# Option B: Download and extract
wget <archive-url> -O nextcloud-install.tar.gz
tar -xzf nextcloud-install.tar.gz
mv nextcloud-install* /opt/nextcloud-install
```

### Make scripts executable
```bash
cd /opt/nextcloud-install
chmod +x src/*.sh
```

## Step 2: Run the Installation

### Start the master installation script
```bash
sudo ./src/00_master_install.sh
```

### Follow the prompts
The script will ask for:
1. **Domain name** (e.g., `cloud.example.com`)
2. **Email address** (for SSL certificates)
3. **Confirmation** to proceed

### Wait for completion
The installation takes 15-30 minutes depending on your server speed and internet connection.

## Step 3: Access Your Installation

### Login to Nextcloud
1. Open your browser and go to `https://yourdomain.com/`
2. Use the admin credentials from `/root/nextcloud-admin-credentials.txt`
3. Complete the initial setup wizard

### Test OnlyOffice Integration
1. Navigate to the "OnlyOffice_Test" folder
2. Click on "Test_Document.docx"
3. The document should open in the OnlyOffice editor
4. Make some changes and save to verify everything works

## What Gets Installed

### Services
- **Nginx** - Web server and reverse proxy
- **PHP 8.3-FPM** - PHP processor for Nextcloud
- **MariaDB** - Database for Nextcloud
- **PostgreSQL** - Database for OnlyOffice
- **Redis** - Caching service
- **OnlyOffice Document Server** - Document editing service

### Security
- **UFW Firewall** - Only allows HTTP, HTTPS, and SSH
- **Fail2ban** - Protects against brute force attacks
- **SSL/TLS** - Let's Encrypt certificates with auto-renewal
- **Security Headers** - XSS protection, HSTS, etc.

### URLs
- **Nextcloud**: `https://yourdomain.com/`
- **OnlyOffice**: `https://yourdomain.com/onlyoffice/`
- **Admin Panel**: Login at `https://yourdomain.com/login`

## Important Files

After installation, these files contain crucial information:

```bash
# Admin credentials
cat /root/nextcloud-admin-credentials.txt

# Database credentials
cat /root/nextcloud-db-credentials.txt

# OnlyOffice JWT secret
cat /root/onlyoffice-jwt-secret.txt

# Complete installation report
cat /root/nextcloud-installation-report.txt
```

## Quick Health Check

Run the diagnostic script to verify everything is working:

```bash
sudo ./src/99_diagnostics.sh
```

This will check:
- ✅ All services are running
- ✅ SSL certificates are valid
- ✅ Integration is working
- ✅ No recent errors

## Common First Steps

### 1. Create Additional Users
```bash
# Via command line
sudo -u www-data php /var/www/nextcloud/occ user:add username

# Or via web interface
# Go to Settings → Users → Add User
```

### 2. Configure Email
```bash
# Set up SMTP for notifications
sudo -u www-data php /var/www/nextcloud/occ config:app:set settings mail_domain --value="yourdomain.com"
sudo -u www-data php /var/www/nextcloud/occ config:app:set settings mail_from_address --value="noreply"
sudo -u www-data php /var/www/nextcloud/occ config:app:set settings mail_smtpmode --value="smtp"
```

### 3. Enable Additional Apps
```bash
# Enable useful apps
sudo -u www-data php /var/www/nextcloud/occ app:enable calendar
sudo -u www-data php /var/www/nextcloud/occ app:enable contacts
sudo -u www-data php /var/www/nextcloud/occ app:enable tasks
```

### 4. Set Up Backups
```bash
# Create backup script
cat > /root/backup-nextcloud.sh << 'EOF'
#!/bin/bash
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/root/backups"
mkdir -p "$BACKUP_DIR"

# Backup database
mysqldump nextcloud > "$BACKUP_DIR/nextcloud-db-$DATE.sql"

# Backup files (excluding data directory - too large)
tar -czf "$BACKUP_DIR/nextcloud-config-$DATE.tar.gz" /var/www/nextcloud/config/

echo "Backup completed: $BACKUP_DIR/nextcloud-*-$DATE.*"
EOF

chmod +x /root/backup-nextcloud.sh

# Add to cron for daily backups
echo "0 2 * * * /root/backup-nextcloud.sh" | crontab -
```

## Troubleshooting Quick Fixes

### OnlyOffice Documents Won't Open
```bash
# Check OnlyOffice service
sudo systemctl status onlyoffice-documentserver

# Restart if needed
sudo systemctl restart onlyoffice-documentserver

# Check healthcheck
curl http://127.0.0.1:8080/healthcheck
```

### SSL Certificate Issues
```bash
# Check certificate status
sudo certbot certificates

# Renew if needed
sudo certbot renew

# Test renewal
sudo certbot renew --dry-run
```

### Performance Issues
```bash
# Check memory usage
free -h

# Check disk space
df -h

# Optimize database
sudo -u www-data php /var/www/nextcloud/occ db:add-missing-indices
sudo -u www-data php /var/www/nextcloud/occ db:convert-filecache-bigint
```

### Reset Admin Password
```bash
# Reset admin password
sudo -u www-data php /var/www/nextcloud/occ user:resetpassword admin
```

## Next Steps

### Security Hardening
1. **Change default passwords** for all accounts
2. **Enable two-factor authentication** for admin accounts
3. **Review firewall rules** and close unnecessary ports
4. **Set up monitoring** for system resources and logs

### Customization
1. **Configure themes** and branding
2. **Install additional apps** from the Nextcloud app store
3. **Set up external storage** if needed
4. **Configure LDAP/AD integration** for enterprise environments

### Maintenance
1. **Set up automated backups** for data and databases
2. **Configure log rotation** to prevent disk space issues
3. **Plan for updates** - both Nextcloud and OnlyOffice
4. **Monitor SSL certificate expiration** (auto-renewal should handle this)

## Getting Help

If you encounter issues:

1. **Run diagnostics**: `sudo ./src/99_diagnostics.sh`
2. **Check logs**: `tail -f /var/log/nextcloud-install.log`
3. **Review the full documentation**: `docs/README.md`
4. **Check service status**: `sudo systemctl status nginx php*-fpm mariadb postgresql redis-server onlyoffice-documentserver`

## Success! 🎉

You now have a fully functional Nextcloud + OnlyOffice installation with:
- ✅ Secure HTTPS access
- ✅ Document editing capabilities
- ✅ Automated backups and maintenance
- ✅ Production-ready security configuration

Your installation is ready for production use!
