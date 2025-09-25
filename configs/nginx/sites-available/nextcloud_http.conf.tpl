# Nextcloud HTTP configuration (pre-SSL)
server {
    listen 80;
    listen [::]:80;
    server_name ${NEXTCLOUD_FQDN};

    root /var/www/nextcloud;
    index index.php index.html;

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
        proxy_set_header   X-Forwarded-Host   $host;
        proxy_set_header   X-Forwarded-Prefix /onlyoffice;
        proxy_set_header   Upgrade            $http_upgrade;
        proxy_set_header   Connection         $connection_upgrade;
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
