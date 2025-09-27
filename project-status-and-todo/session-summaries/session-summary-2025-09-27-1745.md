# Session Summary — September 27, 2025 @ 17:45 UTC

## Objectives
- Capture the ready-to-rebuild checklist after hardening the single-domain automation scripts.
- Confirm which pre-rebuild tasks still matter (params, DNS, secrets).
- Decide how to handle the Cloudflare proxy during the next deployment run.

## Key Notes
- `params.yaml` and generated secrets are ephemeral; they will regenerate on a fresh host, so no prework is needed there.
- Current DNS change is only the Cloudflare proxy toggle (set to "DNS only"); leave it off until after SSL + connector checks succeed on the rebuilt box.
- No value in snapshotting the current VPS—repo state is the source of truth and will be recloned.

## Rebuild Checklist
1. Clone repo on fresh host; run scripts sequentially: `01_system_prep.sh` → (`02_database_setup.sh` if required) → `03_nextcloud_install.sh` → `04_onlyoffice_install.sh` → `05_nginx_config.sh` → `06_ssl_setup.sh` (production Let's Encrypt cert with proxy off) → `07_integration_config.sh`.
2. Smoke tests:
   - After `04`: `curl -fsS http://127.0.0.1:8080/healthcheck`.
   - After `05`: `nginx -t && systemctl reload nginx`.
   - After `06`/`07`: `curl -kI https://docs.test-collab-site.com/onlyoffice/healthcheck`, run `occ onlyoffice:documentserver --check`, and open a sample document in the browser.
3. Secrets/params regenerate automatically; only ensure `/etc/nextcloud-onlyoffice/params.yaml` exists post-`01`.
4. Once the origin passes connector checks, re-enable the Cloudflare proxy and re-run the connector test to confirm TLS/websocket behaviour.

## Follow-Up
- Schedule the rebuild window; once the fresh host is ready, execute the checklist and capture results in a new session summary.
- After proxy re-enable, document any adjustments needed for Cloudflare headers or caching.
