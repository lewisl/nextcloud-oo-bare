

**You**:

does onlyoffice have an arm64 build suitable to run on a Hetzner ARM64 vps?  I think so...   let's verify

---

**ChatGPT**:

Short answer: **Yes.** ONLYOFFICE **Docs / Document Server** has official **ARM64 (aarch64)** builds and Docker images, and it runs fine on a Hetzner ARM64 VPS.

### What’s supported

- **Deb/Ubuntu ARM64 packages** (Docs Community/Developer/Enterprise from v7.1+). Official guide covers ARM64 on Debian/Ubuntu and lists the dependencies. [ONLYOFFICE - Cloud Office Applications](https://helpcenter.onlyoffice.com/docs/installation/docs-community-install-ubuntu-arm64.aspx)

- **Docker (multi-arch) for ARM64** (v7.2+ documented). This is the easiest route on a fresh VPS. [ONLYOFFICE - Cloud Office Applications](https://helpcenter.onlyoffice.com/docs/installation/docs-community-install-docker-arm64.aspx)

- Canonical also published an **Ubuntu ARM64 how-to** for ONLYOFFICE Docs. [Ubuntu](https://ubuntu.com/tutorials/how-to-install-onlyoffice-docs-on-arm64-devices-with-ubuntu)

- Hetzner’s own community tutorial shows installing ONLYOFFICE Docs on **Ubuntu 24.04** (general, but works on ARM64 instances too). [community.hetzner.com](https://community.hetzner.com/tutorials/install-and-configure-onlyoffice-docs-for-nextcloud/?utm_source=chatgpt.com)

**

**Resource sizing:** the Docker ARM64 guide recommends **≥4 GB RAM**, ~40 GB disk, plus swap. Pick a Hetzner ARM64 plan accordingly. [ONLYOFFICE - Cloud Office Applications](https://helpcenter.onlyoffice.com/docs/installation/docs-community-install-docker-arm64.aspx)

### Quick start on a Hetzner ARM64 VPS (Docker)

bash`# with Docker installed
docker run -d --restart=always \
  -p 80:80 -p 443:443 \
  -e JWT_SECRET=choose_a_secret \
  onlyoffice/documentserver:latest
# (Optionally auto-TLS via Let's Encrypt:)
# docker run -d --restart=always -p 80:80 -p 443:443 \
#  -e LETS_ENCRYPT_DOMAIN=docs.example.com \
#  -e LETS_ENCRYPT_MAIL=you@example.com \
#  -e JWT_SECRET=choose_a_secret \
#  onlyoffice/documentserver:latest
`</pre>

These commands come straight from the official ARM64 Docker install notes. [ONLYOFFICE - Cloud Office Applications](https://helpcenter.onlyoffice.com/docs/installation/docs-community-install-docker-arm64.aspx)

### Native (APT) install (ARM64)

If you prefer system packages, the official ARM64 page walks through adding the ONLYOFFICE repo and installing `onlyoffice-documentserver` (with PostgreSQL, RabbitMQ, NGINX). [ONLYOFFICE - Cloud Office Applications+1](https://helpcenter.onlyoffice.com/docs/installation/docs-community-install-ubuntu-arm64.aspx)

### Important caveat (Workspace vs Docs)

- **ONLYOFFICE Workspace Community (the all-in-one suite with Mail/CRM/etc.)**: the official installer **requires amd64** (x86_64) per the docs. So on a Hetzner **ARM64** VPS, stick to **ONLYOFFICE Docs/Document Server** rather than the full Workspace bundle. [ONLYOFFICE - Cloud Office Applications](https://helpcenter.onlyoffice.com/workspace/installation/workspace-install-docker.aspx)

If you’re integrating with Nextcloud, point the Nextcloud ONLYOFFICE app to your Document Server URL and (optionally) enable JWT to lock it down—this is the common, supported ARM64 path. [ONLYOFFICE - Cloud Office Applications](https://helpcenter.onlyoffice.com/docs/installation/docs-community-install-docker-arm64.aspx)

Want me to jot a minimal Nextcloud ⇄ ONLYOFFICE ARM64 config (NGINX reverse-proxy + JWT) for your box?

---

**You**:

we are not going to use docker, but that doesn't matter as long was we can get a tarball that contains the arm64 build

---

**ChatGPT**:

Short version: **ONLYOFFICE Docs (Document Server) is supported on ARM64 and will run on a Hetzner ARM64 VPS.** But **there isn’t an official prebuilt ARM64 “tarball” release**. They ship ARM64 via the package managers and Docker; the only tarballs you’ll see on their mirrors are **source code** (or Docker image .tar files), not a self-contained binary bundle.

### What you can download today

- **Debian/Ubuntu (ARM64) – .deb packages**: available from their repo and mirrors. Example: `onlyoffice-documentserver_arm64.deb` for v9.0.3 is on the SourceForge mirror. [SourceForge](https://sourceforge.net/projects/onlyoffice-document.mirror/files/v9.0.3/?utm_source=chatgpt.com)

- **RHEL/CentOS (ARM64) – .rpm packages**: `onlyoffice-documentserver.aarch64.rpm` is published for recent versions. [SourceForge](https://sourceforge.net/projects/onlyoffice-document.mirror/files/v9.0.3/?utm_source=chatgpt.com)

- **Official docs for ARM64 on Debian/Ubuntu** (install via APT): they document ARM64 since 7.1+. [ONLYOFFICE - Cloud Office Applications](https://helpcenter.onlyoffice.com/docs/installation/docs-community-install-ubuntu-arm64.aspx)

- **Main download page** shows ARM builds for Debian/Ubuntu and RHEL/CentOS. [ONLYOFFICE](https://www.onlyoffice.com/download-docs.aspx?utm_source=chatgpt.com)

### So… no tarball?

Right—no official **binary** tar.gz for ARM64. The tarballs on GitHub/SourceForge are **source archives**; the “.tar.gz” you might see in enterprise/offline docs are **Docker images**, not bare binaries. [ONLYOFFICE - Cloud Office Applications](https://helpcenter.onlyoffice.com/docs/installation/docs-enterprise-install-offline.aspx?utm_source=chatgpt.com)

### Recommended path on a Hetzner ARM64 VPS (no Docker)

- **Debian/Ubuntu**: add ONLYOFFICE’s APT repo and install `onlyoffice-documentserver` (their ARM64 guide walks through it). [ONLYOFFICE - Cloud Office Applications](https://helpcenter.onlyoffice.com/docs/installation/docs-community-install-ubuntu-arm64.aspx)

- **RHEL/CentOS/Alma/Rocky**: use the ARM64 `.rpm`. [SourceForge](https://sourceforge.net/projects/onlyoffice-document.mirror/files/v9.0.3/?utm_source=chatgpt.com)

**

If you _must_ avoid APT/RPM entirely, your options are:**
(a) **Build from source** using their documented build tools, then package/deploy yourself. [ONLYOFFICE - Cloud Office Applications](https://helpcenter.onlyoffice.com/docs/installation/docs-community-compile.aspx?utm_source=chatgpt.com)**
(b) **Manually extract the .deb/.rpm** into a directory and wire up dependencies/services by hand (PostgreSQL, RabbitMQ, NGINX). This works, but it’s fiddly and unsupported compared to using the repo. The ARM64 install doc lists the required services. [ONLYOFFICE - Cloud Office Applications](https://helpcenter.onlyoffice.com/docs/installation/docs-community-install-ubuntu-arm64.aspx)

If you tell me your distro (e.g., Ubuntu 24.04 vs Debian 12 vs Alma 9), I’ll give you the exact commands and a minimal NGINX/JWT config to get it answering on your domain.

---

**You**:

so we can use apt for Ubuntu 24.04

---

**ChatGPT**:

Yes—APT on Ubuntu 24.04 (ARM64) is supported for **ONLYOFFICE Docs (Document Server)**.

Here’s the minimal, known-good sequence:

bash`# 1) Base deps (PostgreSQL + RabbitMQ; nginx comes via deps if needed)
sudo apt update
sudo apt install -y postgresql rabbitmq-server

# 2) Add ONLYOFFICE APT key + repo
sudo mkdir -p -m 700 ~/.gnupg
curl -fsSL https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE \
| gpg --no-default-keyring --keyring gnupg-ring:/tmp/onlyoffice.gpg --import
chmod 644 /tmp/onlyoffice.gpg
sudo chown root:root /tmp/onlyoffice.gpg
sudo mv /tmp/onlyoffice.gpg /usr/share/keyrings/onlyoffice.gpg

echo "deb [signed-by=/usr/share/keyrings/onlyoffice.gpg] https://download.onlyoffice.com/repo/debian squeeze main" \
| sudo tee /etc/apt/sources.list.d/onlyoffice.list

sudo apt update

# (optional but recommended) preseed JWT
echo "onlyoffice-documentserver onlyoffice/jwt-enabled boolean true" | sudo debconf-set-selections
echo "onlyoffice-documentserver onlyoffice/jwt-secret  password YOUR_SECRET" | sudo debconf-set-selections

# 3) Install Document Server
sudo apt install -y onlyoffice-documentserver
`</pre>

- By default it listens on **port 80**; after install you should see the welcome page at `http://<your-server-ip>/`. [ONLYOFFICE - Cloud Office Applications](https://helpcenter.onlyoffice.com/docs/installation/docs-community-install-ubuntu.aspx)

- The ARM64 guidance (originally written for 18.04/20.04) applies the same way on newer Ubuntu; Canonical’s ARM64 tutorial confirms the flow (PostgreSQL, RabbitMQ, then ONLYOFFICE). [ONLYOFFICE - Cloud Office Applications+1](https://helpcenter.onlyoffice.com/docs/installation/docs-community-install-ubuntu-arm64.aspx?utm_source=chatgpt.com)

If you want to run it behind your existing Nginx/Apache and TLS, we can drop in a tight reverse-proxy + JWT snippet next.

---

**You**:

that's awesome.  I am doing this with a separate process.  just wanted to confirm availability

---

**ChatGPT**:

Great—then you’re good to go. ONLYOFFICE Docs **is** available via APT on Ubuntu 24.04 ARM64.

Tiny checklist while you’re at it (just to avoid the usual snags):

- Aim for **≥4 GB RAM** (add 2–4 GB swap if tight).

- Open **80/443** (or set up your reverse proxy/TLS).

- Verify services after install:

bash`systemctl status onlyoffice-documentserver nginx rabbitmq-server postgresql
curl -f http://localhost/healthcheck
`</pre>

- If you’ll integrate with Nextcloud, set a **JWT secret** in `local.json` (or via debconf) and use the same secret in the Nextcloud ONLYOFFICE app.

If you want a minimal Nginx reverse-proxy + JWT snippet, say the word and I’ll drop it in.

---