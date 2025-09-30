#!/bin/bash

# Must-Do Prerequisites for Nextcloud + OnlyOffice automation
# This script DOES NOT make changes. It prints the manual setup you must do
# BEFORE running ./01_system_prep.sh → ./07_integration_config.sh.

set -u

BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

hr() { printf "${CYAN}%s${NC}\n" "============================================================"; }
section() { hr; printf "${BOLD}%s${NC}\n" "$1"; hr; }

main() {
  echo
  section "Must-Do Prerequisites (read me before running 01–07)"
  cat <<'TXT'
This project automates a single-domain Nextcloud + OnlyOffice deployment.
Before you run the scripts, complete these prerequisites. This script only
prints instructions; it does not modify the system.
TXT

  echo
  section "1) Provision a suitable Ubuntu VPS"
  cat <<'TXT'
Required (minimum):
- Ubuntu 22.04+ (24.04 recommended)
- Architecture: aarch64/arm64 or x86_64
- CPU: 4 vCPUs or more
- Memory: 8 GB RAM or more
- Disk: 100 GB or more
- Public IP address reachable over the Internet
TXT

  echo
  section "2) Create DNS records at Cloudflare for your base domain"
  cat <<'TXT'
In your Cloudflare zone for <base-domain>, create:
- A/AAAA:    <base-domain>         → your VPS IP   (Proxied: ON is fine)
- A/AAAA:    www.<base-domain>     → your VPS IP   (Proxied: ON)
- A/AAAA:    docs.<base-domain>    → your VPS IP   (Proxied: ON)

Notes:
- This project uses Let’s Encrypt DNS-01, so Cloudflare proxy (orange cloud) is OK.
- TTL: Auto is fine.
TXT

  echo
  section "3) Create a Cloudflare API token and place it on the server"
  cat <<'TXT'
You need a token that allows DNS-01 challenges for Let’s Encrypt.

Recommended token scopes (least privilege):
- Zone → DNS → Read
- Zone → DNS → Edit
(Restrict the token to the specific zone for <base-domain>.)

On the server, create /etc/letsencrypt/cloudflare.ini with 0600 perms.
Example commands (run as root):

  install -d -m 0700 /etc/letsencrypt
  bash -lc 'umask 077; cat > /etc/letsencrypt/cloudflare.ini <<EOF
# Cloudflare DNS API token for certbot DNS-01
# Docs: https://certbot-dns-cloudflare.readthedocs.io/
dns_cloudflare_api_token = YOUR_CLOUDFLARE_API_TOKEN
EOF'
  chmod 600 /etc/letsencrypt/cloudflare.ini

Keep this file secret. Do NOT commit it to git.
TXT

  echo
  section "4) Install or stage the scripts on the target server"
  cat <<'TXT'
Two common options (choose one):
- Clone the repo to the server (recommended during development):
    sudo apt-get update && sudo apt-get install -y git
    sudo git clone https://github.com/YOUR_ORG/YOUR_REPO.git /srv/collab
    cd /srv/collab/src

- Or upload a release tarball to /srv/collab and extract it there
  (keep file ownership/permissions appropriate for root).

TXT

  echo
  section "5) Prepare the three required input parameters"
  cat <<'TXT'
Have these ready for 01_system_prep.sh:
- Base domain name (example: example.com)
- Admin email for Nextcloud notifications (example: admin@example.com)
- Email for Let’s Encrypt registration/renewal (example: ops@example.com)

You will pass them via flags to 01_system_prep.sh.
TXT

  echo
  section "6) After completing the above, run the scripts"
  cat <<'TXT'
From /srv/collab/src on the server, run:

  sudo ./01_system_prep.sh -d <base-domain> -a <admin-email> -m <letsencrypt-email>
  sudo ./02_database_setup.sh
  sudo ./03_nextcloud_install.sh
  sudo ./04_onlyoffice_install.sh
  sudo ./05_nginx_config.sh
  sudo ./06_ssl_setup.sh
  sudo ./07_integration_config.sh

Tip: If your domain is proxied by Cloudflare (orange cloud), that’s OK.
DNS-01 works through the API token in /etc/letsencrypt/cloudflare.ini.
TXT

  echo
  section "Where to read more"
  cat <<'TXT'
- project-status-and-todo/PROJECT_PLAN.md  (integrated plan and current status)
- project-status-and-todo/CURRENT_BEST_CONFIGURATIONS.md
- docs/DEPLOYMENT_PLAN.md (legacy; being folded into integrated docs)
- tests/nginx_smoke.sh (optional smoke tests for nginx config)

This script is documentation-on-the-run: it reminds you of the absolute
must-do items so you don’t start 01–07 without the essentials.
TXT

  echo
  printf "${GREEN}OK${NC} Prerequisites summary printed. Proceed when ready.\n"
}

main "$@"
