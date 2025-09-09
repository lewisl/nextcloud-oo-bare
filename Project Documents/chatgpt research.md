Lewis' prompt
>   is it possible to integrate onlyoffice document editors with nextcloud: - with both running on the same vps - both behind a single instance of nginx - uninstalling the app specific instances of nginx or apache - using a localhost connection from nextcloud to onlyoffice without ssl or certificates as teh connection is on the same machine and not across the open internet

Short answer: yes—this setup is doable and common.

Here’s the recipe that matches your bullets (single VPS, one nginx, no extra app-webservers, localhost HTTP between apps).

# What you’ll run

* **Nextcloud** (PHP-FPM + nginx frontend)
* **ONLYOFFICE Document Server** (Docker or native) listening **only on 127.0.0.1** (HTTP, no TLS)

# Key Nextcloud settings

In `config.php` add (this is required since NC 19 to allow calls to local/private IPs):

```php
'allow_local_remote_servers' => true,
'onlyoffice' => [
  'verify_peer_off' => true  // relaxes cert checks when you use HTTP/self-signed
]
```

The `allow_local_remote_servers` flag is the standard fix for “Host violates local access rules.” ([GitHub][1], [Nextcloud community][2])
The `verify_peer_off` option (or the checkbox “Disable certificate verification (insecure)” in the ONLYOFFICE app) is the documented way to skip TLS verification when you’re not using HTTPS to the editor. ([api.onlyoffice.com][3])

In **Nextcloud → Apps → ONLYOFFICE**:

* **Document Editing Service address:** `https://cloud.example.com/onlyoffice/`  *(this is the external URL behind nginx)*
* **Document Editing Service address for internal requests from the server:** `http://127.0.0.1:8080/` *(or whatever your DS listens on)*
* **Server address for internal requests from the Document Editing Service:** `http://127.0.0.1/` *(Nextcloud’s local HTTP endpoint)*
* Set a **JWT secret** here and use the same on the Document Server. (JWT is on by default in recent versions; you just need to keep the secrets in sync.) ([OnlyOffice][4])

# ONLYOFFICE Document Server

Run DS bound to localhost only (no public exposure). Example (Docker):

```bash
docker run -d --name ds --restart=unless-stopped \
  -e JWT_ENABLED=true -e JWT_SECRET='yoursecret' \
  -p 127.0.0.1:8080:80 \
  onlyoffice/documentserver
```

If you later use self-signed certs or HTTPS upstreams, you may need to relax storage certificate checks in Document Server’s JSON (e.g., `rejectUnauthorized:false`), but for plain HTTP to 127.0.0.1 you won’t. ([Medium][5])

# Single nginx in front

Terminate TLS once and reverse-proxy to both apps. Minimal example:

```nginx
# --- Nextcloud upstream (php-fpm not shown here) ---
upstream nextcloud {
    server 127.0.0.1:9000;  # if you talk to php-fpm via fastcgi_pass, skip this
}

# --- ONLYOFFICE Document Server upstream ---
upstream onlyoffice {
    server 127.0.0.1:8080;  # docker/native DS bound to localhost
}

server {
    listen 443 ssl http2;
    server_name cloud.example.com;

    # ... ssl_certificate / ssl_certificate_key ...

    client_max_body_size 512m;  # large uploads for office files

    # ----- Nextcloud root -----
    root /var/www/nextcloud;

    # Nextcloud locations (typical NC nginx config omitted for brevity)

    # ----- ONLYOFFICE under /onlyoffice/ -----
    location ^~ /onlyoffice/ {
        proxy_pass         http://onlyoffice/;
        proxy_http_version 1.1;

        # WebSocket support
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

        # Optional: larger buffers for big docs
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}

map $http_upgrade $connection_upgrade {
  default upgrade;
  ''      close;
}
```

Those `X-Forwarded-*` headers and WebSocket bits are the common gotchas when putting ONLYOFFICE behind a reverse proxy; they’re explicitly recommended in community examples and in ONLYOFFICE’s proxy sample configs. ([Nextcloud community][6], [GitHub][7])

# Uninstalling extra webservers

Yes—if you run both apps behind **this one nginx**, you do **not** need separate nginx/apache instances provided by distro packages or containers. Stop/disable any bundled webservers and bind DS to `127.0.0.1` so it’s never exposed directly.

> well, later research shows that this is difficult because onlyoffice has 3 distinct applications that call each other.  it can be done without a private instance of nginx for onlyoffice, but it is difficult.

# Localhost without SSL

Also yes—using **HTTP over 127.0.0.1** is fine. Just make sure:

* Nextcloud allows local remotes (`allow_local_remote_servers`). ([GitHub][1])
* You either check “Disable certificate verification” in the ONLYOFFICE app or set `verify_peer_off` in `config.php` (so the connector doesn’t complain about lack of TLS). ([api.onlyoffice.com][3])

## Another challenge

Lewis' prompt:
> That sounds good. In attempting something similar, some challenges were encounered. The NextCloud connector to OnlyOffice has one required input parameter: the ip address or domain to the onlyoffice server (for the document editors). It only accepts https even if you check the checkbox for "unsecure". It appears to reject choosing unsecured. How does one overcome this?

Yep—what you’re bumping into is mostly **UI validation** on the “public” URL field. The trick is:

* keep the **public** “Document Server address” as **HTTPS** (satisfies the form),
* but route it through **your nginx** to a **localhost HTTP** OnlyOffice, and
* use the **Advanced server settings** for the two **internal** URLs, which *can* be plain HTTP.

Here’s the working pattern:

1. **nginx: one TLS frontend, local HTTP upstream**

* Terminate TLS on nginx and proxy **`/onlyoffice/` → [http://127.0.0.1:8080\`](http://127.0.0.1:8080`)** (your Document Server).
* Make sure you include WebSocket headers and `X-Forwarded-*`. This is the standard reverse-proxy setup shown in OnlyOffice samples/community fixes. ([Nextcloud community][1])

2. **Nextcloud → Apps → ONLYOFFICE settings**

* **Document Server address (public)**: `https://cloud.example.com/onlyoffice/`  ← *must be https to pass the form; it’s your nginx endpoint*.
* **Advanced server settings** (these fields exist specifically for split routing):

  * **ONLYOFFICE Docs address for internal requests from the server**: `http://127.0.0.1:8080/`
  * **Server address for internal requests from ONLYOFFICE Docs**: `http://127.0.0.1/` (whatever NC listens on locally)

  These “internal request” fields are documented by OnlyOffice for cases where public addresses don’t work or must differ from the internal path—and they accept HTTP. ([api.onlyoffice.com][2], [GitHub][3], [Hetzner Community][4])

3. **Nextcloud config.php toggles**

* Allow Nextcloud to talk to private/localhost targets (prevents “Host violates local access rules”):

  ```php
  'allow_local_remote_servers' => true,
  ```

  This option is in the official admin config sample and is the common fix discussed across threads. You can also set it via OCC:
  `sudo -u www-data php occ config:system:set allow_local_remote_servers --value 1`. ([Nextcloud][5], [Nextcloud community][6])
* If you ever end up using self-signed certs between the two (not needed for pure HTTP on 127.0.0.1), you can relax verification:

  ```php
  'onlyoffice' => ['verify_peer_off' => true],
  ```

  (equivalent to checking “Disable certificate verification” in the app). ([Nextcloud community][7])

4. **OnlyOffice Document Server**

* Run it **bound to 127.0.0.1** (no public exposure). If OO must accept a self-signed/unknown cert when it calls back to NC, add
  `USE_UNAUTHORIZED_STORAGE=true` to the container env; this tells DS to accept an untrusted storage (Nextcloud). For pure HTTP you don’t need this. ([Nextcloud community][8])

### Why your field “rejects unsecured”

The **top** “Document Server address” field is intended to be the **external** editor URL and the connector validates it as HTTPS. This is by design, but the **internal** addresses in “Advanced server settings” are explicitly there to let you use **HTTP** on the backend. Users regularly report success with HTTPS public + HTTP internal. ([Nextcloud community][9], [api.onlyoffice.com][2])

### Quick test list

* Open `https://cloud.example.com/onlyoffice/` and you should see the OO welcome JSON—served through nginx.
* Save the connector settings with the HTTPS public URL and the two HTTP internal URLs.
* If save/open fails, check NC logs for “local access rules” (then confirm `allow_local_remote_servers`) and check DS logs like `converter/out.log` for callback/JWT issues. ([Nextcloud community][6], [ONLYOFFICE Community][10])

If you want, paste your nginx `location /onlyoffice/` and your current connector fields and I’ll spot the exact mismatch.

[1]: https://help.nextcloud.com/t/disable-https-requirement/145000?utm_source=chatgpt.com "Disable HTTPS requirement - ℹ️ Support"
[2]: https://api.onlyoffice.com/docs/docs-api/get-started/ready-to-use-connectors/nextcloud-integration/?utm_source=chatgpt.com "Nextcloud integration"
[3]: https://github.com/ONLYOFFICE/onlyoffice-nextcloud?utm_source=chatgpt.com "ONLYOFFICE/onlyoffice-nextcloud: The app which enables ..."
[4]: https://community.hetzner.com/tutorials/install-and-configure-onlyoffice-docs-for-nextcloud/?utm_source=chatgpt.com "Install and Configure ONLYOFFICE Docs for Nextcloud"
[5]: https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/config_sample_php_parameters.html?utm_source=chatgpt.com "Configuration Parameters"
[6]: https://help.nextcloud.com/t/cant-connect-to-onlyoffice-document-server-after-update-to-nc19/83958?utm_source=chatgpt.com "Can't connect to OnlyOffice document server after update ..."
[7]: https://help.nextcloud.com/t/onlyoffice-integration-https-certificate-failed/35160?utm_source=chatgpt.com "OnlyOffice Integration https certificate failed - 📄 Office"
[8]: https://help.nextcloud.com/t/make-nextcloud-onlyoffice-app-accept-self-signed-certificates/83020?utm_source=chatgpt.com "Make nextcloud/onlyoffice app accept self signed certificates"
[9]: https://help.nextcloud.com/t/how-to-make-nextcloud-connect-to-an-internally-deployed-onlyoffice/153858?utm_source=chatgpt.com "How to make nextcloud connect to an internally deployed ..."
[10]: https://forum.onlyoffice.com/t/problem-with-onlyoffice-and-nextcloud-connection/12798?utm_source=chatgpt.com "Problem with OnlyOffice and Nextcloud connection"


# Quick checklist

* [ ] DS listens on `127.0.0.1:8080`
* [ ] Single nginx proxies `/onlyoffice/` → DS and `/` → Nextcloud, with WS + `X-Forwarded-*` headers ([Nextcloud community][6])
* [ ] Nextcloud `config.php`: `allow_local_remote_servers` and (optionally) `verify_peer_off` set ([GitHub][1], [api.onlyoffice.com][3])
* [ ] ONLYOFFICE app in NC uses external `/onlyoffice/` URL + internal localhost URL
* [ ] JWT secret matches on both sides (enabled by default in DS 7.2+) ([OnlyOffice][4])

If you want, tell me how you installed Nextcloud (package vs. docker) and I’ll tailor the exact nginx + app settings to your layout.

[1]: https://github.com/ONLYOFFICE/onlyoffice-nextcloud/issues/293?utm_source=chatgpt.com "Nextcloud 19 compatibility · Issue #293 · ONLYOFFICE/ ..."
[2]: https://help.nextcloud.com/t/trying-to-install-a-new-app-gives-me-a-host-violates-local-access-rules-error/155220?utm_source=chatgpt.com "Trying to install a new app gives me a \"Host violates local ..."
[3]: https://api.onlyoffice.com/docs/docs-api/get-started/ready-to-use-connectors/nextcloud-integration/?utm_source=chatgpt.com "Nextcloud integration"
[4]: https://www.onlyoffice.com/blog/2022/09/what-is-jwt?utm_source=chatgpt.com "How JWT protects your documents | ONLYOFFICE Blog"
[5]: https://medium.com/%40jerome.devops/onlyoffice-on-https-with-nextcloud-and-nginx-e339086e2e46?utm_source=chatgpt.com "OnlyOffice on HTTPS with NextCloud and NGINX"
[6]: https://help.nextcloud.com/t/document-server-only-office-behind-nginx-reverse-proxy/214547?utm_source=chatgpt.com "Document server + Only office behind nginx reverse proxy"
[7]: https://github.com/ONLYOFFICE/document-server-proxy?utm_source=chatgpt.com "ONLYOFFICE/document-server-proxy: Common setting for ..."


# Why Snap is a bad way to do this

Lewis' prompt:
> As a final followup, can snap installations of NextCloud and OpenOfice be used as shortcuts to get the apps installed and then use apt (or other suitable package manager suitable for the target platform) to install nginx. This poses challenges because snap assumes each package stands alone and installs all of its dependencies including Apache for Nextcloud and nginx for onlyoffice. the ideal installation would route all traffic from user browser through ssl to nginx and use internal urls (localhost) for both the nextcloud and onlyoffice endpoints. (though it is possible to relax this for nextcloud which really is the only public internet entry for the deployment).

You’ve hit on the core issue with **snap**: it bundles everything (including its own Apache/nginx, configs, and sandboxing). That works fine for a “self-contained” install, but it’s awkward when your goal is a **single shared nginx** handling SSL and routing.

### Why snaps complicate this

* **Nextcloud snap** → pulls in Apache, enforces its own vhost inside the snap. You can’t simply point nginx at it, because snap mounts its filesystem separately and manages services with `snapd`.
* **ONLYOFFICE snap** → pulls its own nginx and expects to be the endpoint. Same isolation problem.

This makes it hard to use your “ideal architecture” (one nginx with TLS, internal localhost HTTP between apps).

### Options

#### 1. Use apt/docker instead of snaps (recommended)

* Install **Nextcloud** from the distro packages, or better, from the official Nextcloud APT repo (or docker if you prefer container isolation).
* Install **ONLYOFFICE Document Server** from the official repo or docker.
* Install **nginx** from apt and configure it as the single entry point.
* This way, nothing else is fighting you with its own embedded webserver.

#### 2. If you stick with snaps

It *is* possible, but messy:

* You’d need to disable or block the bundled Apache/nginx from binding public ports.
* Then use nginx (your apt-installed one) as a reverse proxy into the snap’s internal socket/port.
  Example: snap Nextcloud listens on 127.0.0.1:80 inside its sandbox → you proxy\_pass from your nginx.
* But you’ll be fighting snap’s confinement rules, auto-updates, and its assumption that it controls the webserver.
* For ONLYOFFICE, similar story: it runs its own nginx inside the snap. You’d have to re-map ports and proxy in. And DS requires WebSocket proxying, which makes double-proxies fragile.

#### 3. Hybrid compromise

* Run **Nextcloud snap** (because it’s well maintained) and expose it only on localhost.
* Run **ONLYOFFICE in docker/apt** (more configurable).
* Put **one apt-nginx** in front of both.
* This reduces, but doesn’t eliminate, snap’s oddities.

### Best practice for your design

If your goal is **clean, one nginx TLS endpoint, localhost backends, internal HTTP between NC and OO**:

* Avoid snap. It’s explicitly designed for self-contained deployments, not shared reverse-proxy setups.
* Use apt or docker packages for both Nextcloud and ONLYOFFICE. They’re well supported and easier to integrate with nginx.
* Reserve snap for when you truly want the “appliance” model.

---

✅ **Answer to your scenario**:
Yes, you can technically install NC and OO as snaps and add nginx from apt on top. But you’ll be fighting snap confinement and bundled webservers the whole way. For the clean architecture you described (single nginx, SSL termination, localhost URLs internally), **skip the snaps and install from apt or docker**. That way, both apps are “headless” and nginx is the one and only frontend.

---

Do you want me to sketch out an **apt-based install recipe** (Nextcloud repo + OnlyOffice repo + nginx config) so you have a concrete alternative to snaps?

Lewis' follow-up response
> Yes. we tried snaps and it was a mess. So, lets look at your proposal. No religion around snap; really don't like docker or docker compose

Perfect — that’s the pragmatic choice 👍.
If you want **one nginx** doing SSL and routing, the cleanest path is:

* **Nextcloud** from its official APT repo
* **ONLYOFFICE Document Server** from its official APT repo
* **nginx** from your distro’s package manager

No snaps, no docker — just systemd-managed services you can point at 127.0.0.1.

---

## 1. Install Nextcloud (APT repo)

On Ubuntu/Debian-like distros:

```bash
sudo apt update
sudo apt install software-properties-common
sudo add-apt-repository ppa:nextcloud-devs/client
# (for the server, use the official .deb repo instead of PPA if available)
sudo apt install nextcloud-server php-fpm mariadb-server
```

* Set up the database (MariaDB/MySQL or PostgreSQL).
* Configure PHP-FPM pool for Nextcloud.
* Do **not** install Apache — stick with php-fpm + nginx.

---

## 2. Install ONLYOFFICE Document Server (APT)

Add the official repo:

```bash
sudo apt update
sudo apt install gnupg2
echo "deb https://download.onlyoffice.com/repo/debian squeeze main" \
  | sudo tee /etc/apt/sources.list.d/onlyoffice.list
wget -qO - https://download.onlyoffice.com/repo/onlyoffice.key \
  | sudo apt-key add -

sudo apt update
sudo apt install onlyoffice-documentserver
```

* This will pull in its own nginx by default. **Disable it** so it doesn’t listen on :80/:443:

```bash
sudo systemctl stop nginx
sudo systemctl disable nginx
```

ONLYOFFICE DS also installs NodeJS services; those run fine under systemd. The bundled nginx is optional once you front it with your own.

Now adjust `/etc/onlyoffice/documentserver/local.json` so DS binds only to localhost:

```json
"services": {
  "CoAuthoring": {
    "server": {
      "port": 8080,
      "bind_address": "127.0.0.1"
    }
  }
}
```

Restart DS:

```bash
sudo systemctl restart onlyoffice-documentserver
```

---

## 3. nginx as the single entrypoint

Install nginx normally:

```bash
sudo apt install nginx
```

Then configure:

```nginx
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 443 ssl http2;
    server_name cloud.example.com;

    ssl_certificate /etc/letsencrypt/live/cloud.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/cloud.example.com/privkey.pem;

    client_max_body_size 512m;

    # --- Nextcloud ---
    root /var/www/nextcloud;

    location / {
        index index.php;
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php/php7.4-fpm.sock;  # adjust version
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
    }

    # --- ONLYOFFICE under /onlyoffice/ ---
    location ^~ /onlyoffice/ {
        proxy_pass         http://127.0.0.1:8080/;
        proxy_http_version 1.1;

        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
```

---

## 4. Nextcloud configuration

In `config/config.php`:

```php
'allow_local_remote_servers' => true,
'onlyoffice' => [
  'verify_peer_off' => true
]
```

Then in the **ONLYOFFICE app settings in Nextcloud**:

* **Document Server address (public)**: `https://cloud.example.com/onlyoffice/`
* **Internal DS address**: `http://127.0.0.1:8080/`
* **Internal NC address (for callbacks)**: `http://127.0.0.1/` (adjust if you run NC on a nonstandard socket/port)
* Set a **JWT secret** in both NC app settings and `/etc/onlyoffice/documentserver/local.json`.

---

## 5. Systemd + maintenance

* Nextcloud: `systemctl status php7.4-fpm` + `systemctl status mysql`
* ONLYOFFICE: `systemctl status onlyoffice-documentserver`
* nginx: `systemctl status nginx`

Everything is managed as native services.

---

✅ With this, you have:

* one nginx serving TLS
* Nextcloud on php-fpm behind nginx
* ONLYOFFICE Document Server on 127.0.0.1:8080 behind nginx
* internal HTTP between NC and OO (safe, since localhost)

---

Do you want me to sketch the **exact APT repo lines** for Nextcloud server (not just client PPA) and the tested MariaDB setup commands, so you have a copy-paste sequence for a new VPS build?


# why bother using apt? why not just use the recommended repo or download from each vendor?


Lewis' prompt
> no. why bother using apt? why not just use the recommended repo or download from each vendor?

Totally fair. For this stack, I’d actually **avoid distro APT packages for Nextcloud itself** and use **vendor sources** for both—while still using your distro for nginx/PHP/DB. Here’s a clean, no-Docker plan.

# What to install from whom (and why)

* **Nextcloud app code:** **download the official tarball** (or use the web installer). That’s the method Nextcloud recommends and documents; it keeps you in control of PHP, nginx, and DB versions without snap/Apache baggage. ([Nextcloud][1], [Nextcloud][2])
* **ONLYOFFICE Document Server:** use **ONLYOFFICE’s own Debian/Ubuntu repo** (or their .deb script) so you get upstream updates and all DS dependencies. You’ll still run it **only on localhost** behind your nginx. ([Ubuntu][3], [ONLYOFFICE - Cloud Office Applications][4])

Below is the short, copy-pasteable recipe.

---

## 1) Nextcloud (vendor tarball)

```bash
# prerequisites (Ubuntu/Debian examples)
sudo apt update
sudo apt install nginx php-fpm php-mysql php-xml php-gd php-curl php-zip php-mbstring \
                 php-intl php-bcmath php-gmp mariadb-server unzip

# download Nextcloud
cd /var/www
sudo curl -LO https://download.nextcloud.com/server/releases/latest.tar.bz2
sudo tar -xjf latest.tar.bz2
sudo chown -R www-data:www-data /var/www/nextcloud
```

Minimal nginx server block (TLS omitted for brevity—use your certs/Let’s Encrypt):

```nginx
server {
  listen 443 ssl http2;
  server_name cloud.example.com;

  root /var/www/nextcloud;

  client_max_body_size 512m;

  location / {
      try_files $uri $uri/ /index.php?$args;
  }

  location ~ \.php$ {
      include fastcgi_params;
      fastcgi_pass unix:/run/php/php-fpm.sock;    # adjust to your PHP sock
      fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
      fastcgi_param PATH_INFO $fastcgi_path_info;
  }
}
```

Add to `config.php` so NC can talk to services on 127.0.0.1:

```php
'allow_local_remote_servers' => true,
```

(This is the standard fix when integrating internal services like ONLYOFFICE over localhost.) ([Nextcloud][5], [Nextcloud community][6])

---

## 2) ONLYOFFICE Document Server (vendor repo) on localhost

Add the upstream repo and install:

```bash
echo "deb https://download.onlyoffice.com/repo/debian squeeze main" \
 | sudo tee /etc/apt/sources.list.d/onlyoffice.list
wget -qO - https://download.onlyoffice.com/repo/onlyoffice.key | sudo apt-key add -
sudo apt update
sudo apt install onlyoffice-documentserver
```

Now make DS listen **only on 127.0.0.1** and not on public ports. Easiest is to change the **bundled nginx** site:

Edit `/etc/onlyoffice/documentserver/nginx/ds.conf` and set a non-conflicting localhost port, e.g. 8080:

```
listen 127.0.0.1:8080;
```

Then reload DS’s nginx:

```bash
sudo systemctl restart nginx    # the nginx that ships with DS
```

(Changing port/listen is officially supported via `ds.conf`; just remember updates can overwrite it—reapply if needed.) ([ONLYOFFICE Community][7])

You can now leave the DS’s own nginx running on **127.0.0.1:8080**, while your main nginx is the **only** public TLS entry.

---

## 3) Front everything with your single nginx
Note: this appears to be inconsistent with the guidelines in Project Documents/nginx_config_for_one_domain_no_docker.md which should be more trusted....

Add a **proxy location** into the same `cloud.example.com` server block:

```nginx
# ONLYOFFICE behind /onlyoffice/
location ^~ /onlyoffice/ {
    proxy_pass         http://127.0.0.1:8080/;
    proxy_http_version 1.1;

    # WebSocket support
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;

    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
}
```

---

## 4) Wire up the connector in Nextcloud

In **Nextcloud → Apps → ONLYOFFICE**:

* **Document Server address (public):** `https://cloud.example.com/onlyoffice/`
* **ONLYOFFICE Docs address for internal requests from the server:** `http://127.0.0.1:8080/`
* **Server address for internal requests from ONLYOFFICE Docs:** `http://127.0.0.1/`

These “Advanced server settings” fields are *specifically* for split public vs internal URLs and can be plain HTTP for localhost. ([ONLYOFFICE - Cloud Office Applications][8], [api.onlyoffice.com][9])

If you want to skip TLS verification (not needed for pure HTTP on 127.0.0.1), there’s also the **disable cert verification** toggle (or `verify_peer_off` in `config.php`). ([api.onlyoffice.com][9])

---

## 5) JWT secret (recommended)

Set a **secret** in the NC ONLYOFFICE app and mirror it in Document Server config (`/etc/onlyoffice/documentserver/local.json`). This is standard and avoids open access from random hosts. (If you hit issues, they’re typically just mismatched secrets; community notes confirm the flow.) ([Nextcloud community][10])

---

## Why this layout

* **Vendor Nextcloud tarball** keeps you on the supported update path (via the web updater/occ) without snap/distro opinions. ([Nextcloud][1])
* **Vendor ONLYOFFICE repo** pulls the exact DS stack they test, and you simply bind its nginx to **127.0.0.1:8080** and reverse-proxy it. ([Ubuntu][3], [ONLYOFFICE Community][7])
* **Single public nginx** = one place for TLS, headers, limits, and logs.

If you want, I can drop in a hardened nginx TLS block (HSTS, OCSP stapling, sane ciphers) and a small checklist for PHP-FPM tuning and Nextcloud’s opcache/APCu settings.

[1]: https://docs.nextcloud.com/server/latest/admin_manual/installation/source_installation.html?utm_source=chatgpt.com "Installation on Linux"
[2]: https://nextcloud.com/install/?utm_source=chatgpt.com "Download and install Nextcloud"
[3]: https://ubuntu.com/tutorials/how-to-install-onlyoffice-server-on-ubuntu?utm_source=chatgpt.com "How to install ONLYOFFICE for integration on Ubuntu"
[4]: https://helpcenter.onlyoffice.com/workspace/installation/workspace-install-linux.aspx?utm_source=chatgpt.com "Installing ONLYOFFICE Workspace Community from RPM/ ..."
[5]: https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/config_sample_php_parameters.html?utm_source=chatgpt.com "Configuration Parameters"
[6]: https://help.nextcloud.com/t/what-does-allow-local-remote-servers-do/188618?utm_source=chatgpt.com "What does `allow_local_remote_servers` do? - ℹ️ Support"
[7]: https://community.onlyoffice.com/t/change-listen-port/8330?utm_source=chatgpt.com "Change listen port - Docs"
[8]: https://helpcenter.onlyoffice.com/integration/nextcloud.aspx?utm_source=chatgpt.com "Integration Guides - Nextcloud - ONLYOFFICE"
[9]: https://api.onlyoffice.com/docs/docs-api/get-started/ready-to-use-connectors/nextcloud-integration/?utm_source=chatgpt.com "Nextcloud integration - api | onlyoffice"
[10]: https://help.nextcloud.com/t/onlyoffice-secret-key-issue/56464?utm_source=chatgpt.com "Onlyoffice Secret Key Issue - Office - Nextcloud community"

# and what about telling php to allow local connections without ssl or tsl?

Lewis' prompt:
```
don't we also need this code for the onlyoffice config?
'allow_local_remote_servers' => true,
'onlyoffice' => [
  'verify_peer_off' => true
]
```

You’ve got it mostly right — but let’s separate the two pieces:

### 1. `allow_local_remote_servers`

Yes, you **do need this** in `config.php` if you are pointing Nextcloud to a **localhost / private IP address** (like `http://127.0.0.1:8080`).
Without it you’ll see errors like *“Host violates local access rules”*.

```php
'allow_local_remote_servers' => true,
```

This setting is global — it isn’t inside the `'onlyoffice'` block. It just tells Nextcloud “yes, I know I’m connecting to a local address, allow it.”

---

### 2. `verify_peer_off`

This one depends on how you connect:

* If your **internal Document Server URL** is plain `http://127.0.0.1:8080` → there is no TLS involved, so nothing to verify. In that case, `verify_peer_off` doesn’t matter.
* If you use **HTTPS** with a self-signed or otherwise untrusted cert → then you need this, to disable certificate validation:

```php
'onlyoffice' => [
  'verify_peer_off' => true
],
```

It’s equivalent to ticking *“Disable certificate verification (insecure)”* in the ONLYOFFICE app’s settings screen.

---

✅ **So in your all-localhost/HTTP design**:
You **must** have `'allow_local_remote_servers' => true,`
You **don’t need** `'verify_peer_off'` unless you later switch your internal URLs to HTTPS with self-signed certs.

---

Would you like me to sketch out a **final clean `config.php` snippet** that shows all the typical Nextcloud options (trusted domains, datadirectory, db, memcache, plus these OnlyOffice bits) so you can drop it in and just edit paths/secrets?

Lewis' prompt:
> I should have asked don't we still need this as part of our nextcloud config?
```
'allow_local_remote_servers' => true,
'onlyoffice' => [
  'verify_peer_off' => true
]
```


Good catch 👍 — here’s the nuance:

### ✅ `allow_local_remote_servers`

Yes, you **do need this** in your `config/config.php` when Nextcloud is configured to talk to **127.0.0.1** (or other private/local IPs). Without it, Nextcloud will refuse with the *“Host violates local access rules”* error.

```php
'allow_local_remote_servers' => true,
```

---

### ⚖️ `onlyoffice => [ 'verify_peer_off' => true ]`

This one is **only required if your internal Document Server URL uses HTTPS with a self-signed (or otherwise untrusted) certificate**.

* In your design, you’re using **plain HTTP over 127.0.0.1** → no TLS verification is performed, so this option isn’t needed.
* If you later decide to wrap the DS in HTTPS with a self-signed cert, then you’d add it:

```php
'onlyoffice' => [
  'verify_peer_off' => true,
],
```

This is functionally the same as checking *“Disable certificate verification (insecure)”* in the OnlyOffice app settings.

---

### 🔑 So for your current localhost/HTTP setup, the minimal Nextcloud additions are:

```php
'allow_local_remote_servers' => true,
```

(and no `verify_peer_off` block is necessary).

---

Do you want me to put together a **sample `config.php` template** that includes these lines plus the other common Nextcloud settings (trusted domains, DB, Redis/APCu, etc.) so you can see it in context?
