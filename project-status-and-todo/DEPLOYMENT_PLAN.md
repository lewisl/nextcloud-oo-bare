# Deployment Plan: NextCloud + OnlyOffice Script Completion

**Date:** September 20, 2024
**Current Status:** Scripts written but with integration issues
**Goal:** Complete working script-based deployment system

## Current Situation

### What's Working
- ✅ NextCloud fully functional at `docs.test-collab-site.com`
- ✅ OnlyOffice service running and responsive to some endpoints
- ✅ Basic infrastructure (nginx, databases, SSL) operational
- ✅ Scripts exist for installation process

### Current Problems
- ❌ OnlyOffice endpoints returning 502 errors on some requests
- ❌ NextCloud cannot reach all OnlyOffice endpoints
- ❌ Integration between NextCloud and OnlyOffice incomplete
- ❌ Scripts have hardcoded domain `test-collab-site.com`
- ❌ Scripts need testing and refinement for clean deployment

### Target Deployment
- **Test domain:** `docs.test-collab-site.com` (current - fix here first)
- **Production target:** `docs.bedfordfallsbbbl.org` (replace existing Cloudron deployment)

## Phase 1: Fix Current Integration Issues

### 1.1 Diagnose OnlyOffice 502 Errors
**Tasks:**
- Run comprehensive diagnostics on current system
- Identify which specific OnlyOffice endpoints are failing
- Check nginx proxy configuration for OnlyOffice
- Verify OnlyOffice service status and logs
- Test direct vs proxied OnlyOffice endpoints

**Expected Issues:**
- Nginx proxy configuration mismatches
- OnlyOffice internal routing problems
- JWT token configuration issues
- WebSocket connection problems
- Port binding/forwarding issues

### 1.2 Fix OnlyOffice Configuration
**Tasks:**
- Correct OnlyOffice nginx configuration (`/etc/onlyoffice/documentserver/nginx/ds.conf`)
- Fix NextCloud nginx proxy settings for OnlyOffice
- Resolve JWT token synchronization between NextCloud and OnlyOffice
- Ensure proper WebSocket support for real-time editing
- Verify all OnlyOffice endpoints respond correctly

### 1.3 Verify Complete Integration
**Tasks:**
- Test document creation/editing through NextCloud
- Verify file save/sync functionality
- Test collaborative editing features
- Confirm all document types (.docx, .xlsx, .pptx) work
- Validate performance and stability

## Phase 2: Script Parameterization

### 2.1 Remove Hardcoded Domains
**Files to modify:**
- `src/01_system_prep_dual_domain.sh`
- `src/02_database_setup_dual_domain.sh`
- `src/03_nextcloud_install_dual_domain.sh`
- `src/04_onlyoffice_install_dual_domain.sh`
- `src/05_nginx_config_dual_domain.sh`
- `src/06_ssl_setup_dual_domain.sh`
- `src/07_integration_config_dual_domain.sh`

**Changes needed:**
- Replace `test-collab-site.com` with parameter variables
- Add domain validation and input handling
- Update nginx template configurations
- Modify SSL certificate requests
- Update NextCloud trusted domains configuration

### 2.2 Add Parameter Support
**Script parameters:**
```bash
BASE_DOMAIN="example.com"           # Base domain (e.g., bedfordfallsbbbl.org)
NEXTCLOUD_SUBDOMAIN="docs"          # NextCloud subdomain (default: docs)
ONLYOFFICE_SUBDOMAIN="onlyoffice"   # OnlyOffice subdomain (default: onlyoffice)
EMAIL="admin@example.com"           # Email for SSL certificates
```

**Usage:**
```bash
./src/01_system_prep_dual_domain.sh --domain bedfordfallsbbbl.org --email admin@bedfordfallsbbbl.org
```

### 2.3 Configuration Template System
**Create:**
- Nginx configuration templates with variable substitution
- NextCloud config templates
- OnlyOffice config templates
- Environment variable file for deployment settings

## Phase 3: Script Testing and Validation

### 3.1 Test Current Domain (test-collab-site.com)
**Process:**
1. Backup current working system
2. Test individual scripts with parameters
3. Validate each component after script execution
4. Test complete workflow from fresh system
5. Verify rollback capabilities

### 3.2 Create Automated Testing Framework
**Components:**
- Extend `src/00_test_runner.sh` with domain parameters
- Add integration tests for OnlyOffice endpoints
- Create validation scripts for each installation phase
- Implement automated rollback on failure

### 3.3 Documentation Updates
**Update:**
- `docs/QUICK_START.md` with parameterized commands
- `docs/DEPLOYMENT.md` with new domain procedures
- `docs/TROUBLESHOOTING.md` with 502 error solutions
- `CLAUDE.md` with updated command syntax

## Phase 4: Production Deployment Preparation

### 4.1 Pre-deployment Analysis
**Tasks:**
- Document current Cloudron deployment at bedfordfallsbbbl.org
- Create migration/backup plan for existing data
- Verify DNS requirements and SSL certificate needs
- Plan downtime window and rollback strategy

### 4.2 Deployment Testing
**Process:**
1. Test complete script workflow on clean test system
2. Validate all parameterized configurations
3. Performance test with realistic workloads
4. Security audit of final configuration
5. Create deployment checklist

### 4.3 Production Deployment
**Steps:**
1. Backup existing Cloudron deployment
2. Prepare new VPS with Ubuntu
3. Execute parameterized installation scripts
4. Migrate data from Cloudron backup
5. Update DNS and SSL certificates
6. Validate full functionality

## Success Criteria

### Phase 1 Complete
- [X] All OnlyOffice endpoints respond without 502 errors
- [X] NextCloud can create/edit documents through OnlyOffice
- [X] Collaborative editing works correctly
- [X] System is stable under normal usage

### Phase 2 Complete
- [ ] All scripts accept domain parameters
- [ ] No hardcoded domains remain in any script
- [ ] Configuration templates work with any domain
- [ ] Scripts validate input parameters

### Phase 3 Complete
- [ ] Complete script workflow tested successfully
- [ ] Automated testing framework operational
- [ ] All documentation updated and accurate
- [ ] Rollback procedures tested and documented

### Phase 4 Complete
- [ ] Production deployment at bedfordfallsbbbl.org successful
- [ ] All features working in production environment
- [ ] Performance meets requirements
- [ ] System ready for ongoing maintenance

## Risk Mitigation

### Configuration Loss Prevention
- Commit working configurations before changes
- Maintain backup of current working system
- Document all manual changes made by Cursor
- Create restore procedures for each phase

### Deployment Risks
- Test all scripts on isolated system first
- Maintain Cloudron backup until new system proven
- Have rollback plan with specific timelines
- Monitor system closely during initial production period

## Timeline Estimate

- **Phase 1 (Fix Integration):** 2-3 days
- **Phase 2 (Parameterization):** 3-4 days
- **Phase 3 (Testing):** 2-3 days
- **Phase 4 (Production Deployment):** 1-2 days

**Total estimated time:** 8-12 days

## Next Immediate Actions

1. **Diagnose current 502 errors** - identify root cause
2. **Fix OnlyOffice configuration** - resolve integration issues
3. **Test document editing** - verify full functionality works
4. **Begin script parameterization** - remove hardcoded domains
5. **Document current manual changes** - capture Cursor modifications

This plan provides a structured approach to completing the deployment system while minimizing risk to the currently working NextCloud installation.