#!/usr/bin/env bash
# One-time helper to install and wire the ONLYOFFICE connector app when the Nextcloud App Store is unavailable.
# Compatible with Nextcloud 31 (uses ONLYOFFICE app v9.7.0). Idempotent-ish.
#
# Usage: sudo bash diagnostics/onlyoffice_connector_manual_fix.sh [NC_FQDN]
# If NC_FQDN is omitted, the script will try to auto-detect from Nextcloud config or nginx.

set -euo pipefail

FQDN="${1:-}"
if [[ -z "${FQDN}" ]]; then
  FQDN=$(sudo -u www-data php /var/www/nextcloud/occ config:system:get overwrite.cli.url 2>/dev/null | sed -E 's#https?://##; s#/.*##' || true)
fi
if [[ -z "${FQDN}" ]]; then
  FQDN=$(awk '/server_name/{print $2}' /etc/nginx/sites-available/*.conf 2>/dev/null | grep -E '^[A-Za-z0-9.-]+$' | head -n1 || true)
fi
if [[ -z "${FQDN}" ]]; then
  echo "ERROR: Could not determine Nextcloud FQDN automatically. Pass it explicitly as the first argument." >&2
  exit 1
fi

echo "Using FQDN=${FQDN}"

# Select connector version compatible with NC 31
TAG="v9.7.0"
ASSET_URL="https://github.com/ONLYOFFICE/onlyoffice-nextcloud/releases/download/${TAG}/onlyoffice.tar.gz"
TMPD=$(mktemp -d /tmp/onlyoffice-app.XXXXXX)
trap 'rm -rf "${TMPD}"' EXIT

echo "== Download ONLYOFFICE connector ${TAG} =="
curl -fL --retry 3 --retry-delay 2 -o "${TMPD}/onlyoffice.tar.gz" "${ASSET_URL}"

echo "== Extract =="
tar -xzf "${TMPD}/onlyoffice.tar.gz" -C "${TMPD}"

SRCDIR=""
if [[ -d "${TMPD}/onlyoffice" ]]; then SRCDIR="${TMPD}/onlyoffice"; else SRCDIR=$(find "${TMPD}" -maxdepth 1 -type d -name 'onlyoffice*' | head -n1); fi
if [[ -z "${SRCDIR}" || ! -f "${SRCDIR}/appinfo/info.xml" ]]; then
  echo "ERROR: onlyoffice app dir not found in archive" >&2
  exit 1
fi

echo "== Install into Nextcloud apps dir =="
rm -rf /var/www/nextcloud/apps/onlyoffice
mv "${SRCDIR}" /var/www/nextcloud/apps/onlyoffice
chown -R www-data:www-data /var/www/nextcloud/apps/onlyoffice

echo "== Enable app =="
sudo -u www-data php /var/www/nextcloud/occ app:enable onlyoffice || true

PUB="https://${FQDN}/onlyoffice/"
INT="http://127.0.0.1:8080/"
STO="https://${FQDN}/"

echo "== Apply connector configuration =="
sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice DocumentServerUrl --value="${PUB}"
sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice DocumentServerInternalUrl --value="${INT}"
sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice StorageUrl --value="${STO}"
sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice jwt_enabled --value=true
sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice jwt_header --value=Authorization

# Read JWT secret from DocumentServer and set it into Nextcloud
python3 - <<'PY'
import json,sys,os
p='/etc/onlyoffice/documentserver/local.json'
try:
  d=json.load(open(p))
  s=d['services']['CoAuthoring']['secret']['browser']['string']
  open('/tmp/oo.secret','w').write(s)
  os.chmod('/tmp/oo.secret',0o600)
  print('secret_bytes', len(s))
except Exception as e:
  print('ERROR reading '+p+': '+str(e))
  sys.exit(1)
PY
sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice jwt_secret --value="$(cat /tmp/oo.secret)"
rm -f /tmp/oo.secret || true

echo "== Verify =="
sudo -u www-data php /var/www/nextcloud/occ app:list --output=json 2>/dev/null | jq -r '[(.enabled|keys[]?), (.disabled|keys[]?)] | flatten | unique | .[]' | grep -i '^onlyoffice$' || true
sudo -u www-data php /var/www/nextcloud/occ onlyoffice:documentserver --check || true

echo "Done. If the check is OK, try opening a DOCX from the Nextcloud UI."

