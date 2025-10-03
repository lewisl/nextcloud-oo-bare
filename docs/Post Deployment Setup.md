Post Deployment Setup

- Setup email forwarding
  - **<u>done for production on 10/2/2025</u>**
```markdown
1. main menu -> Administrative Settings -> (sidebar) Basic Settings -> (scroll down) Email Server section
2. information provided by brevo
3. make sure there is an email address for admin:  set with occ
4. additional settings via occ

  sudo -u www-data php /var/www/nextcloud/occ config:system:set mail_from_address --value="noreply"
  sudo -u www-data php /var/www/nextcloud/occ config:system:set mail_domain --value="bedfordfallsbbbl.org"
```
- Setup groups: ***done for production 10/3/2025***

- Invite or add members: ***all members added for production 10/3/2025***

- Turn on server encryption

```bash
# 1) Make sure the Encryption app is enabled
sudo -u www-data php occ app:enable encryption

# 2) Enable server-side encryption
sudo -u www-data php occ encryption:enable

# (Optional/legacy) If your install defaults to user-key mode, explicitly select master key:
# sudo -u www-data php occ encryption:enable-master-key

# 3) Check status
sudo -u www-data php occ encryption:status
```

- get the keys
  - Here....
    - /srv/nextcloud-data/files_encryption/OC_DEFAULT_MODULE/master_f75e7d07.privateKey
    - /srv/nextcloud-data/files_encryption/OC_DEFAULT_MODULE/master_f75e7d07.publicKey
  - and here: 
- Encrypt existing files:

```

# encrypt everything for all users
sudo -u www-data php occ encryption:encrypt-all

# enable SSE for Group Folders
sudo -u www-data php occ config:app:set groupfolders enable_encryption --value="true"

# verify
sudo -u www-data php occ config:app:get groupfolders enable_encryption

```



- Setup folders: ***Bedford Falls and subfolders added for production 10/3/2025***

- Upload documents from other sources: ***done for production 10/3/2025***

- Device and implement a backup strategy

  - user versioning and trash
  - Hetzner backups: ***enabled for production 10/3/2025***
  - Rclone for nextcloud specific data via cron job

- maybe consider this extra security measure, but it is really not necessary:

  ```bash
  # in your Nextcloud server block
  location = /cron.php {
      allow 127.0.0.1;
      allow ::1;
      deny all;
      include fastcgi_params;
      fastcgi_param SCRIPT_FILENAME $document_root/cron.php;
      fastcgi_pass unix:/run/php/php-fpm.sock;  # adjust if needed
  }
  ```

  

  

- setup a default cron job so that cleanup gets done but not as often as "ajax" setting:

​	***annoyingly done for production 10-2-2025***

```bash
sudo -u www-data crontab -e
*/5 * * * * /usr/bin/php -f /var/www/nextcloud/cron.php >/dev/null 2>&1

```

