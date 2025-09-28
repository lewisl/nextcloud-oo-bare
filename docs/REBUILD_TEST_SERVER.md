# Rebuilding the Test VPS (docs.test-collab-site.com)

When Hetzner rebuilds the test instance everything on disk is wiped, including `/srv/collab`, SSH keys, and this repo. The checklist below brings the machine back to the state expected by the automation scripts.

## 1. Prepare Local Artifacts
- **SSH keys:** Copy the existing private key from `/root/.ssh/id_ed25519_docs` (and matching `.pub`) to a safe location before destroying the server. Do **not** commit it; keep it offline and re-upload after rebuild.
- **Repo contents:** Push the current Git branch to GitHub so all script/config changes survive the rebuild.

## 2. Initial Server Login
1. Log in as `root` using Hetzner’s console/temporary credentials.
2. Create the working directory and fetch the repo:
   ```bash
   mkdir -p /srv/collab
   cd /srv
   git clone git@github.com:<org>/<repo>.git collab
   cd /srv/collab
   git checkout feature/dual-domain-approach
   ```
3. Restore `/root/.ssh` contents:
   ```bash
   mkdir -p /root/.ssh
   chmod 700 /root/.ssh
   # copy id_ed25519_docs and id_ed25519_docs.pub from your safe backup
   chmod 600 /root/.ssh/id_ed25519_docs
   chmod 644 /root/.ssh/id_ed25519_docs.pub
   cat /root/.ssh/id_ed25519_docs.pub >> /root/.ssh/authorized_keys
   chmod 600 /root/.ssh/authorized_keys
   ```
4. If a GitHub deploy key was used, regenerate it (from your workstation) and add the public key to the repo’s deploy-key list, then place the private key on the server (e.g., `/root/.ssh/hetzner_91_99_189_91`). Update `/root/.ssh/config` accordingly.

## 3. Re-run Automation

Before running the automation, update the deployment parameters and let the system prep script generate credentials:

1. Run `sudo ./src/01_system_prep.sh` once. If `/etc/nextcloud-onlyoffice/params.yaml` is missing, the script copies the template and exits with a warning.
2. Edit `/etc/nextcloud-onlyoffice/params.yaml` (root only) and replace the placeholder values for:
   - `deployment.base_domain`
   - `deployment.nextcloud_domain` (should be `docs.<base_domain>`)
   - `deployment.admin_email` and `deployment.letsencrypt_email`
3. Re-run `sudo ./src/01_system_prep.sh`. The script now auto-generates secure secrets for the Nextcloud admin account, both database users, and the JWT. A summary is written to `/root/nextcloud-onlyoffice-secrets.txt` for safekeeping.

With the repo checked out:
```bash
cd /srv/collab
sudo ./src/01_system_prep.sh
sudo ./src/02_database_setup.sh
sudo ./src/03_nextcloud_install.sh
sudo ./src/04_onlyoffice_install.sh   # fix outstanding issues before relying on this step
sudo ./src/05_nginx_config.sh
sudo ./src/06_ssl_setup.sh            # pass --staging for test runs
sudo ./src/07_integration_config.sh
```
Capture each script’s output in `project-status-and-todo/test-results/` as before.

## 4. Post-Install Tasks
- Re-enable the codex SSH user if required (create user, add to `sudo`, copy authorized key).
- Trigger the diagnostics script: `sudo ./src/99_diagnostics.sh`.
- Notify stakeholders to test the web UI at `https://docs.test-collab-site.com`.
- Store the contents of `/root/nextcloud-onlyoffice-secrets.txt` in your password manager, then restrict access to root SSH keys as usual.

Keep this document updated whenever the bootstrap flow changes.
