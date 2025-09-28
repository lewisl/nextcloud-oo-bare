# Next Steps – Nextcloud + OnlyOffice Toolkit

**Date:** September 27, 2025  
**Current Status:** Scripts working; still need a pass of all scripts on bare host with no changes or direct command interventions 
**Architecture:** amd64 Hetzner VPS, Nextcloud + OnlyOffice on single host, `/onlyoffice/` subpath proxy

---

## What’s Working

- ✅ Guard harness (`tests/run_with_guard.sh`) protects live traffic during script runs
- ✅ Scripts 01–05 refactored to consume `configs/params.yaml`, with templates stored under `configs/`
- ✅ Known-good nginx vhost preserved and currently active on the test VPS

## Currently Broken / Needs Attention

- ✅ Nextcloud internal apps (dashboard, viewer, text, photos) return blank views after login
- ✅ `occ onlyoffice:documentserver --check` reports “Conversion error”; DocumentServer logs show JWT permission warnings
- ✅ Cloudflare/browser cache still suspected of serving stale assets despite initial purges

## Script Status and next steps at src/
- ✅ Scripts with 'dual-domain' in the name are misnamed now that we have successfully changed to a single domain 
- ✅ Scripts have been created/edited by different agents over a 6 week development process.  Pretty much all Codex and gpt-5-codex now.
- Script numbering does not always reflect the correct order of execution. **This needs to be investigated further**
- ✅ Scripts have only partially been updated to reflect the current successful deployment at the test site.
- ✅ You should evaluate all scripts for obvious bugs or out-of-date configurations, fix, and then tested
- Determine the correct order that scripts should be run by the admin; consider if specific operations should be moved between scripts to enable sensible operations.  rename the scripts to match the new correct order of execution.  
- Update documentation to show correct instructions for running the revised scripts

## Immediate Actions

1. **Lock in repo state**
   - Commit/push script refactors + configs now (pre-req before any snapshot rollback).

2. ✅ **Restore functionality before further refactors**
   - Diff active nginx vhost against templates and update `src/05_nginx_config.sh` to render the proven configuration.
   - Investigate OnlyOffice conversion error (JWT headers, docservice logs, service restart) until `occ onlyoffice:documentserver --check` passes again.
   - Confirm Cloudflare/cache isn’t serving stale JS (Development Mode, hard refresh). If issues persist, capture browser console/network errors.

3. **Plan execution order / rebuild checklist**
   - Re-evaluate script sequencing (nginx vs. SSL vs. integration) before touching scripts 06–07.
   - Document the intended run order and prerequisites in `docs/DEPLOYMENT.md` prior to additional refactors.
   - Before the next test cycle, follow `docs/REBUILD_TEST_SERVER.md` to rebuild the Hetzner host, recreate `/srv/collab`, and reclone the repo so we start from a clean slate.

4. **Documentation backlog**
   - Once regressions are cleared, update `docs/DEPLOYMENT.md`, `QUICK_START.md`, and `TROUBLESHOOTING.md` for the new flow.

## Open Questions / Decisions

- Whether to remove `onlyoffice.<domain>` DNS record immediately or keep as dormant fallback.
- ✅ Confirm Cloudflare SSL/TLS settings still align with single-origin approach (Full/Strict, proxy on).
- Determine plan for production cutover (bedfordfallsbbbl.org) once automation is stable again.

## Deferred / Nice-to-have

- Harden diagnostics script so it runs non-interactively without clearing terminal state.
- Evaluate lightweight monitoring (systemd timer or cron) to curl `/onlyoffice/healthcheck` and alert on failure.
- Document optional external storage integration steps for future growth.

---

**Owner:** Codex toolkit project  
**Next review checkpoint:** After automation scripts are updated and validated (target: early October 2025)
