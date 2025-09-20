
# Next Steps - Nextcloud + OnlyOffice Deployment

**Date:** September 14, 2025  
**Current Status:** Dual-domain installation completed with OnlyOffice integration issues identified  
**Architecture:** ARM64 (aarch64) - Dual domain approach implemented
 an cow 
## Current Situation

✅ **What Works:**
- Complete dual-domain installation scripts (01-07) created and executed
- Nextcloud accessible at `https://docs.test-collab-site.com` (HTTPS working)
- OnlyOffice accessible at `https://onlyoffice.test-collab-site.com` (HTTPS working)
- SSL certificates working for both domains
- Basic login functionality working
- **Nginx configuration fixed** with proper Nextcloud template
- **PostgreSQL database issues resolved** for OnlyOffice
- **JWT secret configured** for OnlyOffice integration
- **WebSocket support** configured in nginx
- **OnlyOffice services running** (docservice, converter, metrics)

❌ **Remaining Issues:**
- **OnlyOffice discovery endpoint missing**: `/hosting/discovery` returns 404 Not Found
- **Integration incomplete**: Nextcloud cannot discover OnlyOffice capabilities
- **Document editing not functional**: No OnlyOffice document types available in Nextcloud

🎯 **Recent Fixes Applied:**
- Replaced nginx configuration with official Nextcloud template
- Fixed PostgreSQL database name mismatch (OnlyOffice expects `onlyoffice` not `onlyoffice_documentserver`)
- Fixed OnlyOffice nginx port conflict (moved to 8080)
- Fixed Nextcloud HTTPS redirect settings

## Recent Major Fixes Applied

### OnlyOffice Discovery Endpoint Investigation (September 14, 2025)
- **Problem**: OnlyOffice integration failing with 404 errors on `/hosting/discovery`
- **Root Cause**: Discovery endpoint does not exist in OnlyOffice Document Server
- **Investigation Results**: 
  - Searched `/var/www/onlyoffice/documentserver` for discovery-related files
  - Searched `/etc/onlyoffice/documentserver/nginx` for hosting location blocks
  - **No discovery endpoints found** in OnlyOffice installation
- **Status**: OnlyOffice integration incomplete - missing discovery endpoint

### Nginx Configuration Fix (September 14, 2025)
- **Problem**: `/apps/dashboard/` returning 403 Forbidden errors
- **Root Cause**: Nginx configuration was not properly routing requests to PHP-FPM
- **Solution Applied**: Replaced nginx config with official Nextcloud template
- **Result**: Main Nextcloud page now works (302 redirect to login), but `/apps/` still needs verification
- **Status**: Configuration updated, needs testing with authenticated user

### PostgreSQL Database Fix
- **Problem**: OnlyOffice installation failing with database connection errors
- **Root Cause**: OnlyOffice package hardcodes database name as `onlyoffice` (not `onlyoffice_documentserver`)
- **Solution Applied**: Recreated database with correct name and user
- **Result**: OnlyOffice now installs and runs successfully

### OnlyOffice Nginx Port Conflict Fix
- **Problem**: OnlyOffice internal nginx conflicting with main nginx on port 80
- **Solution Applied**: Configured OnlyOffice to use port 8080
- **Result**: Both nginx instances now run without conflicts

## Immediate Next Steps

### 1. Investigate WOPI Alternative for OnlyOffice Integration
- [ ] **Research WOPI protocol**: Check if OnlyOffice supports WOPI instead of discovery endpoint
- [ ] **Check OnlyOffice documentation**: Look for alternative integration methods
- [ ] **Test direct API access**: Try accessing OnlyOffice APIs directly
- [ ] **Verify version compatibility**: Check if this OnlyOffice version supports Nextcloud integration

### 2. Alternative Integration Approaches
- [ ] **Manual configuration**: Try configuring OnlyOffice connector manually in Nextcloud
- [ ] **Check connector settings**: Verify all OnlyOffice connector settings are correct
- [ ] **Test document creation**: Try creating documents directly in OnlyOffice interface
- [ ] **Research community solutions**: Look for ARM64-specific OnlyOffice integration guides

### 3. Script Modifications Needed
- [ ] **Remove admin user creation** from `03_nextcloud_install_dual_domain.sh`
- [ ] **Add CAN_INSTALL file creation** to allow web installer
- [ ] **Ensure proper permissions** for web installer to work
- [ ] **Test web installer flow** end-to-end

### 4. Recovery Sequence
```bash
# 1. Complete cleanup
./99_uninstall_dual_domain.sh

# 2. Run modified scripts (without admin user creation)
./01_system_prep_dual_domain.sh
./02_database_setup_dual_domain.sh
./03_nextcloud_install_dual_domain.sh  # Modified to skip admin user

# 3. Access web installer
# Go to https://docs.test-collab-site.com
# Create admin user through web interface

# 4. Complete OnlyOffice integration
./04_onlyoffice_install_dual_domain.sh
./05_nginx_config_dual_domain.sh
./06_ssl_setup_dual_domain.sh your-email@domain.com
./07_integration_config_dual_domain.sh
```

## Research Commands to Try

```bash
# Check current architecture
uname -m

# Check if Docker has ARM64 OnlyOffice images
docker search onlyoffice

# Check OnlyOffice GitHub releases for ARM64 packages
curl -s https://api.github.com/repos/ONLYOFFICE/DocumentServer/releases/latest

# Look for ARM64-specific repositories
# (Research needed)
```

## Known Issues to Avoid

From previous attempts documented in `Failed attempt at manual install of NextCloud and OnlyOffice.md`:

1. **GPG Key Error**: `NO_PUBKEY 8320CA65CB2DE8E5`
   - Standard GPG key import methods don't work
   - Tried copying to `/etc/apt/trusted.gpg.d/` - still failed

2. **Architecture Mismatch**: 
   - OnlyOffice standard repo assumes x86_64
   - ARM64 packages may not exist in main repo

3. **Repository Issues**:
   - `https://download.onlyoffice.com/repo/debian squeeze main` 
   - May not have ARM64 builds

## Issues Fixed During Reinstall

4. **PostgreSQL Password Authentication**: 
   - Database setup script creates user but password authentication fails
   - **Fix Applied**: Added `ALTER USER onlyoffice PASSWORD 'onlyoffice_password';` after user creation
   - **Script to Fix**: `02_database_setup_dual_domain.sh` - add password setting after user creation

5. **ds-example.service Warning**:
   - Harmless warning from OnlyOffice Document Server example service
   - Not an error - service doesn't exist until OnlyOffice is installed
   - **No Action Needed**: This is expected behavior

6. **SSL/HTTPS Order of Operations Issue**:
   - **Problem**: Web installer requires HTTP access but domain is proxied through Cloudflare with HTTPS
   - **Immediate Workaround**: Unproxy site at Cloudflare to allow HTTP access
   - **Root Cause**: Scripts assume HTTP access for initial setup, but domain is already configured for HTTPS
   - **Action Required**: Rethink entire setup order to handle SSL/HTTPS properly

## Critical Setup Order Issues to Address

### Current Problematic Order:
1. System prep (installs nginx, PHP, databases)
2. Database setup
3. Nextcloud install (expects HTTP access for web installer)
4. OnlyOffice install
5. Nginx config ← **TOO LATE!**
6. SSL setup ← **TOO LATE!**

### Root Problem Identified:
**Partial installations create "works for testing but not for users" state**
- ✅ Server-side: Nextcloud installed, database connected, basic functionality works
- ❌ User-side: Nginx routing incomplete, apps don't load, setup can't be completed
- ❌ Production-ready: Installation is not usable by end users

### Proposed Better Order:
1. System prep (installs nginx, PHP, databases)
2. Database setup
3. **Nginx configuration FIRST** (complete routing setup)
4. **SSL setup** (Let's Encrypt certificates)
5. Nextcloud install (with proper nginx routing and HTTPS)
6. **OnlyOffice install** (after nginx and SSL are configured)
7. Integration config

### Why This Order Eliminates Issues:
- **No HTTP/HTTPS switching**: Everything is HTTPS from the start
- **No proxy conflicts**: Nginx is fully configured before any services
- **No port conflicts**: OnlyOffice gets proper port assignment (8080)
- **No database confusion**: PostgreSQL is set up correctly before OnlyOffice
- **Complete user experience**: Each step creates a fully functional state

### Additional Order Issue Discovered:
**Current Script Order Problem:**
- Script 04: OnlyOffice install
- Script 05: Nginx config ← **TOO LATE!**
- Script 06: SSL setup
- Script 07: Integration config

**Why This Fails:**
- OnlyOffice needs nginx properly configured to be accessible
- Without nginx config, OnlyOffice integration testing will fail
- SSL setup needs nginx config to be complete first

### Corrected Script Execution Order:
**For Current Setup (with existing scripts):**
1. ✅ `01_system_prep_dual_domain.sh` (completed)
2. ✅ `02_database_setup_dual_domain.sh` (completed)
3. ✅ `03_nextcloud_install_dual_domain.sh` (completed)
4. **`05_nginx_config_dual_domain.sh`** ← Run this first!
5. **`06_ssl_setup_dual_domain.sh`** ← Then SSL
6. **`04_onlyoffice_install_dual_domain.sh`** ← Then OnlyOffice
7. **`07_integration_config_dual_domain.sh`** ← Finally integration

**Why This Order Works:**
- Nginx gets fully configured before any service installation
- SSL certificates are obtained before service configuration
- OnlyOffice installs with proper nginx and SSL already in place
- No HTTP/HTTPS switching or proxy conflicts
- End-to-end testing is possible at each step

### Future Script Reordering:
**For New Deployments (recommended order):**
1. `01_system_prep_dual_domain.sh`
2. `02_database_setup_dual_domain.sh`
3. `05_nginx_config_dual_domain.sh`
4. `06_ssl_setup_dual_domain.sh`
5. `03_nextcloud_install_dual_domain.sh`
6. `04_onlyoffice_install_dual_domain.sh`
7. `07_integration_config_dual_domain.sh`

### Why Nginx Must Come First:
- **User Experience**: Without proper nginx routing, apps return 403 errors
- **Complete Setup**: Users can't access `/apps/dashboard/` or other app routes
- **Production Ready**: Each step must create a fully functional state

### Alternative Approaches:
- **Option A**: Set up temporary HTTP subdomain for initial setup
- **Option B**: Configure SSL certificates before Nextcloud installation
- **Option C**: Use local IP access for initial setup, then configure domain
- **Option D**: Modify scripts to handle HTTPS from the start

### Required Script Modifications:

7. **Disable HTTPS Redirect During Setup**:
   - **Problem**: Nextcloud forces HTTPS redirects before SSL certificates are configured
   - **Fix Needed**: Add step to disable HTTPS redirects before web installer
   - **Commands**: 
     ```bash
     sudo -u www-data php /var/www/nextcloud/occ config:system:delete overwrite.cli.url
     sudo -u www-data php /var/www/nextcloud/occ config:system:set overwriteprotocol --value="http"
     ```
   - **Script to Modify**: `03_nextcloud_install_dual_domain.sh` - add after web installer completion

8. **Re-enable HTTPS After SSL Setup**:
   - **Problem**: Need to restore HTTPS redirects after SSL certificates are configured
   - **Fix Needed**: Add step to re-enable HTTPS redirects after SSL setup
   - **Commands**:
     ```bash
     sudo -u www-data php /var/www/nextcloud/occ config:system:set overwriteprotocol --value="https"
     sudo -u www-data php /var/www/nextcloud/occ config:system:set overwrite.cli.url --value="https://docs.test-collab-site.com"
     ```
   - **Script to Modify**: `06_ssl_setup_dual_domain.sh` - add after SSL certificate installation

9. **errors in 01_system_prep_dual_domain.sh**
- sed: -e expression #1, char 67: unknown option to `s' during Generating Secrets
- this is minor: Restarting services...
 systemctl restart ds-example.service
Failed to restart ds-example.service: Unit ds-example.service not found.

## User Experience Completion Checklist

### Before Declaring Setup Complete, Verify:
- [ ] **Basic Access**: `http://domain.com` loads Nextcloud login page
- [ ] **App Routing**: `http://domain.com/apps/dashboard/` loads (not 403 error)
- [ ] **File Upload**: Upload button works and files can be uploaded
- [ ] **Admin Panel**: Settings accessible at `http://domain.com/settings/admin`
- [ ] **User Management**: Can create additional users
- [ ] **App Installation**: Can install/enable apps from app store
- [ ] **Database Apps**: Dashboard, Notes, and other default apps work
- [ ] **SSL/HTTPS**: After SSL setup, all above work over HTTPS
- [ ] **OnlyOffice Integration**: Document editing works in browser
- [ ] **End-to-End**: Complete user workflow from login to file editing

### Server-Side Tests (Not Sufficient):
- [x] Nextcloud `occ status` shows installed
- [x] Database connection works
- [x] PHP-FPM processes running
- [x] Nginx serving basic pages

**Note**: Server-side tests passing does NOT mean user experience works!

## Success Criteria

- [ ] OnlyOffice Document Server running on `127.0.0.1:8080`
- [ ] Nginx reverse proxy working: `https://test-collab-site.com/onlyoffice/`
- [ ] Nextcloud integration functional
- [ ] Document editing works in browser
- [ ] JWT authentication properly configured
- [ ] **ALL User Experience Completion Checklist items verified**

## Files to Reference

- **Scripts**: `/srv/collab/src/` - All installation scripts
- **Research**: `/srv/collab/Project Documents/Failed attempt at manual install of NextCloud and OnlyOffice.md`
- **Config Examples**: `/srv/collab/Project Documents/nginx_config_for_one_domain_no_docker.md`
- **Architecture Notes**: `/srv/collab/Project Documents/chatgpt research.md`

## Emergency Fallback

If OnlyOffice proves impossible on ARM64:
- Deploy Nextcloud-only (scripts 01-03, 05-06)
- Document the limitation
- Consider x86_64 server for OnlyOffice requirement

---

**Remember**: Augment Code got this working on the same hardware, so there IS a solution!
