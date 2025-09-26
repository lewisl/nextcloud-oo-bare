include /etc/nginx/includes/http-common.conf;
server {
  listen 127.0.0.1:8080;
  server_tokens off;
  set $secure_link_secret __SECURE_LINK_SECRET__;
  include /etc/nginx/includes/ds-*.conf;
}
