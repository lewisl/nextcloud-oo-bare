# Current Best Configurations

This document maintains the current best versions of all important configuration files and settings. These are the "golden copies" that represent working configurations.

## OnlyOffice Document Server Configuration

### Current Working Configuration (as of 2025-09-15)

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
        "inbox": { "string": "GeE90SG6xtH@%N" },
        "outbox": { "string": "GeE90SG6xtH@%N" },
        "session": { "string": "GeE90SG6xtH@%N" }
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

**Status:** ✅ WORKING - service now binding to IPv4 (127.0.0.1:8000) and discovery endpoint accessible

**Issues resolved:**
1. ✅ Service now binding to IPv4 (127.0.0.1:8000)
2. ✅ Using correct 3 secret parameters (inbox, outbox, session)
3. ✅ Proper IPv4 binding for nginx proxy working
4. ✅ Discovery endpoint accessible via nginx proxy

### NextCloud OnlyOffice App Configuration

**Current settings:**
- DocumentServerUrl: `https://onlyoffice.test-collab-site.com/`
- DocumentServerInternalUrl: `http://127.0.0.1:8080/` (nginx proxy)
- JWT Secret: `GeE90SG6xtH@%N`
- JWT Enabled: `true`

**Status:** Configured but connection failing due to OnlyOffice service issues

## Nginx Configuration

**File:** `/etc/nginx/sites-available/docs.test-collab-site.com`

**OnlyOffice proxy section:**
```nginx
# OnlyOffice integration
location ^~ /onlyoffice/ {
    proxy_pass http://127.0.0.1:8080/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Host $server_name;

    # WebSocket support
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
    client_max_body_size 100M;
}
```

**Status:** Working - nginx is listening on port 8080 and proxying to OnlyOffice

## Issues to Resolve

1. **OnlyOffice IPv4 Binding:** Service needs to bind to 127.0.0.1:8000 (IPv4) not :::8000 (IPv6)
2. **Secret Parameters:** Need to verify which 3 secret parameters are actually required
3. **Service Communication:** OnlyOffice docservice needs to be accessible via IPv4 for nginx proxy

## Last Known Working State

Before the regression, the system was working with:
- NextCloud accessible at `https://docs.test-collab-site.com`
- OnlyOffice accessible at `https://onlyoffice.test-collab-site.com`
- OnlyOffice integration working in NextCloud
- Document editing functional

## Recovery Plan

1. Fix OnlyOffice IPv4 binding issue
2. Verify correct secret parameters (3 instead of 4?)
3. Test end-to-end document editing functionality
4. Update this document with working configuration
5. Commit working state to version control
