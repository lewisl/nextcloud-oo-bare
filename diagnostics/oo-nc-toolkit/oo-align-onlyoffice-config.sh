#!/usr/bin/env bash
set -euo pipefail
SECRET="${1:-}"
if [[ -z "${SECRET}" ]]; then
  SECRET="$(openssl rand -base64 48)"
fi
echo "Using secret: $SECRET"
CFG="/etc/onlyoffice/documentserver/local.json"
TMP="${CFG}.new"
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required. Installing (apt)..."
  apt-get update -y && apt-get install -y jq
fi
jq --arg s "$SECRET" '
  .wopi = {"enable": true} |
  .services = (.services // {}) |
  .services.CoAuthoring = (.services.CoAuthoring // {}) |
  .services.CoAuthoring.token = (
    .services.CoAuthoring.token // {}
    | . + {
        "enable": { "browser": true, "request": { "inbox": true, "outbox": true } },
        "inbox":  { "string": $s },
        "outbox": { "string": $s },
        "browser":{"string": $s },
        "authorizationHeader": "Authorization"
      }
  ) |
  .services.CoAuthoring += {
    "request-filtering": {
      "enable": true,
      "allowPrivateIPAddress": true,
      "allowLoopback": true,
      "allowedHosts": ["docs.test-collab-site.com"]
    }
  }
' "$CFG" > "$TMP"
mv "$TMP" "$CFG"
echo "$SECRET" > /root/onlyoffice-shared-secret.txt
echo "Wrote updated $CFG and saved secret to /root/onlyoffice-shared-secret.txt"
