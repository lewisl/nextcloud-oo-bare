# AGENTS.md — Runbook

## Purpose
Operate and maintain a **single-domain** Nextcloud + OnlyOffice deployment on Ubuntu 24.04 with nginx reverse proxy and auto SSL.

## Audience
System administrators with limited Linux/bash experience.

## Always Do
1. After a fix/feature → document it by creating or updating `project-status-and-todo/session-summaries/session-summary-YYYY-MM-DD-HHMM.md` (UTC timestamp).
2. Significant multi-file edits may also get an optional `project-status-and-todo/change-summaries/summary-YYYY-MM-DD-HHMM.md` entry.
3. On config change → update `configs/**` and sync `project-status-and-todo/CURRENT_BEST_CONFIGURATIONS.md`.
4. Keep `project-status-and-todo/` free of ad-hoc summary files—stick to the two directories above.
5. Run internal server tests (curl endpoints, service status, JWT/key checks).  
6. Only declare “fixed” after user verifies web UI.

## Critical Paths
- `configs/nginx/*.conf`
- `configs/nextcloud/config.php`
- `configs/onlyoffice/local.json`
- `project-status-and-todo/**`

## Secrets & Inventory
- Never commit live secrets.  
- Domains/IPs live in `inventory/.env` + `inventory/hosts.yml`.

## Workflow
- Edit with VS Code Remote-SSH.  
- Run Codex **via CLI on the VPS** in a stable SSH terminal.  
- Keep logs under `.codex/sessions` inside repo.

## Service Lifecycle
```bash
sudo systemctl status nginx php8.3-fpm redis-server onlyoffice-documentserver
sudo systemctl restart <service>
sudo nginx -t
```

## Troubleshooting
- 502 errors → `nginx -t && systemctl status nginx && tail -n200 /var/log/nginx/error.log`
- OnlyOffice JWT mismatch → check shared secret in Nextcloud + `configs/onlyoffice/local.json`
- SSL renew → `systemctl status certbot.timer && journalctl -u certbot`

## References
- Technical requirements/architecture → `docs/Product-Requirements-Document.md`
- Deployment plan → `docs/DEPLOYMENT_PLAN.md`
- Current configs → `project-status-and-todo/CURRENT_BEST_CONFIGURATIONS.md`
