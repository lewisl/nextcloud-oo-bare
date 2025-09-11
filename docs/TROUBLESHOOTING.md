# Troubleshooting Guide

Common issues and their solutions for Nextcloud + OnlyOffice bare metal installation.

## Quick Diagnostic

Always start with the diagnostic script:
```bash
sudo ./src/99_diagnostics.sh
```

This will identify most common issues automatically.

## Installation Issues

### Installation Fails at System Preparation

**Symptoms**: Script fails during package installation
```bash
# Check available disk space
df -h

# Check memory
free -h

# Update package lists
sudo apt update

# Fix broken packages
sudo apt --fix-broken install

# Retry installation
sudo ./src/01_system_prep.sh
```

### Database Setup Fails

**Symptoms**: Cannot connect to database or user creation fails
```bash
# Check MariaDB status
sudo systemctl status mariadb

# Reset MariaDB root password
sudo mysql_secure_installation

# Check PostgreSQL status
sudo systemctl status postgresql

# Restart database services
sudo systemctl restart mariadb postgresql

# Retry database setup
sudo ./src/02_database_setup.sh
```

### SSL Certificate Acquisition Fails

**Symptoms**: Let's Encrypt certificate request fails

**Common Causes**:
1. Domain doesn't point to server
2. Firewall blocking port 80
3. Nginx not running

**Solutions**:
```bash
# Check DNS resolution
dig yourdomain.com

# Check if domain points to your server
curl -I http://yourdomain.com/

# Check firewall
sudo ufw status

# Ensure nginx is running
sudo systemctl start nginx

# Test HTTP access
curl -I http://yourdomain.com/

# Retry SSL setup
sudo ./src/06_ssl_setup.sh
```

## Service Issues

### Nginx Won't Start

**Check configuration**:
```bash
# Test nginx configuration
sudo nginx -t

# Check for port conflicts
sudo netstat -tuln | grep :80
sudo netstat -tuln | grep :443

# Check nginx logs
sudo tail -f /var/log/nginx/error.log

# Fix permissions
sudo chown -R www-data:www-data /var/www/nextcloud

# Restart nginx
sudo systemctl restart nginx
```

### PHP-FPM Issues

**Symptoms**: 502 Bad Gateway errors
```bash
# Check PHP-FPM status
sudo systemctl status php*-fpm

# Check PHP-FPM logs
sudo tail -f /var/log/php*-fpm.log

# Check socket permissions
ls -la /run/php/

# Restart PHP-FPM
sudo systemctl restart php*-fpm
```

### OnlyOffice Document Server Won't Start

**Check service status**:
```bash
# Check service status
sudo systemctl status onlyoffice-documentserver

# Check detailed logs
sudo journalctl -u onlyoffice-documentserver -f

# Check if port is available
sudo netstat -tuln | grep :8080

# Check PostgreSQL connection
sudo -u postgres psql -c "SELECT 1;"

# Restart OnlyOffice
sudo systemctl restart onlyoffice-documentserver

# Wait for startup (can take 30-60 seconds)
sleep 60

# Test healthcheck
curl http://127.0.0.1:8080/healthcheck
```

## Integration Issues

### OnlyOffice Documents Won't Open

**Symptoms**: Documents show error or don't load in editor

**Check JWT Configuration**:
```bash
# Get Nextcloud JWT secret
sudo -u www-data php /var/www/nextcloud/occ config:app:get onlyoffice jwt_secret

# Get OnlyOffice JWT secret
sudo cat /root/onlyoffice-jwt-secret.txt

# They should match - if not, update Nextcloud:
sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice jwt_secret --value="YOUR_JWT_SECRET"
```

**Check URLs**:
```bash
# Check configured URLs
sudo -u www-data php /var/www/nextcloud/occ config:app:get onlyoffice DocumentServerUrl
sudo -u www-data php /var/www/nextcloud/occ config:app:get onlyoffice DocumentServerInternalUrl

# Should be:
# DocumentServerUrl: https://yourdomain.com/onlyoffice/
# DocumentServerInternalUrl: http://127.0.0.1:8080/
```

**Test Connectivity**:
```bash
# Test external access
curl -I https://yourdomain.com/onlyoffice/healthcheck

# Test internal access
curl -I http://127.0.0.1:8080/healthcheck

# Both should return HTTP 200
```

### Documents Open But Can't Save

**Check file permissions**:
```bash
# Fix Nextcloud permissions
sudo chown -R www-data:www-data /var/www/nextcloud /srv/nextcloud-data
sudo find /var/www/nextcloud -type f -exec chmod 640 {} \;
sudo find /var/www/nextcloud -type d -exec chmod 750 {} \;
sudo find /srv/nextcloud-data -type f -exec chmod 640 {} \;
sudo find /srv/nextcloud-data -type d -exec chmod 750 {} \;

# Check disk space
df -h /srv/nextcloud-data
```

**Check Nextcloud logs**:
```bash
sudo tail -f /var/www/nextcloud/data/nextcloud.log
```

## Performance Issues

### Slow Document Loading

**Check system resources**:
```bash
# Check memory usage
free -h

# Check CPU usage
top

# Check disk I/O
iotop

# Check network connectivity
ping google.com
```

**Optimize OnlyOffice**:
```bash
# Increase OnlyOffice memory limits
sudo nano /etc/onlyoffice/documentserver/local.json

# Add or modify:
{
  "services": {
    "CoAuthoring": {
      "server": {
        "maxRequestSize": "100mb"
      }
    }
  }
}

# Restart OnlyOffice
sudo systemctl restart onlyoffice-documentserver
```

**Optimize Nextcloud**:
```bash
# Add missing database indices
sudo -u www-data php /var/www/nextcloud/occ db:add-missing-indices

# Convert to big int
sudo -u www-data php /var/www/nextcloud/occ db:convert-filecache-bigint

# Update htaccess
sudo -u www-data php /var/www/nextcloud/occ maintenance:update:htaccess
```

### High Memory Usage

**Check memory consumers**:
```bash
# Check process memory usage
ps aux --sort=-%mem | head -20

# Check OnlyOffice memory usage
sudo systemctl status onlyoffice-documentserver

# Restart services to free memory
sudo systemctl restart onlyoffice-documentserver nginx php*-fpm
```

## SSL/Certificate Issues

### Certificate Expired

```bash
# Check certificate status
sudo certbot certificates

# Renew certificates
sudo certbot renew

# If renewal fails, check DNS and HTTP access
dig yourdomain.com
curl -I http://yourdomain.com/

# Force renewal
sudo certbot renew --force-renewal
```

### Mixed Content Warnings

**Check nginx configuration**:
```bash
# Ensure all redirects use HTTPS
sudo nano /etc/nginx/sites-available/yourdomain.com

# Look for and fix any HTTP references
# Restart nginx
sudo systemctl restart nginx
```

## Database Issues

### Database Connection Errors

**Check MariaDB**:
```bash
# Test connection
mysql -u nextcloud -p

# Check database status
sudo systemctl status mariadb

# Check logs
sudo tail -f /var/log/mysql/error.log

# Restart if needed
sudo systemctl restart mariadb
```

**Check PostgreSQL**:
```bash
# Test connection
sudo -u postgres psql -d onlyoffice

# Check status
sudo systemctl status postgresql

# Restart if needed
sudo systemctl restart postgresql
```

### Database Corruption

**For MariaDB**:
```bash
# Check and repair tables
sudo mysqlcheck -u root -p --auto-repair --check --optimize nextcloud
```

**For PostgreSQL**:
```bash
# Check database integrity
sudo -u postgres psql -d onlyoffice -c "SELECT pg_database_size('onlyoffice');"
```

## Network Issues

### Firewall Blocking Connections

```bash
# Check UFW status
sudo ufw status verbose

# Allow necessary ports
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Check iptables
sudo iptables -L

# Reset UFW if needed
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 'Nginx Full'
sudo ufw enable
```

### DNS Resolution Issues

```bash
# Check DNS resolution
nslookup yourdomain.com
dig yourdomain.com

# Check /etc/hosts
cat /etc/hosts

# Test external connectivity
ping 8.8.8.8
curl -I google.com
```

## File Permission Issues

### Permission Denied Errors

```bash
# Reset all Nextcloud permissions
sudo chown -R www-data:www-data /var/www/nextcloud /srv/nextcloud-data

# Set correct file permissions
sudo find /var/www/nextcloud -type f -exec chmod 640 {} \;
sudo find /var/www/nextcloud -type d -exec chmod 750 {} \;

# Set correct data permissions
sudo find /srv/nextcloud-data -type f -exec chmod 640 {} \;
sudo find /srv/nextcloud-data -type d -exec chmod 750 {} \;

# Make occ executable
sudo chmod +x /var/www/nextcloud/occ

# Fix config permissions
sudo chmod 640 /var/www/nextcloud/config/config.php
```

## Log Analysis

### Key Log Locations

```bash
# Nextcloud logs
sudo tail -f /var/www/nextcloud/data/nextcloud.log

# Nginx logs
sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/nginx/access.log

# PHP-FPM logs
sudo tail -f /var/log/php*-fpm.log

# OnlyOffice logs
sudo journalctl -u onlyoffice-documentserver -f

# System logs
sudo journalctl -f

# Installation logs
sudo tail -f /var/log/nextcloud-install.log
```

### Common Error Patterns

**502 Bad Gateway**: PHP-FPM not running or socket issues
**504 Gateway Timeout**: OnlyOffice taking too long to respond
**SSL errors**: Certificate issues or mixed content
**Permission denied**: File ownership or permission issues
**Database errors**: Connection or authentication problems

## Recovery Procedures

### Complete Service Restart

```bash
# Stop all services
sudo systemctl stop nginx php*-fpm mariadb postgresql redis-server onlyoffice-documentserver

# Wait a moment
sleep 10

# Start services in order
sudo systemctl start mariadb postgresql redis-server
sleep 5
sudo systemctl start php*-fpm onlyoffice-documentserver
sleep 10
sudo systemctl start nginx

# Check all services
sudo systemctl status nginx php*-fpm mariadb postgresql redis-server onlyoffice-documentserver
```

### Reset to Known Good State

```bash
# Restore from backup (if available)
sudo systemctl stop nginx php*-fpm

# Restore Nextcloud config
sudo cp /var/www/nextcloud/config/config.php.backup /var/www/nextcloud/config/config.php

# Restore nginx config
sudo cp /etc/nginx/sites-available/yourdomain.com.backup /etc/nginx/sites-available/yourdomain.com

# Test and restart
sudo nginx -t
sudo systemctl start nginx php*-fpm
```

### Emergency Rollback

```bash
# Use the master script rollback feature
sudo ./src/00_master_install.sh --rollback
```

## Getting Additional Help

### Collect Diagnostic Information

```bash
# Run full diagnostics
sudo ./src/99_diagnostics.sh > diagnostic-report.txt

# Collect system information
sudo dmesg > dmesg.log
sudo journalctl --since "1 hour ago" > system.log

# Package the logs
tar -czf nextcloud-debug-$(date +%Y%m%d).tar.gz diagnostic-report.txt dmesg.log system.log /var/log/nextcloud-install.log
```

### Before Seeking Help

1. Run the diagnostic script
2. Check recent log entries
3. Verify DNS and network connectivity
4. Ensure adequate system resources
5. Try restarting services
6. Document exact error messages and steps to reproduce

This information will help others assist you more effectively.
