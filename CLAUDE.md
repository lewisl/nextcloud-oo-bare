# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **NextCloud + OnlyOffice integration project** for bare metal Ubuntu deployments. The repository contains installation scripts, configuration files, and comprehensive documentation for deploying a dual-domain NextCloud + OnlyOffice Document Server setup.

### Current Architecture
- **NextCloud domain**: `docs.test-collab-site.com` (port 443)
- **OnlyOffice domain**: `onlyoffice.test-collab-site.com` (port 443)
- **Internal OnlyOffice service**: IPv4 only (127.0.0.1:8000)
- **Nginx proxy**: 127.0.0.1:8080 → 127.0.0.1:8000
- **Database**: MariaDB (NextCloud) + PostgreSQL (OnlyOffice)
- **Current branch**: `feature/dual-domain-approach`

## Essential Commands

### Development and Testing
```bash
# Run comprehensive system diagnostics
sudo ./src/99_diagnostics.sh

# Interactive testing framework (runs scripts line-by-line)
sudo ./src/00_test_runner.sh

# Fix database permissions and setup
sudo ./fix_database_setup.sh

# Complete system uninstall (for testing)
sudo ./src/99_uninstall.sh
```

### Service Management
```bash
# Check all services status
sudo systemctl status nginx mariadb postgresql redis-server php8.3-fpm onlyoffice-documentserver

# Restart all services in correct order
sudo systemctl restart mariadb postgresql redis-server
sudo systemctl restart php8.3-fpm onlyoffice-documentserver
sudo systemctl restart nginx

# Test nginx configuration
sudo nginx -t && sudo systemctl reload nginx

# OnlyOffice health checks
curl -sS http://127.0.0.1:8000/healthcheck  # Direct OnlyOffice
curl -sS http://127.0.0.1:8080/healthcheck  # Via nginx proxy
```

### NextCloud Management
```bash
# NextCloud CLI (from /var/www/nextcloud)
sudo -u www-data php occ status
sudo -u www-data php occ app:list | grep onlyoffice
sudo -u www-data php occ config:app:get onlyoffice DocumentServerUrl
sudo -u www-data php occ config:app:get onlyoffice DocumentServerInternalUrl

# Database maintenance
sudo -u www-data php occ db:add-missing-indices
sudo -u www-data php occ db:convert-filecache-bigint
```

### Installation Scripts (Dual-Domain)
```bash
# System preparation
sudo ./src/01_system_prep_dual_domain.sh

# Database setup
sudo ./src/02_database_setup_dual_domain.sh

# NextCloud installation
sudo ./src/03_nextcloud_install_dual_domain.sh

# OnlyOffice installation
sudo ./src/04_onlyoffice_install_dual_domain.sh

# Nginx configuration
sudo ./src/05_nginx_config_dual_domain.sh

# SSL setup (requires domain and email parameters)
sudo ./src/06_ssl_setup_dual_domain.sh user@domain.com domain.com

# Integration configuration
sudo ./src/07_integration_config_dual_domain.sh
```

## Development Rules (Critical)

**⚠️ ALWAYS follow the development rules in `DEVELOPMENT_RULES.md` - these prevent regressions in a working system.**

### Key Principles
- **Always commit working state before ANY changes**
- **Make ONE change at a time and test immediately**
- **Never override working configurations without understanding them**
- **Ask permission before making changes to working systems**
- **"Diagnose" means TEST and EXAMINE only - NO CHANGES without explicit permission**

### Configuration Safety
- Current working configurations are documented in `docs/CURRENT_BEST_CONFIGURATIONS.md`
- Key config files: `/etc/onlyoffice/documentserver/local.json`, `/var/www/nextcloud/config/config.php`
- Network setup uses IPv4 only - no IPv6

## Current Status (feature/dual-domain-approach)

### ✅ Working
- NextCloud PDF viewer, image viewer, markdown editor
- OnlyOffice service running on IPv4 (127.0.0.1:8000)
- All NextCloud apps functioning
- Nginx proxy working (127.0.0.1:8080 → 127.0.0.1:8000)

### ❌ Not Working
- OnlyOffice not reachable from NextCloud
- OnlyOffice integration (cannot edit .docx files through NextCloud)
- JWT currently disabled for testing

## Key Files and Locations

### Configuration Files
- OnlyOffice config: `/etc/onlyoffice/documentserver/local.json`
- NextCloud config: `/var/www/nextcloud/config/config.php`
- NextCloud nginx: `/etc/nginx/sites-available/docs.test-collab-site.com`
- OnlyOffice nginx: `/etc/onlyoffice/documentserver/nginx/ds.conf`

### Documentation
- Current status: `docs/CURRENT_STATUS_SUMMARY.md`
- Best configurations: `docs/CURRENT_BEST_CONFIGURATIONS.md`
- Quick start: `docs/QUICK_START.md`
- Deployment guide: `docs/DEPLOYMENT.md`
- Troubleshooting: `docs/TROUBLESHOOTING.md`

### Cursor Rules
- Development workflow: `.cursor/rules/development-workflow.mdc`
- NextCloud + OnlyOffice specific: `.cursor/rules/nextcloud-onlyoffice.mdc`
- Nginx configuration: `.cursor/rules/nginx-configuration.mdc`
- Testing protocol: `.cursor/rules/testing-protocol.mdc`

### Log Files
- Installation: `/var/log/nextcloud-install.log`
- Diagnostics: `/var/log/nextcloud-diagnostics.log`
- NextCloud: `/var/www/nextcloud/data/nextcloud.log`
- Nginx: `/var/log/nginx/error.log`
- PHP-FPM: `/var/log/php8.3-fpm.log`
- OnlyOffice: `journalctl -u onlyoffice-documentserver`

## Integration Architecture

### Network Flow
1. **External requests** → nginx (port 443) → NextCloud/OnlyOffice
2. **OnlyOffice integration** → NextCloud calls 127.0.0.1:8080 → nginx proxy → 127.0.0.1:8000 (OnlyOffice)
3. **WebSocket support** required for real-time editing

### Database Architecture
- **MariaDB**: NextCloud data, user accounts, file metadata
- **PostgreSQL**: OnlyOffice document server, conversion services
- **Redis**: NextCloud caching, session management

### Security Notes
- JWT tokens currently disabled for troubleshooting
- OnlyOffice bound to IPv4 localhost only (127.0.0.1:8000)
- External access via nginx reverse proxy only
- SSL/TLS termination at nginx level

## Troubleshooting Quick Reference

### Common Issues
1. **OnlyOffice not reachable**: Check service status, nginx proxy, internal connectivity
2. **Document won't open**: Check JWT configuration, URL settings, file permissions
3. **SSL certificate issues**: Use `certbot certificates` and `certbot renew`
4. **Performance issues**: Check memory usage, restart services, optimize database

### First Debugging Steps
1. Run `sudo ./src/99_diagnostics.sh`
2. Check service status: `systemctl status nginx php8.3-fpm mariadb postgresql redis-server onlyoffice-documentserver`
3. Test OnlyOffice health: `curl http://127.0.0.1:8000/healthcheck`
4. Check recent logs in `/var/log/` directories

### Recovery Commands
```bash
# Emergency service restart
sudo systemctl restart mariadb postgresql redis-server php8.3-fpm onlyoffice-documentserver nginx

# Fix permissions
sudo chown -R www-data:www-data /var/www/nextcloud /srv/nextcloud-data

# Reset to known good state (documented in TROUBLESHOOTING.md)
git checkout feature/dual-domain-approach
```

Remember: This is a working system in production - always commit current state before making changes and follow the regression prevention rules.