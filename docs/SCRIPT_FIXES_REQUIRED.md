# Script Fixes Required

**Date:** September 20, 2024
**Status:** OnlyOffice services now running after manual fixes

## Critical Issues Found and Fixed

### 1. Missing OnlyOffice Log4js Configuration File
**Problem:** OnlyOffice services failing with log configuration error
**Root Cause:** Missing `production-linux.json` log4js configuration file
**Manual Fix Applied:**
```bash
cp /etc/onlyoffice/documentserver/log4js/production.json /etc/onlyoffice/documentserver/log4js/production-linux.json
```

**Script Changes Needed:**
- Add this copy command to OnlyOffice installation script
- Ensure log4js configuration files are properly created

### 2. Incorrect systemd Service Environment
**Problem:** Services looking for wrong NODE_ENV and log files
**Root Cause:** systemd service files configured for wrong environment names
**Manual Fix Applied:**
- Changed `NODE_ENV=production` to `NODE_ENV=production-linux` in:
  - `/etc/systemd/system/ds-docservice.service`
  - `/etc/systemd/system/ds-converter.service`

**Script Changes Needed:**
- Update OnlyOffice installation script to create service files with correct environment
- Or ensure `production.json` config exists with proper naming

### 3. Invalid OnlyOffice JWT Token Configuration Structure
**Problem:** Services failing with "Configuration property 'services.CoAuthoring.token.enable.request.outbox' is not defined"
**Root Cause:** Incorrect JWT token configuration structure in `local.json`

**Manual Fix Applied:**
Changed `/etc/onlyoffice/documentserver/local.json` from:
```json
"token": {
  "enable": true,
  "inbox": { "string": "GeE90SG6xtH@%N" },
  "outbox": { "string": "GeE90SG6xtH@%N" },
  "browser": { "string": "GeE90SG6xtH@%N" },
  "authorizationHeader": "Authorization"
}
```

To:
```json
"token": {
  "enable": {
    "browser": true,
    "request": {
      "inbox": false,
      "outbox": false
    }
  },
  "browser": {
    "secretFromInbox": true
  },
  "inbox": {
    "header": "Authorization",
    "prefix": "Bearer ",
    "inBody": false
  },
  "outbox": {
    "header": "Authorization",
    "prefix": "Bearer ",
    "algorithm": "HS256",
    "expires": "5m"
  }
}
```

**Script Changes Needed:**
- Update OnlyOffice configuration template with correct JWT structure
- Ensure JWT tokens are disabled for initial setup (`inbox: false, outbox: false`)

### 4. OnlyOffice Private IP Address Blocking
**Problem:** OnlyOffice blocking connections to localhost/private IPs for security
**Root Cause:** Default security setting prevents OnlyOffice from downloading files from `127.0.0.1:8080`
**Error:** `DNS lookup 127.0.0.1 is not allowed. Because, It is private IP address.`

**Manual Fix Applied:**
Added to `/etc/onlyoffice/documentserver/local.json`:
```json
"server": {
  "port": 8000,
  "allowPrivateIPAddress": true,
  "allowIPAddressForRequests": true
}
```

**Script Changes Needed:**
- Add private IP address permissions to OnlyOffice configuration template
- This allows OnlyOffice to communicate with NextCloud via internal localhost URLs

## OnlyOffice Services Status

### Required Services (3 total):
1. **ds-docservice** ✅ RUNNING - Document editing service (port 8000)
2. **ds-converter** ✅ RUNNING - File conversion service
3. **ds-metrics** ✅ RUNNING - Metrics collection service

### Not Required:
- **ds-example** - Example service (disabled, not needed)

## Current Working Configuration

### Service Status:
```bash
systemctl status ds-docservice ds-converter ds-metrics
```

### Key Configuration Files:
- `/etc/onlyoffice/documentserver/local.json` - Main OnlyOffice config (FIXED)
- `/etc/onlyoffice/documentserver/log4js/production-linux.json` - Log config (CREATED)
- `/etc/systemd/system/ds-docservice.service` - Service definition (FIXED)
- `/etc/systemd/system/ds-converter.service` - Service definition (FIXED)

## Next Steps for Script Updates

### Priority 1: OnlyOffice Installation Script (`src/04_onlyoffice_install_dual_domain.sh`)
1. **Add log4js file creation:**
   ```bash
   cp /etc/onlyoffice/documentserver/log4js/production.json \
      /etc/onlyoffice/documentserver/log4js/production-linux.json
   ```

2. **Use correct JWT configuration template** - Replace JWT token section with proper structure

3. **Ensure correct systemd environment** - Either:
   - Set `NODE_ENV=production-linux` in service files, OR
   - Create proper `production.json` → `production-linux.json` mapping

### Priority 2: Integration Script (`src/07_integration_config_dual_domain.sh`)
1. **Verify all 3 services are running** before proceeding with NextCloud integration
2. **Add service validation** with proper error handling

### Priority 3: Diagnostic Script (`src/99_diagnostics.sh`)
1. **Add checks for all 3 OnlyOffice services**
2. **Add JWT configuration validation**
3. **Add log4js configuration file checks**

## Testing Required After Script Updates

1. **Clean installation test** - Deploy on fresh system using updated scripts
2. **Service startup validation** - Ensure all 3 services start correctly
3. **Configuration validation** - Verify JWT and log configurations are correct
4. **Integration test** - Confirm NextCloud can connect to OnlyOffice

## Files to Update

### Must Update:
- `src/04_onlyoffice_install_dual_domain.sh` - OnlyOffice installation
- `src/07_integration_config_dual_domain.sh` - Integration configuration
- `src/99_diagnostics.sh` - Diagnostic checks

### Should Update:
- `docs/TROUBLESHOOTING.md` - Add these specific fixes
- `docs/CURRENT_BEST_CONFIGURATIONS.md` - Update with working config

### Configuration Templates:
- OnlyOffice `local.json` template needs JWT structure fix
- systemd service templates need environment correction

---

**Status:** Manual fixes complete, OnlyOffice services running. Ready to update scripts with these fixes.