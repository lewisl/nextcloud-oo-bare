### important information about webserver configurations within the nextcloud and onlyoffice containers

```
root@ubuntu-8gb-fsn1-1:/# # Inspect the web server & PHP inside Nextcloud
docker exec -it ab43a44c17d1 bash -lc 'apache2ctl -S || httpd -S 2>/dev/null; php -v'
VirtualHost configuration:
*:80                   %{HTTP_HOST} (/etc/apache2/sites-enabled/nextcloud.conf:3)
ServerRoot: "/etc/apache2"
Main DocumentRoot: "/var/www/html"
Main ErrorLog: "|/bin/cat"
Mutex default: dir="/var/run/apache2/" mechanism=default 
Mutex mpm-accept: using_defaults
Mutex watchdog-callback: using_defaults
Mutex rewrite-map: using_defaults
PidFile: "/var/run/apache2/apache2.pid"
Define: DUMP_VHOSTS
Define: DUMP_RUN_CFG
User: name="www-data" id=33
Group: name="www-data" id=33
PHP 8.3.6 (cli) (built: Dec  2 2024 12:36:18) (NTS)
Copyright (c) The PHP Group
Zend Engine v4.3.6, Copyright (c) Zend Technologies
    with Zend OPcache v8.3.6, Copyright (c), by Zend Technologies
root@ubuntu-8gb-fsn1-1:/# # Find the OnlyOffice container by its config file
for c in $(docker ps -q); do
  if docker exec "$c" sh -lc 'test -f /etc/onlyoffice/documentserver/local.json'; then
    echo "DOCS_CID=$c"
    export DOCS_CID="$c"
    break
  fi
done

# Inspect NGINX inside OnlyOffice (if found)
[ -n "$DOCS_CID" ] && docker exec -it "$DOCS_CID" bash -lc 'nginx -T | head -n 40; ss -ltnp | grep :80 || true'
root@ubuntu-8gb-fsn1-1:/# # 1) By image name (most reliable, 1-liner)
docker ps --format '{{.ID}} {{.Image}}' | awk 'tolower($2) ~ /onlyoffice|documentserver/ {print "DOCS_CID="$1; exit}'
DOCS_CID=1892eb1b843b
root@ubuntu-8gb-fsn1-1:/# # 2) Probe each container for OnlyOffice config
for c in $(docker ps -q); do
  if docker exec "$c" sh -lc 'test -f /etc/onlyoffice/documentserver/local.json'; then
    echo "DOCS_CID=$c"
    break
  fi
done
root@ubuntu-8gb-fsn1-1:/# # list vhost(s) for the other app id
ls -1 /etc/nginx/applications/a28b41c1-60b8-4bbb-9eac-3ca6add05627

# show the server_name and proxy_pass for each of those files
for f in /etc/nginx/applications/a28b41c1-60b8-4bbb-9eac-3ca6add05627/*.conf; do 
  echo "== $f =="; grep -E 'server_name|proxy_pass' "$f" | sed 's/^/  /'
done
onlyoffice.bedfordfallsbbbl.org.conf
== /etc/nginx/applications/a28b41c1-60b8-4bbb-9eac-3ca6add05627/onlyoffice.bedfordfallsbbbl.org.conf ==
      server_name  onlyoffice.bedfordfallsbbbl.org;
      server_name  onlyoffice.bedfordfallsbbbl.org;
          proxy_pass http://172.18.18.242:80;
          proxy_pass http://127.0.0.1:3000/well-known-handler/;
          proxy_pass http://172.18.18.242:80;
root@ubuntu-8gb-fsn1-1:/# 
```