#!/usr/bin/env bash
set -euo pipefail
SECRET_FILE="/root/onlyoffice-shared-secret.txt"
if [[ -s "$SECRET_FILE" ]]; then
  SECRET="$(cat "$SECRET_FILE")"
else
  SECRET="${1:-}"
fi
if [[ -z "${SECRET:-}" ]]; then
  echo "Usage: $0 <JWT_SECRET> (or ensure $SECRET_FILE exists)"
  exit 1
fi
DS_PUBLIC="${DS_PUBLIC:-https://docs.test-collab-site.com/onlyoffice/}"
DS_INTERNAL="${DS_INTERNAL:-http://127.0.0.1:8080/}"
NC_STORAGE="${NC_STORAGE:-https://docs.test-collab-site.com/}"

sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice DocumentServerUrl --value="$DS_PUBLIC"
sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice DocumentServerInternalUrl --value="$DS_INTERNAL"
sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice StorageUrl --value="$NC_STORAGE"
sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice jwt_secret --value="$SECRET"
sudo -u www-data php /var/www/nextcloud/occ config:app:set onlyoffice jwt_header --value="Authorization"

echo "Connector values set."
