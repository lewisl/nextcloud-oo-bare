# Next Steps - Nextcloud + OnlyOffice Deployment

**Date:** September 12, 2025  
**Current Status:** System cleaned, ready for fresh installation  
**Architecture:** ARM64 (aarch64) - This is KEY to the OnlyOffice issue

## Current Situation

✅ **What Works:**
- Scripts 01-03 (system prep, database, Nextcloud) have worked previously
- System is completely clean after running `99_uninstall.sh`
- All components removed, ready for fresh start

❌ **Main Issue:**
- OnlyOffice Document Server fails to install via standard APT repository on ARM64
- GPG key issues: `NO_PUBKEY 8320CA65CB2DE8E5`
- Standard OnlyOffice repo doesn't seem to have proper ARM64 packages

🎯 **Key Insight:**
- **Augment Code successfully deployed OnlyOffice on this EXACT same ARM64 server**
- This proves it IS possible - we just need to find the right method

## Immediate Next Steps

### 1. Research OnlyOffice ARM64 Installation Methods
- [ ] Check if OnlyOffice has official ARM64 Docker images
- [ ] Look for manual .deb package downloads for ARM64
- [ ] Research building from source for ARM64
- [ ] Check if there's a different repository for ARM64 packages
- [ ] Look into snap/flatpak alternatives

### 2. Alternative Installation Approaches
- [ ] **Docker Method**: OnlyOffice officially supports Docker - check ARM64 images
- [ ] **Manual Download**: Direct .deb download from OnlyOffice releases
- [ ] **Build from Source**: Last resort but most flexible
- [ ] **Different Repository**: Check if there's an ARM64-specific repo

### 3. Quick Test Sequence
Once we find the right OnlyOffice method:
```bash
# 1. Run the working scripts
./01_system_prep.sh    # ~5 minutes
./02_database_setup.sh # ~2 minutes  
./03_nextcloud_install.sh # ~3 minutes

# 2. Install OnlyOffice using discovered method
# (Method TBD based on research)

# 3. Complete the deployment
./05_nginx_config.sh   # Configure reverse proxy
./06_ssl_setup.sh your-email@domain.com test-collab-site.com
./07_integration_config.sh # Connect Nextcloud + OnlyOffice
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
