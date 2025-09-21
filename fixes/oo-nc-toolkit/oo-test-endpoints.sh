#!/usr/bin/env bash
set -euo pipefail
echo "DocService 8000:"
curl -sI http://127.0.0.1:8000/hosting/discovery | head -n1 || true
echo "Internal nginx 8080:"
curl -sI http://127.0.0.1:8080/hosting/discovery | head -n1 || true
echo "Public subpath:"
curl -sI https://docs.test-collab-site.com/onlyoffice/hosting/discovery | head -n1 || true
echo "Healthcheck 8000:"
curl -sI http://127.0.0.1:8000/healthcheck | head -n1 || true
