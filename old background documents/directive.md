# OnlyOffice Document Server Deployment Automation Project

## Project Overview

You are tasked with creating a complete, production-ready deployment automation toolkit to deply NextCloud with OnlyOffice Document Server on an ubuntu vps with SSL, server encryption by Nextcloud, ssl certificate renewal automation, 3rd party email forwarding for NextCloud, and comprehensive lifecycle management. This toolkit will be used by system administrators who may be competent but unfamiliar with NextCloud and OnlyOffice's complex deployment requirements on a single server behind a single web server (nginx).

## Target User Profile

**Primary User**: Conscientious but inexperienced system administrator who needs to:
- Deploy NextCloud and OnlyOffice Document Server reliably and securely
- Manage ongoing operations without deep Nextcloud, OnlyOffice or Linux application expertise
- Troubleshoot issues using clear documentation and diagnostic tools
- Maintain security best practices throughout the deployment lifecycle

## Critical Project Context

### OnlyOffice Deployment Complexity
- **28+ containers** across ~10 YAML configuration files
- **Complex dependencies**: MySQL → RabbitMQ/Redis → DocumentServer
- **Fragmented documentation** - official OnlyOffice docs are often outdated
- **Configuration spread across 12-15 files** requiring careful coordination
- **No single systemctl command** - each container group managed separately

### VPS Requirements
- **CloudFlare DNS + Let's Encrypt SSL** automation
- **Production security hardening** including firewall, JWT configuration (optional)
- **Droplet sizing and optimization** for OnlyOffice's resource requirements (will be handled by human manager)

### Security Architecture
Only these data types require encrypted block storage:
1. **User documents** (`/app/onlyoffice/DocumentServer/data` → `/var/www/onlyoffice/Data`)
2. **MySQL database** (`/app/onlyoffice/mysql/data` → `/var/lib/mysql`)
3. **Application logs** (`/app/onlyoffice/DocumentServer/logs` → `/var/log/onlyoffice`)
4. **Document processing cache** (`/app/onlyoffice/DocumentServer/lib` → `/var/lib/onlyoffice`)

## Development Environment Setup

### Recommended Execution Method

**Execute Claude Code via SSH session on Digital Ocean droplet** for optimal development environment.

#### Setup Process:
1. **Create DO droplet** (Ubuntu 22.04 LTS, 8GB RAM, 4 vCPU minimum)
2. **SSH into droplet**: `ssh root@your-droplet-ip`  
3. **Invoke Claude Code from within the SSH terminal session**
4. **Claude Code works directly in the production target environment**

#### Why SSH Session Approach is Optimal:
- **Real infrastructure access** - immediate DO block storage, networking, firewall interaction
- **Production environment** - actual Ubuntu 22.04, Docker, resource constraints
- **No credential sharing** - user maintains full control of DO account/billing
- **Real-time oversight** - user can observe and intervene during development
- **Immediate validation** - scripts tested on actual deployment target
- **Clean termination** - exit SSH session when complete, destroy droplet

#### Alternative Approaches (Not Recommended):
- **Local development** - Cannot test DO-specific features (block storage, networking)
- **Full credential sharing** - Security/billing risks, less user control
- **Separate test/deploy phases** - Introduces environment differences and complexity

#### Security Model:
- User creates and controls all DO infrastructure
- Claude Code operates only within the provided droplet environment  
- No DO API credentials required by Claude Code
- User maintains full billing and access control
- Development droplet destroyed after script completion

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