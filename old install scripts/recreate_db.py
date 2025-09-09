import re
import glob

def parse_env_file(filename):
    creds = {}
    with open(filename) as f:
        for line in f:
            if '=' in line and not line.strip().startswith('#'):
                k, v = line.strip().split('=', 1)
                creds[k] = v
    return creds

def parse_yml_file(filename):
    creds = {}
    with open(filename) as f:
        parent = None
        for line in f:
            line = line.strip()
            if re.match(r'^\w+:$', line):
                parent = line.rstrip(':')
            m = re.match(r'^(\w+):\s*(.+)$', line)
            if m:
                k, v = m.group(1), m.group(2)
                if parent == 'mysql' or parent == 'database':
                    creds[k] = v
                elif k in ['user', 'password', 'name', 'db_user', 'db_pass', 'db_name']:
                    creds[k] = v
    return creds

env_creds = parse_env_file('.env')
db_creds = {}
for fname in glob.glob('*.yml'):
    db_creds.update(parse_yml_file(fname))

# Map all keys to the container's expected names
result = {
    'database': env_creds.get('MYSQL_DATABASE') or db_creds.get('name') or db_creds.get('db_name'),
    'user': env_creds.get('MYSQL_USER') or db_creds.get('user') or db_creds.get('db_user'),
    'password': env_creds.get('MYSQL_PASSWORD') or db_creds.get('password') or db_creds.get('db_pass'),
    'root_password': env_creds.get('MYSQL_ROOT_PASSWORD')
}
print(result)


# an outcome
# {'database': 'docspace', 'user': '${PRODUCT}_user', 'password': 'JO8PWS9l9H53T1UZppEe', 'root_password': 'tFp7uKGHzB1hGCWHES1N'}

""" 
docker run -d \
  --name onlyoffice-mysql \
  -e MYSQL_ROOT_PASSWORD=tFp7uKGHzB1hGCWHES1N \
  -e MYSQL_DATABASE=docspace \
  -e MYSQL_USER=docspace_user \
  -e MYSQL_PASSWORD=JO8PWS9l9H53T1UZppEe \
  -v /mnt/docspace_data/mysql_data:/var/lib/mysql \
  mysql:8 """