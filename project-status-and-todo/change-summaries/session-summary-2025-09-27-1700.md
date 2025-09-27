# 2025-09-27 – Clean VPS test cycle

## Observations
- `03_nextcloud_install.sh` aborted because `bzip2` was missing on a fresh host.
- `04_onlyoffice_install.sh` failed while preparing directories: the script chowned files to `ds:ds` before the package created the account; later the installer also stalled waiting for debconf input and RabbitMQ was absent, leading to AMQP connection spam.
- Iterating on scripts required repeated apt operations; the default 10s timeout in the harness exposed the lack of retry/timeout tuning.
- Certbot runs succeeded only after granting a longer runtime. Using the staging endpoint keeps us under rate limits but causes the connector self-check to distrust the origin TLS chain (especially when Cloudflare proxying is enabled).
- The connector health test also fails when Cloudflare’s proxy serves an untrusted certificate or when DocumentServer secure-link validation blocks the generated download URL.

## Script adjustments made
- `src/01_system_prep.sh`: added retry-friendly apt opts, ensured `bzip2` and `rabbitmq-server` are installed, and enabled RabbitMQ alongside other core services.
- `src/03_nextcloud_install.sh`: now asserts `bzip2` exists before downloading the archive.
- `src/04_onlyoffice_install.sh`: creates the `ds` account up-front, pre-seeds DocumentServer debconf answers with the database credentials, and relies on the RabbitMQ service provided by script 01.
- `src/06_ssl_setup.sh`: uses the same apt retry options so certbot installs survive transient network hiccups.
- `src/07_integration_config.sh`: expands the warning emitted when the connector check fails, calling out staging-certificate and proxy-related causes so the operator knows what to double-check.

## Follow-up
- Once we switch from staging to a production Let’s Encrypt certificate, re-enable Cloudflare’s proxy and re-run `07_integration_config.sh` to verify the connector is clean without the temporary relaxations.
- Remove any staging-only toggles (e.g. `verify_peer_off` or custom `local.json` overrides) before the production run.
