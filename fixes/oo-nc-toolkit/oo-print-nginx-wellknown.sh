    #!/usr/bin/env bash
    cat <<'NGINX'
# Place these inside your server { } for docs.test-collab-site.com

location = /.well-known/webfinger    { return 301 $scheme://$host/index.php/.well-known/webfinger; }
location = /.well-known/nodeinfo     { return 301 $scheme://$host/index.php/.well-known/nodeinfo; }
location = /.well-known/host-meta    { return 301 $scheme://$host/index.php/.well-known/host-meta; }
location = /.well-known/host-meta.json { return 301 $scheme://$host/index.php/.well-known/host-meta.json; }

location = /ocm-provider/  { return 301 $scheme://$host/index.php/ocm-provider/; }
location ^~ /ocm-provider/ { rewrite ^/ocm-provider/(.*)$ /index.php/ocm-provider/$1 last; }

location = /ocs-provider/  { return 301 $scheme://$host/index.php/ocs-provider/; }
location ^~ /ocs-provider/ { rewrite ^/ocs-provider/(.*)$ /index.php/ocs-provider/$1 last; }

# OnlyOffice subpath (ensure trailing slash on proxy_pass)
location ^~ /onlyoffice/ {
    proxy_pass http://127.0.0.1:8080/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Host $server_name;
    proxy_connect_timeout 60s;
    proxy_send_timeout 3600s;
    proxy_read_timeout 3600s;
    proxy_buffering off;
    proxy_request_buffering off;
    client_max_body_size 100M;
}
NGINX
