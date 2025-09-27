# Nextcloud HTTP configuration (pre-SSL)
server {
    listen 80;
    listen [::]:80;
    server_name ${NEXTCLOUD_FQDN};

    root /var/www/nextcloud;
    index index.php index.html;

    client_max_body_size 512M;
    client_body_timeout  300s;
    send_timeout         300s;
    keepalive_timeout    75s;

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
        proxy_set_header   X-Forwarded-Proto  $scheme;
        proxy_set_header   X-Forwarded-Host   $host/onlyoffice;
        proxy_set_header   X-Forwarded-Port   $server_port;
        proxy_set_header   X-Forwarded-Prefix "";
        proxy_set_header   Authorization      $http_authorization;
        proxy_set_header   Upgrade            $http_upgrade;
        proxy_set_header   Connection         $connection_upgrade;
        client_max_body_size 200m;
        proxy_read_timeout    3600s;
        proxy_send_timeout    3600s;
        proxy_buffering       off;
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
}
