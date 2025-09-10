#!/bin/bash

# Step 2: Dual Database Setup
# Creates Nextcloud database in MariaDB and OnlyOffice database in PostgreSQL

set -e

echo "=== Step 2: Dual Database Setup ==="
echo "This creates:"
echo "- Nextcloud database in MariaDB"
echo "- OnlyOffice database in PostgreSQL"
echo ""

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

# Check if both databases are installed
if ! command -v mysql &> /dev/null; then
    echo "Error: MariaDB not installed. Run 1_system_prep.sh first."
    exit 1
fi

if ! command -v psql &> /dev/null; then
    echo "Error: PostgreSQL not installed. Run 1_system_prep.sh first."
    exit 1
fi

echo "Starting database services..."
systemctl start mariadb

# Check if PostgreSQL cluster exists, create if needed
echo "Checking PostgreSQL cluster..."
if ! pg_lsclusters | grep -q "16.*main"; then
    echo "Creating PostgreSQL cluster 16/main..."
    pg_createcluster 16 main
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create PostgreSQL cluster"
        exit 1
    fi
fi

# Start PostgreSQL cluster
echo "Starting PostgreSQL cluster..."
pg_ctlcluster 16 main start || {
    echo "Error: Failed to start PostgreSQL cluster"
    exit 1
}

# Enable PostgreSQL service
systemctl enable postgresql

# Wait for services to start
sleep 5

# Verify PostgreSQL is running
if ! pg_lsclusters | grep -q "16.*main.*online"; then
    echo "Error: PostgreSQL cluster is not online"
    echo "Cluster status:"
    pg_lsclusters
    exit 1
fi

echo "PostgreSQL cluster is online"

# Generate random passwords
NEXTCLOUD_DB_PASSWORD=$(openssl rand -base64 24)
ONLYOFFICE_DB_PASSWORD=$(openssl rand -base64 24)

echo "Generated database passwords:"
echo "  Nextcloud (MariaDB): $NEXTCLOUD_DB_PASSWORD"
echo "  OnlyOffice (PostgreSQL): $ONLYOFFICE_DB_PASSWORD"

echo ""
echo "=== Configuring MariaDB for Nextcloud ==="

# Create Nextcloud database and user in MariaDB
mysql -e "CREATE DATABASE IF NOT EXISTS nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;" || {
    echo "Error: Failed to create nextcloud database"
    exit 1
}

# Check if user exists and handle accordingly
if mysql -e "SELECT User FROM mysql.user WHERE User='nextcloud' AND Host='localhost';" | grep -q nextcloud; then
    echo "Nextcloud user already exists. Updating password..."
    mysql -e "ALTER USER 'nextcloud'@'localhost' IDENTIFIED BY '$NEXTCLOUD_DB_PASSWORD';" || {
        echo "Error: Failed to update nextcloud user password"
        exit 1
    }
else
    echo "Creating nextcloud user..."
    mysql -e "CREATE USER 'nextcloud'@'localhost' IDENTIFIED BY '$NEXTCLOUD_DB_PASSWORD';" || {
        echo "Error: Failed to create nextcloud user"
        exit 1
    }
fi

mysql -e "GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

echo "MariaDB configured: database 'nextcloud' with user 'nextcloud'"

echo ""
echo "=== Configuring PostgreSQL for OnlyOffice ==="

# Configure PostgreSQL for OnlyOffice
# Check if user exists and handle accordingly
if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='onlyoffice'" | grep -q 1; then
    echo "OnlyOffice user already exists. Updating password..."
    sudo -u postgres psql -c "ALTER USER onlyoffice WITH PASSWORD '$ONLYOFFICE_DB_PASSWORD';" || {
        echo "Error: Failed to update onlyoffice user password"
        exit 1
    }
else
    echo "Creating onlyoffice user..."
    sudo -u postgres psql -c "CREATE USER onlyoffice WITH PASSWORD '$ONLYOFFICE_DB_PASSWORD';" || {
        echo "Error: Failed to create onlyoffice user"
        exit 1
    }
fi

# Check if database exists and create if needed
if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw onlyoffice; then
    echo "OnlyOffice database already exists."
else
    echo "Creating onlyoffice database..."
    sudo -u postgres psql -c "CREATE DATABASE onlyoffice OWNER onlyoffice;" || {
        echo "Error: Failed to create onlyoffice database"
        exit 1
    }
fi

sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE onlyoffice TO onlyoffice;" || {
    echo "Error: Failed to grant privileges to onlyoffice user"
    exit 1
}

echo "PostgreSQL configured: database 'onlyoffice' with user 'onlyoffice'"

echo ""
echo "=== Testing database connections ==="

# Test MariaDB connection
if mysql -u nextcloud -p$NEXTCLOUD_DB_PASSWORD -e "SELECT 1;" nextcloud >/dev/null 2>&1; then
    echo "MariaDB connection test: SUCCESS"
else
    echo "MariaDB connection test: FAILED"
    exit 1
fi

# Test PostgreSQL connection
if PGPASSWORD=$ONLYOFFICE_DB_PASSWORD psql -h localhost -U onlyoffice -d onlyoffice -c "SELECT 1;" >/dev/null 2>&1; then
    echo "PostgreSQL connection test: SUCCESS"
else
    echo "PostgreSQL connection test: FAILED"
    exit 1
fi

# Save credentials
cat > /root/nextcloud_db_credentials.txt << EOL
Database Credentials for Nextcloud + OnlyOffice Setup
=====================================================

Nextcloud Database (MariaDB)
----------------------------
Host: localhost
Database: nextcloud
Username: nextcloud
Password: $NEXTCLOUD_DB_PASSWORD
Connection test: mysql -u nextcloud -p nextcloud

OnlyOffice Database (PostgreSQL)
---------------------------------
Host: localhost
Database: onlyoffice
Username: onlyoffice
Password: $ONLYOFFICE_DB_PASSWORD
Connection test: PGPASSWORD='$ONLYOFFICE_DB_PASSWORD' psql -h localhost -U onlyoffice -d onlyoffice

System Information
------------------
MariaDB Status: $(systemctl is-active mariadb)
PostgreSQL Status: $(systemctl is-active postgresql)
Created: $(date)

Notes:
- MariaDB runs on port 3306
- PostgreSQL runs on port 5432
- Both databases can run simultaneously
EOL

echo ""
echo "Step 2 Complete!"
echo "Both database systems configured:"
echo "MariaDB: nextcloud database ready"  
echo "PostgreSQL: onlyoffice database ready"
echo "Credentials saved to: /root/nextcloud_db_credentials.txt"
echo ""
echo "Database status:"
echo "- MariaDB: $(systemctl is-active mariadb)"
echo "- PostgreSQL: $(systemctl is-active postgresql)"
echo ""
echo "Next: Run 3_nextcloud.sh"