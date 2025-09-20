# Technical Analysis: Current System State

**Date:** September 20, 2024
**System:** docs.test-collab-site.com
**Status:** NextCloud working, OnlyOffice integration partially broken

## Current Architecture

### Working Components
- **NextCloud:** Fully functional at `https://docs.test-collab-site.com`
- **OnlyOffice Service:** Running on `127.0.0.1:8000`
- **Nginx:** Proxying and SSL termination working
- **Databases:** MariaDB (NextCloud) and PostgreSQL (OnlyOffice) operational
- **Basic Infrastructure:** SSL certificates, firewall, basic services

### Network Configuration
```
External → nginx:443 → NextCloud (docs.test-collab-site.com)
External → nginx:443 → OnlyOffice (onlyoffice.test-collab-site.com)
NextCloud → nginx:8080 → OnlyOffice:8000 (internal communication)
```

## OnlyOffice Integration Issues

### Symptom: 502 Bad Gateway Errors
**Affected endpoints:**
- Some OnlyOffice API endpoints return 502 instead of proper responses
- NextCloud cannot fully communicate with OnlyOffice Document Server
- Document editing may fail or be unreliable

### Potential Root Causes

#### 1. Nginx Proxy Configuration Issues
**File:** `/etc/nginx/sites-available/docs.test-collab-site.com`
**Potential problems:**
- Incorrect proxy headers for OnlyOffice endpoints
- Missing WebSocket upgrade configuration
- Timeout settings too aggressive
- Upstream definition issues

#### 2. OnlyOffice Internal Configuration
**File:** `/etc/onlyoffice/documentserver/local.json`
**Potential problems:**
- Port binding conflicts
- JWT token misconfiguration
- Database connection issues
- Service discovery problems

#### 3. NextCloud OnlyOffice App Configuration
**Configuration in NextCloud:**
```
DocumentServerUrl: https://onlyoffice.test-collab-site.com/
DocumentServerInternalUrl: http://127.0.0.1:8080/
```
**Potential problems:**
- URL mismatch between internal and external endpoints
- JWT secret synchronization issues
- App configuration corruption

#### 4. Service Communication Issues
**Potential problems:**
- OnlyOffice services not fully started
- Network connectivity between components
- Permission/firewall blocking internal requests
- Race conditions during service startup

## Manual Changes Made by Cursor

### Areas Modified
Based on the project status, manual configuration changes have been made to:
- OnlyOffice Document Server configuration
- Nginx proxy configuration
- NextCloud OnlyOffice app settings
- Possibly JWT token configurations

### Need to Document
**Critical:** We need to identify and document exactly what manual changes were made so they can be:
1. Validated as correct solutions
2. Incorporated into the installation scripts
3. Replicated in future deployments

## Current Configuration State

### OnlyOffice Service Status
**Expected behavior:**
- Service running and bound to 127.0.0.1:8000
- Health check endpoint responding: `curl http://127.0.0.1:8000/healthcheck`
- All API endpoints responding correctly

### NextCloud Integration Status
**Expected behavior:**
- OnlyOffice app installed and enabled
- Document server URLs configured correctly
- JWT tokens synchronized between systems
- Document editing working in NextCloud interface

### Nginx Proxy Status
**Expected behavior:**
- External OnlyOffice requests proxied correctly
- Internal NextCloud-to-OnlyOffice requests working
- WebSocket connections established for real-time editing
- Proper headers and timeouts configured

## Diagnostic Commands

### OnlyOffice Service Health
```bash
# Check service status
sudo systemctl status onlyoffice-documentserver

# Check specific service components
sudo systemctl status ds-docservice ds-converter ds-metrics

# Test health endpoint
curl -v http://127.0.0.1:8000/healthcheck

# Test via nginx proxy
curl -v http://127.0.0.1:8080/healthcheck

# Check OnlyOffice logs
sudo journalctl -u onlyoffice-documentserver -n 50
```

### NextCloud Integration Status
```bash
# Check OnlyOffice app status
sudo -u www-data php /var/www/nextcloud/occ app:list | grep onlyoffice

# Get current configuration
sudo -u www-data php /var/www/nextcloud/occ config:app:get onlyoffice DocumentServerUrl
sudo -u www-data php /var/www/nextcloud/occ config:app:get onlyoffice DocumentServerInternalUrl
sudo -u www-data php /var/www/nextcloud/occ config:app:get onlyoffice jwt_secret

# Check NextCloud logs for OnlyOffice errors
sudo tail -f /var/www/nextcloud/data/nextcloud.log | grep -i onlyoffice
```

### Nginx Configuration Validation
```bash
# Test nginx configuration
sudo nginx -t

# Check nginx access logs for OnlyOffice requests
sudo tail -f /var/log/nginx/access.log | grep onlyoffice

# Check nginx error logs
sudo tail -f /var/log/nginx/error.log
```

### Network Connectivity Tests
```bash
# Test direct OnlyOffice access
curl -I http://127.0.0.1:8000/

# Test OnlyOffice via nginx proxy
curl -I http://127.0.0.1:8080/

# Test external OnlyOffice endpoint
curl -I https://onlyoffice.test-collab-site.com/

# Test specific OnlyOffice API endpoints
curl -v http://127.0.0.1:8000/hosting/discovery
curl -v http://127.0.0.1:8080/hosting/discovery
```

## Script Hardcoding Issues

### Hardcoded Domain References
**Files containing `test-collab-site.com`:**
- All installation scripts in `src/` directory
- Configuration templates
- Nginx configuration files
- SSL certificate commands

### Required Parameterization
**Script modifications needed:**
1. **Domain parameter handling**
   ```bash
   DOMAIN=${1:-"example.com"}
   NEXTCLOUD_DOMAIN="docs.${DOMAIN}"
   ONLYOFFICE_DOMAIN="onlyoffice.${DOMAIN}"
   ```

2. **Configuration template substitution**
   ```bash
   sed "s/DOMAIN_PLACEHOLDER/${DOMAIN}/g" template.conf > final.conf
   ```

3. **Validation and error handling**
   ```bash
   if [[ -z "$DOMAIN" ]]; then
       echo "Error: Domain parameter required"
       exit 1
   fi
   ```

## Resolution Strategy

### Phase 1: Immediate Fixes
1. **Diagnose 502 errors** - identify exact failing endpoints
2. **Fix OnlyOffice configuration** - resolve service communication
3. **Correct nginx proxy** - ensure proper forwarding
4. **Synchronize JWT tokens** - fix authentication

### Phase 2: Script Updates
1. **Remove hardcoded domains** - parameterize all scripts
2. **Add input validation** - ensure robust parameter handling
3. **Update configuration templates** - make domain-agnostic
4. **Test parameterized scripts** - validate complete workflow

### Phase 3: Production Preparation
1. **Full system testing** - validate complete solution
2. **Documentation updates** - reflect all changes
3. **Deployment procedures** - prepare for bedfordfallsbbbl.org
4. **Backup and rollback plans** - ensure safety

## Success Metrics

### Integration Working
- [ ] All OnlyOffice endpoints return proper HTTP responses (no 502s)
- [ ] NextCloud can create new documents through OnlyOffice
- [ ] Document editing works reliably in NextCloud interface
- [ ] Collaborative editing functions correctly
- [ ] Document save/sync operates without errors

### Scripts Ready
- [ ] All scripts accept domain parameters
- [ ] No hardcoded domains remain
- [ ] Scripts can deploy to any domain successfully
- [ ] Complete workflow tested on clean system
- [ ] Documentation updated and accurate

This analysis provides the foundation for systematic resolution of the current issues and completion of the deployment script system.