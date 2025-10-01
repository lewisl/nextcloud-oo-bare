# Session Summary — 2025-10-01 03:38 UTC

## Context
Fresh single-domain deployment (Nextcloud + OnlyOffice DocumentServer under /onlyoffice) on Ubuntu 24.04. All infra stood up (nginx, PHP-FPM, Redis, MariaDB, Postgres, OnlyOffice DS), SSL OK. Final integration failed because the OnlyOffice Nextcloud connector app was missing.

## Root Cause
- Nextcloud App Store outage/500 responses made the OnlyOffice connector “disappear” from the GUI Apps catalog and caused `occ app:install onlyoffice` to fail.
- Our scripts did not regress: 03_nextcloud_install.sh never installed the connector (by design). The connector is installed/configured in script 07. The outage prevented the normal path.

## One-time Remediation Applied (no core script changes)
- Manually installed OnlyOffice connector from GitHub release (compatible with NC 31):
  - OnlyOffice Nextcloud app v9.7.0: https://github.com/ONLYOFFICE/onlyoffice-nextcloud/releases/tag/v9.7.0
  - Asset used: `onlyoffice.tar.gz`
- Enabled the app and wired connector settings:
  - DocumentServerUrl: https://docs.test-collab-site.com/onlyoffice/
  - DocumentServerInternalUrl: http://127.0.0.1:8080/
  - StorageUrl: https://docs.test-collab-site.com/
  - jwt_enabled: true
  - jwt_header: Authorization
  - jwt_secret: copied from /etc/onlyoffice/documentserver/local.json (CoAuthoring.secret.browser.string)
- Verified integration:
  - `occ onlyoffice:documentserver --check` → “Document server … is successfully connected.”

## Notes
- We saw a transient CLI hiccup (quoting/EOF while setting config in a one-liner); resolved by writing the JWT to a file then passing it safely to `occ`.
- “Open in the same tab” preference appears off now. This can be toggled later via OnlyOffice app settings (GUI) or `occ config:app:set onlyoffice sameTab --value=true`. We deferred.
- We also corrected earlier nginx subpath proxy headers (already in repo):
  - X-Forwarded-Host = $host
  - X-Forwarded-Prefix = /onlyoffice

## Why this happened
- The Nextcloud Apps catalog is populated dynamically from apps.nextcloud.com. When the store returns 500, non-bundled apps won’t show up and `occ app:install` fails. Recently, Nextcloud shipped a major release, so intermittent App Store instability is plausible.

## Decision
- Do not change core scripts yet. We’ll observe App Store stability; the manual fallback lives as an operator helper (see diagnostics script below). If outages persist, we can integrate an automatic GitHub fallback in 07 with version pinning per NC major.

## Operator Helper (one-time fix)
See `diagnostics/onlyoffice_connector_manual_fix.sh` committed alongside this summary for the exact, idempotent steps we used to recover when the App Store was down.

## Quick Verification Commands
- App presence: `sudo -u www-data php /var/www/nextcloud/occ app:list | grep onlyoffice`
- Connector check: `sudo -u www-data php /var/www/nextcloud/occ onlyoffice:documentserver --check`
- DS health: `curl -I https://<fqdn>/onlyoffice/healthcheck`

## Next steps (optional)
- Flip “same tab” preference later if desired: `sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice sameTab --value=true`
- If App Store instability continues, add a guarded fallback path in 07 to fetch from GitHub with Nextcloud-version-aware compatibility.

