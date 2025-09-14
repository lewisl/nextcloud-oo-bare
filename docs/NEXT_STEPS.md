
# Next Steps - Nextcloud + OnlyOffice Deployment

**Date:** September 14, 2025  
**Current Status:** Dual-domain installation completed but with critical issues  
**Architecture:** ARM64 (aarch64) - Dual domain approach implemented

## Current Situation

✅ **What Works:**
- Complete dual-domain installation scripts (01-07) created and executed
- Nextcloud accessible at `https://docs.test-collab-site.com`
- OnlyOffice accessible at `https://onlyoffice.test-collab-site.com`
- SSL certificates working for both domains
- Basic login functionality working

❌ **Critical Issues:**
- Admin user created via `occ` commands instead of web installer
- Missing default files and sample content
- Upload/add button not functional
- Default apps (dashboard, notes) not properly initialized
- Configuration corrupted by manual admin user creation

🎯 **Root Cause:**
- Used `occ` commands to create admin user instead of letting web installer handle it
- This bypassed proper initialization of user data directory and skeleton files
- Web installer is now blocked due to existing incomplete configuration

## Immediate Next Steps

### 1. Fix Nextcloud Installation Issues
- [ ] **Complete uninstall**: Remove all traces of current installation
- [ ] **Modify scripts**: Update installation scripts to NOT create admin user via `occ`
- [ ] **Let web installer run**: Allow Nextcloud web installer to create admin user properly
- [ ] **Verify default files**: Ensure skeleton directory and sample files are created
- [ ] **Test functionality**: Verify upload, apps, and all default features work

### 2. Script Modifications Needed
- [ ] **Remove admin user creation** from `03_nextcloud_install_dual_domain.sh`
- [ ] **Add CAN_INSTALL file creation** to allow web installer
- [ ] **Ensure proper permissions** for web installer to work
- [ ] **Test web installer flow** end-to-end

### 3. Recovery Sequence
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

## Success Criteria

- [ ] OnlyOffice Document Server running on `127.0.0.1:8080`
- [ ] Nginx reverse proxy working: `https://test-collab-site.com/onlyoffice/`
- [ ] Nextcloud integration functional
- [ ] Document editing works in browser
- [ ] JWT authentication properly configured

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
