# OnlyOffice Document Server Deployment Automation Project

## Project Overview

You are tasked with creating a complete, production-ready deployment automation toolkit for NextCloud with OnlyOffice Document Server editors on my chosen vpn host with SSL automation, and comprehensive lifecycle management. This toolkit will be used by system administrators who may be competent but unfamiliar with NextCloud and OnlyOffice's complex deployment requirements.

## Target User Profile

**Primary User**: Conscientious but inexperienced system administrator who needs to:
- Deploy NextOffice reliably and securely
- Deploy and integrate OnlyOffice to provide online office style editors that enable concurrent collaborative editing
- Manage ongoing operations without deep bash or linux expertise
- Troubleshoot issues using clear documentation and diagnostic tools
- Maintain security best practices throughout the deployment lifecycle

## Critical Project Context

### Preferred Approach
1. Use publicly available downloads of NextCloud and OnlyOffice from the developers websites or github repos
2. Use platform apt for front end nginx
3. Do not deploy Apache specifically for NextCloud
4. Do not deploy an nginx instance specifically for OnlyOffice
5. Do not use snap, Docker, Docker Compose or Cloudron
6. Provide correct configuration

### OnlyOffice Deployment Complexity
- **Complex dependencies**: Postgresql → RabbitMQ/Redis → DocumentServer
- **Fragmented documentation** - official OnlyOffice docs are often outdated

### NextCloud Deployment Complexity
- most "comfortable" with MariaDB/MySQL, but reliable with Postgresql
- probably undesirable to deploy NextCloud and OnlyOffice running on same instance of Postgresql for performance and isolation reasons: **This topic should be researched to determine preferred approach**
- Several things Cloudron automates that would need to be replicated in the non-containerized deployment:
  - automatic renewals of certificates
  - easy updating of applications (NextCloud and OnlyOffice)
  - easy stop/restart of applications
  - easy access to bash shell within application containers (if we succeed with non-containerized deployment then this won't matter...)
  - Cloudron requires API token for modifying DNS records at Cloudflare (if we get the single domain installation to work, this won't be needed...)

### Hosting and internet access Requirements
- **CloudFlare DNS + Let's Encrypt SSL** automation
- Brevo email forwarding enabled in Nextcloud for admin emails: invites to new members; update notifications for modifications of documents, etc.
- **Production security hardening** including ufw firewall, JWT configuration (actually this is optional, but it is not the hardest thing to get right)

### Security Architecture
1. Use NextCloud "server encryption" with masterkey (requires enabling NextCloud application extension using NextCloud gui)
2. Public facing nginx instance accessed with ssl and Let's Encrypt certificates
3. localhost access from nginx to Nextcloud and OnlyOffice

## Development Environment Setup

### Recommended Execution Method

**Execute Augment remote agent via SSH session on chosen host for optimal development environment.
1. Test site is
2. Production site is

#### Completed for test:
1. **Create Hetzner project with server** (Ubuntu 24.04 LTS, 8GB RAM, 4 vCPU minimum, 80GB SSD)
2. ssh key pair created, no passphrase
3. **SSH into droplet**: `ssh root@91.98.89.18`  
4. **Invoke Augment agent in the SSH terminal session**

#### Completed for production:
1. **Create Hetzner project with server** (Ubuntu 24.04 LTS, 8GB RAM, 4 vCPU minimum, 160GB SSD)
2. ssh key pair created with passphrase
3. **SSH into droplet**: `ssh root@91.99.189.91`  
4. **Invoke Augment agent in the SSH terminal session**

#### Security Model:
- User creates and controls all server VPS infrastructure
- No DO API credentials required by Claude Code
- User maintains full billing and access control

## Project Requirements

### Phase 1: Infrastructure Discovery and Analysis
**Objective**: Understand OnlyOffice's actual deployment structure

**Tasks**:
1. **Deploy OnlyOffice using official installation script** on DO droplet
2. **Discover all generated configuration files** (.env, YAML files, etc.)
3. **Map container dependencies** and startup/shutdown ordering requirements
4. **Identify volume mappings** that need encrypted storage redirection
5. **Document actual vs. expected configuration structure**

**Deliverables**:
- Container dependency map
- Volume mapping inventory
- Configuration file analysis
- Installation process documentation

### Phase 2: Encrypted Storage Migration System
**Objective**: Create post-installation migration to encrypted block storage

**Tasks**:
1. **Create DO block storage** with encryption enabled
2. **Develop data migration scripts** to move sensitive data to encrypted storage
3. **Modify OnlyOffice configuration files** to redirect volume mappings
4. **Validate encrypted storage integration** without breaking functionality
5. **Create rollback procedures** for failed migrations

**Deliverables**:
- Block storage setup automation
- Data migration scripts with integrity checking
- Configuration modification tools
- Migration validation tests

### Phase 3: Container Lifecycle Management
**Objective**: Reliable start/stop/restart/health monitoring for all containers

**Tasks**:
1. **Build dependency-aware startup scripts** (MySQL → RabbitMQ/Redis → DocumentServer)
2. **Create graceful shutdown procedures** (reverse dependency order)
3. **Implement comprehensive health checking** (container status + service connectivity)
4. **Develop log aggregation and monitoring** across all containers
5. **Create troubleshooting diagnostic tools**

**Deliverables**:
- `onlyoffice-manager.sh` with start/stop/restart/status commands
- Health monitoring system with actionable alerts
- Log analysis and diagnostic tools
- Troubleshooting runbooks

### Phase 4: SSL and Security Automation
**Objective**: Automated SSL certificate management and security hardening

**Tasks**:
1. **Implement CloudFlare DNS + Let's Encrypt** certificate automation
2. **Configure automatic certificate renewal** with OnlyOffice integration
3. **Apply security hardening** (JWT configuration, firewall rules, container security)
4. **Create security validation tests** to verify proper configuration
5. **Document security maintenance procedures**

**Deliverables**:
- SSL automation with CloudFlare integration
- Security hardening scripts
- Security validation test suite
- Security maintenance documentation

### Phase 5: Documentation and User Experience
**Objective**: Production-ready documentation for system administrators

**Tasks**:
1. **Create step-by-step deployment guide** with prerequisite checking
2. **Write operational runbooks** for common maintenance tasks
3. **Develop troubleshooting guides** with common issues and solutions
4. **Create configuration templates** for different deployment scenarios
5. **Build validation checklists** for deployment verification

**Deliverables**:
- Complete deployment documentation
- Operational runbooks
- Troubleshooting guides
- Configuration templates
- Deployment validation checklists

## Technical Specifications

### Required Digital Ocean Resources
- **Droplet**: 8GB RAM, 4 vCPU, 160GB SSD (Ubuntu 22.04 LTS)
- **Block Storage**: Encrypted volume, minimum 100GB
- **Networking**: CloudFlare DNS management capability
- **Firewall**: Configured for HTTP/HTTPS/SSH only

### OnlyOffice Configuration
- **Database**: MySQL (OnlyOffice default, not PostgreSQL)
- **Message Queue**: RabbitMQ
- **Caching**: Redis
- **SSL**: Let's Encrypt with CloudFlare DNS validation
- **Security**: JWT enabled with strong secrets

### Script Architecture Requirements
- **Idempotent execution** - can safely re-run over existing deployments
- **Dependency awareness** - proper container startup/shutdown ordering
- **Error handling** - graceful failure with actionable error messages
- **Logging** - comprehensive logging for debugging and auditing
- **Validation** - health checks and configuration verification at each step

## Success Criteria

### Functional Requirements
1. **Single-command deployment** from fresh DO droplet to production-ready OnlyOffice
2. **Encrypted storage** for all sensitive data (documents, database, logs)
3. **Automatic SSL** certificate management with renewal
4. **Container lifecycle management** with proper dependency handling
5. **Health monitoring** with early warning for potential issues

### Operational Requirements
1. **Documentation quality** suitable for inexperienced administrators
2. **Troubleshooting capability** with diagnostic tools and runbooks
3. **Maintenance automation** for routine tasks (log rotation, cleanup, updates)
4. **Security compliance** with production security best practices
5. **Disaster recovery** procedures for common failure scenarios

### Quality Standards
1. **Scripts must be production-ready** - robust error handling, logging, validation
2. **Documentation must be complete** - no assumption of prior OnlyOffice knowledge
3. **Security must be comprehensive** - encrypted storage, SSL, access controls, hardening
4. **Operations must be reliable** - predictable behavior, graceful failure handling
5. **User experience must be excellent** - clear instructions, helpful error messages, intuitive workflows

## Development Environment

### Available Tools
- **Digital Ocean API** for infrastructure automation
- **SSH access** to created droplets for configuration and testing
- **Docker and docker-compose** for container management
- **OnlyOffice official installation scripts** as the foundation
- **CloudFlare API** for DNS and SSL automation

### Development Approach
1. **Test on real infrastructure** - use actual DO droplets and block storage
2. **Document everything** - capture actual behavior, not theoretical expectations
3. **Validate continuously** - test each component as it's developed
4. **Focus on user experience** - optimize for the target system administrator profile
5. **Plan for disposal** - all development infrastructure will be destroyed after completion

## Deliverable Structure

### Scripts
- `do-infrastructure-setup.sh` - DO droplet and block storage preparation
- `onlyoffice-enhanced-install.sh` - OnlyOffice installation with encrypted storage
- `onlyoffice-manager.sh` - Container lifecycle management
- `ssl-automation.sh` - CloudFlare + Let's Encrypt integration
- `security-hardening.sh` - Production security configuration
- `maintenance-tools.sh` - Routine maintenance automation
- `test-deployment.sh` - Comprehensive validation testing

### Documentation
- `README.md` - Quick start guide and overview
- `DEPLOYMENT-GUIDE.md` - Complete step-by-step deployment instructions
- `OPERATIONS-MANUAL.md` - Day-to-day operational procedures
- `TROUBLESHOOTING.md` - Common issues and diagnostic procedures
- `SECURITY.md` - Security configuration and maintenance
- `ARCHITECTURE.md` - Technical architecture and design decisions

### Configuration Templates
- Environment configuration templates
- CloudFlare integration examples
- Security policy templates
- Monitoring and alerting configurations

This project will result in a complete, battle-tested deployment toolkit that transforms OnlyOffice's complex installation process into a reliable, secure, and maintainable system that any competent system administrator can successfully deploy and operate.