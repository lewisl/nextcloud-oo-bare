# Configuration Files Repository

This directory contains the **golden configuration files** for the Nextcloud + OnlyOffice dual-domain setup.

## Purpose

- **Prevent regressions** by maintaining known-working configurations
- **Version control** all critical config files
- **Easy reference** for troubleshooting and deployment
- **Template source** for installation scripts

## Structure

### `nginx/sites-available/`
- `docs.test-collab-site.com.conf` - **Working Nextcloud nginx config** (from ChatGPT)
- `onlyoffice.test-collab-site.com` - OnlyOffice nginx reverse proxy config

### `php/`
- `php.ini` - Main PHP 8.3 configuration with Nextcloud optimizations
- `php-fpm.conf` - PHP-FPM process manager configuration  
- `pool.d/` - PHP-FPM pool configurations (www.conf, etc.)

### `nextcloud/`
- `config.php` - Nextcloud application configuration
- Contains database settings, trusted domains, SSL settings

### `onlyoffice/`
- `local.json` - OnlyOffice DocumentServer local configuration
- `production-linux.json` - OnlyOffice production settings
- *(These will be populated after OnlyOffice installation)*

### Root Files
- `params.yaml` - Deployment parameters (domains, database credentials, etc.)

## Usage

### For Developers
- **Reference**: Check these files when troubleshooting
- **Comparison**: Diff against current system configs to find issues
- **Restoration**: Copy files back to restore working state

### For Scripts
- **Templates**: Scripts should generate configs based on these templates
- **Validation**: Compare script output against these golden configs
- **Testing**: Use these configs to verify installation scripts

## Maintenance

- **Update after successful changes**: When configs are modified and tested working
- **Commit changes**: Version control all modifications with descriptive messages
- **Document rationale**: Note why changes were made in commit messages

## Current Status

✅ **Nginx**: Working ChatGPT configuration that fixes /apps/ routing
✅ **PHP**: Production-ready configuration for Nextcloud
✅ **Parameters**: Deployment settings for dual-domain setup
🔄 **Nextcloud**: Basic working configuration
⏳ **OnlyOffice**: Pending installation of OnlyOffice DocumentServer

---

**Last Updated**: September 20, 2025  
**Architecture**: Dual-domain (docs.domain.com + onlyoffice.domain.com)  
**Status**: Nextcloud working, OnlyOffice pending installation
