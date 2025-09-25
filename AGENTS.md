# OnlyOffice Document Server Deployment Automation Project

## Project Overview

You are tasked with creating a complete, production-ready deployment automation toolkit for NextCloud with OnlyOffice Document Server editors on my chosen vpn host with SSL automation, and comprehensive lifecycle management. This toolkit will be used by system administrators who are barely competent and unfamiliar with NextCloud and OnlyOffice's complex deployment requirements.

## Target User Profile

**Primary User**: Conscientious but inexperienced system administrator who needs to:
- Deploy NextOffice reliably and securely
- Deploy and integrate OnlyOffice to provide online office-style editors that enable concurrent collaborative editing
- Manage ongoing operations without deep bash or linux expertise
- Troubleshoot issues using clear documentation and diagnostic tools
- Maintain security best practices throughout the deployment lifecycle

## **Mandatory**: always do this while working
1. After a bug fix or feature is completed:
   - append summary of changes in 
2. If a configuration was changed
   1. update or replace or add the appropriate configuration file or snippet (comment it as a snippet) in the approprate directory of 'configs/'
   2. Make the documentation of these configs consistent in [CURRENT_BEST_CONFIGURATIONS.md](project-status-and-todo/CURRENT_BEST_CONFIGURATIONS.md)
3. When requested or when the user is going to end the session:
   - add a session-summary with date/time in the file name at [session-summaries](project-status-and-todo/session-summaries)
4. Perform internal server tests such as curl to see results of invoking app endpoints, checking for service existence and running status, comparing keys and credentials that must match across applications. This list is not exhaustive: you may and should propose and perform suitable tests as you deem effective
5. request user to test webgui at website after internal tests pass and before declaring bug fixed or feature completed

## Technical Specifications

see [Product Requirements Document](docs/Product Requirements Document.md) sections "Technical Requirements" and "Technical Architecture"


## Script Architecture Requirements
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


## Development Environment Setup

### Test VPS already set up
1. **Hetzner project with server** (Ubuntu 24.04 LTS, 8GB RAM, 4 vCPU minimum, 80GB SSD)
2. ssh key pair created, no passphrase
3. **SSH into droplet**: `ssh root@91.98.89.18`  
4. coding agent will be enable to work at the server with access to the installation of the apps and a clone of the github repo for the deployment scripts

### Production VPS alreeady setup
1. **Hetzner project with server** (Ubuntu 24.04 LTS, 8GB RAM, 4 vCPU minimum, 160GB SSD)
2. ssh key pair created with passphrase
3. **SSH into droplet**: `ssh root@91.99.189.91`  
4. There will not be any development work on the scripts here. Afer the scripts are complete, they can be installed by creating a suitable directory on the server and cloning the repo.  The scripts will be run to perform installation and configuration of the apps.

### DNS configuration already setup
1. Already exists at Cloudflare
2. With our successful single domain approach, the onlyoffice.<domain> domains are legacy and will be removed after development is completed
3. Test site is test-collab-site with docs.test-collab-site.com for NextCloud with internal routing to /onlyoffice/ and proxied by CloudFlare
4. Production site is bedfordfallsbbbl.org with docs.bedfordfallsbbbl.org for NextCloud with internal routing to /onlyoffice/ and proxied by Cloudflare
5. This means scripts should not hardcode domain names.

### Security Model at the VPS:
- User creates and controls all server VPS infrastructure
- No vps credentials required by coding agent
- User maintains full billing and access control

### Configuration Safety
- Current working configurations are documented in `docs/CURRENT_BEST_CONFIGURATIONS.md` and saved in `configs`
- Key config files: `/etc/onlyoffice/documentserver/local.json`, `/var/www/nextcloud/config/config.php`, '/etc/onlyoffice/documentserver/production-linux.json'
- Network setup uses IPv4 only - no IPv6

### Documentation of current status of development project and deployment testing during development in **`project-status-and-todo`**
- Current status: `project-status-and-todo/CURRENT_STATUS_SUMMARY.md`
- Best configurations: `project-status-and-todo/CURRENT_BEST_CONFIGURATIONS.md`
- Things to do: `docs/DEPLOYMENT_PLAN.md`, `project-status-and-todo/NEXT_STEPS.md`
- Detailed view of technical issues in current deployment: `project-status-and-todo/TECHNICAL_ANALYSIS.md`


## Development plan

### Overview
Start by creating a successful deployment of NextCloud, OnlyOffice and their dependencies. Examine the deployment and its configuration and keep track of the commands used to implement it. Then, modify the scripts so that they are able to install, configure and verify the deployment on the test and later, a suitable production server.

### Development Approach
1. **Test on real infrastructure** - use the test server to get the deployment working
2. **Modify the scripts** to create exactly that deployment on a new or "cleaned" server
3. **Document everything** - capture actual behavior, not theoretical expectations
4. **Validate continuously** - test each component as it's developed
5. **Focus on user experience** - optimize for the target system administrator profile
6. **Longterm use of test site** - development infrastructure will be kept for future feature additions or changes and for testing/debugging.  

### git branch for development
**feature/dual-domain-approach**
OK, it's misnamed now because we have successfully changed to a one domain approach,  but it is unnecessary housekeeping to change the branch name at this point.

### Phase 1: Infrastructure Discovery and Analysis
**Objective**: Understand NextCloud and OnlyOffice actual deployment structure

**Tasks**:
1. Install dependencies using apt.
1. **Deploy NextCloud using official installation script for latest, stable community edition.** Ensure php, redis and mysql are configured correctly.
2. **Deploy OnlyOffice** using apt to obtain compatible package.
3. **Discover all generated configuration files** (.env, YAML files, etc.)
4. Meet startup/shutdown ordering requirements in maintenance scripts
5. **Document working configuration** in appropriate text files in the repo in configs directory

**Deliverables**:
- working scripts for installation, configuration and maintenance
- Container dependency map
- Volume mapping inventory
- Configuration files
- Installation process documentation

#### Log Files
- Installation: `/var/log/nextcloud-install.log`
- Diagnostics: `/var/log/nextcloud-diagnostics.log`
- NextCloud: `/var/www/nextcloud/data/nextcloud.log`
- Nginx: `/var/log/nginx/error.log`
- PHP-FPM: `/var/log/php8.3-fpm.log`
- OnlyOffice: `journalctl -u onlyoffice-documentserver`

### Phase 2 (an extension of Phase 1): SSL and Security Automation
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
- compatible with domain registered at Cloudflare DNS
- assume proxied domain
- try to avoid turning proxying on/off by the user during installation.  This can work be configuring nginx before installing NextCloud and OnlyOffice

### Phase 3: Create finished scripts and some maintenance scripts

#### Installation scripts
A starting point is at [Product Requirements Document.md](docs/Product Requirements Document.md) under the heading "Technical Architecture" then "File Structure". You may modify the names and number and order of execution for the scripts during the development process.

#### Development and Testing
```bash
# Run comprehensive system diagnostics
sudo ./src/99_diagnostics.sh

# Interactive testing framework (runs scripts line-by-line)
sudo ./src/00_test_runner.sh


# Complete system uninstall (for testing)
sudo ./src/99_uninstall.sh
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

### Reset to known good state (documented in TROUBLESHOOTING.md)
git checkout feature/dual-domain-approach
```
