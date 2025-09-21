# OnlyOffice configuration for onlyoffice.test-collab-site.com
server {
    listen 80;
    listen [::]:80;
    server_name onlyoffice.test-collab-site.com;
    
    # Redirect HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name onlyoffice.test-collab-site.com;
    
    # SSL configuration (will be updated by SSL setup script)
    ssl_certificate /etc/letsencrypt/live/onlyoffice.test-collab-site.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/onlyoffice.test-collab-site.com/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/onlyoffice.test-collab-site.com/chain.pem;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Strict-Transport-Security "max-age=63072000" always;
    
    # Rate limiting for OnlyOffice
    limit_req zone=onlyoffice burst=10 nodelay;
    
    # Proxy to OnlyOffice internal nginx
    location / {
        proxy_pass http://127.0.0.1:80;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $server_name;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # File upload size
        client_max_body_size 100M;
        
        # Buffering
        proxy_buffering off;
        proxy_request_buffering off;
    }
    
    # Health check
    location /healthcheck {
        proxy_pass http://127.0.0.1:80/healthcheck;
        access_log off;
    }
    
    # Static files caching
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg)$ {
        proxy_pass http://127.0.0.1:80;
        proxy_set_header Host $host;
        proxy_cache_valid 200 1d;
        expires 1d;
        add_header Cache-Control "public, immutable";
    }
}
