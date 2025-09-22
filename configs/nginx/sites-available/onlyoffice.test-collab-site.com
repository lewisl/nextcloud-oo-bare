# OnlyOffice reverse proxy for onlyoffice.test-collab-site.com
server {
    listen 80;
    server_name onlyoffice.test-collab-site.com;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade           $http_upgrade;
        proxy_set_header Connection        "upgrade";
        client_max_body_size 200m;
        proxy_read_timeout 360s;
        proxy_send_timeout 360s;
        proxy_buffering off;
    }

    location /healthcheck {
        proxy_pass http://127.0.0.1:8080/healthcheck;
        access_log off;
    }
}

server {
    listen 443 ssl http2;
    server_name onlyoffice.test-collab-site.com;

    ssl_certificate     /etc/letsencrypt/live/onlyoffice.test-collab-site.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/onlyoffice.test-collab-site.com/privkey.pem;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_protocols TLSv1.2 TLSv1.3;

    add_header Content-Security-Policy "frame-ancestors 'self' https://docs.test-collab-site.com" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade           $http_upgrade;
        proxy_set_header Connection        "upgrade";
        client_max_body_size 200m;
        proxy_read_timeout 360s;
        proxy_send_timeout 360s;
        proxy_buffering off;
    }

    location /healthcheck {
        proxy_pass http://127.0.0.1:8080/healthcheck;
        access_log off;
    }
}
