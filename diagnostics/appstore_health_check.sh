#!/usr/bin/env bash
# Quick health check for Nextcloud App Store availability and the ONLYOFFICE app endpoint.
# Safe to run repeatedly; read-only network probes.
#
# Usage: bash diagnostics/appstore_health_check.sh

set -euo pipefail

red()  { printf "\033[31m%s\033[0m\n" "$*"; }
yel()  { printf "\033[33m%s\033[0m\n" "$*"; }
grn()  { printf "\033[32m%s\033[0m\n" "$*"; }
sec()  { echo; yel "== $* =="; }

BASE="https://apps.nextcloud.com/api/v1"
APP="onlyoffice"

sec "DNS and TLS"
getent ahosts apps.nextcloud.com | head -n2 || true
openssl s_client -brief -connect apps.nextcloud.com:443 </dev/null 2>/dev/null | sed -n '1,8p' || true

sec "HEAD ${BASE}/apps/${APP}"
code=$(curl -sS -o /dev/null -w "%{http_code}\n" -I "${BASE}/apps/${APP}" || echo "000")
echo "status: ${code}"
[[ "${code}" == "200" ]] && grn OK || red "NOT OK"

sec "GET first bytes ${BASE}/apps/${APP}"
curl -sS "${BASE}/apps/${APP}" | sed -n '1,5p' || true

sec "Catalog listing (unauth) ${BASE}/apps?page=1"
code=$(curl -sS -o /dev/null -w "%{http_code}\n" -I "${BASE}/apps?page=1" || echo "000")
echo "status: ${code} (401 is expected without token)"

sec "Latency sample"
/usr/bin/time -f 'elapsed=%Es' curl -sS -o /dev/null "${BASE}/apps/${APP}" || true

sec "Summary"
if [[ "${code}" == "500" ]]; then
  red "App Store appears to be returning 5xx"
else
  echo "See status codes above; 200 on app endpoint means available."
fi

