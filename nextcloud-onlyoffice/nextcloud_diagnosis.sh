#!/bin/bash

# Complete Nextcloud + OnlyOffice System Diagnosis
# This script captures the current state of everything

echo "=== NEXTCLOUD + ONLYOFFICE SYSTEM DIAGNOSIS ==="
echo "Generated: $(date)"
echo "=============================================="
echo

echo "=== SYSTEM OVERVIEW ==="
echo "OS: $(lsb_release -d | cut -f2)"
echo "Hostname: $(hostname)"
echo "IP Address: $(curl -s ifconfig.me)"
echo

echo "=== SNAP PACKAGES ==="
snap list | grep -E "(nextcloud|onlyoffice|core)"
echo

echo "=== RUNNING SERVICES ==="
echo "nginx processes:"
ps aux | grep nginx | grep -v grep
echo
echo "OnlyOffice processes:"
ps aux | grep -i onlyoffice | grep -v grep
echo
echo "Nextcloud processes:"
ps aux | grep -E "(nextcloud|httpd)" | grep -v grep
echo

echo "=== NETWORK PORTS ==="
echo "Listening ports:"
netstat -tlnp | grep -E ":80|:82|:443|:8000|:8080|:8443"
echo

echo "=== NGINX CONFIGURATION ==="
echo "Active nginx sites:"
ls -la /etc/nginx/sites-enabled/
echo
echo "Current nextcloud site config:"
echo "--- /etc/nginx/sites-available/nextcloud ---"
cat /etc/nginx/sites-available/nextcloud 2>/dev/null || echo "File not found"
echo "--- End config ---"
echo

echo "=== NEXTCLOUD SNAP STATUS ==="
echo "Nextcloud snap info:"
snap info nextcloud | head -20
echo
echo "Nextcloud connections:"
snap connections nextcloud | head -10
echo
echo "Nextcloud configuration:"
snap get nextcloud | head -10
echo

echo "=== ONLYOFFICE SNAP STATUS ==="
echo "OnlyOffice snap info:"
snap info onlyoffice-ds | head -20
echo
echo "OnlyOffice connections:"
snap connections onlyoffice-ds | head -10
echo
echo "OnlyOffice configuration:"
snap get onlyoffice-ds
echo

echo "=== NEXTCLOUD ONLYOFFICE APP STATUS ==="
echo "Installed apps:"
nextcloud.occ app:list | grep -E "(onlyoffice|ONLY)"
echo
echo "OnlyOffice app configuration:"
echo "DocumentServerUrl: $(nextcloud.occ config:app:get onlyoffice DocumentServerUrl)"
echo "StorageUrl: $(nextcloud.occ config:app:get onlyoffice StorageUrl)"
echo "jwt_enabled: $(nextcloud.occ config:app:get onlyoffice jwt_enabled)"
echo "jwt_secret: $(nextcloud.occ config:app:get onlyoffice jwt_secret)"
echo "jwt_header: $(nextcloud.occ config:app:get onlyoffice jwt_header)"
echo

echo "=== CONNECTIVITY TESTS ==="
echo "Testing local connections:"
echo -n "OnlyOffice port 82 health: "
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:82/ || echo "FAILED"
echo

echo -n "OnlyOffice port 8000 health: "
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/healthcheck || echo "FAILED"
echo

echo -n "Nextcloud port 8080 health: "
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/ || echo "FAILED"
echo

echo "Testing external proxy:"
DOMAIN=$(nextcloud.occ config:app:get onlyoffice DocumentServerUrl | sed 's|/$||')
if [ -n "$DOMAIN" ]; then
    echo -n "OnlyOffice proxy health: "
    curl -s -o /dev/null -w "%{http_code}" "${DOMAIN}/healthcheck" || echo "FAILED"
    echo
fi

echo "=== SSL CERTIFICATES ==="
echo "Let's Encrypt certificates:"
ls -la /etc/letsencrypt/live/ 2>/dev/null || echo "None found"
echo

echo "=== FIREWALL STATUS ==="
ufw status numbered
echo

echo "=== RECENT LOG ERRORS ==="
echo "Recent nginx errors:"
tail -n 5 /var/log/nginx/error.log 2>/dev/null || echo "No error log found"
echo
echo "Recent OnlyOffice logs:"
snap logs onlyoffice-ds -n 5 2>/dev/null || echo "No logs available"
echo

echo "=== FILE PERMISSIONS ==="
echo "OnlyOffice snap data permissions:"
ls -la /var/snap/onlyoffice-ds/current/var/www/onlyoffice/Data/ 2>/dev/null || echo "Directory not accessible"
echo

echo "=============================================="
echo "DIAGNOSIS COMPLETE"
echo "=============================================="