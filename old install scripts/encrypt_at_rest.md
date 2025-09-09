To move data after the fact, you must:
Create desired folders on your secure block storage (/mnt/docspace_data/app_data, /mnt/docspace_data/log_data, /mnt/docspace_data/lib, /mnt/docspace_data/mysql_data).
Update your docker-compose.yml or docker run commands to point volumes to these new locations.
Stop your containers, move existing data from old volumes to new locations (if you have live data), and restart containers.


You are absolutely right: it is not enough to just point the Docker volumes to your new block storage directories. You must also ensure that all configuration files—especially ds.yml and possibly others—are updated so the ONLYOFFICE components inside your containers look for their data, logs, and (for MySQL, if relevant) sockets at the correct (container-internal) paths that now point to your block storage.

Let’s break this down step by step:

## 1. **Volume Mounts (Host → Container)**

You are already clear: in your docker-compose.yml or docker run commands, you want:

- /mnt/docspace_data/app_data → /var/www/onlyoffice/Data
- /mnt/docspace_data/log_data → /var/log/onlyoffice
- /mnt/docspace_data/lib      → /var/lib/onlyoffice
- /mnt/docspace_data/mysql_data → /var/lib/mysql (for MySQL container)

So for each service in docker-compose.yml, in the volumes section, use these bindings:
```yaml
volumes:
  - /mnt/docspace_data/app_data:/var/www/onlyoffice/Data
  - /mnt/docspace_data/log_data:/var/log/onlyoffice
  - /mnt/docspace_data/lib:/var/lib/onlyoffice
# If MySQL:
  - /mnt/docspace_data/mysql_data:/var/lib/mysql
```

## 2. **Update ds.yml and Related .yml Files**

This is important!

**ONLYOFFICE DocSpace** (and DocumentServer) reads its configuration from ds.yml and possibly other YAML files. Inside these files, you will find absolute paths for various components.

- These paths MUST MATCH the container-internal paths, i.e., the right-side of your Docker volume maps.

**So:**  
- In ds.yml (and any other config), set the directories to the container-internal paths:
    ```yaml
    data_path: /var/www/onlyoffice/Data
    logs_path: /var/log/onlyoffice
    lib_path: /var/lib/onlyoffice
    ```
- Do NOT set these to your host paths like /mnt/docspace_data/xxx—the container cannot see those, only the paths inside the container.

**Summary:**  
- Right-side of Docker mapping (e.g. /var/www/onlyoffice/Data) **goes in your config files**.
- Left-side (e.g. /mnt/docspace_data/app_data) exists only on your host/droplet and is specified in Docker Compose or docker run.

## 3. **Where is ds.yml? How to Edit**

- It will either be in your persistent data directory (typically /var/www/onlyoffice/Data inside the container, so /mnt/docspace_data/app_data on your host if mapped), or in the default app directory.
- You may need to edit it either on your host file system (if it already exists), or exec into the running container to find and edit it.
    - On your host:  
      ```bash
      nano /mnt/docspace_data/app_data/ds.yml
      ```
    - Or from inside the running container:
      ```bash
      docker exec -it onlyoffice-documentserver /bin/bash
      nano /var/www/onlyoffice/Data/ds.yml
      ```

## 4. **Other .yml or Config Files**

- If you use docker-compose, you may see other YAML config files for related services (MySQL, Mail, etc.). All persistent data paths in those should match your Docker volume mounts.
- If you see things like `core.yml`, `sso.yml`, or similar, check for any absolute paths in them as well.

## 5. **Final Checks**

1. After you've set up mounts and config:
    - `docker-compose down`
    - `docker-compose up -d`
2. Check logs to ensure there are **no errors about missing directories or permissions**.

**In Summary:**

- Yes, you must update ds.yml and any other container config files to use the container-internal paths—those are mapped to your block storage by Docker.
- The Docker volume mapping (`-v host_dir:container_dir`) is the only place that specifies the host-side location (`/mnt/docspace_data/whatever`).
- The config files inside the container must only reference the container-internal path (right of the colon).

If you post your ds.yml and docker-compose.yml, I can check them for correctness!

**Bottom line:**  
You are exactly right: both Docker volume mappings AND the config file YAML paths must be aligned—with config files referencing container-internal paths, and Docker Compose (or docker run) mapping those to your host persistent storage. There is no harm in manually editing ds.yml and related files to ensure correct operation on your encrypted volume.


The **.env file** is a standard way to centrally define environment variables used by Docker containers—either for Docker Compose or directly with Docker’s `--env-file` flag. In ONLYOFFICE DocSpace/DocumentServer deployments, the .env file is not always created by default, but it plays these roles if present:

## What Role Does .env Play?

1. **Central Env Variable Storage:**  
   - The .env file allows you to set environment variables outside your `docker-compose.yml` or your direct `docker run` commands[4][2].
   - It is especially useful for secrets (like JWT keys), port settings, and paths that might change between environments.

2. **Configuration for Docker Compose:**  
   - In a Docker Compose setup, variables in `.env` can be referenced in your compose file as `${VARIABLE}`. This makes the configuration portable and easier to update.
   - For example:
     ```env
     DOCSPACE_APP_DATA=/mnt/docspace_data/app_data
     DOCSPACE_LOG_DATA=/mnt/docspace_data/log_data
     DOCSPACE_LIB=/mnt/docspace_data/lib
     DOCSPACE_MYSQL_DATA=/mnt/docspace_data/mysql_data
     ONLYOFFICE_JWT_SECRET=yoursecret
     ```
   - These can be used in `volumes:` or the `environment:` section of your `docker-compose.yml`.

3. **Direct Docker Use via --env-file:**  
   - If you run containers manually, you can use:
     ```bash
     docker run --env-file /path/to/.env ...
     ```
   - This will set all variables from the `.env` file as environment variables inside the container[1][4].

4. **Passing Configuration Down to ONLYOFFICE:**  
   - ONLYOFFICE supports certain configuration via environment variables, such as:
     - `JWT_ENABLED`, `JWT_SECRET`, `JWT_HEADER`
     - `SSL_CERTIFICATE_PATH`, `SSL_KEY_PATH`
     - `ONLYOFFICE_HTTPS_HSTS_ENABLED`, etc.[1]
   - These can either be set in the `.env` file and referenced, or set directly.

5. **Compose File Composition:**  
   - When using complex stacks (e.g., with MySQL and multiple storage locations), `.env` helps keep configurations for all paths, secrets, and settings in one editable file.

## Does ONLYOFFICE Require .env?

- **Not always by default:**  
  - If you run everything by hand and hardcode configs in your docker-compose.yml/docker run, you might not have a .env file.
  - But it’s strongly recommended for maintainability, especially in production.

## Practical Example

Your `.env` might look like this:
```env
DOCSPACE_APP_DATA=/mnt/docspace_data/app_data
DOCSPACE_LOG_DATA=/mnt/docspace_data/log_data
DOCSPACE_LIB=/mnt/docspace_data/lib
DOCSPACE_MYSQL_DATA=/mnt/docspace_data/mysql_data
ONLYOFFICE_JWT_SECRET=verysecrettoken
```
Then your `docker-compose.yml` uses:
```yaml
services:
  onlyoffice-documentserver:
    image: onlyoffice/documentserver:9.0.3.1
    volumes:
      - ${DOCSPACE_APP_DATA}:/var/www/onlyoffice/Data
      - ${DOCSPACE_LOG_DATA}:/var/log/onlyoffice
      - ${DOCSPACE_LIB}:/var/lib/onlyoffice
    environment:
      - JWT_ENABLED=true
      - JWT_SECRET=${ONLYOFFICE_JWT_SECRET}
```

## What It Does NOT Do

- Editing `.env` will only affect new containers started after the change (not running ones).
- It does not affect file-based config parameters (like paths in `ds.yml`) unless your compose or start scripts are templated to copy those values.
- If you change `.env`, you usually need to run `docker-compose up -d` (or restart) for changes to take effect.

---
**In summary:**  
The .env file is a convenient (but not mandatory) place to define environment variables for your Dockerized ONLYOFFICE stack. It maps and secures secrets, storage paths, and certain config toggles, and keeps your deployment maintainable. It should align with the internal container paths (right side of your Docker volumes), but does not automatically update config files like `ds.yml`—you must still ensure all system components are in sync[1][2][4][5].

[1] https://helpcenter.onlyoffice.com/docs/installation/docs-enterprise-install-docker.aspx
[2] https://github.com/ONLYOFFICE/Docker-DocumentServer
[3] https://forum.onlyoffice.com/t/internal-ip-instead-of-domainname-when-try-to-edit-document/11804
[4] https://hub.docker.com/r/onlyoffice/documentserver
[5] https://admin.seatable.com/installation/components/onlyoffice/
[6] https://helpcenter.onlyoffice.com/docspace/installation/docspace-community-install-script.aspx
[7] https://hub.docker.com/r/onlyoffice/communityserver
[8] https://forum.onlyoffice.com/t/doceditor-fetch-error-docker-version/10870
[9] https://haiwen.github.io/seafile-admin-docs/12.0/extension/only_office/
[10] https://community.onlyoffice.com/t/docspace-mysql-credentials/12544