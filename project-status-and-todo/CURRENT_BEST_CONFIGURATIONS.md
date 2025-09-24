# Current Best Configurations

This document maintains the current best versions of all important configuration files and settings. These are the "golden copies" that represent working configurations.

## OnlyOffice Document Server Configuration

### Current Working Configuration (validated 2025-09-24)

**File:** `/etc/onlyoffice/documentserver/local.json`

```json
{
  "wopi": {
    "enable": true
  },
  "services": {
    "CoAuthoring": {
      "ip": "127.0.0.1",
      "server": { 
        "port": 8000
      },
      "sql": {
        "type": "postgres",
        "dbHost": "127.0.0.1",
        "dbPort": 5432,
        "dbName": "onlyoffice",
        "dbUser": "onlyoffice",
        "dbPass": "onlyoffice",
        "ssl": { "enable": false }
      },
      "redis": {
        "host": "127.0.0.1",
        "port": 6379
      },
      "rabbitmq": {
        "url": "amqp://guest:guest@127.0.0.1:5672"
      },
      "secret": {
        "browser": { "string": "1cc880382bce64842006d1070f9e551391e67c37fa758975cbd2c2ad6652c637", "file": "" },
        "inbox":   { "string": "1cc880382bce64842006d1070f9e551391e67c37fa758975cbd2c2ad6652c637", "file": "" },
        "outbox":  { "string": "1cc880382bce64842006d1070f9e551391e67c37fa758975cbd2c2ad6652c637", "file": "" },
        "session": { "string": "1cc880382bce64842006d1070f9e551391e67c37fa758975cbd2c2ad6652c637", "file": "" }
      },
      "token": {
        "enable": {
          "request": {
          "inbox": true,
          "outbox": true
          },
        }
      }
    }
  }
}
```

**Status:** ✅ Document Server bound to IPv4 loopback and reachable locally; public access now fronted exclusively by the Nextcloud `/onlyoffice/` subpath

**Current Configuration (JWT Disabled for Testing):**
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

**Issues resolved:**
1. ✅ Service now binding to IPv4 (127.0.0.1:8000)
2. ✅ Using correct 3 secret parameters (inbox, outbox, session)
3. ✅ Proper IPv4 binding for nginx proxy working
4. ✅ Discovery endpoint accessible via nginx proxy

**Validation notes (2025-09-24):**
1. ✅ `/onlyoffice/` proxy confirmed with `healthcheck`, `hosting/discovery`, and `api.js`
2. ✅ OCC connector check returns "Document server … successfully connected"
3. ✅ Browser smoke tests pass for `.docx`, `.xlsx`, `.pptx`, `.pdf`, and built-in viewers

### NextCloud OnlyOffice App Configuration

**Current settings:**
- DocumentServerUrl: `https://docs.<domain>/onlyoffice/`
- DocumentServerInternalUrl: `http://127.0.0.1:8080/`
- StorageUrl: `https://docs.<domain>/`
- JWT Secret: `1cc880382bce64842006d1070f9e551391e67c37fa758975cbd2c2ad6652c637`
- JWT Header: `AuthorizationJwt`
- JWT Enabled: `true`

**Status:** ✅ One-domain subpath mode active; OCC commands above are idempotent for reruns

## Nginx Configuration

**File:** `/etc/nginx/sites-available/docs.test-collab-site.com`

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
