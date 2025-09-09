# Transport + STARTTLS on 587
occ config:system:set mail_smtpmode   --value="smtp"
occ config:system:set mail_smtpsecure --value="tls"
occ config:system:set mail_smtphost   --value="smtp-relay.brevo.com"
occ config:system:set mail_smtpport   --value="587"

# Auth
occ config:system:set mail_smtpauth      --value="1" --type=integer
occ config:system:set mail_smtpauthtype  --value="LOGIN"
occ config:system:set mail_smtpname      --value="95d5ed001@smtp-brevo.com"
occ config:system:set mail_smtppassword  --value="4VcQ8Ntq5JFfb3Zh"   # your real Brevo SMTP key

# From
occ config:system:set mail_from_address --value="lewis"
occ config:system:set mail_domain       --value="neilson-levin.org"

# Quick sanity
occ config:system:get mail_smtpmode
occ config:system:get mail_smtpsecure
occ config:system:get mail_smtphost
occ config:system:get mail_smtpport
occ config:system:get mail_smtpname
occ config:system:get mail_from_address
occ config:system:get mail_domain
