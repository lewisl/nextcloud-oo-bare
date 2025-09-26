# Per-Script Execution Checklists (2025-09-25)

These checklists keep testing incremental. After each script is refactored, run the matching plan on the test VPS before moving on. Capture command output in `project-status-and-todo/test-results/` (one file per script + date). If a step fails, stop, fix, and rerun from the top of that script.

---

## 01_system_prep.sh
**Preconditions**
- Snapshot/backup taken or VM disposable.
- `/etc/nextcloud-onlyoffice/params.yaml` exists or template ready.

**Steps**
1. Run `sudo ./src/01_system_prep.sh`.
2. Record generated Nextcloud admin password + JWT secret from console output.
3. Check `/var/log/nextcloud-install.log` for errors (`tail -n 50`).
4. Verify services: `systemctl status nginx php8.3-fpm mariadb postgresql redis-server fail2ban`.
5. Confirm UFW rules (`sudo ufw status`) and Redis socket permissions (`stat /run/redis/redis-server.sock`).

**Diagnostics & Pass Criteria**
- `NC_OO_PARAMS_PATH=/etc/nextcloud-onlyoffice/params.yaml python3 src/lib/config_loader.py --get deployment.nextcloud_admin_password` → non-placeholder value with length ≥ 16.
- `NC_OO_PARAMS_PATH=/etc/nextcloud-onlyoffice/params.yaml python3 src/lib/config_loader.py --get jwt.secret` → non-placeholder 64 hex chars.
- `sudo systemctl is-active nginx php8.3-fpm mariadb postgresql redis-server fail2ban` → each reports `active`.
- `sudo ufw status` → shows `Status: active` and allows `OpenSSH`, `80/tcp`, `443/tcp`.
- `stat -c "%U:%G %a" /run/redis/redis-server.sock` → owner `redis`, group `redis`, permissions `660` (or `770` depending on distro); document actual result in test log.

**Rollback/Recovery**
- If secrets were regenerated unintentionally, restore prior `/etc/nextcloud-onlyoffice/params.yaml` from backup or snapshot.
- If package install broke, `apt-get remove` the new packages or revert snapshot.

---

## 02_database_setup.sh
**Preconditions**
- `01_system_prep.sh` completed successfully.
- MariaDB/PostgreSQL running (`systemctl status`).

**Steps**
1. Run `sudo ./src/02_database_setup.sh`.
2. Validate MariaDB access: `mysql -u "$NEXTCLOUD_DB_USER" -p'***' -e "SHOW DATABASES;"`.
3. Validate PostgreSQL access: `PGPASSWORD=*** psql -h localhost -U "$ONLYOFFICE_DB_USER" -d "$ONLYOFFICE_DB_NAME" -c "\dt"`.
4. Check `pg_hba.conf` contains localhost-only rules.
5. Log outputs to `test-results/database_setup_<date>.txt`.

**Diagnostics & Pass Criteria**
- `mysql -u "$NEXTCLOUD_DB_USER" -p'***' -e "SELECT 1;" "$NEXTCLOUD_DB_NAME"` → returns `1`.
- `mysql -u root -e "SHOW GRANTS FOR '$NEXTCLOUD_DB_USER'@'localhost';"` → includes privileges on `$NEXTCLOUD_DB_NAME`.
- `PGPASSWORD=*** psql -h localhost -U "$ONLYOFFICE_DB_USER" -d "$ONLYOFFICE_DB_NAME" -c "SELECT 1;"` → returns `1`.
- `sudo -u postgres psql -d "$ONLYOFFICE_DB_NAME" -c '\dt'` → shows Document Server tables (if previously installed) or empty list on first run; record outcome.
- `grep -E "127\.0\.0\.1/32" /etc/postgresql/*/main/pg_hba.conf` → entry exists; ensure no external CIDR entries remain.

**Rollback/Recovery**
- Drop databases/users if necessary (`mysql DROP DATABASE`, `DROP USER`; `psql DROP DATABASE/ROLE`).
- Restore original `pg_hba.conf` from `.backup` if replacement caused issues.

---

## 03_nextcloud_install.sh
**Preconditions**
- Databases provisioned (script 02 run).
- `NEXTCLOUD_ROOT` absent or safe to replace; data directory acceptable to wipe.

**Steps**
1. Run `sudo ./src/03_nextcloud_install.sh`.
2. Verify `occ status`: `sudo -u www-data php /var/www/nextcloud/occ status`.
3. Confirm trusted domain setting: `occ config:system:get trusted_domains 1`.
4. Check Redis config (`occ config:system:get redis host`).
5. Hit health page: `curl -kI https://docs.<domain>/status.php` (Cloudflare proxied? use direct IP + HOST header if necessary).
6. Document results in `test-results/nextcloud_install_<date>.txt`.

**Diagnostics & Pass Criteria**
- `sudo -u www-data php /var/www/nextcloud/occ status` → reports `installed: true`, `version: $NEXTCLOUD_VERSION`.
- `sudo -u www-data php /var/www/nextcloud/occ config:system:get trusted_domains 1` → equals `$NEXTCLOUD_FQDN`.
- `sudo -u www-data php /var/www/nextcloud/occ config:system:get redis host` → equals `/run/redis/redis-server.sock`.
- `curl -k https://docs.<domain>/status.php` (or IP + Host header) → JSON includes `"installed":true` and `"maintenance":false`.
- Optional: `sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --off` → ensures not stuck in maintenance.

**Rollback/Recovery**
- Uninstall script `sudo ./src/99_uninstall.sh` (after we refactor), or remove `/var/www/nextcloud` and DB manually, then rerun script 03.
- Restore snapshot if Nextcloud files were replaced unintentionally.

---

## 04_onlyoffice_install.sh
**Preconditions**
- Database provisioning script completed (OnlyOffice DB/user exists).
- `params.yaml` contains JWT secret and admin credentials.

**Steps**
1. Run `sudo ./tests/run_with_guard.sh ./src/04_onlyoffice_install.sh`.
2. Tail `/var/log/nextcloud-install.log` if warnings appear.
3. Verify systemd status: `systemctl status onlyoffice-documentserver`.
4. Run health probes:
   - `curl -fsS http://127.0.0.1:8080/healthcheck`
   - `curl -fsS http://127.0.0.1:8080/hosting/discovery | head -n 5`
5. Inspect JWT/database fields: `sudo python3 - <<'PY' ...` (see diagnostics below).
6. Log results to `test-results/onlyoffice_install_<date>.txt`.

**Diagnostics & Pass Criteria**
- `systemctl is-active onlyoffice-documentserver` → `active`.
- `curl -fsS http://127.0.0.1:8080/healthcheck` → HTTP 200 with `true` payload.
- `sudo python3 - <<'PY'` snippet:
  ```python
  import json; import sys
  data = json.load(open('/etc/onlyoffice/documentserver/local.json'))
  co = data['services']['CoAuthoring']
  print(co['sql']['dbName'], co['sql']['dbUser'])
  print(co['secret']['session']['string'][:16])
  print(co['request-filtering']['allowedHosts'])
  ```
  → DB name/user match params, JWT prefix matches expected, allowed hosts include `docs.<domain>` and `127.0.0.1`.
- Optional: `curl -fsS http://127.0.0.1:8080/web-apps/apps/api/documents/api.js` returns JS (sanity check that static assets load).

**Rollback/Recovery**
- If configuration becomes corrupted, restore `/etc/onlyoffice/documentserver/local.json` from backup and rerun script.
- Reinstall package with `apt-get purge onlyoffice-documentserver` followed by rerun if service fails to start.

---

## 05_nginx_config.sh
**Preconditions**
- Scripts 01–04 completed (Nextcloud + OnlyOffice installed).
- `/etc/onlyoffice/documentserver/local.json` present.

**Steps**
1. Run `sudo ./tests/run_with_guard.sh ./src/05_nginx_config.sh`.
2. Execute `sudo ./tests/nginx_smoke.sh` (uses loopback `--resolve` to avoid Cloudflare caching).
3. Verify site file: `sudo ls -l /etc/nginx/sites-available/${NEXTCLOUD_DOMAIN}.conf`.
4. Confirm symlink: `readlink /etc/nginx/sites-enabled/${NEXTCLOUD_DOMAIN}.conf`.
5. Confirm websocket snippet deployed: `sudo cat /etc/nginx/conf.d/00_websocket_upgrade_map.conf`.
6. Log results to `test-results/nginx_config_<date>.txt`.

**Diagnostics & Pass Criteria**
- `nginx -t` → `syntax is ok` and `test is successful`.
- `systemctl status nginx` → `active (running)`.
- `sudo ./tests/nginx_smoke.sh` terminates with exit code 0.
- `curl -sk --resolve docs.<domain>:443:127.0.0.1 https://docs.<domain>/status.php` → JSON with `"installed":true`.
- `sudo python3 - <<'PY'` check to ensure `/etc/nginx/sites-available/${NEXTCLOUD_DOMAIN}.conf` contains `proxy_pass http://127.0.0.1:8080/`.

**Rollback/Recovery**
- Restore previous config from backup or Git if nginx fails to reload.
- `systemctl restart nginx` and monitor `/var/log/nginx/error.log` for specifics.

---

## 06_ssl_setup.sh
**Preconditions**
- Scripts 01–05 completed; nginx serving HTTP for challenge.
- DNS for `docs.<domain>` resolves to the server (proxy/CDN accommodates HTTP challenge).

**Steps**
1. Run `sudo ./src/06_ssl_setup.sh --staging` to exercise issuance logic without consuming production rate limits.
2. Verify certificates: `sudo certbot certificates --cert-name docs.<domain>`.
3. Confirm renewal timer: `systemctl status certbot.timer`.
4. Re-run production issuance (omit `--staging`) once staging passes.
5. Execute `sudo ./tests/nginx_smoke.sh` to ensure HTTPS vhost now serves with the certificate and static assets still resolve.
6. Record outputs in `test-results/ssl_setup_<date>.txt`.

**Diagnostics & Pass Criteria**
- `sudo certbot certificates --cert-name docs.<domain>` → lists `Certificate Name`, `Domains`, and `Expiry` (staging cert shows fake CA until real run).
- `sudo openssl x509 -in /etc/letsencrypt/live/docs.<domain>/cert.pem -noout -issuer` → issuer matches either “(STAGING) Artificial Apricot R3” or Let’s Encrypt production CA.
- `systemctl is-enabled certbot.timer` → `enabled` and `systemctl status certbot.timer` shows `Active: active (running)` with next trigger.
- `sudo ./tests/nginx_smoke.sh` returns exit code 0, confirming `/onlyoffice/healthcheck` and `.mjs` assets work over HTTPS.

**Rollback/Recovery**
- Remove staging files with `sudo rm -rf /etc/letsencrypt/live/docs.<domain>-0001` (or relevant) if staging issuance leaves duplicates.
- Disable certbot timer (`systemctl disable --now certbot.timer`) if issuance failed and you need to retry later.
- Restore nginx config from Git if re-rendering introduced syntax errors, then rerun script after fixing the issue.

---

## 07_integration_config.sh
**Preconditions**
- Scripts 01–06 completed; Document Server and nginx are healthy.
- `tests/nginx_smoke.sh` passes.

**Steps**
1. Run `sudo ./src/07_integration_config.sh`.
2. Observe occ output for connector settings and health check.
3. If warnings appear, inspect `/var/log/nextcloud-install.log` and `/var/log/nginx/nextcloud_error.log`.
4. Save command output to `test-results/integration_config_<date>.txt`.

**Diagnostics & Pass Criteria**
- `sudo -u www-data php /var/www/nextcloud/occ config:app:get onlyoffice DocumentServerUrl` → `https://docs.<domain>/onlyoffice/`.
- `sudo -u www-data php /var/www/nextcloud/occ config:app:get onlyoffice DocumentServerInternalUrl` → `http://127.0.0.1:8080/`.
- `sudo -u www-data php /var/www/nextcloud/occ config:app:get onlyoffice jwt_header` → `Authorization`.
- `sudo -u www-data php /var/www/nextcloud/occ onlyoffice:documentserver --check` → returns “Document server … successfully connected”.
- `sudo ./tests/nginx_smoke.sh` exit code 0 (already triggered by the script, but rerun if troubleshooting).

**Rollback/Recovery**
- Re-run `src/04_onlyoffice_install.sh` if JWT secrets drifted or DocumentServer lost its public URL config.
- Restore Nextcloud config from backup (`config/config.php` and OnlyOffice app settings) if occ values were overwritten incorrectly, then rerun this script.
- Consult DocumentServer logs (`/var/log/onlyoffice/documentserver/`) if health checks fail.

---

## 99_uninstall.sh
**Preconditions**
- You have a safe snapshot/backup; this script deletes databases, certs, and application files.
- `params.yaml` still reflects the deployment you want to remove.

**Steps**
1. Optional: create manual backups or specify a custom backup directory (`--backup-dir /path`).
2. Run `sudo ./src/99_uninstall.sh` (add `--yes` for non-interactive, `--skip-backup` if you already saved artifacts, `--purge-packages` to remove nginx/php/onlyoffice packages).
3. After completion, inspect `/var/log/nextcloud-install.log` for any warnings noted during cleanup.

**Diagnostics & Pass Criteria**
- `/var/www/nextcloud`, `/var/www/onlyoffice`, `/etc/onlyoffice`, `/etc/letsencrypt/live/docs.<domain>` are removed.
- `mysql -uroot -e "SHOW DATABASES"` no longer lists the Nextcloud DB; `sudo -u postgres psql -c '\l'` no longer lists the OnlyOffice DB.
- `ls /etc/nginx/sites-available` no longer contains `docs.<domain>.conf`; `nginx -t` still succeeds.
- If `--purge-packages` was used, `dpkg -l | grep onlyoffice-documentserver` returns nothing.
- `sudo crontab -l` (if any) has no entries containing `nextcloud/cron.php`; `/etc/cron.d/nextcloud` removed.

**Rollback/Recovery**
- Restore from the generated tarballs in the backup directory (nginx, onlyoffice, letsencrypt) if needed.
- Reinstall via scripts 01–07 to rebuild the stack.

---

## Repo hygiene during tests
- Before running scripts, stage and commit refactor changes. Push to origin so snapshot reverts won't lose work.
- After each test run, capture logs/output and add any observed adjustments back into these checklists.
- Use `sudo ./tests/run_with_guard.sh <script>` to execute installers with automatic maintenance-mode handling and service restarts (pass additional arguments after the script path).
