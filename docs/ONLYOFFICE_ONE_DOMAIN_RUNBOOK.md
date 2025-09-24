# OnlyOffice One-Domain Cutover Runbook

*Last updated: 2025-09-24*

This runbook captures the manual steps to migrate an existing dual-domain Nextcloud + OnlyOffice deployment on the test VPS to the single-domain `/onlyoffice/` subpath model. Do **not** update the automation scripts until every step below has been executed and validated on the live stack.

---

## 0. Pre-flight checklist

1. **Environment:** Test VPS (Ubuntu 24.04). All commands assume `root`.
2. **Current state:**
   - Nextcloud served at `https://docs.<domain>`
   - OnlyOffice served at `https://onlyoffice.<domain>`
   - JWT secrets known and matching between systems
3. **Files to back up:**
   - `/etc/nginx/sites-available/docs.<domain>`
   - `/etc/nginx/sites-available/onlyoffice.<domain>`
   - `/etc/onlyoffice/documentserver/nginx/ds.conf`
   - `/etc/onlyoffice/documentserver/nginx/conf.d/*.conf`
   - `/etc/onlyoffice/documentserver/local.json`
4. **Diagnostics:** Run `sudo ./src/99_diagnostics.sh` and stash the log before making changes.

```bash
sudo ./src/99_diagnostics.sh
ls -1 /root/oo-nc-diagnostics-*.log | tail -n1
```

---

## 1. Restrict Document Server to loopback

> Goal: ensure the Document Server only listens on `127.0.0.1` so it can be safely fronted by the Nextcloud vhost.

1. Edit `/etc/onlyoffice/documentserver/nginx/ds.conf` (and any includes) so every `listen` directive uses `127.0.0.1:<port>` and remove IPv6 listeners.
2. Update upstream blocks to reference `127.0.0.1` explicitly instead of `localhost`.
3. Restart services and verify health locally:

```bash
sudo systemctl restart onlyoffice-documentserver
sleep 10
curl -fsSI http://127.0.0.1:8080/healthcheck | head -n1
curl -fsS  http://127.0.0.1:8080/hosting/discovery | head
```

**Stop here if either curl fails**. Check `journalctl -u onlyoffice-documentserver` before proceeding.

---

## 2. Install WebSocket upgrade map in nginx

1. Ensure the helper exists once at the http level:

```nginx
# /etc/nginx/conf.d/00_websocket_upgrade_map.conf
map $http_upgrade $connection_upgrade {
    default upgrade;
    '' close;
}
```

2. Reload nginx to confirm there are no syntax issues:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

---

## 3. Patch the Nextcloud vhost with `/onlyoffice/`

1. Insert the proxy block shown below into `/etc/nginx/sites-available/docs.<domain>` immediately before the existing `location /` stanza:

```nginx
location ^~ /onlyoffice/ {
    proxy_pass         http://127.0.0.1:8080/;
    proxy_http_version 1.1;

    proxy_set_header   Host               $host;
    proxy_set_header   X-Real-IP          $remote_addr;
    proxy_set_header   X-Forwarded-For    $proxy_add_x_forwarded_for;
    proxy_set_header   X-Forwarded-Proto  $scheme;
    proxy_set_header   X-Forwarded-Host   $host;
    proxy_set_header   X-Forwarded-Prefix /onlyoffice;
    proxy_set_header   Upgrade            $http_upgrade;
    proxy_set_header   Connection         $connection_upgrade;

    client_max_body_size 200m;
    proxy_read_timeout    3600s;
    proxy_send_timeout    3600s;
    proxy_buffering       off;
    proxy_redirect        off;
}
```

2. Test and reload nginx:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

3. Probe through the public endpoint while the old vhost is still enabled:

```bash
curl -fsSI https://docs.<domain>/onlyoffice/healthcheck | head -n1
curl -fsS  https://docs.<domain>/onlyoffice/hosting/discovery | head
curl -fsSI https://docs.<domain>/onlyoffice/web-apps/apps/api/documents/api.js | head -n5
```

If any command fails, inspect `/var/log/nginx/nextcloud_error.log` and **do not proceed** until resolved.

---

## 4. Update OnlyOffice connector settings in Nextcloud

1. Snapshot current settings:

```bash
sudo -u www-data php /var/www/nextcloud/occ config:app:get onlyoffice --output=json > /root/onlyoffice-occ-before.json
```

2. Apply the subpath values (replace `<domain>` and `${JWT_SECRET}` as appropriate):

```bash
sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice DocumentServerUrl --value="https://docs.<domain>/onlyoffice/"
sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice DocumentServerInternalUrl --value="http://127.0.0.1:8080/"
sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice StorageUrl --value="https://docs.<domain>/"
sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice jwt_secret --value="${JWT_SECRET}"
sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice jwt_header --value="AuthorizationJwt"
```

3. Ensure `config.php` allows local calls (add if missing):

```php
'allow_local_remote_servers' => true,
```

4. Validate the connector:

```bash
sudo -u www-data php /var/www/nextcloud/occ onlyoffice:documentserver --check
```

Expect the command to report “successfully connected.” If it fails, review `/var/www/nextcloud/data/nextcloud.log` and skip the next step until fixed.

---

## 5. Browser smoke tests

1. Hard-refresh the Nextcloud Files app (Shift+Reload).
2. Create and open `.docx`, `.xlsx`, and `.pptx` documents.
3. Check browser developer tools → Network tab for 404 or mixed-content errors under `/onlyoffice/`.
4. Confirm collaborative editing works with two sessions, if possible.

Document results and capture screenshots if issues arise.

---

## 6. Disable the legacy OnlyOffice vhost

1. Remove the enabled symlink but keep the file for rollback:

```bash
sudo unlink /etc/nginx/sites-enabled/onlyoffice.<domain>
sudo nginx -t && sudo systemctl reload nginx
```

2. Verify the old hostname now fails (expected 4xx/5xx):

```bash
curl -I https://onlyoffice.<domain>
```

3. Re-run the diagnostics script and archive the log alongside the pre-flight version.

---

## 7. Rollback procedure (test once)

If anything breaks:

```bash
sudo ln -s /etc/nginx/sites-available/onlyoffice.<domain> /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice DocumentServerUrl --value="https://onlyoffice.<domain>/"
sudo -u www-data php /var/www/nextcloud/occ onlyoffice:documentserver --check
```

Ensure the rollback commands work end-to-end before declaring victory.

---

## 8. Post-success actions

1. Update `project-status-and-todo/CURRENT_BEST_CONFIGURATIONS.md` and `Systematic testing.md` with actual results (✅ completed 2025-09-24).
2. Capture nginx diffs from the live server for comparison with repo templates.
3. Disable automatic renewal for `onlyoffice.<domain>` once confident in single-domain mode:
   ```bash
   certbot delete --cert-name onlyoffice.<domain>
   # or manually remove /etc/letsencrypt/renewal/onlyoffice.<domain>.conf and reload certbot timers
   ```
4. Only after the runbook succeeds should we port the changes into the automation scripts (`src/05_nginx_config_dual_domain.sh`, etc.).

---

## 9. Execution log

- **2025-09-24** — Runbook executed on test VPS (`docs.test-collab-site.com`).
  - Health checks, OCC verification, and browser smoke tests succeeded for `.docx`, `.xlsx`, `.pptx`, `.pdf`, images, and markdown viewers.
  - Legacy `onlyoffice.<domain>` vhost disabled; rollback symlink retained for emergencies.
  - Next steps: propagate changes to documentation/automation and retire unused TLS certificate.

*End of runbook*
