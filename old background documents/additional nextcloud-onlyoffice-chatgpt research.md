

**ChatGPT**:

Awesome — here’s a tight, copy-pasteable setup for **ONLYOFFICE Docs behind your own Nginx** on Ubuntu 24.04 ARM64, with **JWT** enabled. No Docker.

# 1) Enable JWT in ONLYOFFICE

Edit `/etc/onlyoffice/documentserver/local.json`:

json`{
  "services": {
    "CoAuthoring": {
      "token": {
        "enable": true,
        "useforrequest": true,
        "inbox":  { "string": "CHANGE_ME_SUPER_SECRET" },
        "outbox": { "string": "CHANGE_ME_SUPER_SECRET" }
      }
    }
  }
}
`</pre>

Then restart:

bash`sudo systemctl restart onlyoffice-documentserver
`</pre>

Sanity check:

bash`curl -f http://127.0.0.1/healthcheck && echo "OK"
`</pre>

# 2) Nginx reverse proxy vhost (HTTPS-ready)

Assuming you want `docs.example.com` to front ONLYOFFICE. The ONLYOFFICE package runs its own internal stack on `127.0.0.1:8080` (proxied by its bundled Nginx to :80). We’ll **bypass the bundled Nginx** and proxy straight to :8080 for clarity.

Create `/etc/nginx/sites-available/onlyoffice-docs.conf`:

nginx`map $http_upgrade $connection_upgrade {
  default upgrade;
  ''      close;
}

server {
  listen 80;
  listen [::]:80;
  server_name docs.example.com;

  # (Optional) ACME HTTP-01 challenge if you use certbot/lego externally
  location /.well-known/acme-challenge/ { root /var/www/html; }

  # Increase upload limits for big docs (adjust as needed)
  client_max_body_size 100M;

  # Proxy everything to ONLYOFFICE’s app server
  location / {
    proxy_pass         http://127.0.0.1:8080;
    proxy_http_version 1.1;

    # Required for websockets/co-editing
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;

    # Preserve host + scheme for callback URLs
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # Timeouts generous for long editing sessions
    proxy_connect_timeout   60s;
    proxy_send_timeout      120s;
    proxy_read_timeout      120s;
    send_timeout            120s;
  }
}
`</pre>

Enable & reload:

bash`sudo ln -s /etc/nginx/sites-available/onlyoffice-docs.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
`</pre>
**

If the package’s own Nginx is already binding to :80, stop/disable its server block (or the whole service) to avoid port conflicts, e.g. `sudo systemctl stop nginx && sudo systemctl start nginx` after replacing configs. If you prefer to keep the package’s Nginx, change `proxy_pass` above to `http://127.0.0.1:80;` (double-proxy is fine, just a tad noisier).

For TLS (Let’s Encrypt), run certbot in your usual way and add the `server { listen 443 ssl; … }` block with `ssl_certificate`/`ssl_certificate_key` lines. Everything else stays the same.

# 3) Nextcloud ↔ ONLYOFFICE settings (if applicable)

In Nextcloud → **Settings → ONLYOFFICE**:

- **Document Editing Service address**: `https://docs.example.com/`

- **Secret key (JWT)**: `CHANGE_ME_SUPER_SECRET`

- (Optional) **Advanced server settings** → **Internal address** if Nextcloud reaches Document Server over private network; otherwise leave blank.

Save, then open a test `.docx` in Nextcloud to confirm the editor loads.

## Quick troubleshoot checklist

- `curl -I http://127.0.0.1:8080/` returns 200? (ONLYOFFICE app server alive)

- `curl -I https://docs.example.com/` returns 200 and the welcome page loads?

- Websocket OK? While editing, `nginx -T` shows the `map $http_upgrade` and upgrade headers present.

- JWT mismatch? You’ll see “Invalid token” in the browser/Network panel—ensure Nextcloud secret exactly matches `local.json`.

If you want, tell me your exact domain and whether Nextcloud is on the same host or another VPS, and I’ll tailor the proxy/JWT bits (including internal-only allowlists and a sample CSP).

---

**You**:

Nextcloud and onlyoffice are on the same vps

---

**ChatGPT**:

Perfect—since both **Nextcloud** and **ONLYOFFICE Docs** live on the _same VPS_, the cleanest setup is a **single-domain / path-based** reverse proxy. That keeps everything same-origin (no CORS pain) and is easy to secure with JWT.

### Overview

- Public URL your users visit: `https://cloud.example.com/`

- ONLYOFFICE served under a path: `https://cloud.example.com/onlyoffice/`

- Internally, proxy `/onlyoffice/` to the Document Server service on `127.0.0.1:8080`

- Lock things with a shared **JWT secret**

## 1) Enable JWT in ONLYOFFICE (if not done)

`/etc/onlyoffice/documentserver/local.json`:

json`{
  "services": {
    "CoAuthoring": {
      "token": {
        "enable": true,
        "useforrequest": true,
        "inbox":  { "string": "CHANGE_ME_SUPER_SECRET" },
        "outbox": { "string": "CHANGE_ME_SUPER_SECRET" }
      }
    }
  }
}
`</pre>

bash`sudo systemctl restart onlyoffice-documentserver
`</pre>

## 2) Nextcloud Nginx vhost — add a path proxy for ONLYOFFICE

In your **Nextcloud** server block (the one that listens on 80/443 for `cloud.example.com`), add:

nginx`# ---- ONLYOFFICE path-based reverse proxy ----
# Serve ONLYOFFICE under https://cloud.example.com/onlyoffice/
map $http_upgrade $onlyoffice_connection_upgrade { default upgrade; '' close; }

location ^~ /onlyoffice/ {
    # Optional: bump upload size for big docs
    client_max_body_size 100M;

    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $onlyoffice_connection_upgrade;

    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # Forward to Document Server app (most installs expose 127.0.0.1:8080)
    proxy_pass http://127.0.0.1:8080/;

    # Long-polling / websockets timeouts for co-editing
    proxy_connect_timeout   60s;
    proxy_send_timeout      120s;
    proxy_read_timeout      120s;
    send_timeout            120s;
}
`</pre>

Then reload:

bash`sudo nginx -t && sudo systemctl reload nginx
`</pre>
**

If your Document Server listens on a different port, adjust `proxy_pass`.**
If ONLYOFFICE shipped its own nginx snippets that also bind to :80,:443, just make sure you’re not double-binding. The path-proxy above works with the standard ONLYOFFICE service listening internally.

## 3) Nextcloud app settings (Admin → ONLYOFFICE)

- **Document Editing Service address**:**
`https://cloud.example.com/onlyoffice/`

- **Secret key (JWT)**:**
`CHANGE_ME_SUPER_SECRET`  (must match `local.json`)

- **Advanced server settings**: leave the “internal addresses” empty since you’re same host & same origin. (You can add them later if you split hosts.)

Save → open a test `.docx` from Files and it should load in the editor.

## 4) (Optional) Lock down access a bit more

- **Firewall**: ensure ONLYOFFICE’s internal service binds to `127.0.0.1` (default) so it’s not reachable externally except through Nginx.

- **CSP**: same-origin path setup usually needs no extra CSP tweaks. If you’ve hardened CSP, allow the `/onlyoffice/` path for scripts/websockets.

- **Rate limits** (optional): don’t rate-limit `/onlyoffice/` paths; co-editing uses many long requests.

## 5) Quick health checks

bash`# Document Server alive?
curl -f http://127.0.0.1:8080/healthcheck && echo OK

# Nginx path proxy reachable?
curl -I https://cloud.example.com/onlyoffice/
`</pre>

If the editor fails to open:

- “Invalid token” → JWT mismatch between Nextcloud app and `local.json`.

- Spinning loader / 502 → check Nginx error log and `systemctl status onlyoffice-documentserver`.

- Websockets errors → confirm the `Upgrade/Connection` headers & `map` block are present.

If you share your exact domain name and any custom Nginx hardening you’re using (HSTS, CSP, proxy buffers), I can fold those into the snippet so it drops in cleanly.
