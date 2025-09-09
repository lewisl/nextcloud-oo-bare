Perfect — here’s a concise **Brevo + Nextcloud on Cloudron playbook** you can hand to Augment. It captures only the steps that matter, with expected results, so the agent can both *configure* and *verify* without guesswork.

---

# 📋 Nextcloud + Brevo SMTP (Cloudron) Checklist

### Inputs

* **Brevo SMTP username:** `95d5ed001@smtp-brevo.com`
* **Brevo SMTP key (password):** `xkeysib-…` (must be an SMTP key, *not* an API key)
* **From local part:** `lewis`
* **From domain:** `neilson-levin.org`
* **Admin user email (unique real inbox):** e.g. `admin@somewhere-real.org`
* **Normal user email:** `lewis@neilson-levin.org`

---

### 1. Configure Nextcloud via OCC

Run these inside the Nextcloud container:

```bash
occ config:system:set mail_smtpmode   --value="smtp"
occ config:system:set mail_smtpsecure --value="tls"
occ config:system:set mail_smtphost   --value="smtp-relay.brevo.com"
occ config:system:set mail_smtpport   --value="587"

occ config:system:set mail_smtpauth     --value="1" --type=integer
occ config:system:set mail_smtpauthtype --value="LOGIN"

occ config:system:set mail_smtpname     --value="95d5ed001@smtp-brevo.com"
occ config:system:set mail_smtppassword --value="xkeysib-REPLACE_WITH_REAL_KEY"

occ config:system:set mail_from_address --value="lewis"
occ config:system:set mail_domain       --value="neilson-levin.org"
```

---

### 2. Sanity check config

```bash
occ config:system:get mail_smtpmode      # smtp
occ config:system:get mail_smtpsecure    # tls
occ config:system:get mail_smtphost      # smtp-relay.brevo.com
occ config:system:get mail_smtpport      # 587
occ config:system:get mail_smtpauth      # 1
occ config:system:get mail_smtpauthtype  # LOGIN
occ config:system:get mail_smtpname      # 95d5ed001@smtp-brevo.com
occ config:system:get mail_from_address  # lewis
occ config:system:get mail_domain        # neilson-levin.org
```

---

### 3. Smoke test SMTP credentials

```bash
U='95d5ed001@smtp-brevo.com'
P='xkeysib-REPLACE_WITH_REAL_KEY'
printf "EHLO test\r\nAUTH LOGIN\r\n$(printf %s "$U"|base64)\r\n$(printf %s "$P"|base64)\r\nQUIT\r\n" \
| openssl s_client -starttls smtp -connect smtp-relay.brevo.com:587 -crlf -quiet | sed -n '1,12p'
```

✅ Expected: `235 Authentication succeeded`
❌ If `535 Authentication failed`: regenerate a new Brevo SMTP key and repeat.

---

### 4. Test from Nextcloud

* Log in as **admin user** (with its own unique email).
* Go to **Admin → Email server** → click **Send test email**.
* Immediately check **Brevo → Transactional → Logs**.

✅ Expected: entry appears (Delivered, Blocked, or Bounced).

---

### 5. Admin profile email hygiene

* Admin must have a unique email address (real inbox, even if rarely checked).
* Normal user keeps their real working inbox.
* Optional: clear admin profile email later if you don’t want it reused:

  ```bash
  occ user:setting admin settings email ""
  ```

---

### Notes for Augment

* Ignore Nextcloud’s GUI for setting SMTP — it’s unreliable. Always use `occ`.
* Brevo only supports **587 + STARTTLS**, so stick with `mail_smtpsecure=tls`.
* “From” address is defined by `mail_from_address` + `mail_domain`, not by admin’s profile.
* Logs live under `/app/data/nextcloud.log`. If test fails, tail this file after sending to see the exact SMTP error.

---

👉 Would you like me to also prepare the **same checklist as a ready-to-run Bash script** (so Augment only fills in the SMTP key as a variable)?
