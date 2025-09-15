# Nextcloud + OnlyOffice (Two Domains, No Docker)

A **copy/paste-friendly** baseline you can commit to repo and use as a regression-proof reference.

> Domains used below: `docs.test-collab-site.com` (Nextcloud) and `onlyoffice.test-collab-site.com` (OnlyOffice). Adjust if yours differ. PHP-FPM socket shown for PHP 8.3; change if needed.

---

## 1) Requirements & Assumptions

- **OS**: Ubuntu 22.04/24.04 (systemd present)
- **Packages**: nginx, php-fpm (8.1+), curl, openssl
- **Nextcloud** path: `/var/www/nextcloud` (owner `www-data`)
- **OnlyOffice DocumentServer** installed (deb), services supervised (`ds-docservice`, `ds-converter` or monolithic `onlyoffice-documentserver`)
- **Network model**: Both apps on same VPS
  - DS **docservice** binds **IPv4** on `127.0.0.1:8000`
  - Fronting nginx for DS listens on **127.0.0.1:8080** (private), and a public vhost on 443 for `onlyoffice.*`
  - Nextcloud public vhost on 443 for `docs.*`
- **TLS**: Valid certificates on both public vhosts
- **JWT**: One shared secret used for DS inbox/outbox/browser; header name `Authorization`
- **Optional**: If using internal self-signed certs, temporarily allow DS to connect ignoring TLS verify in Nextcloud OnlyOffice app (`verify_peer_off=1`) until fixed.

---

## 2) OnlyOffice: `local.json` (two variants)

> File: `/etc/onlyoffice/documentserver/local.json` (create directory if missing). Keep overrides **minimal**.

### 2.1 Minimal with JWT **disabled** (for A/B testing)
```json
{
  "services": {
    "CoAuthoring": {
      "server": { "ip": "127.0.0.1", "port": 8000 }
    }
  },
  "token": { "enable": false }
}
```

### 2.2 Production with JWT **enabled**
```json
{
  "services": {
    "CoAuthoring": {
      "server": { "ip": "127.0.0.1", "port": 8000 }
    }
  },
  "token": {
    "enable": true,
    "inbox":   { "string": "<REDACTED_LONG_RANDOM_SECRET>" },
    "outbox":  { "string": "<REDACTED_LONG_RANDOM_SECRET>" },
    "browser": { "string": "<REDACTED_LONG_RANDOM_SECRET>" },
    "authorizationHeader": "Authorization"
  }
}
```

**Restart DS** (try in this order):
```bash
sudo systemctl restart ds-docservice ds-converter || \
sudo systemctl restart onlyoffice-documentserver || { sudo supervisorctl reread; sudo supervisorctl update; sudo supervisorctl restart all; }
```

**IPv4 enforcement note**: If something reverts to IPv6, ensure `local.json` binds `127.0.0.1`. If the app tries `::`, optionally set `net.ipv6.bindv6only=0` and keep DS on IPv4.

---

## 3) Nginx: OnlyOffice public vhost + internal proxy

### 3.1 Public vhost (443) — `onlyoffice.test-collab-site.com`
```nginx
server {
    listen 443 ssl http2;
    server_name onlyoffice.test-collab-site.com;

    # … ssl_certificate / ssl_certificate_key …

    # Web-apps and static files (served by DS’ bundled nginx include normally);
    # If you’re fronting DS yourself, proxy to a local DS listener.
    location / {
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade           $http_upgrade;
        proxy_set_header Connection        $connection_upgrade;
        client_max_body_size 200m;
        proxy_pass http://127.0.0.1:8080;
    }
}
```

### 3.2 Internal DS frontend (8080 → 8000)
```nginx
server {
    listen 127.0.0.1:8080;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade           $http_upgrade;
        proxy_set_header Connection        $connection_upgrade;
        client_max_body_size 200m;
    }
}
```

```bash
sudo nginx -t && sudo systemctl reload nginx
```

---

## 4) Nginx: Nextcloud public vhost — `docs.test-collab-site.com`
```nginx
server {
    listen 443 ssl http2;
    server_name docs.test-collab-site.com;

    root /var/www/nextcloud;
    index index.php;

    # … ssl_certificate / ssl_certificate_key …

    client_max_body_size 200m;
    fastcgi_buffers 64 4K;

    add_header Referrer-Policy "no-referrer" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;

    location = /robots.txt { allow all; log_not_found off; access_log off; }

    location / {
        rewrite ^ /index.php$request_uri;
    }

    location ~ \.php(?:$|/) {
        fastcgi_split_path_info ^(.+?\.php)(/.*)$;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
        fastcgi_param HTTPS on;
        fastcgi_param modHeadersAvailable true;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;  # adjust to your PHP-FPM socket
    }

    location ~ \.(?:css|js|woff2?|svg|gif|map)$ {
        try_files $uri /index.php$request_uri;
        expires 6M; access_log off;
    }

    location ~ \.(?:png|html|ttf|ico|jpg|jpeg)$ {
        try_files $uri /index.php$request_uri;
        expires 6M; access_log off;
    }

    # Well-knowns (CalDAV/CardDAV)
    location = /.well-known/carddav { return 301 /remote.php/dav; }
    location = /.well-known/caldav  { return 301 /remote.php/dav; }
}
```

```bash
sudo nginx -t && sudo systemctl reload nginx
```

---

## 5) Nextcloud — OnlyOffice app settings (A/B then production)

Run as `www-data`:

### 5.1 Internal routing (most common fix)
```bash
# Public DocumentServer URL (what browsers load)
sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice DocumentServerUrl --value="https://onlyoffice.test-collab-site.com/"

# Internal URL DS should use to reach Nextcloud (same host → safest)
sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice DocumentServerInternalUrl --value="http://127.0.0.1/"

# Internal URL NC uses to reach DS (via DS nginx on 127.0.0.1:8080)
sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice StorageUrl --value="http://127.0.0.1:8080/"
```

### 5.2 JWT disabled (for testing)
```bash
sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice jwt_enabled --value=0
```

### 5.3 JWT enabled (production)
```bash
sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice jwt_enabled --value=1
sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice jwt_secret  --value="<REDACTED_LONG_RANDOM_SECRET>"
sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice jwt_header  --value="Authorization"
```

### 5.4 Temporary TLS workaround (if internal trust chain not ready)
```bash
sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice verify_peer_off --value=1
```
> Set back to `0` when certs are fixed.

---

## 6) Nextcloud `config.php` essentials

> File: `/var/www/nextcloud/config/config.php`
```php
'trusted_domains' =>
  array ( 0 => 'docs.test-collab-site.com', ),
'overwrite.cli.url' => 'https://docs.test-collab-site.com',
'overwritehost' => 'docs.test-collab-site.com',
'overwriteprotocol' => 'https',
// If behind a proxy:
// 'trusted_proxies' => ['127.0.0.1'],
'allow_local_remote_servers' => true,
```
(You only need the `onlyoffice => verify_peer_off` block if you use internal HTTPS with an untrusted cert.)

---

## 7) “Proof” Diagnostics (paste and check)

### 7.1 DS IPv4 & health
```bash
ss -ltnp 'sport = :8000' || netstat -ltnp | grep :8000
curl -sS http://127.0.0.1:8000/healthcheck || curl -sS http://127.0.0.1:8080/healthcheck
curl -sS https://onlyoffice.test-collab-site.com/web-apps/apps/api/documents/api.js | head -n1
```

### 7.2 DS reachability to Nextcloud
```bash
curl -I http://127.0.0.1/status.php
curl -I https://docs.test-collab-site.com/status.php
```

### 7.3 JWT state
```bash
sudo -u www-data php /var/www/nextcloud/occ config:app:get onlyoffice jwt_enabled jwt_header jwt_secret
```

### 7.4 Nginx & app logs (tail)
```bash
sudo tail -n 100 /var/log/onlyoffice/documentserver/docservice/out.log
sudo tail -n 100 /var/log/onlyoffice/documentserver/converter/out.log
sudo tail -n 100 /var/log/nginx/error.log
sudo -u www-data php /var/www/nextcloud/occ log:tail --lines=100
```

---

## 8) Symptom → Likely Cause Map

- **Markdown edits work** but **.docx fails with “Error while downloading…”** → Internal URL mapping wrong (Section 5.1) or JWT header/secret mismatch (Sections 2.2 & 5.3). Test with JWT disabled first (Sections 2.1 & 5.2).
- **PDF viewer fails** → Same internal mapping issue; occasionally CSP headers. Ensure `StorageUrl` and `DocumentServerInternalUrl` are set to reachable **http://127.0.0.1/** and **http://127.0.0.1:8080/** as above.
- **Nextcloud connection test fails** but web-apps load → DS can serve UI, but cannot fetch file from NC. Fix Section 5.1; then re-enable JWT.

---

## 9) Backups & Rollback

Before changing anything:
```bash
sudo cp -a /etc/onlyoffice/documentserver/local.json{,.bak.$(date +%s)} 2>/dev/null || true
sudo cp -a /etc/nginx/sites-available{,.bak.$(date +%s)}
sudo cp -a /var/www/nextcloud/config/config.php{,.bak.$(date +%s)}
```

Rollback by restoring the `*.bak.TIMESTAMP` files and reloading services.

---

## 10) Repo Layout Suggestion

```
infra/nextcloud-onlyoffice/
  README.md                # Paste the “Proof Diagnostics” and Symptom→Cause map
  nginx/
    onlyoffice_public.conf
    onlyoffice_internal_8080.conf
    nextcloud_public.conf
  onlyoffice/
    local.json.disabled    # 2.1
    local.json.jwt         # 2.2 (no secrets; template only)
  nextcloud/
    config.php.sample      # only the keys shown above
    occ_commands.sh        # Section 5 commands, sans secrets
```

> Store secrets in your secret manager or `.env` outside the repo. Replace via deploy tooling.

---

## 11) Fix Strategy Checklist (quick A/B)

1. Set **Section 5.1** (internal URLs) → reload nginx.
2. Set **JWT disabled** (Sections 2.1 + 5.2) → test `.docx` once.
3. If working, switch to **2.2 + 5.3** (JWT enabled) → test again.
4. If still failing: capture logs (Section 7.4) and re-check DNS/certs.

---

**End of baseline.** Paste any unexpected outputs from Section 7 and we’ll zero in further.
