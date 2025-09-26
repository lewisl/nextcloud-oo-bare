#!/usr/bin/env bash
# Lightweight nginx regression tests for Nextcloud + OnlyOffice deployment
# Assumes scripts 01-05 have run and nginx is serving the managed vhost.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_LOADER="${PROJECT_ROOT}/src/lib/config_loader.py"
PARAMS_FILE="/etc/nextcloud-onlyoffice/params.yaml"
LOG_FILE="/var/log/nextcloud-diagnostics.log"
RESOLVE_IP="127.0.0.1"

log() {
    printf "[nginx-smoke] %s\n" "$1" | tee -a "$LOG_FILE"
}

die() {
    printf "[nginx-smoke][ERROR] %s\n" "$1" | tee -a "$LOG_FILE" >&2
    exit 1
}

if [[ ! -f "$PARAMS_FILE" ]]; then
    die "Parameters file $PARAMS_FILE not found; run 01_system_prep.sh first"
fi

exports=$(NC_OO_PARAMS_PATH="$PARAMS_FILE" python3 "$CONFIG_LOADER" --env) || die "Unable to load deployment parameters"
eval "$exports"

: "${NEXTCLOUD_FQDN:?NEXTCLOUD_FQDN missing from params.yaml}"
SITE_CONF="/etc/nginx/sites-available/${NEXTCLOUD_FQDN}.conf"

if [[ -f "/etc/letsencrypt/live/${NEXTCLOUD_FQDN}/fullchain.pem" ]]; then
    EXPECT_PROTO="https;"
    EXPECT_PORT="443;"
    SCHEME="https"
    RESOLVE_PORT=443
    CURL_FLAGS=(-kfsS)
else
    EXPECT_PROTO="\$scheme;"
    EXPECT_PORT="\$server_port;"
    SCHEME="http"
    RESOLVE_PORT=80
    CURL_FLAGS=(-fsS)
fi

log "Testing nginx configuration syntax"
nginx -t >/dev/null

log "Ensuring vhost contains required proxy headers"
grep -F "proxy_set_header   Authorization      \$http_authorization;" "$SITE_CONF" >/dev/null || die "Missing Authorization header"
if ! grep -F "proxy_set_header   X-Forwarded-Proto  $EXPECT_PROTO" "$SITE_CONF" >/dev/null; then
    die "Missing expected X-Forwarded-Proto header"
fi
if ! grep -F "proxy_set_header   X-Forwarded-Port   $EXPECT_PORT" "$SITE_CONF" >/dev/null; then
    die "Missing expected X-Forwarded-Port header"
fi

log "Checking static asset rewrites include modern bundles"
substr="location ~ ^/(?!index\\.php/).*(?:css|js|mjs|wasm|woff2?|svg|gif|map)$"
grep -F "$substr" "$SITE_CONF" >/dev/null || die "Static asset location block missing modern extensions"

log "Validating text/javascript MIME mapping for .mjs"
if ! grep -Eq '^\s*text/javascript\s+mjs;' /etc/nginx/mime.types; then
    die "text/javascript mjs mapping missing from /etc/nginx/mime.types"
fi

log "Probing /onlyoffice/healthcheck via loopback"
curl "${CURL_FLAGS[@]}" --resolve "${NEXTCLOUD_FQDN}:${RESOLVE_PORT}:${RESOLVE_IP}" "${SCHEME}://${NEXTCLOUD_FQDN}/onlyoffice/healthcheck" | grep -q '^true$' || die "OnlyOffice healthcheck failed"

log "Probing Viewer /.mjs asset via loopback"
MJS_PATH="${SCHEME}://${NEXTCLOUD_FQDN}/apps/viewer/js/viewer-main.mjs"
status=$(curl -kfsSI --resolve "${NEXTCLOUD_FQDN}:${RESOLVE_PORT}:${RESOLVE_IP}" "$MJS_PATH" | awk 'NR==1{print $2}') || die "Failed to fetch viewer-main.mjs"
[[ "$status" == "200" ]] || die "viewer-main.mjs returned status $status"
ctype=$(curl -kfsSI --resolve "${NEXTCLOUD_FQDN}:${RESOLVE_PORT}:${RESOLVE_IP}" "$MJS_PATH" | awk 'BEGIN{IGNORECASE=1}/^content-type:/{print $2; exit}' | tr -d '\r')
[[ "$ctype" == "text/javascript" ]] || die "viewer-main.mjs wrong content-type ($ctype)"

log "Probing Text app .mjs asset via loopback"
TEXT_MJS="${SCHEME}://${NEXTCLOUD_FQDN}/apps/text/js/text-init.mjs"
status=$(curl -kfsSI --resolve "${NEXTCLOUD_FQDN}:${RESOLVE_PORT}:${RESOLVE_IP}" "$TEXT_MJS" | awk 'NR==1{print $2}') || die "Failed to fetch text-init.mjs"
[[ "$status" == "200" ]] || die "text-init.mjs returned status $status"
ctype=$(curl -kfsSI --resolve "${NEXTCLOUD_FQDN}:${RESOLVE_PORT}:${RESOLVE_IP}" "$TEXT_MJS" | awk 'BEGIN{IGNORECASE=1}/^content-type:/{print $2; exit}' | tr -d '\r')
[[ "$ctype" == "text/javascript" ]] || die "text-init.mjs wrong content-type ($ctype)"

log "nginx smoke tests passed"
