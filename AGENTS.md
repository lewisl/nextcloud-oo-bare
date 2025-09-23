# OnlyOffice Document Server Deployment Automation Project

## Project Overview

You are tasked with creating a complete, production-ready deployment automation toolkit for NextCloud with OnlyOffice Document Server editors on my chosen vpn host with SSL automation, and comprehensive lifecycle management. This toolkit will be used by system administrators who are barely competent and unfamiliar with NextCloud and OnlyOffice's complex deployment requirements.

This is a **NextCloud + OnlyOffice integration project** for bare metal Ubuntu deployments. The repository contains installation scripts, configuration files, and comprehensive documentation for deploying a dual-domain NextCloud + OnlyOffice Document Server setup.

## Target User Profile

**Primary User**: Conscientious but inexperienced system administrator who needs to:
- Deploy NextOffice reliably and securely
- Deploy and integrate OnlyOffice to provide online office-style editors that enable concurrent collaborative editing
- Manage ongoing operations without deep bash or linux expertise
- Troubleshoot issues using clear documentation and diagnostic tools
- Maintain security best practices throughout the deployment lifecycle

## Technical Specifications

### Required VPS Resources
- **VPS**: 8GB RAM, 4 vCPU, 160GB SSD (Ubuntu 22.04 LTS)
- **Networking**: CloudFlare DNS management capability
- **Firewall**: Configured for HTTP/HTTPS/SSH only

### NextCloud Configuration
- **Database**: Mariadb as mysql instance
- **Caching**: memcache (optional but desirable optimization)
- **SSL**: Let's Encrypt 
- **Security**: JWT enabled with strong secrets
- **OnlyOffice integration**: connector app "OnlyOffice" installed and correctly configured *after* OnlyOffice has been installed

### OnlyOffice Configuration
- **Database**: Postgres 
- **Message Queue**: RabbitMQ
- **Caching**: Redis
- **SSL**: Let's Encrypt with CloudFlare DNS validation
- **Security**: JWT enabled with strong secrets

### Script Architecture Requirements
- **Idempotent execution** - can safely re-run over existing deployments, if possible
- **Dependency awareness** - proper container startup/shutdown ordering
- **Error handling** - graceful failure with actionable error messages
- **Logging** - comprehensive logging for debugging and auditing
- **Validation** - health checks and configuration verification at each step

## Critical Project Context

### Preferred Approach
1. Use publicly available downloads of NextCloud and OnlyOffice from the developers websites, github repos or Debian package managers
2. Use platform apt for front end nginx
3. install both NextCloud and OnlyOffice on the same vps instance, provided by the user
4. Do not deploy Apache specifically for NextCloud
5. Do not deploy an nginx instance specifically for OnlyOffice
6. Do not use snap, Docker, Docker Compose or Cloudron
7. Provide correct configuration for a reverse proxy on nginx and for NextCloud to integrate with OnlyOffice
8. Use docs.<base domain> as the domain for NextCloud and onlyoffice.<base domain> for OnlyOffice.  
9. Install Let's Encrypt certificates for both domains and setup automatic renewal for the certs
10. Use a reverse proxy configuration of nginx that can use a local connection to the OnlyOffice instance

### OnlyOffice Deployment Complexity
- **Complex dependencies**: Postgresql → RabbitMQ/Redis → DocumentServer
- **Fragmented documentation** - official OnlyOffice docs are often outdated

### NextCloud Deployment Complexity
- most "comfortable" with MariaDB/MySQL, but reliable with Postgresql
- requirements:
  - automatic renewals of certificates
  - easy updating of applications (NextCloud and OnlyOffice)
  - easy stop/restart of applications
  
### Hosting and internet access Requirements
- **CloudFlare DNS + Let's Encrypt SSL** automation
- **Production security hardening** including ufw firewall, JWT configuration (actually this is optional, but it is not the hardest thing to get right)
- Efficiency optimizations such as Redis and memcache

### Security Architecture
1. Use NextCloud "server encryption" with masterkey (requires enabling NextCloud application extension using NextCloud gui). This can be done by the user via the NextCloud gui
2. Public facing nginx instance accessed with ssl and Let's Encrypt certificates
3. localhost access from nginx to Nextcloud and OnlyOffice

### Post-setup Tasks to be performed by Admin, not coding agents
- Brevo email forwarding enabled in Nextcloud for admin emails: invites to new members; update notifications for modifications of documents, etc. Note that the user should do this separately with the NextCloud Gui and the Brevo gui.
- Add users and one "team" group
- Turn on Server Side Encryption and install Base Encryption app
- Create suitable project folder structure under one top level folder
- Upload previously completed documents from other approved sources

## Development Environment Setup

### Recommended Execution Method

#### Completed for test:
1. **Hetzner project with server** (Ubuntu 24.04 LTS, 8GB RAM, 4 vCPU minimum, 80GB SSD)
2. ssh key pair created, no passphrase
3. **SSH into droplet**: `ssh root@91.98.89.18`  
4. coding agent will be enable to work at the server with access to the installation of the apps and a clone of the github repo for the deployment scripts

#### Completed for production:
1. **Hetzner project with server** (Ubuntu 24.04 LTS, 8GB RAM, 4 vCPU minimum, 160GB SSD)
2. ssh key pair created with passphrase
3. **SSH into droplet**: `ssh root@91.99.189.91`  
4. There will not be any development work on the scripts here. Afer the scripts are complete, they can be installed by creating a suitable directory on the server and cloning the repo.  The scripts will be run to perform installation and configuration of the apps.

#### Completed dns configuration
1. Already exists at Cloudflare
2. Test site is test-collab-site with docs.test-collab-site.com for NextCloud and onlyoffice.test-collab-site.com
3. Production site is bedfordfallsbbbl.org with docs.bedfordfallsbbbl.org for NextCloud and onlyoffice.Bedfordfallsbbbl.org for OnlyOffice
   > note: we may experiment with a single domain approach
4. This means scripts should not hardcode domain names.

#### Security Model at the VPS:
- User creates and controls all server VPS infrastructure
- No vps credentials required by coding agent
- User maintains full billing and access control

### Configuration Safety
- Current working configurations are documented in `docs/CURRENT_BEST_CONFIGURATIONS.md` and saved in `configs`
- Key config files: `/etc/onlyoffice/documentserver/local.json`, `/var/www/nextcloud/config/config.php`, '/etc/onlyoffice/documentserver/production-linux.json'
- Network setup uses IPv4 only - no IPv6
## Project Requirements

### Phase 1: Infrastructure Discovery and Analysis
**Objective**: Understand NextCloud and OnlyOffice actual deployment structure

**Tasks**:
1. **Deploy OnlyOffice using official installation script**
2. **Discover all generated configuration files** (.env, YAML files, etc.)
3. Meet startup/shutdown ordering requirements in maintenance scripts
4. **Document working configuration** in appropriate text files in the repo in configs directory

**Deliverables**:
- working scripts for installation, configuration and maintenance
- Container dependency map
- Volume mapping inventory
- Configuration files
- Installation process documentation

### Phase 2 (really an extension of Phase 1): SSL and Security Automation
**Objective**: Automated SSL certificate management and security hardening

**Tasks**:
1. **Implement Let's Encrypt** certificate automation
2. **Configure automatic certificate renewal** for both the docs.<domain> and onlyoffice.<domain>
3. **Apply security hardening** (JWT configuration, firewall rules, container security)
4. **Create security validation tests** to verify proper configuration
5. **Document security maintenance procedures**

**Deliverables**:
- SSL automation 
- Security hardening as part of the deployment (installation and configuration) scripts
- Security validation test suite
- Security maintenance documentation

**Requirements**:
- compatible with domains registered at Cloudflare DNS
- assume proxied domains (though possible not for onlyoffice which only is accessed by NextCloud)
- try to avoid turning proxying on/off by the user during installation.  This can work be configuring nginx before installing NextCloud and OnlyOffice

### Phase 3: Create finished scripts and some maintenance scripts

#### Development and Testing
```bash
# Run comprehensive system diagnostics
sudo ./src/99_diagnostics.sh

# Interactive testing framework (runs scripts line-by-line)
sudo ./src/00_test_runner.sh


# Complete system uninstall (for testing)
sudo ./src/99_uninstall.sh
```

#### Service Management
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

#### NextCloud Management
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

#### Installation Scripts (Dual-Domain)
> order and naming subject to change based on final testing and improvement of scripts!
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


### Phase 4: Container Lifecycle Management
**Objective**: Reliable start/stop/restart/health monitoring for both apps on the VPS

**Tasks**:
1. **Build dependency-aware startup scripts** (MySQL → RabbitMQ/Redis → DocumentServer)
2. **Create graceful shutdown procedures** (reverse dependency order)
3. **Implement comprehensive health checking** (container status + service connectivity)
4. **Develop log aggregation and monitoring** across all containers
5. **Create troubleshooting diagnostic tools**

**Deliverables**:
- `nc-oo-manager.sh` with start/stop/restart/status commands
- Health monitoring system with actionable alerts
- Log analysis and diagnostic tools
- Troubleshooting runbooks

### Phase 5: Documentation and User Experience
**Objective**: Production-ready documentation for system administrators

**Tasks**:
1. **Create step-by-step deployment guide** with prerequisite checking
2. **Write operational runbooks** for common maintenance tasks
3. **Develop troubleshooting guides** with common issues and solutions
4. **Create configuration templates** for the preferred deployment scenarios
5. **Build validation checklists** for deployment verification

**Deliverables**:
- Complete deployment documentation
- Operational runbooks
- Troubleshooting guides
- Configuration templates
- Deployment validation checklists



## Success Criteria

### Functional Requirements
1. **Sequenced deployment**: user-admin runs scripts in prescribed order
2. **Encrypted storage** for documents
3. **Automatic SSL** certificate management with renewal
4. **Container lifecycle management** with proper dependency handling
5. **Health monitoring** with early warning for potential issues

### Operational Requirements
1. **Documentation quality** suitable for inexperienced administrators
2. **Troubleshooting capability** with diagnostic tools and runbooks
3. **Maintenance automation** for routine tasks (log rotation, cleanup, updates)
4. **Security compliance** with production security best practices

### Quality Standards
1. **Scripts must be production-ready** - robust error handling, logging, validation
2. **Documentation must be complete** - no assumption of prior NextCloud or OnlyOffice knowledge
3. **Security must be comprehensive** - encrypted storage, SSL, access controls, hardening
4. **Operations must be reliable** - predictable behavior, graceful failure handling
5. **User experience must be excellent** - clear instructions, helpful error messages, intuitive workflows

### Deferred
1. **Backup strategy**: after successful script driven deployment is successful
   1. Will this be a simple export all documents via the NextCloud gui as the simplest, most reliable and useable document backup?
   2. Will server snapshots be used to enable backup of the entire "enchilada"?

## Development Environment

### Available Tools
- **SSH access** to the test and production servers
- **NextCloud official installation scripts** as the foundation if they meet these deployment requirements
- **OnlyOffice official installation scripts** as the foundation if they meet these deployment requirements
- **CloudFlare API** for DNS and SSL automation--this is probably NOT needed

### Documentation of current status of development project and deployment testing during development in **`project-status-and-todo`**
- Current status: `project-status-and-todo/CURRENT_STATUS_SUMMARY.md`
- Best configurations: `project-status-and-todo/CURRENT_BEST_CONFIGURATIONS.md`
- Things to do: `docs/DEPLOYMENT_PLAN.md`, `project-status-and-todo/NEXT_STEPS.md`
- Detailed view of technical issues in current deployment: `project-status-and-todo/TECHNICAL_ANALYSIS.md`

### Security Notes
- External access via nginx reverse proxy only
- SSL/TLS termination at nginx level

### Log Files
- Installation: `/var/log/nextcloud-install.log`
- Diagnostics: `/var/log/nextcloud-diagnostics.log`
- NextCloud: `/var/www/nextcloud/data/nextcloud.log`
- Nginx: `/var/log/nginx/error.log`
- PHP-FPM: `/var/log/php8.3-fpm.log`
- OnlyOffice: `journalctl -u onlyoffice-documentserver`
- 
### Development Approach
1. **Test on real infrastructure** - use the test server to get the deployment working
2. **Document everything** - capture actual behavior, not theoretical expectations
3. **Validate continuously** - test each component as it's developed
4. **Focus on user experience** - optimize for the target system administrator profile
5. **Plan for disposal** - development infrastructure will eventually be destroyed if no longer needed

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


## Deliverable Structure

### Scripts
- currently existing in the repo /src directory
- new scripts can be created as needed until the deployment automation is verified as successful

### Documentation for users of the scripts in `docs`
- Quick start: `docs/QUICK_START.md`
- Deployment guide: `docs/DEPLOYMENT.md`
- Day-to-day operational procedures: `OPERATIONS-MANUAL.md`
- Troubleshooting: `docs/TROUBLESHOOTING.md`
- detailed project description: `docs/PROJECT_SUMMARY.md`
- read me (quickstart guide and overview): `/docs/README.md
- detailed technical description: <not present yet>--when the scripts are successful and production ready and the details of successful deployment are confirmed, update `project-status-and-todo/TECHNICAL_ANALYSIS.md` and copy to `docs`
- Security configuration and maintenance: `docs/SECURITY.md`

### Configuration Documentation
- Verified configuration files for nginx, NextCloud and OnlyOffice in configs directory of repo
- NextCloud-OnlyOffice integration examples


This project will result in a complete, battle-tested deployment toolkit that transforms NextCloud with OnlyOffice's complex installation process into a reliable, secure, and maintainable system that any competent system administrator can successfully deploy and operate.