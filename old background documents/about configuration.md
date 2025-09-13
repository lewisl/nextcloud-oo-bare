

**You**:

Can you package this uip so it's clear--the chat conversation meanders a lot...

---

**ChatGPT**:

here’s the clean, consolidated “single-box, no-docker” handbook you asked for. drop it into your repo as `docs/DEPLOY_SINGLE_BOX.md`.

# Nextcloud + OnlyOffice on one VPS (no Docker, one nginx)

**Target:** Ubuntu 24.04 • nginx • PHP-FPM 8.3 • Redis • MariaDB (Nextcloud) • PostgreSQL (OnlyOffice DS)**
**Topology:** one nginx process, two server blocks:

- public vhost `https://DOMAIN` serves Nextcloud and **proxies** `/onlyoffice/`

- OnlyOffice Document Server (DS) ships its own nginx **server block**, bound to **127.0.0.1:8080** (loopback only)

**

Use the same layout for **test** (`test-collab-site.com`) and **prod** (`docs.bedfordfallsbbbl.org`). Swap `DOMAIN` and `EMAIL` accordingly.

## 0) Variables (set once)

- `DOMAIN` = `test-collab-site.com` (test) or `docs.bedfordfallsbbbl.org` (prod)

- `EMAIL`  = admin mail for Let’s Encrypt, e.g. `admin@DOMAIN`

- `DS_JWT` = long random shared secret for OnlyOffice DS & Nextcloud app

- DB passwords: replace all `CHANGE_ME`

## 1) Base packages (non-interactive)

bash`apt-get update -y
apt-get install -y --no-install-recommends \
  nginx-full curl jq unzip ca-certificates \
  php8.3-fpm php8.3-{cli,gd,xml,curl,zip,mbstring,intl,bcmath,gmp,imagick,apcu} \
  redis-server php8.3-redis \
  mariadb-server mariadb-client php8.3-mysql \
  postgresql postgresql-contrib \
  certbot python3-certbot-nginx
echo 'export DEBIAN_FRONTEND=noninteractive PAGER=cat GIT_PAGER=cat SYSTEMD_PAGER=cat' >> /root/.bashrc
`</pre>

## 2) Databases

### MariaDB for Nextcloud

bash`mysql -uroot <<'SQL'
CREATE DATABASE IF NOT EXISTS nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS 'nc_user'@'localhost' IDENTIFIED BY 'CHANGE_ME';
GRANT ALL PRIVILEGES ON nextcloud.* TO 'nc_user'@'localhost';
FLUSH PRIVILEGES;
SQL
`</pre>

### PostgreSQL for OnlyOffice DS

bash`sudo -u postgres psql <<'SQL'
CREATE DATABASE onlyoffice;
CREATE USER ds_user WITH ENCRYPTED PASSWORD 'CHANGE_ME';
GRANT ALL PRIVILEGES ON DATABASE onlyoffice TO ds_user;
SQL
`</pre>

## 3) Install OnlyOffice Document Server (native) and bind to 127.0.0.1:8080

- Install the `onlyoffice-documentserver` package (add OnlyOffice repo as per their docs), then:

bash`apt-get install -y onlyoffice-documentserver
`</pre>

- Change DS nginx **listen** to **loopback:8080** (so it’s not public). Find the file:

bash`grep -R --line-number -E 'listen .*80' /etc/nginx /etc/onlyoffice/documentserver/nginx 2>/dev/null
`</pre>

Edit the DS server block you find:

nginx`listen 127.0.0.1:8080;
server_name localhost;
`</pre>

- Configure DS to use **host PostgreSQL** and **JWT** (names may be `token` or `jwt` depending on version). Edit:

`/etc/onlyoffice/documentserver/local.json`

json`{
  "services": {
    "CoAuthoring": {
      "sql": {
        "type": "postgres",
        "dbHost": "127.0.0.1",
        "dbPort": 5432,
        "dbName": "onlyoffice",
        "dbUser": "ds_user",
        "dbPass": "CHANGE_ME"
      },
      "token": { "enable": true, "inBody": true, "secret": "DS_JWT_VALUE" }
    }
  }
}
`</pre>

- Reload:

bash`nginx -t && systemctl reload nginx
systemctl restart onlyoffice-documentserver
journalctl -u onlyoffice-documentserver -n 100 --no-pager | tail -n +1
`</pre>
**

DS should now answer locally: `curl -I http://127.0.0.1:8080/`

## 4) Public nginx vhost (Nextcloud at `/`, DS proxied at `/onlyoffice/`)

Create `/etc/nginx/sites-available/nextcloud.conf` and replace **DOMAIN** everywhere:

nginx`# HTTP → HTTPS (LE challenges allowed)
server {
    listen 80;
    server_name DOMAIN;
    location /.well-known/acme-challenge/ { root /var/www/html; }
    return 301 https://$host$request_uri;
}

# Nextcloud + OnlyOffice (proxied) over HTTPS
server {
    listen 443 ssl http2;
    server_name DOMAIN;

    ssl_certificate     /etc/letsencrypt/live/DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/DOMAIN/privkey.pem;

    client_max_body_size 512M;
    fastcgi_read_timeout 360s;

    root /var/www/nextcloud;
    index index.php index.html /index.php$request_uri;

    # Nextcloud well-known
    location = /robots.txt { allow all; log_not_found off; access_log off; }
    location ^~ /.well-known {
        location = /.well-known/carddav { return 301 /remote.php/dav; }
        location = /.well-known/caldav  { return 301 /remote.php/dav; }
        try_files $uri $uri/ =404;
    }

    # Static cache
    location ~ \.(?:css|js|svg|gif|png|jpg|ico)$ {
        try_files $uri /index.php$request_uri;
        expires 6M; access_log off;
        add_header Cache-Control "public, no-transform";
    }

    # PHP via php-fpm 8.3 (adjust if version differs)
    location ~ \.php(?:$|/) {
        try_files $uri /index.php$request_uri;
        include fastcgi_params;
        fastcgi_split_path_info ^(.+?\.php)(/.*)$;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_param modHeadersAvailable true;
        fastcgi_param front_controller_active true;
        fastcgi_intercept_errors on;
    }

    # Protect sensitive paths
    location ~ ^/(?:\.|autotest|occ|issue|indie|db_|console) { deny all; }
    location ~ ^/(?:build|tests|config|lib|3rdparty|templates|data)/ { deny all; }

    # ----- OnlyOffice Document Server proxy -----
    location ^~ /onlyoffice/ {
        proxy_pass http://127.0.0.1:8080/;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Host $host;

        proxy_set_header Upgrade $http_upgrade;   # websockets
        proxy_set_header Connection "upgrade";

        client_max_body_size 512M;
        proxy_read_timeout 3600s;
    }

    access_log /var/log/nginx/nextcloud.access.log;
    error_log  /var/log/nginx/nextcloud.error.log;
}
`</pre>

Enable + TLS:

bash`ln -s /etc/nginx/sites-available/nextcloud.conf /etc/nginx/sites-enabled/nextcloud.conf
nginx -t && systemctl reload nginx
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL"
`</pre>

## 5) PHP 8.3 essentials

`/etc/php/8.3/fpm/php.ini`

ini`memory_limit = 512M
upload_max_filesize = 512M
post_max_size = 512M
max_execution_time = 360
date.timezone = UTC

; Opcache
opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=192
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=10000
opcache.save_comments=1

; APCu
apc.enable_cli=1
`</pre>

`/etc/php/8.3/fpm/pool.d/www.conf`

ini`listen = /run/php/php8.3-fpm.sock
pm = dynamic
pm.max_children = 12
pm.start_servers = 3
pm.min_spare_servers = 2
pm.max_spare_servers = 6
pm.max_requests = 500
`</pre>

Reload:

bash`systemctl reload php8.3-fpm
`</pre>

## 6) Nextcloud `config.php` (MariaDB + Redis)

`/var/www/nextcloud/config/config.php` (owner `www-data`):

php`<?php
$CONFIG = array (
  'trusted_domains' => ['DOMAIN'],
  'overwrite.cli.url' => 'https://DOMAIN',
  'overwriteprotocol' => 'https',
  'default_phone_region' => 'US',
  'datadirectory' => '/var/ncdata',
  'logfile' => '/var/log/nextcloud.log',
  'loglevel' => 2,

  'memcache.local'   => '\\OC\\Memcache\\APCu',
  'memcache.locking' => '\\OC\\Memcache\\Redis',
  'redis' => ['host' => '/var/run/redis/redis-server.sock', 'port' => 0],

  'dbtype' => 'mysql',
  'dbname' => 'nextcloud',
  'dbhost' => 'localhost:3306',
  'dbuser' => 'nc_user',
  'dbpassword' => 'CHANGE_ME',

  'installed' => true,
);
`</pre>

Background jobs:

bash`crontab -u www-data -l 2>/dev/null | sed '/cron.php/d' | crontab -u www-data -
( crontab -u www-data -l 2>/dev/null; echo "*/5 * * * * php -f /var/www/nextcloud/cron.php" ) | crontab -u www-data -
`</pre>

## 7) Wire Nextcloud ↔ OnlyOffice

In Nextcloud **Apps → ONLYOFFICE**:

- **Document Server URL:****
`https://DOMAIN/onlyoffice/`

- **Secret key:** same value as `DS_JWT` in DS `local.json`.

Save → open a test doc.

## 8) Quick sanity checks

bash`# nginx config & reload
nginx -t && systemctl reload nginx

# php-fpm socket present?
ss -xl | grep php8.3-fpm.sock || systemctl status php8.3-fpm --no-pager

# Nextcloud baseline
sudo -u www-data php /var/www/nextcloud/occ status
sudo -u www-data php /var/www/nextcloud/occ check

# Front door & DS
curl -I https://$DOMAIN/ | head -n1
curl -I http://127.0.0.1:8080/ | head -n1   # DS local
`</pre>

## 9) Gotchas & fixes

- **502/504** → nginx `fastcgi_pass` socket must match your PHP version (`/run/php/php8.3-fpm.sock`).

- **Large uploads fail** → bump **both** nginx `client_max_body_size` and PHP `upload_max_filesize/post_max_size`.

- **OnlyOffice won’t open** → DS URL must be `/onlyoffice/`; JWT secret must match; proxy must include `Upgrade/Connection` headers.

- **Redirect/login loop** → ensure `'overwriteprotocol' => 'https'` and correct `trusted_domains`.

- **Locks/perf** → Redis socket configured in `config.php` and `php8.3-redis` installed.

### Test → Prod checklist

- Provision VPS identically.

- Copy configs; change **DOMAIN** + **EMAIL**; new cert via `certbot --nginx`.

- Create fresh MariaDB user password; update `config.php`.

- DS `local.json`: keep same JWT (or rotate), keep `127.0.0.1:8080`.

- Verify with the sanity checks above.

If you want, tell me your final `DOMAIN`, `EMAIL`, and the exact passwords/JWT you plan to use (or placeholders you prefer), and I’ll generate a single **sed-ready** block you can paste to configure all files in one go.

---
