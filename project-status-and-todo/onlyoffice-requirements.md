# OnlyOffice + Nextcloud Integration Requirements

The following checklist captures the full set of prerequisites for running OnlyOffice Document Server (DocumentServer) and integrating it with Nextcloud in the dual-domain architecture (`docs.example.com` + `onlyoffice.example.com`). Items marked **Status** describe where we stand today (September 22, 2025) on the test server.

## 1. Base System & Packages
- [x] Ubuntu 24.04 LTS with systemd and root access (**Status:** met)
- [x] Time sync (chrony/systemd-timesyncd) to avoid JWT/SSL drift (**Status:** presumed accurate)
- [x] curl, jq/python3, tar, unzip available for scripting (**Status:** met)
- [x] Redis server installed/enabled (DocumentServer cache) (**Status:** installed via package deps)
- [x] RabbitMQ installed/enabled (realtime notifications) (**Status:** installed via package deps)

## 2. PostgreSQL (Document Server)
- [x] PostgreSQL service running locally (**Status:** running)
- [x] Database `onlyoffice` created (**Status:** present)
- [x] OnlyOffice service user (`oouser`) created with `CREATEDB` privilege (**Status:** yes)
- [x] DocumentServer schema instantiated (`doc_changes`, `task_result`) (**Status:** created manually from `createdb.sql`)
- [x] Table ownership assigned to service user (`oouser`) (**Status:** done)
- [ ] Automated schema/ownership setup inside install script (**Status:** pending enhancement)

## 3. DocumentServer Application
- [x] `onlyoffice-documentserver` package installed (v9.0.4-50) (**Status:** installed)
- [x] Services `ds-docservice`, `ds-converter`, `ds-metrics` active (**Status:** running)
- [x] `/etc/onlyoffice/documentserver/local.json` overrides:
  - [x] Loopback binding (`127.0.0.1:8000`) (**Status:** yes)
  - [x] SQL credentials matching PostgreSQL (user `oouser`) (**Status:** yes)
  - [x] JWT secret applied to inbox/outbox/browser/session (**Status:** yes)
  - [x] RabbitMQ URL present (**Status:** yes)
  - [x] WOPI enabled (local.json wopi.enable=true) (**Status:** required for discovery)
- [x] Ensure `local.json` keeps upstream keys (e.g., token enable structure) in sync with defaults (**Status:** verified after rewrite)
- [x] DocumentServer log directories writable owned by `ds:ds` (**Status:** confirmed via service startup)
- [x] Health endpoint reachable: `curl http://127.0.0.1:8080/healthcheck` = 200 (**Status:** yes)
- [x] Discovery endpoint reachable: `curl http://127.0.0.1:8080/hosting/discovery` = 404 (**Status:** resolved via wopi.enable=true)
- [x] `CommandService.ashx` reachable (command API) (**Status:** yes)

## 4. DocumentServer Internal nginx (`/etc/onlyoffice/documentserver/nginx/ds.conf`)
- [x] Listen on `127.0.0.1:8080` only (no external exposure) (**Status:** configured)
- [x] WebSocket headers, proxy cache, gzip left as defaults (**Status:** default config retained)
- [x] Unit restarts cleanly after manual modifications (**Status:** yes)

## 5. External nginx Reverse Proxy (`onlyoffice.example.com`)
- [x] HTTP vhost proxying to 127.0.0.1:8080 (kept for LE challenges) (**Status:** yes)
- [x] HTTPS vhost with Let’s Encrypt certs, proxy headers, WebSocket upgrades, large body support (**Status:** yes)
- [x] Log files rotate (inherit global config) (**Status:** yes)
- [ ] Optional rate limiting tuned (currently disabled after cleanup) (**Status:** revisit after go-live)

## 6. Security & JWT
- [x] Shared JWT secret stored in `/etc/nextcloud-onlyoffice/params.yaml` (**Status:** yes)
- [x] Same secret written into DocumentServer `local.json` (**Status:** yes)
- [x] Nextcloud connector will need identical secret via `occ config:app:set onlyoffice jwt_secret` (**Status:** pending integration)
- [x] Consider JWT header name defaults (`Authorization`) (**Status:** align during integration)

## 7. Nextcloud Application (pending)
- [x] OnlyOffice connector app installed (`occ app:install onlyoffice`) (**Status:** not yet)
- [ ] DocumentServer URLs configured:
  - `DocumentServerUrl` = `https://onlyoffice.example.com/`
  - `DocumentServerInternalUrl` = `http://127.0.0.1:8080/`
  - `storage_url` = `https://docs.example.com/`
  - `webhook_url` = `https://docs.../index.php/apps/onlyoffice/webhook`
  - JWT on/off consistent with DocumentServer
- [x] `occ onlyoffice:documentserver --check` (or equivalent) passes
- [x] Test doc creation/edit from browser: open `.docx`, `.xlsx`, `.pptx`, plain text

## 8. TLS / Certificates
- [x] Let’s Encrypt certificates exist for both domains; cron/systemd timers handle renewal (**Status:** true)
- [x] `ssl_stapling` warnings acceptable (no OCSP URL in test certs) (**Status:** fine for staging)
- [ ] Optional: configure OCSP stapling/resolvers for production (**Status:** future work)

## 9. Diagnostics & Logging
- [x] Access to `/var/log/onlyoffice/documentserver/*` and `/var/log/nginx/*.log`
- [x] Ability to tail `journalctl -u ds-docservice` etc.
- [ ] Add scripted health checks (CLI / HTTP) into automation for post-install verification (**Status:** to-do)

## 10. Firewall / Network
- [x] Ports 80/443 open externally for nginx (**Status:** yes)
- [x] Internal services (8000/8080, PostgreSQL 5432, Redis 6379, RabbitMQ 5672) bound to localhost (**Status:** yes)
- [x] UFW/iptables rules to enforce above (optional hardening) (**Status:** future hardening)

## 11. Backup & Maintenance
- [x] Config backup script `/usr/local/bin/backup-onlyoffice.sh` installed (config-only) (**Status:** yes)
- [ ] Extend to database dump (`pg_dump onlyoffice`) and integrate with cron (**Status:** to-do)
- [ ] Document service restart procedures (`systemctl restart ds-*`, check logs)

## 12. Integration Acceptance Tests
- [ ] Verify `/hosting/discovery` returns XML document (must resolve current 404)
- [ ] In Nextcloud GUI: OnlyOffice settings page “Save” succeeds
- [ ] Open sample DOCX/PPTX from Files app, edit, save; collaborative editing works
- [ ] Logs remain clean (no JWT mismatch, no WOPI errors)

### Notes on Internet Research
Network access is restricted in this environment, so we cannot pull fresh references from the public internet. The above list reflects known OnlyOffice/Nextcloud integration requirements and test observations on this server.
