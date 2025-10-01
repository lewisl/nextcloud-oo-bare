#!/usr/bin/env bash
# Collects OnlyOffice connector + DocumentServer status in a concise report.
# Usage: bash diagnostics/onlyoffice_connector_status.sh [NC_FQDN]

set -euo pipefail

sec(){ echo; echo "== $* =="; }

FQDN="${1:-}"
if [[ -z "${FQDN}" ]]; then
  FQDN=$(sudo -u www-data php /var/www/nextcloud/occ config:system:get overwrite.cli.url 2>/dev/null | sed -E 's#https?://##; s#/.*##' || true)
fi
if [[ -z "${FQDN}" ]]; then
  FQDN=$(awk '/server_name/{print $2}' /etc/nginx/sites-available/*.conf 2>/dev/null | grep -E '^[A-Za-z0-9.-]+$' | head -n1 || true)
fi

sec "Versions"
php -v | head -n1 || true
sudo -u www-data php /var/www/nextcloud/occ -V || true

sec "OnlyOffice app state"
sudo -u www-data php /var/www/nextcloud/occ app:list --output=json 2>/dev/null | jq -r '[(.enabled|keys[]?), (.disabled|keys[]?)] | flatten | unique | .[]' | grep -i '^onlyoffice$' || echo 'onlyoffice not listed'

sec "OnlyOffice connector config (safe)"
sudo -u www-data php /var/www/nextcloud/occ config:list onlyoffice 2>/dev/null | sed -n '1,200p'

sec "DocumentServer local.json (JWT summary)"
python3 - <<'PY'
import json
p='/etc/onlyoffice/documentserver/local.json'
try:
  d=json.load(open(p))
  sec=d['services']['CoAuthoring']['secret']
  print('browser len:', len((sec.get('browser',{}).get('string') or '')))
  print('inbox   len:', len((sec.get('inbox',{}).get('string') or '')))
  print('outbox  len:', len((sec.get('outbox',{}).get('string') or '')))
  print('hdr in  :', d['services']['CoAuthoring']['token']['inbox'].get('header'))
  print('hdr out :', d['services']['CoAuthoring']['token']['outbox'].get('header'))
except Exception as e:
  print('ERR reading local.json:', e)
PY

sec "Connector self-check"
sudo -u www-data php /var/www/nextcloud/occ onlyoffice:documentserver --check || true

if [[ -n "${FQDN}" ]]; then
  sec "Health endpoints"
  curl -sS -k -m 15 -D - "https://${FQDN}/onlyoffice/healthcheck" -o /dev/null | sed -n '1,12p' || true
  curl -sS -m 10 http://127.0.0.1:8080/healthcheck || true; echo
fi

