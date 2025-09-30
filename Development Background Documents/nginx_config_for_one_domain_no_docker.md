Got it—let’s do the **one-domain** setup cleanly. Below is a drop-in NGINX config that serves **Nextcloud at `/`** and **ONLYOFFICE Document Server under `/onlyoffice/`** on the **same FQDN** (e.g., `docs.example.org`). It’s intentionally minimal but production-ready.

Assumptions (adjust ports/paths if yours differ):

* Nextcloud runs via **PHP-FPM** (no Apache) at `127.0.0.1:9000`.
* ONLYOFFICE Document Server (DS) listens **locally** at `127.0.0.1:8082` (either the DEB/RPM reconfigured to 8082 on localhost, or the Docker container published as `127.0.0.1:8082->80`).

---

# 1) Put this at the **http** level (once)

`/etc/nginx/conf.d/00_maps.conf`

```nginx
# WebSocket upgrade helper usable in any server block
map $http_upgrade $connection_upgrade { default upgrade; '' close; }
```

---

# 2) Single server block for **docs.example.org**

`/etc/nginx/conf.d/nextcloud.conf`

```nginx
# HTTP -> HTTPS
server {
  listen 80;
  server_name docs.example.org;
  return 301 https://$host$request_uri;
}

# HTTPS vhost serving BOTH Nextcloud and ONLYOFFICE (under /onlyoffice/)
server {
  listen 443 ssl http2;
  server_name docs.example.org;

  # --- TLS (fill in your certs) ---
  ssl_certificate     /etc/letsencrypt/live/docs.example.org/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/docs.example.org/privkey.pem;
  add_header Strict-Transport-Security "max-age=63072000" always;

  # --- Nextcloud basics ---
  root /srv/nextcloud/html;
  index index.php;
  client_max_body_size 0;          # large uploads
  sendfile on;

  # CalDAV/CardDAV .well-known redirects
  location = /.well-known/carddav { return 301 /remote.php/dav/; }
  location = /.well-known/caldav { return 301 /remote.php/dav/; }
  # (optional) Let’s Encrypt ACME
  location ^~ /.well-known/acme-challenge/ { root /var/www/letsencrypt; }

  # Nextcloud app
  location / {
    try_files $uri $uri/ /index.php$request_uri;
  }

  # PHP-FPM handler
  location ~ \.php$ {
    include fastcgi_params;
    fastcgi_split_path_info ^(.+\.php)(/.+)$;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    fastcgi_param PATH_INFO $fastcgi_path_info;
    fastcgi_pass 127.0.0.1:9000;     # <-- PHP-FPM
    fastcgi_intercept_errors on;
    fastcgi_request_buffering off;   # better for large uploads
    fastcgi_read_timeout 3600;
  }

  # Static caching (optional)
  location ~ \.(?:css|js|woff2?|svg|gif|map)$ {
    try_files $uri /index.php$request_uri;
    expires 6M; access_log off;
  }

  # Deny access to sensitive paths
  location ~ ^/(?:\.|3rdparty|config|lib|templates|data)(/|$) { return 403; }

  # --- ONLYOFFICE under /onlyoffice/ ---
  location ^~ /onlyoffice/ {
    proxy_pass         http://127.0.0.1:8082/;   # note trailing slash
    proxy_http_version 1.1;

    # CRITICAL: tell DS its public host+path so it generates correct URLs
    proxy_set_header   X-Forwarded-Host  $host/onlyoffice;

    # Standard proxy+WS headers
    proxy_set_header   Host              $host;
    proxy_set_header   X-Real-IP         $remote_addr;
    proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header   X-Forwarded-Proto $scheme;
    proxy_set_header   Upgrade           $http_upgrade;
    proxy_set_header   Connection        $connection_upgrade;

    # Avoid proxy prefix confusion
    proxy_set_header   X-Forwarded-Prefix "";

    # Long-lived connections & big payloads
    client_max_body_size 0;
    proxy_read_timeout    3600;
    proxy_send_timeout    3600;
    proxy_buffering off;
    proxy_redirect off;
  }
}
```

> Two easy-to-miss details that make this work:
>
> * The **trailing slash** on `proxy_pass ... 8082/;`
> * The **`X-Forwarded-Host $host/onlyoffice`** header so DS knows it lives under a sub-path

---

# 3) Nextcloud → ONLYOFFICE wiring (occ)

Run these once Nextcloud is up (adjust paths/commands to your install):

```bash
# Browsers should load the editor from the sub-path on your Nextcloud domain:
sudo -u www-data php /srv/nextcloud/html/occ \
  config:app:set onlyoffice DocumentServerUrl --value="https://docs.example.org/onlyoffice/"

# Server-to-server calls can hit DS locally:
sudo -u www-data php /srv/nextcloud/html/occ \
  config:app:set onlyoffice DocumentServerInternalUrl --value="http://127.0.0.1:8082/"

# Align JWT with DS' /etc/onlyoffice/documentserver/local.json
sudo -u www-data php /srv/nextcloud/html/occ \
  config:app:set onlyoffice jwt_secret --value="your-shared-secret"
# (header defaults to "Authorization" unless you changed it)
```

---

# 4) Quick health checks

```bash
# NGINX test & reload
sudo nginx -t && sudo systemctl reload nginx

# DS through the sub-path:
curl -kI https://docs.example.org/onlyoffice/healthcheck
curl -ks https://docs.example.org/onlyoffice/hosting/discovery | head
```

You should see `200 OK` and discovery XML.

---

## Notes on the DS side (bare-metal install)

* If you use the **DEB/RPM** for Document Server, change its internal NGINX to bind **127.0.0.1:8082** (to avoid clashing with your system NGINX on 80/443). Alternatively, keep DS on 80 **but** bound to 127.0.0.1 and change the `proxy_pass` accordingly.
* Set JWT in `/etc/onlyoffice/documentserver/local.json` (`"enable": true`, `"secret": "...", "header": "Authorization"`), then restart DS services.

---

## That’s the whole “one domain” story

* **One** public name (`docs.example.org`) for both apps.
* Clean, standard NGINX; easy to maintain and tweak.
* No Cloudron/Docker requirements—just your system services.
* If you ever decide to split DS to its own domain later, you can lift the `location ^~ /onlyoffice/` into its own `server { }` on `onlyoffice.example.org` with the same proxy headers/timeouts.

If you want, tell me your actual cert paths, PHP-FPM socket/port, and where DS listens, and I’ll tailor the snippets to your exact box so you can copy-paste without edits.


awesome — glad it helped!

want a tiny “pin-to-notes” cheat sheet? here’s the distilled version you can reuse later.

# one-domain setup (nextcloud + onlyoffice under `/onlyoffice/`)

**nginx (http level, once):**

```nginx
map $http_upgrade $connection_upgrade { default upgrade; '' close; }
```

**nginx server block for `docs.example.org`:**

```nginx
# HTTP -> HTTPS
server { listen 80; server_name docs.example.org; return 301 https://$host$request_uri; }

server {
  listen 443 ssl http2;
  server_name docs.example.org;
  # ssl_certificate ... ; ssl_certificate_key ... ; (HSTS optional)

  root /srv/nextcloud/html;
  index index.php;
  client_max_body_size 0;

  location = /.well-known/carddav { return 301 /remote.php/dav/; }
  location = /.well-known/caldav { return 301 /remote.php/dav/; }

  location / { try_files $uri $uri/ /index.php$request_uri; }

  # PHP-FPM (adjust socket/port)
  location ~ \.php$ {
    include fastcgi_params;
    fastcgi_split_path_info ^(.+\.php)(/.+)$;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    fastcgi_param PATH_INFO $fastcgi_path_info;
    fastcgi_pass 127.0.0.1:9000;
    fastcgi_request_buffering off;
    fastcgi_intercept_errors on;
    fastcgi_read_timeout 3600;
  }

  # ONLYOFFICE under subpath (adjust DS upstream)
  location ^~ /onlyoffice/ {
    proxy_pass         http://127.0.0.1:8082/;   # NOTE trailing slash
    proxy_http_version 1.1;

    # critical so DS generates subpath-correct URLs:
    proxy_set_header   X-Forwarded-Host  $host/onlyoffice;

    proxy_set_header   Host              $host;
    proxy_set_header   X-Real-IP         $remote_addr;
    proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header   X-Forwarded-Proto $scheme;
    proxy_set_header   Upgrade           $http_upgrade;
    proxy_set_header   Connection        $connection_upgrade;

    client_max_body_size 0;
    proxy_read_timeout    3600;
    proxy_send_timeout    3600;
    proxy_buffering off;
    proxy_redirect off;
  }
}
```

**nextcloud → onlyoffice (run once):**

```bash
# browsers load DS from the subpath:
occ config:app:set onlyoffice DocumentServerUrl --value="https://docs.example.org/onlyoffice/"

# server-to-server calls stay local:
occ config:app:set onlyoffice DocumentServerInternalUrl --value="http://127.0.0.1:8082/"
occ config:app:set onlyoffice jwt_secret --value="<same-secret-as-DS>"
```

**smoke tests:**

```bash
nginx -t && systemctl reload nginx
curl -kI  https://docs.example.org/onlyoffice/healthcheck
curl -ks  https://docs.example.org/onlyoffice/hosting/discovery | head
```

**php limits (common gotcha):**

```ini
# nextcloud php.ini / php-fpm pool
upload_max_filesize = 4G
post_max_size       = 4G
max_execution_time  = 3600
memory_limit        = 512M
```

if you ever want me to tailor those snippets to your exact host paths/ports/cert locations, say the word and i’ll drop in a version you can paste in as-is.
