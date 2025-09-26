# Nextcloud + ONLYOFFICE (one‑domain, subpath `/onlyoffice/`) — Fix & Verify Playbook

This playbook makes your working bare‑metal deployment robust after the nginx re‑provision.
It packages **all** steps from our thread (including the immediately‑preceding prompts) into one
copy‑pasteable runbook you can hand to Codex (or execute manually).

Tested assumptions (adapt paths/domains if different):
- **Domain:** `docs.test-collab-site.com`
- **Nextcloud root:** `/var/www/nextcloud`
- **PHP-FPM socket:** `unix:/run/php/php8.3-fpm.sock`
- **DocumentServer (DS) listeners:** `127.0.0.1:8080` (DS nginx) and `*:8000` (docservice)
- **Single domain / subpath** approach: DS public URL is `https://docs.test-collab-site.com/onlyoffice/`

> Safety: Commands below are **idempotent** where possible. Always back up configs first.

---

## 0) Quick backups

```bash
set -euo pipefail

# nginx
sudo cp -a /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak.$(date +%F_%H%M%S) || true
sudo cp -a /etc/nginx/sites-available/docs.test-collab-site.com.conf \
           /etc/nginx/sites-available/docs.test-collab-site.com.conf.bak.$(date +%F_%H%M%S) || true

# OnlyOffice DS
sudo cp -a /etc/onlyoffice/documentserver/local.json \
           /etc/onlyoffice/documentserver/local.json.bak.$(date +%F_%H%M%S) || true

# Nextcloud config
sudo cp -a /var/www/nextcloud/config/config.php \
           /var/www/nextcloud/config/config.php.bak.$(date +%F_%H%M%S) || true
```

---

## 1) Ensure core nginx includes & MIME (main `nginx.conf`)

Your **/etc/nginx/nginx.conf** must include these lines inside the `http {}` block:

```nginx
include       /etc/nginx/mime.types;
default_type  application/octet-stream;

include /etc/nginx/conf.d/*.conf;
include /etc/nginx/sites-enabled/*;
```

**Verify:**

```bash
sudo nginx -T | sed -n '1,150p' | grep -E 'mime\.types|conf\.d/\*|sites-enabled/\*'
```

If any are missing, add them and reload at the end of this playbook.

---

## 2) Harden the `/onlyoffice/` reverse proxy block (nginx vhost)

Add (or confirm) the following in the **443** server block for `docs.test-collab-site.com`:

```nginx
location ^~ /onlyoffice/ {
    proxy_pass         http://127.0.0.1:8080/;   # DS bundled nginx
    proxy_http_version 1.1;

    proxy_set_header   Host               $host;
    proxy_set_header   X-Real-IP          $remote_addr;
    proxy_set_header   X-Forwarded-For    $proxy_add_x_forwarded_for;
    proxy_set_header   X-Forwarded-Proto  https;
    proxy_set_header   X-Forwarded-Host   $host;
    proxy_set_header   X-Forwarded-Port   443;
    proxy_set_header   X-Forwarded-Prefix /onlyoffice;

    # Forward auth header explicitly so DS can validate JWT
    proxy_set_header   Authorization      $http_authorization;

    # Websocket upgrade
    proxy_set_header   Upgrade            $http_upgrade;
    proxy_set_header   Connection         $connection_upgrade;

    client_max_body_size 200m;
    proxy_read_timeout    3600s;
    proxy_send_timeout    3600s;
    proxy_buffering       off;
    proxy_redirect        off;
}
```

Also ensure you have a websocket map included (via your script it should be at
`/etc/nginx/conf.d/00_websocket_upgrade_map.conf`). It must define:

```nginx
map $http_upgrade $connection_upgrade {
  default upgrade;
  ''      close;
}
```

Additionally, confirm `/etc/nginx/mime.types` includes `text/javascript  mjs;` so the Viewer/Text `.mjs` bundles keep a `text/javascript` MIME type.

**Verify map is included:**
```bash
sudo nginx -T | grep -n 'websocket_upgrade' -n || true
```

> If you’re generating this block from a template, update the template so Codex renders these headers.

---

## 3) Pin DS public URL, JWT headers, and converter binaries (OnlyOffice `local.json`)

Explicitly set the DS public URL, align JWT header names with Nextcloud, and point the converter at the bundled binaries (prevents `spawn null ENOENT` errors):

```bash
# Requires jq (install if needed): sudo apt-get update && sudo apt-get install -y jq
sudo jq '
  .services.CoAuthoring += {"public": {"url": "https://docs.test-collab-site.com/onlyoffice"}} |
  .services.CoAuthoring.token.inbox.header = "Authorization" |
  .services.CoAuthoring.token.outbox.header = "Authorization" |
  .FileConverter.converter.docbuilderPath = "/var/www/onlyoffice/documentserver/server/FileConverter/bin/docbuilder" |
  .FileConverter.converter.x2tPath = "/var/www/onlyoffice/documentserver/server/FileConverter/bin/x2t"
' /etc/onlyoffice/documentserver/local.json \
| sudo tee /etc/onlyoffice/documentserver/local.json.tmp >/dev/null && \
sudo mv /etc/onlyoffice/documentserver/local.json.tmp /etc/onlyoffice/documentserver/local.json
```

Restart DS services (DocService + FileConverter):

```bash
sudo systemctl restart ds-docservice.service ds-converter.service
```

> **Note:** This does **not** change your JWT secret; it just pins header names, the public URL, and converter paths.


---

## 4) Align Nextcloud OnlyOffice app config (via `occ`)

Use the same public/internal URLs and header `Authorization`, and copy DS’s JWT secret into NC.

```bash
# Extract DS JWT secret (covers common DS versions/paths)
DS_JWT=$(jq -r '
  .services.CoAuthoring.secret?.browser?.string //
  .services.CoAuthoring.secret?.inbox?.string //
  empty
' /etc/onlyoffice/documentserver/local.json)

# Set NC app config
sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice DocumentServerUrl --value="https://docs.test-collab-site.com/onlyoffice/"
sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice DocumentServerInternalUrl --value="http://127.0.0.1:8080/"
sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice StorageUrl --value="https://docs.test-collab-site.com/"
sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice jwt_header --value="Authorization"
[ -n "$DS_JWT" ] && sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice jwt_secret --value="$DS_JWT"

# Optional: temporarily skip TLS peer verification to diagnose trust issues; flip back later.
# sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice verify_peer_off --value="true"

# Show config (for logs)
sudo -u www-data php /var/www/nextcloud/occ config:list onlyoffice
```

---

## 5) Make Nextcloud always speak HTTPS (no HTTP→HTTPS signature break)

In `/var/www/nextcloud/config/config.php`, ensure:

```php
'overwrite.cli.url' => 'https://docs.test-collab-site.com',
'overwriteprotocol' => 'https',
```

Then run:
```bash
sudo -u www-data php /var/www/nextcloud/occ maintenance:repair
```

---

## 6) Reload nginx and quick health checks

```bash
sudo nginx -t && sudo systemctl reload nginx

# DS health
curl -fsS http://127.0.0.1:8080/healthcheck && echo OK
curl -fsS http://127.0.0.1:8000/healthcheck && echo OK

# Discovery through the public path (should include /onlyoffice/ in urlsrc values)
curl -ks https://docs.test-collab-site.com/onlyoffice/hosting/discovery | head -n 30

# NC static assets sanity
curl -I https://docs.test-collab-site.com/core/js/oc.js
curl -I https://docs.test-collab-site.com/core/img/logo/logo.svg
```

---

## 7) Run the OnlyOffice connector test in Nextcloud

In the NC admin UI → **Settings → ONLYOFFICE** → Save / Check connection.

### If you still see an error
Immediately collect logs (copy these blocks as‑is):

```bash
# OnlyOffice DS logs (paths can vary; these are common)
ls -1 /var/log/onlyoffice/documentserver/*/*log || true
tail -n 200 /var/log/onlyoffice/documentserver/converter/out.log || true
tail -n 200 /var/log/onlyoffice/documentserver/docservice/out.log || true

# Front nginx logs
tail -n 200 /var/log/nginx/nextcloud_error.log || true
tail -n 200 /var/log/nginx/nextcloud_access.log || true
```

Typical failure signatures and fixes:
- **401/403** from DS fetching NC file → JWT header not forwarded or wrong header name → ensure
  `proxy_set_header Authorization $http_authorization;` and `jwt_header="Authorization"` on NC & DS.
- **TLS/peer verify** errors → CA chain or time mismatch; test with `verify_peer_off=true`, then fix CA chain
  (update `ca-certificates`, ensure fullchain served by nginx) and turn verification back **off → false**.
- **404 on /apps/onlyoffice/** paths → add an explicit pass‑through before generic PHP block:
  ```nginx
  location ^~ /apps/onlyoffice/ { try_files $uri /index.php$request_uri; }
  ```

---

## 8) Optional niceties for the nginx Nextcloud block

- Prefer this router form (avoids some rare double‑encoding cases):
  ```nginx
  location / { try_files $uri $uri/ /index.php?$args; }
  ```

- Keep the security block at the end to prevent stray PHP execution:
  ```nginx
  location ~ \.php$ { return 404; }
  ```

---

## 9) Rollback notes

If anything goes sideways, you can restore the backups you made in step 0:

```bash
# Example: restore nginx.conf
sudo cp -a /etc/nginx/nginx.conf.bak.YYYY-MM-DD_HHMMSS /etc/nginx/nginx.conf
sudo nginx -t && sudo systemctl reload nginx
```

---

## 10) Final checklist

- [ ] `/etc/nginx/nginx.conf` includes `mime.types`, `conf.d/*.conf`, `sites-enabled/*`
- [ ] `/onlyoffice/` block forwards `Authorization` header and sets `X-Forwarded-Proto https`, `X-Forwarded-Port 443`
- [ ] DS `local.json` pins `.services.CoAuthoring.public.url = "https://docs.test-collab-site.com/onlyoffice"`, sets `token.{inbox,outbox}.header = "Authorization"`, and defines `FileConverter.converter.{x2tPath,docbuilderPath}` to the bundled binaries.
- [ ] NC OnlyOffice app config:
  - `DocumentServerUrl = https://docs.test-collab-site.com/onlyoffice/`
  - `DocumentServerInternalUrl = http://127.0.0.1:8080/`
  - `StorageUrl = https://docs.test-collab-site.com/`
  - `jwt_header = Authorization`
  - `jwt_secret` matches DS secret
- [ ] Nextcloud `config.php` has `overwriteprotocol=https` and `overwrite.cli.url` set to the HTTPS origin
- [ ] Connector test passes; editing a `.docx` opens the OnlyOffice editor

---

### Appendix: One‑shot script to apply sections 3–6 (safe to rerun)

```bash
#!/usr/bin/env bash
set -euo pipefail

DOMAIN="docs.test-collab-site.com"
NC_ROOT="/var/www/nextcloud"
DS_LOCAL="/etc/onlyoffice/documentserver/local.json"

command -v jq >/dev/null || { echo "Installing jq..."; sudo apt-get update && sudo apt-get install -y jq; }

# Pin DS public URL, JWT headers, and converter binaries
sudo jq --arg pub "https://$DOMAIN/onlyoffice" '
  .services.CoAuthoring += {"public": {"url": $pub}} |
  .services.CoAuthoring.token.inbox.header = "Authorization" |
  .services.CoAuthoring.token.outbox.header = "Authorization" |
  .FileConverter.converter.docbuilderPath = "/var/www/onlyoffice/documentserver/server/FileConverter/bin/docbuilder" |
  .FileConverter.converter.x2tPath = "/var/www/onlyoffice/documentserver/server/FileConverter/bin/x2t"
' "$DS_LOCAL" | sudo tee "$DS_LOCAL.tmp" >/dev/null && sudo mv "$DS_LOCAL.tmp" "$DS_LOCAL"
sudo systemctl restart ds-docservice.service ds-converter.service

# Read DS JWT secret
DS_JWT=$(jq -r '
  .services.CoAuthoring.secret?.browser?.string //
  .services.CoAuthoring.secret?.inbox?.string //
  empty
' "$DS_LOCAL")

# Apply NC OnlyOffice settings
sudo -u www-data php "$NC_ROOT/occ" config:app:set onlyoffice DocumentServerUrl --value="https://$DOMAIN/onlyoffice/"
sudo -u www-data php "$NC_ROOT/occ" config:app:set onlyoffice DocumentServerInternalUrl --value="http://127.0.0.1:8080/"
sudo -u www-data php "$NC_ROOT/occ" config:app:set onlyoffice StorageUrl --value="https://$DOMAIN/"
sudo -u www-data php "$NC_ROOT/occ" config:app:set onlyoffice jwt_header --value="Authorization"
[ -n "$DS_JWT" ] && sudo -u www-data php "$NC_ROOT/occ" config:app:set onlyoffice jwt_secret --value="$DS_JWT"

# Force Nextcloud to prefer HTTPS URLs
sudo sed -i -E \
  -e "s/'overwrite\.cli\.url'.*/'overwrite.cli.url' => 'https:\/\/$DOMAIN',/g" \
  -e "s/'overwriteprotocol'.*/'overwriteprotocol' => 'https',/g" \
  "$NC_ROOT/config/config.php" || true
grep -q "overwriteprotocol" "$NC_ROOT/config/config.php" || \
  sudo sed -i "/);/i \ \ 'overwriteprotocol' => 'https'," "$NC_ROOT/config/config.php"
grep -q "overwrite.cli.url" "$NC_ROOT/config/config.php" || \
  sudo sed -i "/);/i \ \ 'overwrite.cli.url' => 'https:\/\/$DOMAIN'," "$NC_ROOT/config/config.php"

sudo -u www-data php "$NC_ROOT/occ" maintenance:repair

# Reload nginx
sudo nginx -t && sudo systemctl reload nginx

echo "Done. Now run the OnlyOffice connector test in Nextcloud."
```

---

**End of playbook.**
