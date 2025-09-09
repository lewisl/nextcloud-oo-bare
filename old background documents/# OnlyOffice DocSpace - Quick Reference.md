# OnlyOffice DocSpace - Quick Reference

## 🚀 Installation Quick Start

```bash
# 1. Fresh droplet setup
git clone https://github.com/your-repo/docspace-deploy.git
cd docspace-deploy
chmod +x *.sh
sudo ./onlyoffice-pre-install.sh --install-tools --setup-storage /dev/sda

# 2. Configure DNS (A records for domain and www pointing to server IP)

# 3. Install OnlyOffice via DO 1-Click Marketplace

# 4. Post-installation setup
sudo ./onlyoffice-post-install.sh admin@example.com example.com

# 5. Configure Cloudflare SSL to "Full (strict)"
```

## 🛠️ Essential Commands

### Service Management
```bash
onlyoffice-status              # Check all services
onlyoffice-health              # Health check
onlyoffice-start               # Start all services
onlyoffice-stop                # Stop all services
onlyoffice-restart             # Restart all services
```

### Troubleshooting
```bash
onlyoffice-health -v --fix     # Comprehensive check + auto-fix
onlyoffice-logs proxy          # View proxy logs
onlyoffice-logs mysql-server   # View database logs
onlyoffice-exec proxy nginx -t # Test nginx config
```

### Service Groups
```bash
onlyoffice-start infrastructure   # MySQL, Redis, etc.
onlyoffice-start api              # API services
onlyoffice-start frontend         # Web interface
onlyoffice-restart mysql-server   # Individual service
```

## 🔍 Common Issues & Fixes

### SSL Redirect Loop (`ERR_TOO_MANY_REDIRECTS`)
```bash
# Fix Cloudflare SSL mode
# Go to Cloudflare → SSL/TLS → Overview
# Set to "Full (strict)"

# Verify certificates
ls -la /etc/letsencrypt/live/docspace/
onlyoffice-exec proxy nginx -t
```

### Services Won't Start
```bash
onlyoffice-health -v           # Check what's failing
onlyoffice-logs mysql-server   # Check database
onlyoffice-restart --force     # Force restart
```

### Storage Issues
```bash
df -h /mnt/docspace_data       # Check disk space
mountpoint /mnt/docspace_data  # Verify mount
ls -la /mnt/docspace_data/     # Check permissions
```

### DNS Problems
```bash
nslookup yourdomain.com 1.1.1.1  # Test DNS
curl ifconfig.me                  # Get server IP
dig yourdomain.com                # Check propagation
```

## 📂 Key File Locations

```
/mnt/docspace_data/              # Encrypted storage
├── app_data/                    # User files & settings
├── mysql_data/                  # Database
└── log_data/                    # Application logs

/app/onlyoffice/                 # Installation
├── .env                         # Configuration
└── config/docspace-ssl-setup    # SSL script

/usr/local/bin/onlyoffice-*      # Management commands
/etc/letsencrypt/live/docspace/  # SSL certificates
```

## 🔒 Security Checklist

- [ ] SSL certificates working (https://yourdomain.com)
- [ ] Data on encrypted storage (`/mnt/docspace_data`)
- [ ] Cloudflare SSL set to "Full (strict)"
- [ ] DNS pointing to correct server IP
- [ ] Backups created and tested
- [ ] System updates applied
- [ ] SSH key authentication enabled

## 📊 Monitoring Commands

```bash
# Daily checks
onlyoffice-health --summary
df -h /mnt/docspace_data
docker ps | grep -c onlyoffice

# Certificate expiry
openssl x509 -enddate -noout -in /etc/letsencrypt/live/docspace/fullchain.pem

# Resource usage
onlyoffice-status -v
htop
```

## 🆘 Emergency Recovery

### Service Recovery
```bash
onlyoffice-stop --force
onlyoffice-start infrastructure
sleep 30
onlyoffice-start
```

### Storage Recovery
```bash
# Check last backup
cat /root/.onlyoffice-last-backup

# Restore from backup
BACKUP_DIR=$(cat /root/.onlyoffice-last-backup)
onlyoffice-stop
# Restore data from $BACKUP_DIR
onlyoffice-start
```

### SSL Recovery
```bash
# Reset to HTTP
cd /app/onlyoffice
./config/docspace-ssl-setup --default

# Re-setup SSL
./config/docspace-ssl-setup admin@example.com example.com
```

## 📞 Support Contacts

- **Logs:** `onlyoffice-logs --all`
- **Health:** `onlyoffice-health -v`
- **OnlyOffice Forum:** https://forum.onlyoffice.com
- **DO Support:** For infrastructure issues

---

*Keep this reference handy for daily operations and emergency situations.*