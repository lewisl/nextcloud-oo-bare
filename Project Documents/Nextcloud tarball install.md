Got it. Below is a **complete, copy-pasteable, non-Docker, non-Snap, tarball** install of Nextcloud on a fresh Ubuntu/Debian VPS with **nginx + PHP-FPM + MariaDB**. It ends with a working site on HTTPS and is ready for your ONLYOFFICE integration (localhost backend).

I’ll assume:

* Domain: `cloud.example.com`
* Web root (tarball already extracted): `/var/www/nextcloud`
* Data dir: `/srv/nextcloud-data` (outside the web root)
* You’re using `sudo` and want everything as **www-data**.

You can change variables at the top and re-use all commands as-is.

---

# 0) Variables (edit these once)

```bash
# ====== EDIT THESE ======
export NC_DOMAIN="test-collab-site.com"
export NC_DB="nextcloud"
export NC_DB_USER="nextcloud"
export NC_DB_PASS="$(openssl rand -base64 24)"     # or set your own
export NC_ADMIN_USER="admin"
export NC_ADMIN_PASS="$(openssl rand -base64 18)"  # or set your own
export NC_DATA_DIR="/srv/nextcloud-data"
# ========================

# detect PHP minor version (8.1 / 8.2 / 8.3, etc.)
export PHPVER="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
echo "Using PHP $PHPVER"
```

> Tip: run `echo $NC_DB_PASS $NC_ADMIN_PASS` and stash them somewhere safe.

---

# 1) System packages

```bash
sudo apt update
sudo apt install -y nginx mariadb-server \
  php-fpm php-mysql php-xml php-gd php-curl php-zip php-mbstring php-intl php-bcmath php-gmp \
  php-apcu php-imagick redis-server php-redis unzip curl certbot python3-certbot-nginx
```

---

# 2) Create Nextcloud data directory & set perms

```bash
sudo mkdir -p "$NC_DATA_DIR"
sudo chown -R www-data:www-data "$NC_DATA_DIR"
sudo chmod 750 "$NC_DATA_DIR"
```

If you haven’t already:

```bash
# you said you already did this, but for completeness:
cd /var/www
sudo curl -LO https://download.nextcloud.com/server/releases/latest.tar.bz2
sudo tar -xjf latest.tar.bz2
sudo chown -R www-data:www-data /var/www/nextcloud
```

---

# 3) MariaDB: secure & create DB/user

```bash
# optional but recommended hardening wizard:
sudo mysql_secure_installation

# create DB and user (utf8mb4)
sudo mysql -e "CREATE DATABASE \`$NC_DB\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
sudo mysql -e "CREATE USER '$NC_DB_USER'@'localhost' IDENTIFIED BY '$NC_DB_PASS';"
sudo mysql -e "GRANT ALL PRIVILEGES ON \`$NC_DB\`.* TO '$NC_DB_USER'@'localhost'; FLUSH PRIVILEGES;"
```

---

# 4) PHP-FPM tuning for Nextcloud

Create a dedicated ini so it survives package updates:

```bash
sudo tee /etc/php/$PHPVER/fpm/conf.d/90-nextcloud.ini >/dev/null <<'EOF'
; Nextcloud recommended PHP settings
memory_limit = 512M
upload_max_filesize = 512M
post_max_size = 512M
max_execution_time = 360
output_buffering = Off

; OPcache
opcache.enable=1
opcache.enable_cli=1
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=10000
opcache.memory_consumption=128
opcache.save_comments=1
opcache.revalidate_freq=60

; APCu (local cache)
apc.enable_cli=1
EOF

sudo systemctl restart php$PHPVER-fpm
```

---

# 5) nginx server block for Nextcloud

Create the site:

```bash
sudo tee /etc/nginx/sites-available/$NC_DOMAIN >/dev/null <<EOF
map \$http_upgrade \$connection_upgrade {
  default upgrade;
  ''      close;
}

server {
  listen 80;
  server_name $NC_DOMAIN;
  root /var/www/nextcloud;

  # Let’s Encrypt ACME challenge
  location ^~ /.well-known/acme-challenge/ { allow all; }

  # Redirect everything else to HTTPS
  location / { return 301 https://\$host\$request_uri; }
}

server {
  listen 443 ssl http2;
  server_name $NC_DOMAIN;
  root /var/www/nextcloud;

  # ======== TLS (certs filled by certbot) ========
  ssl_certificate     /etc/letsencrypt/live/$NC_DOMAIN/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/$NC_DOMAIN/privkey.pem;

  # Large uploads
  client_max_body_size 512m;
  fastcgi_buffers 64 4K;

  # Security headers (add/adjust as you like)
  add_header Referrer-Policy "no-referrer" always;
  add_header X-Content-Type-Options "nosniff" always;
  add_header X-Frame-Options "SAMEORIGIN" always;
  add_header X-XSS-Protection "1; mode=block" always;
  add_header X-Robots-Tag "none" always;

  # .well-known redirects (caldav/carddav)
  location = /.well-known/carddav  { return 301 /remote.php/dav/; }
  location = /.well-known/caldav   { return 301 /remote.php/dav/; }
  # Nextcloud other well-knowns
  location ^~ /.well-known         { try_files \$uri \$uri/ =404; }

  # Main routes
  index index.php index.html /index.php\$request_uri;

  location / {
    try_files \$uri \$uri/ /index.php\$request_uri;
  }

  # PHP handling
  location ~ \.php(?:\$|/) {
    fastcgi_split_path_info ^(.+?\.php)(/.*)\$;
    include fastcgi_params;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    fastcgi_param PATH_INFO \$fastcgi_path_info;
    fastcgi_param modHeadersAvailable true;
    fastcgi_param front_controller_active true;
    fastcgi_pass unix:/run/php/php$PHPVER-fpm.sock;
    fastcgi_intercept_errors on;
    fastcgi_request_buffering off;
  }

  # Deny access to some dirs/files
  location ~ ^/(?:\.|autotest|occ|issue|indie|db_|console) { return 404; }
  location ~* \.(?:bak|config|sql|fla|psd|ini|log|sh|swp)\$ { deny all; }

  # Static caching
  location ~* \.(?:css|js|woff2?|svg|gif|map)\$ {
    try_files \$uri /index.php\$request_uri;
    expires 6M; access_log off; add_header Cache-Control "public";
  }
}
EOF

sudo ln -s /etc/nginx/sites-available/$NC_DOMAIN /etc/nginx/sites-enabled/$NC_DOMAIN
sudo nginx -t && sudo systemctl reload nginx
```

Issue the certificate (this updates the TLS paths automatically if needed):

```bash
sudo certbot --nginx -d "$NC_DOMAIN" --redirect --agree-tos -m you@example.com -n
sudo systemctl reload nginx
```

---

# 6) Install Nextcloud via OCC (non-interactive)

We’ll do the install from CLI instead of the web installer.

```bash
cd /var/www/nextcloud
sudo -u www-data php occ maintenance:install \
  --database "mysql" \
  --database-name "$NC_DB" \
  --database-user "$NC_DB_USER" \
  --database-pass "$NC_DB_PASS" \
  --admin-user "$NC_ADMIN_USER" \
  --admin-pass "$NC_ADMIN_PASS" \
  --data-dir "$NC_DATA_DIR"
```

Set the trusted domain and overwrite URL:

```bash
sudo -u www-data php occ config:system:set trusted_domains 1 --value="$NC_DOMAIN"
sudo -u www-data php occ config:system:set overwrite.cli.url --value="https://$NC_DOMAIN/"
```

Enable recommended caches (APCu local + Redis locking):

```bash
# Redis socket (default) is /var/run/redis/redis-server.sock on many distros
# Ensure redis is running:
sudo systemctl enable --now redis-server

# Tell Nextcloud to use APCu + Redis
sudo -u www-data php occ config:system:set memcache.local --value="\\OC\\Memcache\\APCu"
sudo -u www-data php occ config:system:set memcache.locking --value="\\OC\\Memcache\\Redis"
sudo -u www-data php occ config:system:set redis host --value="/var/run/redis/redis-server.sock"
sudo -u www-data php occ config:system:set redis port --value="0" --type=integer
```

(If your Redis uses TCP instead of a socket, set `host` to `127.0.0.1` and `port` to `6379`.)

---

# 7) Permissions hardening (optional but good practice)

```bash
sudo find /var/www/nextcloud/ -type f -print0 | sudo xargs -0 chmod 0640
sudo find /var/www/nextcloud/ -type d -print0 | sudo xargs -0 chmod 0750
sudo chown -R www-data:www-data /var/www/nextcloud
sudo chown -R www-data:www-data "$NC_DATA_DIR"
```

---

# 8) Cron for background jobs

```bash
# switch to www-data crontab
( sudo -u www-data crontab -l 2>/dev/null; echo "*/5 * * * * php -f /var/www/nextcloud/cron.php" ) | sudo -u www-data crontab -
```

Then in **Settings → Administration → Basic settings** set Background jobs to **Cron**.

---

# 9) Verify

```bash
# nginx + php-fpm + redis + db status
systemctl status nginx --no-pager
systemctl status php$PHPVER-fpm --no-pager
systemctl status redis-server --no-pager
systemctl status mariadb --no-pager

# Nextcloud status
cd /var/www/nextcloud
sudo -u www-data php occ status
```

Visit: `https://$NC_DOMAIN/` and log in with `$NC_ADMIN_USER` / `$NC_ADMIN_PASS`.

---

## (Optional) Prep for ONLYOFFICE later

Add this so Nextcloud can talk to 127.0.0.1 backends (for your DS localhost link):

```bash
sudo -u www-data php occ config:system:set allow_local_remote_servers --value=1
```

If you later decide to use HTTPS with a self-signed cert between NC and DS, you can disable peer verification:

```bash
sudo -u www-data php occ config:app:set onlyoffice verify_peer_off --value=true
```

---

## Troubleshooting pointers

* nginx errors: `/var/log/nginx/error.log`
* PHP-FPM: `/var/log/php$PHPVER-fpm.log`
* Nextcloud app log: `/var/www/nextcloud/data/nextcloud.log`
* OCC help: `sudo -u www-data php occ list`

---

### That’s it

You now have a clean, **tarball-based** Nextcloud with nginx/PHP-FPM/MariaDB, TLS via Let’s Encrypt, APCu + Redis caching, cron, and it’s ready to wire up **ONLYOFFICE** behind your same nginx (localhost HTTP). If you want, I can add the `/onlyoffice/` proxy stanza to this same server block next.
