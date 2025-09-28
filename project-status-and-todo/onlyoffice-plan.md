# OnlyOffice Installation & Integration Plan

## ✅ Key Issues Identified
- `src/04_onlyoffice_install_dual_domain.sh` rewrites OnlyOffice's bundled nginx to proxy to itself (127.0.0.1:8080 -> 127.0.0.1:8080), causing a loop instead of hitting docservice ports.
- The same script rewrites `local.json` via a broad `sed` that touches every `"string":` field, risking corruption of unrelated values.
- Systemd management references `ds-*` units that do not exist in current packages; actual service names differ.
- Integration script reachability check reuses the Nextcloud HTTP status for OnlyOffice, masking failures.
- `src/07_integration_config_dual_domain.sh` rebuilds `local.json` with hard-coded DB credentials, undermining prior configuration and template structure.
- `occ app:install onlyoffice` runs unconditionally; replays will fail if the app is already present.

## Planned Actions
1. ✅ **Baseline Validation**
   - Verify `params.yaml` parameters for OnlyOffice and Nextcloud domains.
   - Capture current OnlyOffice service names and log directories for reference.

2. ✅ **Stabilize `04_onlyoffice_install_dual_domain.sh`**
   - Update repository key handling, ensure `apt install` is re-runnable, and configure vendor nginx to bind localhost on a safe port without self-proxy.
   - Replace ad-hoc `local.json` edits with a template from `configs/onlyoffice/`, injecting DB/JWT values safely.
   - Manage the correct systemd units (`onlyoffice-documentserver` and associated timers) with enable/start semantics and health checks.
   - Reconcile generated main nginx proxy config with the known-good version and save back into `configs/nginx` after validation.

3. **Rework `07_integration_config_dual_domain.sh`**
   - Make app installation idempotent (install only if missing, otherwise ensure `app:enable`).
   - Adjust OnlyOffice/Nextcloud settings using `occ config:app:set` without clobbering `local.json`; reuse JWT/internal URLs defined earlier.
   - Correct reachability tests, add discovery/JWT verification calls, and log actionable diagnostics.
   - After creating the test document, run `occ files:scan --path="admin/files/test-document.txt"` so it appears in the UI.

4. **Diagnostics & Manual Overrides**
   - Prepare helper commands (curl discovery, `occ` checks, log tails) for troubleshooting during test runs.
   - Document how to toggle JWT, clear caches, or adjust nginx on the fly if needed.

5. **Align Overall Script Flow**
   - Once scripts are reliable, revisit numbering/order (likely `01` → `02` → `05` → `06` → `03` → `04` → `07`).
   - Update documentation to reflect the final deployment sequence for production domain rollout.
