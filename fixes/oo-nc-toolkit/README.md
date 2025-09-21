# Nextcloud + ONLYOFFICE Toolkit

## Scripts
- `oo-nc-diagnostics.sh` – one-shot diagnostics (writes /root/oo-nc-diagnostics-*.log).
- `oo-align-onlyoffice-config.sh [SECRET]` – enables WOPI/JWT, allows loopback/private IPs; saves secret at /root/onlyoffice-shared-secret.txt.
- `oo-set-nextcloud-connector.sh [SECRET]` – sets Nextcloud app values to match DS; reads secret from /root/onlyoffice-shared-secret.txt if present.
- `oo-install-ds-units.sh` – installs `ds-docservice` and `ds-converter` systemd units with required environment.
- `oo-print-nginx-wellknown.sh` – prints the nginx `location` stanzas to satisfy NC diagnostics.
- `oo-test-endpoints.sh` – quick discovery/health checks (8000/8080/public).

## Suggested order
1. `./oo-nc-diagnostics.sh`
2. `./oo-align-onlyoffice-config.sh` (optionally pass your own secret)
3. `./oo-install-ds-units.sh`
4. `systemctl restart ds-docservice ds-converter`
5. `./oo-set-nextcloud-connector.sh`
6. `./oo-test-endpoints.sh`

## Notes
- Requires `jq`, `curl`, `openssl`, `systemd`.
- Adjust domain `docs.test-collab-site.com` in scripts if your hostname differs.
