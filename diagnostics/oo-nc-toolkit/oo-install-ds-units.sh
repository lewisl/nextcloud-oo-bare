    #!/usr/bin/env bash
    set -euo pipefail
    LOG4JS="${LOG4JS:-production-linux.json}"
    if [[ ! -f "/etc/onlyoffice/documentserver/log4js/${LOG4JS}" ]]; then
      echo "log4js file /etc/onlyoffice/documentserver/log4js/${LOG4JS} not found. Available:"
      ls -1 /etc/onlyoffice/documentserver/log4js || true
      exit 1
    fi
    sudo tee /etc/systemd/system/ds-docservice.service >/dev/null <<EOF
[Unit]
Description=ONLYOFFICE DocService
After=network.target

[Service]
Environment=NODE_ENV=production
Environment=NODE_CONFIG_DIR=/etc/onlyoffice/documentserver
Environment=LOG4JS_CONFIG=/etc/onlyoffice/documentserver/log4js/${LOG4JS}
WorkingDirectory=/var/www/onlyoffice/documentserver/server/DocService
ExecStart=/var/www/onlyoffice/documentserver/server/DocService/docservice
Restart=on-failure
StandardOutput=append:/var/log/onlyoffice/documentserver/docservice/out.log
StandardError=inherit

[Install]
WantedBy=multi-user.target
EOF

    sudo tee /etc/systemd/system/ds-converter.service >/dev/null <<EOF
[Unit]
Description=ONLYOFFICE FileConverter
After=network.target

[Service]
Environment=NODE_ENV=production
Environment=NODE_CONFIG_DIR=/etc/onlyoffice/documentserver
Environment=LOG4JS_CONFIG=/etc/onlyoffice/documentserver/log4js/${LOG4JS}
WorkingDirectory=/var/www/onlyoffice/documentserver/server/FileConverter
ExecStart=/var/www/onlyoffice/documentserver/server/FileConverter/converter
Restart=on-failure
StandardOutput=append:/var/log/onlyoffice/documentserver/converter/out.log
StandardError=inherit

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable --now ds-docservice ds-converter
    systemctl status ds-docservice ds-converter --no-pager || true
