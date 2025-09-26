## Server configuration detail

**Operating system:** Linux 6.8.0-83-generic #83-Ubuntu SMP PREEMPT_DYNAMIC Fri Sep  5 14:23:58 UTC 2025 aarch64

**Webserver:** nginx/1.24.0 (fpm-fcgi)

**Database:** mysql 10.11.13

**PHP version:** 8.3.6

Modules loaded: Core, date, libxml, openssl, pcre, zlib, filter, hash, json, random, Reflection, SPL, session, standard, sodium, cgi-fcgi, mysqlnd, PDO, xml, apcu, bcmath, calendar, ctype, curl, dom, mbstring, FFI, fileinfo, ftp, gd, gettext, gmp, iconv, igbinary, imagick, intl, exif, mysqli, pdo_mysql, pdo_pgsql, pgsql, Phar, posix, readline, redis, shmop, SimpleXML, sockets, sysvmsg, sysvsem, sysvshm, tokenizer, xmlreader, xmlwriter, xsl, zip, Zend OPcache

**Nextcloud version:** 31.0.9 - 31.0.9.1

**Updated from an older Nextcloud/ownCloud or fresh install:** 

**Where did you install Nextcloud from:** unknown

<details><summary>Signing status</summary>

{
    "core": {
        "EXTRA_FILE": {
            "nextcloud.log": {
                "expected": "",
                "current": "dcb704816d59e06878fac7fe85add04ed3fbf2c64c4f717007aa6a5866c35985b90fe65351be60b890b6f923e472974d5271ef8b78e8e956c2cf9063a312155e"
            },
            "ocs\/nextcloud.log": {
                "expected": "",
                "current": "5555e3daf440a6c04ac6644d5806efdff3cd0966c9286fef092b0953e89112a4f26c37b255788c50db4b553b5852d9a556198ed22b98a4dc79be9a0ff69c2a60"
            },
            "ocs-provider\/nextcloud.log": {
                "expected": "",
                "current": "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e"
            }
        }
    }
}
</details>

<details><summary>List of activated apps</summary>

```
Enabled:
 - activity: 4.0.0
 - app_api: 5.0.2
 - bruteforcesettings: 4.0.0
 - circles: 31.0.0
 - comments: 1.21.0
 - contactsinteraction: 1.12.0
 - dashboard: 7.11.0
 - federation: 1.21.0
 - files_downloadlimit: 4.0.0
 - files_pdfviewer: 4.0.0
 - files_reminders: 1.4.0
 - files_sharing: 1.23.1
 - files_trashbin: 1.21.0
 - files_versions: 1.24.0
 - firstrunwizard: 4.0.0
 - logreader: 4.0.0
 - mail: 5.5.2
 - nextcloud_announcements: 3.0.0
 - onlyoffice: 9.10.0
 - password_policy: 3.0.0
 - photos: 4.0.0
 - privacy: 3.0.0
 - recommendations: 4.0.0
 - related_resources: 2.0.0
 - richdocuments: 8.7.5
 - serverinfo: 3.0.0
 - sharebymail: 1.21.0
 - support: 3.0.0
 - survey_client: 3.0.0
 - systemtags: 1.21.1
 - text: 5.0.0
 - updatenotification: 1.21.0
 - user_status: 1.11.0
 - weather_status: 1.11.0
 - webhook_listeners: 1.2.0
Disabled:
 - admin_audit
 - encryption
 - files_external
 - notifications: 4.0.0
 - suspicious_login
 - twofactor_nextcloud_notification
 - twofactor_totp
 - user_ldap

```
</details>

<details><summary>Configuration (config/config.php)</summary>

```
{
    "instanceid": "***REMOVED SENSITIVE VALUE***",
    "passwordsalt": "***REMOVED SENSITIVE VALUE***",
    "secret": "***REMOVED SENSITIVE VALUE***",
    "trusted_domains": [
        "docs.test-collab-site.com",
        "docs.test-collab-site.com"
    ],
    "datadirectory": "***REMOVED SENSITIVE VALUE***",
    "dbtype": "mysql",
    "version": "31.0.9.1",
    "overwrite.cli.url": "https:\/\/docs.test-collab-site.com",
    "dbname": "***REMOVED SENSITIVE VALUE***",
    "dbhost": "***REMOVED SENSITIVE VALUE***",
    "dbport": "",
    "dbtableprefix": "oc_",
    "mysql.utf8mb4": true,
    "dbuser": "***REMOVED SENSITIVE VALUE***",
    "dbpassword": "***REMOVED SENSITIVE VALUE***",
    "installed": true,
    "overwriteprotocol": "https",
    "defaultapp": "",
    "maintenance": false,
    "loglevel": "0",
    "debug": "true",
    "log_type": "file",
    "logfile": "nextcloud.log",
    "theme": "",
    "app_install_overwrite": [],
    "allow_local_remote_servers": true,
    "default_phone_region": "US",
    "memcache.local": "\\OC\\Memcache\\APCu",
    "memcache.locking": "\\OC\\Memcache\\Redis",
    "redis": {
        "host": "***REMOVED SENSITIVE VALUE***",
        "port": 0,
        "timeout": 0
    }
}
```
</details>

**Cron Configuration:** 

Mode: cron
Last: 2025-09-25T23:30:01+00:00 (243 seconds ago)


**External storages:** files_external is disabled

**Encryption:** no

**User-backends:** 
 * OC\User\Database


**Subscription:** 
 * No valid subscription key set


**Browser:** Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36

## Setup checks

<details><summary>network</summary>

 * JavaScript modules support: Unable to run check for JavaScript support. Please remedy or confirm manually if your webserver serves `.mjs` files using the JavaScript MIME type.
   To allow this check to run you have to make sure that your Web server can connect to itself. Therefore it must be able to resolve and connect to at least one of its `trusted_domains` or the `overwrite.cli.url`. This failure may be the result of a server-side DNS mismatch or outbound firewall rule.
 * Font file loading: Could not check for otf loading support. Please check manually if your webserver serves `.otf` files.
   To allow this check to run you have to make sure that your Web server can connect to itself. Therefore it must be able to resolve and connect to at least one of its `trusted_domains` or the `overwrite.cli.url`. This failure may be the result of a server-side DNS mismatch or outbound firewall rule.

</details>

<details><summary>system</summary>

 * Files reminder: The files_reminder app needs the notification app to work properly. You should either enable notifications or disable files_reminder.
 * Errors in the log: 17 warnings in the logs since September 18, 2025, 4:34:04 PM
 * Debug mode: This instance is running in debug mode. Only enable this for local development and not in production environments.
 * Maintenance window start: Server has no maintenance window start time configured. This means resource intensive daily background jobs will also be executed during your main usage time. We recommend to set it to a time of low usage, so users are less impacted by the load caused from these heavy tasks.

</details>

<details><summary>security</summary>

 * Code integrity: Some files have not passed the integrity check. List of invalid files… Rescan…
 * HTTP headers: Some headers are not set correctly on your instance
   - The `X-Robots-Tag` HTTP header is not set to `noindex,nofollow`. This is a potential security or privacy risk, as it is recommended to adjust this setting accordingly.
   - The `X-Permitted-Cross-Domain-Policies` HTTP header is not set to `none`. This is a potential security or privacy risk, as it is recommended to adjust this setting accordingly.
   

</details>

<details><summary>database</summary>

 * Database missing indices: Detected some missing optional indices. Occasionally new indices are added (by Nextcloud or installed applications) to improve database performance. Adding indices can sometimes take awhile and temporarily hurt performance so this is not done automatically during upgrades. Once the indices are added, queries to those tables should be faster. Use the command `occ db:add-missing-indices` to add them.
   Missing indices:
    "dav_shares_resourceid_type" in table "dav_shares", 
    "dav_shares_resourceid_access" in table "dav_shares", 
    "mail_messages_strucanalyz_idx" in table "mail_messages", 
    "mail_acc_prov_idx" in table "mail_accounts", 
    "mail_alias_accid_idx" in table "mail_aliases", 
    "fs_name_hash" in table "filecache", 
    "systag_objecttype" in table "systemtag_object_mapping", 
    "unique_category_per_user" in table "vcategory", 
    "mail_messages_mb_id_uid_uidx" in table "mail_messages", 
    "mail_smime_certs_uid_email_idx" in table "mail_smime_certificates", 
    "mail_trusted_senders_idx" in table "mail_trusted_senders", 
    "mail_coll_idx" in table "mail_coll_addresses", 
    "cards_prop_abid_name_value" in table "cards_properties"

</details>

<details><summary>config</summary>

 * Email test: You have not set or verified your email server configuration, yet. Please head over to the "Basic settings" in order to set them. Afterwards, use the "Send email" button below the form to verify your settings.

</details>

<details><summary>php</summary>

 * PHP getenv: PHP does not seem to be setup properly to query system environment variables. The test with getenv("PATH") only returns an empty response.

</details>

