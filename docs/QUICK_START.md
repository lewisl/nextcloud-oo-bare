# Quick Start Guide

## Prerequisites Checklist

Before running any scripts, ensure you have:

- [ ] Ubuntu 22.04+ server with root access
- [ ] Domain name with DNS A records pointing to server IPv4
- [ ] Email address for SSL certificates
- [ ] Server IPv4 address (no IPv6)

## Required Information

Gather this information before starting:

```bash
# Your domain name
DOMAIN="cloud.example.com"

# Your email for Let's Encrypt
EMAIL="admin@example.com"

# Your server's IPv4 address
SERVER_IP="1.2.3.4"
```

## Installation Commands

Run these commands **in order** on your server:

### 1. System Setup
```bash
./01_system_prep.sh
```
**Time:** ~5 minutes  
**Verifies:** All services running, PHP modules loaded

### 2. Database Setup
```bash
./02_database_setup.sh
```
**Time:** ~2 minutes  
**Creates:** Database credentials in `/root/*-credentials.txt`

### 3. Nextcloud Installation
```bash
./03_nextcloud_install.sh
```
**Time:** ~3 minutes  
**Creates:** Admin credentials in `/root/nextcloud-admin-credentials.txt`

### 4. Nginx Configuration
**Manual step** - Replace `YOURDOMAIN.COM` with your actual domain:

```bash
# Create nginx config
cat > /etc/nginx/sites-available/YOURDOMAIN.COM << 'EOF'
server {
    listen 80;
    server_name YOURDOMAIN.COM www.YOURDOMAIN.COM;
    
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
ln -sf /etc/nginx/sites-available/YOURDOMAIN.COM /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# Update Nextcloud trusted domains
cd /var/www/nextcloud
sudo -u www-data php occ config:system:set trusted_domains 0 --value='YOURDOMAIN.COM'
sudo -u www-data php occ config:system:set trusted_domains 1 --value='www.YOURDOMAIN.COM'
sudo -u www-data php occ config:system:set overwrite.cli.url --value='https://YOURDOMAIN.COM/'
```

### 5. SSL Setup
**Replace with your actual email and domain:**
```bash
./06_ssl_setup.sh your-email@domain.com yourdomain.com
```
**Time:** ~2 minutes  
**Result:** HTTPS access enabled

### 6. Test Access
```bash
# Get admin credentials
cat /root/nextcloud-admin-credentials.txt

# Test HTTPS access
curl -I https://yourdomain.com/
```

## Optional: OnlyOffice Integration

### 7. Install OnlyOffice
```bash
./04_onlyoffice_install.sh
```
**Time:** ~5 minutes  
**Result:** Document server running on port 8000

### 8. Configure Integration
```bash
./07_integration_config.sh
```
**Time:** ~2 minutes  
**Result:** OnlyOffice integrated with Nextcloud

## Verification Checklist

After installation, verify:

- [ ] **HTTPS Access**: `https://yourdomain.com/` loads
- [ ] **Admin Login**: Use credentials from `/root/nextcloud-admin-credentials.txt`
- [ ] **SSL Certificate**: Valid and trusted
- [ ] **File Upload**: Test uploading a file
- [ ] **OnlyOffice** (if installed): Can edit documents

## Common Issues

### SSL Certificate Fails
```bash
# Check if domain resolves to your server
dig +short yourdomain.com

# Verify nginx is serving the domain
curl -H "Host: yourdomain.com" http://localhost/
```

### Trusted Domain Error
```bash
cd /var/www/nextcloud
sudo -u www-data php occ config:system:set trusted_domains 0 --value='yourdomain.com'
```

### Service Not Running
```bash
# Check all services
systemctl status nginx mariadb postgresql redis-server php8.3-fpm

# Restart if needed
systemctl restart service-name
```

## Important Files

| File | Purpose |
|------|---------|
| `/root/nextcloud-admin-credentials.txt` | Nextcloud admin login |
| `/root/nextcloud-db-credentials.txt` | Database credentials |
| `/root/ssl-setup-summary.txt` | SSL certificate info |
| `/var/log/nextcloud-install.log` | Installation logs |

## Security Notes

After installation:
1. **Change admin password** on first login
2. **Review firewall**: `ufw status`
3. **Check fail2ban**: `fail2ban-client status`
4. **Update system**: `apt update && apt upgrade`

## Support

- **Logs**: Check `/var/log/nextcloud-install.log`
- **Nginx errors**: `/var/log/nginx/error.log`
- **PHP errors**: `/var/log/php8.3-fpm.log`
- **Service status**: `systemctl status service-name`

For detailed information, see [DEPLOYMENT.md](DEPLOYMENT.md).
