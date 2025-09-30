# Integrated Project Plan — Nextcloud + OnlyOffice Automation

**Last updated:** 2025-09-30
**Maintainer:** Codex Toolkit Project
**Scope:** Test VPS (`docs.test-collab-site.com`) leading to production (`docs.bedfordfallsbbbl.org`)

---

## 1. Current Deployment Snapshot
- ✅ Nextcloud 31.0.9 on Ubuntu 24.04 (arm64) with MariaDB, Redis, PHP-FPM, nginx reverse proxy.
- ✅ OnlyOffice Document Server 9.0.4 listening locally on 8080 and exposed via `/onlyoffice/` subpath.
- ✅ Cloudflare proxy enabled; HTTPS served by Let’s Encrypt with automated renewal (`certbot.timer`).
- ✅ Scripts `01`–`07` succeeded end-to-end in a single pass on a clean host (2025-09-30) with zero manual intervention.
- ✅ `src/99_diagnostics.sh` updated for correct service detection, OCC checks, SSL discovery, and non-interactive operation.
- ✅ Nextcloud admin diagnostics: All checks passed (no warnings).

## 2. Completed Milestones
1. Single-domain architecture finalized; `/onlyoffice/` reverse proxy validated with Cloudflare in front.
2. OnlyOffice JWT + secure link synchronization automated; confirmed collaborative editing.
3. Same-tab editing UX verified in-browser; navigation regression resolved.
4. Certbot automation operational with timestamps logged in `journalctl -u certbot.service`.

5. 2025-09-30: First end-to-end one-pass deployment (scripts 01–07) succeeded with perfect web UI verification; OnlyOffice connector OK; Cloudflare Full (Strict) with Let’s Encrypt DNS-01.

## 3. Active Workstreams & Priority Tasks

### A. Stabilize & Document Current State (In Progress)
- [x] Fix `src/99_diagnostics.sh` (terminal handling, service detection, OCC DB probe, SSL summary inputs, OnlyOffice discovery/JWT checks).
- [ ] Capture authoritative configs/snippets in `configs/` and align `CURRENT_BEST_CONFIGURATIONS.md` as updates occur.
- [x] Record current `occ app:list` (enabled/disabled) and agree on defaults for automated install (see session readiness snapshot 2025-09-28).
- [x] Enable the Nextcloud encryption app (and update scripts/templates) once defaults are finalized.

### B. Address Nextcloud Platform Warnings (Completed)
- [x] Schedule maintenance window via `occ config:system:set maintenance_window_start` and document in scripts/runbooks.
- [x] Plan/run `occ maintenance:repair --include-expensive` after scheduling downtime.
- [x] Amend nginx template to set `X-Robots-Tag "noindex,nofollow"` and `X-Permitted-Cross-Domain-Policies "none"`.
- [x] Update PHP-FPM pool (`clear_env = no`), install `php8.3-gmp`, ensure Imagick SVG support (`libmagickcore-6.q16-6-extra`).
- [x] Define baseline SMTP config guidance (placeholder until production mail host chosen).

### C. Script Validation Cycle (Completed 2025-09-30)
- [x] Rebuild test VPS, clone repo, and execute scripts `01` → `07` with zero manual intervention. (2025-09-30)
- [ ] Capture stdout/stderr logs for each script run; archive under `logs/` or `project-status-and-todo/test-runs/`.
- [x] Run internal validation (`occ` checks, curl healthchecks, updated diagnostics script) and request web UI confirmation. (2025-09-30)
- [ ] Update documentation/checklists to reflect actual fully automated run.

### D. Documentation Packaging (Parallel after C)
- [ ] Split deliverables into “Admin Runbook” (deployment + routine tasks) and “Maintainer Guide” (script internals, troubleshooting).
- [ ] Refresh `docs/DEPLOYMENT.md`, `QUICK_START.md`, `TROUBLESHOOTING.md`, folding in current configs and verification steps.
- [ ] Deprecate superseded planning docs (`DEPLOYMENT_PLAN.md`, `NEXT_STEPS.md`, `onlyoffice-plan.md`) once this integrated plan is approved.

### E. Production Rollout (After Documentation Sign-off)
- [ ] Prepare clean production VPS (Ubuntu 24.04, larger SSD) and verify prerequisites (DNS, Cloudflare settings).
- [ ] Execute scripts with production parameters, monitor Let’s Encrypt issuance, and validate end-user workflows.
- [ ] Coordinate any data migration from legacy Cloudron if applicable; final DNS cutover and smoke tests.

### F. Post-Deployment Lifecycle (Planned)
- [ ] Design maintenance utility (`nc-oo-manager.sh` or similar) providing start/stop/restart/status, health checks, and post-upgrade config refresh hooks.
- [ ] Extend monitoring (e.g., timer curling `/onlyoffice/healthcheck`, OCC sanity checks) for ongoing operations.
- [ ] Establish upgrade playbooks for Nextcloud/OnlyOffice (including config diff + reapply steps).

## 4. Testing & Validation Checklist
- OCC commands: `status`, `onlyoffice:documentserver --check`, `config:app:get` for URLs/JWT.
- HTTP checks: `curl -k https://127.0.0.1/status.php`, `curl -k https://127.0.0.1/onlyoffice/healthcheck`, discovery endpoint sanity.
- Service health: `systemctl status` for nginx, php8.3-fpm, mariadb, redis, `ds-docservice`, `ds-converter`, `ds-metrics` (post-refactor, aggregated in diagnostics script).
- SSL: `certbot certificates`, timer status, nginx reload logs.
- Front-end verification: user login, image previews, OnlyOffice doc create/edit, markdown preview, multi-user collaboration test.

## 5. Deliverables Inventory
- Scripts `src/01`–`07`, `src/99_diagnostics.sh`, test harnesses (`00_test_runner.sh`, `99_uninstall.sh`).
- Config templates under `configs/` + `CURRENT_BEST_CONFIGURATIONS.md`.
- Documentation set: Admin Runbook, Maintainer Guide, Troubleshooting, Quick Start, integrated plan (this file).
- Session summaries & change logs for audit trail.

## 6. Dependencies & Risks
- Cloudflare proxy behaviour during Let’s Encrypt issuance (ensure HTTP challenge served locally).
- Package updates (Nextcloud, OnlyOffice) introducing breaking config changes; mitigated via maintenance script and runbooks.
- Resource limits on arm64 Hetzner VPSs—monitor memory/disk before production cutover.

## 7. Next Review Gate
- Complete Workstreams A+B action items and present updated diagnostics + remediation plan.
- Confirm automated script run on rebuilt test host before scheduling production deployment.

---

**Pending Approval:** Once this integrated plan is reviewed, we will retire redundant planning docs and treat this file as the single source of truth.
