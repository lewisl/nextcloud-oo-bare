# Next Steps – Nextcloud + OnlyOffice Toolkit

**Date:** September 24, 2025  
**Current Status:** One-domain deployment validated on test VPS (docs.test-collab-site.com)  
**Architecture:** amd64 Hetzner VPS, Nextcloud + OnlyOffice on single host, `/onlyoffice/` subpath proxy

---

## What’s Working

- ✅ Nextcloud served at `https://docs.<domain>` with full app functionality
- ✅ OnlyOffice Document Server reachable via subpath (`/onlyoffice/`) and loopback (`127.0.0.1:8080`)
- ✅ JWT secret synchronized between Nextcloud and Document Server (`occ onlyoffice:documentserver --check` passes)
- ✅ Browser smoke tests for `.docx`, `.xlsx`, `.pptx`, `.pdf`, markdown, and image viewers
- ✅ Legacy `onlyoffice.<domain>` nginx site disabled while keeping rollback symlink

## Immediate Actions

1. **Retire unused TLS certificate**
   - Run `certbot delete --cert-name onlyoffice.test-collab-site.com` (or equivalent) to stop renewal attempts.
   - Remove any cron/systemd renewal hooks specific to the old hostname.

2. **Update documentation** *(in progress)*
   - ✅ `CURRENT_BEST_CONFIGURATIONS.md` updated.
   - ✅ `Systematic testing.md` updated with execution record.
   - ☐ Refresh `docs/DEPLOYMENT.md`, `QUICK_START.md`, and `TROUBLESHOOTING.md` to reference one-domain flow.

3. **Automation alignment**
   - Extract the validated manual steps into `src/05_nginx_config_dual_domain.sh` and `src/07_integration_config_dual_domain.sh` (rename to reflect single-domain mode).
   - Ensure scripts deploy `/etc/nginx/conf.d/00_websocket_upgrade_map.conf` and disable the legacy vhost if present.
   - Add OCC commands to enforce the new URLs and JWT header consistently.

4. **Testing cadence**
   - Re-run `./src/00_test_runner.sh` once scripts are updated to confirm idempotency.
   - Add a targeted smoke-test script for `/onlyoffice/` subpath (curl + occ + browser checklist reference).

## Open Questions / Decisions

- Whether to remove `onlyoffice.<domain>` DNS record immediately or keep as dormant fallback.
- Confirm Cloudflare SSL/TLS settings still align with single-origin approach (Full/Strict, proxy on).
- Determine plan for production cutover (bedfordfallsbbbl.org) once automation is updated and retested.

## Deferred / Nice-to-have

- Harden diagnostics script so it runs non-interactively without clearing terminal state.
- Evaluate lightweight monitoring (systemd timer or cron) to curl `/onlyoffice/healthcheck` and alert on failure.
- Document optional external storage integration steps for future growth.

---

**Owner:** Codex toolkit project  
**Next review checkpoint:** After automation scripts are updated and validated (target: early October 2025)
