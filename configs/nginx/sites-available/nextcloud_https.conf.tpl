server {
    listen 80;
    listen [::]:80;
    server_name ${NEXTCLOUD_FQDN};

    # Allow Let's Encrypt challenge without redirect loops
    location ^~ /.well-known/acme-challenge/ {
        root /var/www/nextcloud;
        default_type "text/plain";
    }

    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${NEXTCLOUD_FQDN};

    ssl_certificate     /etc/letsencrypt/live/${NEXTCLOUD_FQDN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${NEXTCLOUD_FQDN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;
    ssl_stapling on;
    ssl_stapling_verify on;

    root   /var/www/nextcloud;
    index  index.php index.html;

    client_max_body_size 512M;
    client_body_timeout  300s;
    send_timeout         300s;
    keepalive_timeout    75s;

    add_header Strict-Transport-Security "max-age=15552000; includeSubDomains; preload" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer" always;
    add_header Permissions-Policy "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()" always;
    add_header X-Robots-Tag "noindex,nofollow" always;
    add_header X-Permitted-Cross-Domain-Policies "none" always;

    location = /.well-known/carddav { return 301 /remote.php/dav; }
    location = /.well-known/caldav  { return 301 /remote.php/dav; }
    location = /.well-known/webfinger { return 301 /index.php/.well-known/webfinger; }
    location = /.well-known/nodeinfo  { return 301 /index.php/.well-known/nodeinfo; }
    location = /.well-known/host-meta { return 301 /public.php?service=host-meta; }
    location = /.well-known/host-meta.json { return 301 /public.php?service=host-meta-json; }
    location ^~ /.well-known/acme-challenge/ {
        root /var/www/nextcloud;
        default_type "text/plain";
    }

    location ^~ /onlyoffice/ {
        proxy_pass         http://127.0.0.1:${ONLYOFFICE_PORT}/;
        proxy_http_version 1.1;
        proxy_set_header   Host               $host;
        proxy_set_header   X-Real-IP          $remote_addr;
        proxy_set_header   X-Forwarded-For    $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto  https;
        proxy_set_header   X-Forwarded-Host   $host/onlyoffice;
        proxy_set_header   X-Forwarded-Port   443;
        proxy_set_header   X-Forwarded-Prefix "";
        proxy_set_header   Authorization      $http_authorization;
        proxy_set_header   Upgrade            $http_upgrade;
        proxy_set_header   Connection         $connection_upgrade;
        client_max_body_size 200m;
        proxy_read_timeout    3600s;
        proxy_send_timeout    3600s;
        proxy_buffering       off;
        proxy_redirect        off;
    }

    location / {
        try_files $uri $uri/ /index.php$request_uri;
    }

    location ^~ /index.php {
        fastcgi_split_path_info ^(.+?\.php)(/.*)$;
        try_files $fastcgi_script_name =404;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO       $fastcgi_path_info;
        fastcgi_param modHeadersAvailable true;
        fastcgi_param front_controller_active true;
        fastcgi_pass unix:${PHP_FPM_SOCKET};
        fastcgi_intercept_errors on;
        fastcgi_request_buffering off;
    }

    location ^~ /remote.php {
        fastcgi_split_path_info ^(.+?\.php)(/.*)$;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO       $fastcgi_path_info;
        fastcgi_param modHeadersAvailable true;
        fastcgi_param front_controller_active true;
        fastcgi_pass unix:${PHP_FPM_SOCKET};
        fastcgi_intercept_errors on;
        fastcgi_request_buffering off;
    }

    # Static assets (hashed bundles, modules, wasm)
    location ~ ^/(?!index\.php/).*(?:css|js|mjs|wasm|woff2?|svg|gif|map)$ {
        try_files $uri /index.php$request_uri;
        expires 6M;
        add_header Cache-Control "public, max-age=15552000, immutable";
        access_log off;
    }

    location ~ ^/(?!index\.php/).*(?:png|html|ttf|ico|jpg|jpeg|webp|avif)$ {
        try_files $uri /index.php$request_uri;
        expires 6M;
        add_header Cache-Control "public, max-age=15552000, immutable";
        access_log off;
    }

    # Force app directories through front controller but allow direct asset hits
    location ~ ^/apps/(?!.*/api/)(?!.*\.[^/]+$).*/?$ {
        rewrite ^(.*)$ /index.php$1 last;
    }

    location = /robots.txt  { allow all; log_not_found off; access_log off; }
    location = /favicon.ico { log_not_found off; access_log off; }
    location ^~ /public.php { try_files $uri $uri/ /index.php$request_uri; }

    location ~ ^/(?:build|tests|config|lib|3rdparty|templates|data)(?:$|/) { return 404; }
    location ~ ^/(?:\.|autotest|occ|issue|indie|db_|console) { return 404; }

    location ~ \.php(?:$|/) {
        fastcgi_split_path_info ^(.+?\.php)(/.*)$;
        try_files $fastcgi_script_name =404;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO       $fastcgi_path_info;
        fastcgi_param modHeadersAvailable true;
        fastcgi_param front_controller_active true;
        fastcgi_pass unix:${PHP_FPM_SOCKET};
        fastcgi_intercept_errors on;
        fastcgi_request_buffering off;
    }

    location ~ \.php$ { return 404; }

    access_log /var/log/nginx/nextcloud_access.log;
    error_log  /var/log/nginx/nextcloud_error.log warn;
}
