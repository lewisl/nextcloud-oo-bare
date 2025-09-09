#!/bin/bash

# Step 2: Dual Database Setup (Revised)
# Creates both Nextcloud (MariaDB) and OnlyOffice (PostgreSQL) databases

set -e

echo "=== Step 2: Dual Database Setup ==="
echo "This creates:"
echo "  📁 Nextcloud database (MariaDB)"
echo "  🐘 OnlyOffice database (PostgreSQL)"
echo ""

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

# Check if both databases are installed
if ! command -v mysql &> /dev/null; then
    echo "Error: MariaDB not installed. Run step1_system_prep.sh first."
    exit 1
fi

if ! command -v psql &> /dev/null; then
    echo "Error: PostgreSQL not installed. Run step1_system_prep.sh first."
    exit 1
fi

echo "Starting database services..."
systemctl start mariadb postgresql

# Generate random passwords
NEXTCLOUD_DB_PASSWORD=$(openssl rand -base64 24)
ONLYOFFICE_DB_PASSWORD=$(openssl rand -base64 24)

echo "Generated database passwords:"
echo "  Nextcloud (MariaDB): $NEXTCLOUD_DB_PASSWORD"
echo "  OnlyOffice (PostgreSQL): $ONLYOFFICE_DB_PASSWORD"
echo ""

echo "=== Configuring MariaDB for Nextcloud ==="
# Create Nextcloud database and user in MariaDB
mysql -e "CREATE DATABASE IF NOT EXISTS nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;" 2>/dev/null || {
    echo "Nextcloud database creation failed. May already exist."
}

mysql -e "CREATE USER IF NOT EXISTS 'nextcloud'@'localhost' IDENTIFIED BY '$NEXTCLOUD_DB_PASSWORD';" 2>/dev/null || {
    echo "Nextcloud user creation failed. May already exist. Updating password..."
    mysql -e "ALTER USER 'nextcloud'@'localhost' IDENTIFIED BY '$NEXTCLOUD_DB_PASSWORD';"
}

mysql -e "GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

echo "✅ MariaDB configured for Nextcloud"

echo ""
echo "=== Configuring PostgreSQL for OnlyOffice ==="

# Create OnlyOffice database and user in PostgreSQL
sudo -u postgres psql -c "CREATE DATABASE onlyoffice;" 2>/dev/null || {
    echo "OnlyOffice database may already exist, dropping and recreating..."
    sudo -u postgres psql -c "DROP DATABASE IF EXISTS onlyoffice;"
    sudo -u postgres psql -c "CREATE DATABASE onlyoffice;"
}

sudo -u postgres psql -c "CREATE USER onlyoffice WITH PASSWORD '$ONLYOFFICE_DB_PASSWORD';" 2>/dev/null || {
    echo "OnlyOffice user may already exist, updating password..."
    sudo -u postgres psql -c "ALTER USER onlyoffice WITH PASSWORD '$ONLYOFFICE_DB_PASSWORD';"
}

sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE onlyoffice TO onlyoffice;"
sudo -u postgres psql -c "ALTER DATABASE onlyoffice OWNER TO onlyoffice;"

echo "✅ PostgreSQL configured for OnlyOffice"

# Test database connections
echo ""
echo "Testing database connections..."

echo -n "  MariaDB connection: "
if mysql -u nextcloud -p$NEXTCLOUD_DB_PASSWORD -e "SELECT 1;" nextcloud > /dev/null 2>&1; then
    echo "✅ Working"
else
    echo "❌ Failed"
    exit 1
fi

echo -n "  PostgreSQL connection: "
if PGPASSWORD=$ONLYOFFICE_DB_PASSWORD psql -h localhost -U onlyoffice -d onlyoffice -c "SELECT 1;" > /dev/null 2>&1; then
    echo "✅ Working"
else
    echo "❌ Failed"
    exit 1
fi

# Save credentials
cat > /root/nextcloud-db-credentials.txt << EOL
Nextcloud Database (MariaDB)
============================
Host: localhost
Port: 3306
Database: nextcloud
Username: nextcloud
Password: $NEXTCLOUD_DB_PASSWORD

OnlyOffice Database (PostgreSQL)  
=================================
Host: localhost
Port: 5432
Database: onlyoffice
Username: onlyoffice
Password: $ONLYOFFICE_DB_PASSWORD

Created: $(date)

Test Commands:
- MariaDB: mysql -u nextcloud -p nextcloud
- PostgreSQL: PGPASSWORD='$ONLYOFFICE_DB_PASSWORD' psql -h localhost -U onlyoffice -d onlyoffice
EOL

echo ""
echo "Both database systems configured:"
echo "📁 MariaDB: nextcloud database ready"  
echo "🐘 PostgreSQL: onlyoffice database ready"
echo "💾 Credentials saved to: /root/nextcloud-db-credentials.txt"
echo ""
echo "Database status:"
echo "- MariaDB: $(systemctl is-active mariadb)"
echo "- PostgreSQL: $(systemctl is-active postgresql)"
echo ""
echo "Next: Run step3_nextcloud_install.sh"