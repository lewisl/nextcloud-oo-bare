# Critical Development Rules - No Regressions

## 🚨 MANDATORY RULES - NEVER BREAK THESE

### 1. Version Control First
- **ALWAYS commit working state before ANY changes**
- Make small, incremental commits
- Each commit should be a single logical change
- Test before committing
- Use descriptive commit messages

### 2. Change Management
- **Make ONE change at a time**
- Test immediately after each change
- If change breaks anything, revert immediately
- Don't try to "fix" with more changes
- Ask permission before making changes to working systems

### 3. Configuration Safety
- **Never override working configurations without understanding the full system**
- Read existing configs first, don't assume
- Document every change and why it's needed
- Capture current state before making changes
- Use configuration management tools when available

### 4. Testing Protocol
- Test end-to-end functionality after each change
- Verify all related services still work
- Check logs for errors after changes
- Test both internal and external access
- Validate user experience, not just technical functionality

### 5. Troubleshooting Approach
- **Read first, change second**
- Understand the problem before proposing solutions
- Check logs and existing documentation
- Ask clarifying questions before making changes
- If unsure about a change, ask user first

### 6. Diagnosis vs. Fixing
- **"Diagnose" means TEST and EXAMINE only - NO CHANGES**
- Run tests and examine output to determine potential causes
- Document the cause of problems and save in project for review
- May include proposals for specific solutions
- May document proposed fixes or changes
- **"Diagnose" does NOT mean fix, change, or run commands that modify the system**
- Only make changes after explicit permission to proceed with fixes

### 7. Configuration Documentation
- **Maintain current best versions** of all important configuration files
- Save working configurations as part of project documentation
- Update documentation immediately after fixing something
- Store configurations in version control with clear commit messages
- Never lose working configurations when making changes
- Keep a "golden copy" of each working configuration

### 8. Recovery Procedures
- Always have a rollback plan
- Know how to revert each type of change
- Keep backups of critical configurations
- Document recovery procedures
- Test recovery procedures before needing them

## 🔧 SPECIFIC TO THIS PROJECT

### NextCloud + OnlyOffice Integration
- Never change JWT secrets without understanding the full auth flow
- Always check both NextCloud and OnlyOffice configurations
- Verify port configurations match nginx setup
- Test document editing functionality after any changes
- Check both internal and external URLs

### Nginx Configuration
- Never modify nginx configs without understanding the full routing
- Test all proxy configurations
- Verify SSL/TLS settings
- Check WebSocket support for OnlyOffice
- Validate all location blocks

### Database Changes
- Always backup before schema changes
- Test connection strings after changes
- Verify user permissions
- Check for data integrity issues

## 📋 CHECKLIST BEFORE ANY CHANGE

- [ ] Current state is committed to git
- [ ] I understand what the current system does
- [ ] I have a clear rollback plan
- [ ] I'm making only ONE change
- [ ] I have permission to make this change
- [ ] I know how to test the change
- [ ] I know what could break

## 🚫 NEVER DO THESE

- Make multiple changes simultaneously
- Override working configurations without understanding them
- Assume what a configuration does without reading it
- Try to "fix" a broken system with more changes
- Skip testing after changes
- Work on production systems without permission
- Make changes without committing working state first

## ✅ ALWAYS DO THESE

- Commit working state before changes
- Make one change at a time
- Test immediately after each change
- Ask permission for changes
- Document what you're changing and why
- Have a rollback plan
- Test end-to-end functionality
- Read existing configurations first

---

**Remember: It's better to ask permission and be slow than to break a working system and be fast.**
