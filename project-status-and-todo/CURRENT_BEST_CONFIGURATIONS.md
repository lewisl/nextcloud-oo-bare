# Current Best Configurations

This document maintains the current best versions of all important configuration files and settings. These are the "golden copies" that represent working configurations.

## OnlyOffice Document Server Configuration

### Maintained Configuration (managed by `src/04_onlyoffice_install.sh`)

**File:** `/etc/onlyoffice/documentserver/local.json`

See `configs/onlyoffice/local.json` for the managed snippet (placeholders replace secrets). Key requirements enforced by the script:

- DocumentServer listens on `127.0.0.1:8000` only.
- PostgreSQL credentials come from `configs/params.yaml` (`onlyoffice` section).
- JWT secret matches the shared value used by Nextcloud (`jwt.secret`).
- Request filtering allows traffic from `docs.<domain>`, `onlyoffice.<domain>`, and loopback.
- RabbitMQ URL defaults to `amqp://guest:guest@localhost`; WOPI support stays enabled.

**Status:** ✅ DocumentServer stays behind nginx reverse proxy; healthchecks pass at `http://127.0.0.1:8080/healthcheck`.

**Validation notes (2025-09-25):**
- `curl -fsS http://127.0.0.1:8080/healthcheck` returns `true`.
- `systemctl is-active onlyoffice-documentserver` reports `active` after script rerun.
- Allowed hosts include `docs.test-collab-site.com` and `127.0.0.1`.

**Companion file:** `/etc/onlyoffice/documentserver/production-linux.json` is replaced from `configs/onlyoffice/production-linux.json` to keep static content paths aligned with the managed deployment.

### NextCloud OnlyOffice App Configuration

**Current settings:**
- DocumentServerUrl: `https://docs.<domain>/onlyoffice/`
- DocumentServerInternalUrl: `http://127.0.0.1:8080/`
- StorageUrl: `https://docs.<domain>/`
- JWT Secret: `<JWT_SECRET>` (matches params.yaml)
- JWT Header: `AuthorizationJwt`
- JWT Enabled: `true`

**Status:** ✅ One-domain subpath mode active; OCC commands above are idempotent for reruns

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

**Status:** ✅ Live configuration in production test; requires `/etc/nginx/conf.d/00_websocket_upgrade_map.conf`

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
