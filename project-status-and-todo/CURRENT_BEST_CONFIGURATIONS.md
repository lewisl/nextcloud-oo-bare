# Current Best Configurations

This document maintains the current best versions of all important configuration files and settings. These are the "golden copies" that represent working configurations.

## Deployment Parameters Template

- **Template path:** `configs/params.yaml`
- **Install location:** `/etc/nextcloud-onlyoffice/params.yaml` (copied by `src/01_system_prep.sh` on first run)
- **Placeholders:** every value defaults to a `CHANGE_ME_*` token so administrators must supply the real base domain, contact emails, and database credentials before continuing. The system prep script auto-generates secure values for the Nextcloud admin password and JWT secret if the placeholders remain.
- **Reminder:** the Nextcloud FQDN must begin with `docs.` and the OnlyOffice FQDN with `onlyoffice.` to satisfy validation in `src/lib/config_loader.py`.
- **Package note:** `src/01_system_prep.sh` installs `php-apcu`/`php-apcu-bc` so the `memcache.local` setting resolves without manual intervention.

## OnlyOffice Document Server Configuration

### Maintained Configuration (managed by `src/04_onlyoffice_install.sh`)

**File:** `/etc/onlyoffice/documentserver/local.json`

See `configs/onlyoffice/local.json` for the managed template (the installer renders it with deployment parameters). Key requirements enforced by the script:

- DocumentServer listens on `127.0.0.1:8000` only.
- DocumentServer advertises `https://docs.<domain>/onlyoffice` through `.services.CoAuthoring.public.url` so subpath deployments work.
- PostgreSQL credentials come from `configs/params.yaml` (`onlyoffice` section).
- JWT secret matches the shared value used by Nextcloud (`jwt.secret`).
- JWT headers for both inbound (`token.inbox.header`) and outbound (`token.outbox.header`) traffic are set to `Authorization` to match the nginx proxy passthrough and Nextcloud connector settings.
- Request filtering allows traffic from `docs.<domain>`, `onlyoffice.<domain>`, and loopback.
- RabbitMQ URL defaults to `amqp://guest:guest@localhost`; WOPI support stays enabled.
- FileConverter uses explicit binary paths for `x2t` and `docbuilder` to avoid spawn errors on Ubuntu 24.04 (`FileConverter.converter.{x2tPath,docbuilderPath}`).
- Storage signed-link protection now inherits the same secure link secret that nginx embeds in `/etc/onlyoffice/documentserver/nginx/ds.conf`; the installer keeps `storage.fs.secretString` in sync automatically to prevent 403 errors during connector self-checks.

**Status (validated 2025-09-26):** ✅ DocumentServer stays behind nginx reverse proxy; healthchecks pass at `http://127.0.0.1:8080/healthcheck` and conversion succeeds after restart of `ds-converter.service`.

**Validation notes (2025-09-26):**
- `curl --max-time 30 http://127.0.0.1:8080/healthcheck` returns `true`.
- `systemctl is-active ds-docservice ds-converter` reports `active` after script rerun.
- `sudo -u www-data php /var/www/nextcloud/occ onlyoffice:documentserver --check` succeeds once docs.<domain> presents a trusted certificate; using Let's Encrypt staging under the Cloudflare proxy currently surfaces `Error while downloading the document file to be converted` (expected).
- Allowed hosts include `docs.test-collab-site.com` and `127.0.0.1`.

**Companion file:** `/etc/onlyoffice/documentserver/production-linux.json` is replaced from `configs/onlyoffice/production-linux.json` to keep static content paths aligned with the managed deployment.
- **Nginx sub-config:** `src/04_onlyoffice_install.sh` now renders `/etc/onlyoffice/documentserver/nginx/ds.conf` from `configs/onlyoffice/nginx/ds.conf.tpl`, preserving any existing secure-link secret across reruns.

### NextCloud OnlyOffice App Configuration

**Current settings:**
- DocumentServerUrl: `https://docs.<domain>/onlyoffice/`
- DocumentServerInternalUrl: `http://127.0.0.1:8080/`
- StorageUrl: `https://docs.<domain>/`
- JWT Secret: `<JWT_SECRET>` (matches params.yaml)
- JWT Header: `Authorization`
- JWT Enabled: `true`
- sameTab: `true` (keeps editing within the Nextcloud browser tab so the close control behaves correctly)

**Status:** ✅ One-domain subpath mode active; OCC commands above are idempotent for reruns.

## Nginx Configuration

**File:** `/etc/nginx/sites-available/docs.<domain>.conf`

Managed via `src/05_nginx_config.sh` using templates in `configs/nginx/` (`nginx.conf`, `conf.d/00_websocket_upgrade_map.conf`, and `sites-available/nextcloud_{http,https}.conf.tpl`).

**OnlyOffice proxy section (subpath mode):**
```nginx
# OnlyOffice editor under /onlyoffice/
location ^~ /onlyoffice/ {
    proxy_pass         http://127.0.0.1:8080/;
    proxy_http_version 1.1;

    proxy_set_header   Host               $host;
    proxy_set_header   X-Real-IP          $remote_addr;
    proxy_set_header   X-Forwarded-For    $proxy_add_x_forwarded_for;
    proxy_set_header   X-Forwarded-Proto  https;
    proxy_set_header   X-Forwarded-Host   $host;
    proxy_set_header   X-Forwarded-Port   443;
    proxy_set_header   X-Forwarded-Prefix /onlyoffice;
    proxy_set_header   Authorization      $http_authorization;
    proxy_set_header   Upgrade            $http_upgrade;
    proxy_set_header   Connection         $connection_upgrade;

    client_max_body_size 200m;
    proxy_read_timeout    3600s;
    proxy_send_timeout    3600s;
    proxy_buffering       off;
    proxy_redirect        off;
}

# Cache-busting for hashed static assets (includes modern modules)
location ~ ^/(?!index\.php/).*\.(?:css|js|mjs|wasm|woff2?|svg|gif|map)$ {
    try_files $uri /index.php$request_uri;
    expires 6M;
    add_header Cache-Control "public, max-age=15552000, immutable";
    access_log off;
}

location ~ ^/(?!index\.php/).*\.(?:png|html|ttf|ico|jpg|jpeg|webp|avif)$ {
    try_files $uri /index.php$request_uri;
    expires 6M;
    add_header Cache-Control "public, max-age=15552000, immutable";
    access_log off;
}

# Force directories under /apps/ through the front controller while allowing direct asset requests
location ~ ^/apps/(?!.*/api/)(?!.*\.[^/]+$).*/?$ {
    rewrite ^(.*)$ /index.php$1 last;
}
```

**Status:** ✅ Live configuration in production test; requires `/etc/nginx/conf.d/00_websocket_upgrade_map.conf`.

**Additional requirement:** Ensure `/etc/nginx/mime.types` defines `text/javascript  mjs;` so Nextcloud’s Viewer/Text `.mjs` bundles ship with the correct MIME type.

## Follow-up Actions

1. Keep legacy `onlyoffice.<domain>` nginx vhost on disk (disabled) for emergency rollback.
2. Remove `onlyoffice.<domain>` from certbot renewal set once production cutover is complete.
3. Integrate the validated nginx + OCC steps into automation scripts after documentation updates.
4. Run `./src/99_diagnostics.sh` post-change and archive results with date stamps.

## System Hardening Snippets (added 2025-09-25)

**Fail2ban jail overrides** – `configs/fail2ban/nextcloud-onlyoffice.conf`
```ini
[nginx-http-auth]
enabled = true
port    = http,https
logpath = /var/log/nginx/error.log
maxretry = 5

[nginx-limit-req]
enabled = true
port    = http,https
logpath = /var/log/nginx/error.log
maxretry = 20
findtime = 300
bantime  = 3600

[nextcloud]
enabled  = true
port     = http,https
logpath  = /var/www/nextcloud/data/nextcloud.log
maxretry = 5
findtime = 300
bantime  = 3600
```

**PHP override snippet** – `configs/php/nextcloud.ini`
```ini
memory_limit = 512M
max_execution_time = 300
max_input_time = 300
post_max_size = 1024M
upload_max_filesize = 1024M
always_populate_raw_post_data = -1
opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=10000
opcache.revalidate_freq=1
```

The system prep script copies these snippets into `/etc/fail2ban/jail.d/nextcloud-onlyoffice.conf` and `/etc/php/8.3/{fpm,cli}/conf.d/90-nextcloud.ini` respectively.

**Credential bootstrap**
- On first run, `src/01_system_prep.sh` replaces placeholder values in `/etc/nextcloud-onlyoffice/params.yaml` for the Nextcloud admin password and JWT secret with freshly generated random credentials. The script prints those values so the administrator can record them securely.
