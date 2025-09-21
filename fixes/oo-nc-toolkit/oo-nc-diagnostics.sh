#!/usr/bin/env bash
set -euo pipefail
OUT="/root/oo-nc-diagnostics-$(date +%F-%H%M).log"
exec > >(tee -a "$OUT") 2>&1
echo "==== TIMESTAMP ===="
date -Is
echo "==== KERNEL / OS ===="
uname -a || true
lsb_release -a 2>/dev/null || cat /etc/os-release || true

echo "==== SERVICES (systemd) ===="
systemctl list-units --type=service | grep -E 'nginx|php|mysql|mariadb|onlyoffice|ds-|documentserver|redis' || true

echo "==== PORTS (80,443,8080,8082,8000,6379) ===="
ss -ltnp | grep -E ':(80|443|8080|8082|8000|6379)\b' || true

echo "==== NGINX -T (headers only) ===="
nginx -t || true
echo "# vhosts:"
nginx -T 2>/dev/null | awk '/^# configuration file .*sites-enabled/ || /^ *server_name /{print}' || true

echo "==== NEXTCLOUD OCC ===="
sudo -u www-data php /var/www/nextcloud/occ status || true
sudo -u www-data php /var/www/nextcloud/occ config:list onlyoffice || true

echo "==== NEXTCLOUD CONFIG.PHP (snips) ===="
grep -E 'onlyoffice|allow_local_remote_servers|redis|memcache' -n /var/www/nextcloud/config/config.php || true

echo "==== ONLYOFFICE local.json ===="
if command -v jq >/dev/null 2>&1; then
  jq . /etc/onlyoffice/documentserver/local.json || cat /etc/onlyoffice/documentserver/local.json || true
else
  cat /etc/onlyoffice/documentserver/local.json || true
fi

echo "==== ONLYOFFICE default.json (token block) ===="
if command -v jq >/dev/null 2>&1; then
  jq '.services.CoAuthoring.token' /etc/onlyoffice/documentserver/default.json || true
else
  grep -n '"token"' -n /etc/onlyoffice/documentserver/default.json -n | head -n 40 || true
fi

echo "==== HEALTHCHECKS ===="
curl -sI http://127.0.0.1:8000/healthcheck | head -n1 || true
curl -sI http://127.0.0.1:8000/hosting/discovery | head -n1 || true
curl -sI http://127.0.0.1:8080/hosting/discovery | head -n1 || true
if command -v hostname >/dev/null 2>&1; then H=$(hostname -f || hostname); else H=""; fi
curl -sI https://docs.test-collab-site.com/onlyoffice/hosting/discovery | head -n1 || true

echo "==== LOG TAILS ===="
tail -n 100 /var/log/nginx/error.log 2>/dev/null || true
tail -n 100 /var/log/onlyoffice/documentserver/docservice/out.log 2>/dev/null || true
tail -n 100 /var/log/onlyoffice/documentserver/converter/out.log 2>/dev/null || true

echo "Diagnostics complete -> $OUT"
