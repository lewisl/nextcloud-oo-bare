Session Goals

Verify the current running deployment (services up, OnlyOffice editing, LetsEncrypt renewals etc.).
Capture any config or runtime deltas so we can fold them back into the scripts/docs.
Next Execution Milestones

Rebuild test host, run scripts 01→07 with zero manual intervention, capture logs/artifacts.
Update configs/ snippets and project-status-and-todo/CURRENT_BEST_CONFIGURATIONS.md if anything changes; note we’re still missing project-status-and-todo/CURRENT_STATUS_SUMMARY.md.
Split documentation into admin-facing “user” guide vs. maintainer runbooks.
Define production rollout flow before we touch the real box.
Diagnostic Reminders

Internal checks once writable: systemctl status ds-docservice ds-converter ds-metrics, sudo -u www-data php occ onlyoffice:documentserver --check, curl http://127.0.0.1/onlyoffice/healthcheck (or equivalent), and ./src/99_diagnostics.sh.
After internal tests pass, we always ask you to confirm via the web GUI.

Enabled Nextcloud Apps Snapshot (2025-09-28)

activity, app_api, bruteforcesettings, circles, cloud_federation_api, comments, contactsinteraction, dashboard, dav, encryption, federatedfilesharing, federation, files, files_downloadlimit, files_pdfviewer, files_reminders, files_sharing, files_trashbin, files_versions, firstrunwizard, logreader, lookup_server_connector, nextcloud_announcements, notifications, oauth2, onlyoffice, password_policy, photos, privacy, profile, provisioning_api, recommendations, related_resources, serverinfo, settings, sharebymail, support, survey_client, systemtags, text, theming, twofactor_backupcodes, updatenotification, user_status, viewer, weather_status, webhook_listeners, workflowengine.

Disabled: admin_audit, files_external, suspicious_login, twofactor_nextcloud_notification, twofactor_totp, user_ldap.
