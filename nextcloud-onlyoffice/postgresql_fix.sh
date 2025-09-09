#!/bin/bash

# Quick PostgreSQL fix script

echo "=== PostgreSQL Diagnosis and Fix ==="

echo "1. Checking PostgreSQL service status:"
systemctl status postgresql --no-pager -l

echo ""
echo "2. Checking if PostgreSQL is running:"
ps aux | grep postgres | grep -v grep || echo "No PostgreSQL processes found"

echo ""
echo "3. Checking PostgreSQL socket directory:"
ls -la /var/run/postgresql/ 2>/dev/null || echo "Socket directory doesn't exist"

echo ""
echo "4. Checking PostgreSQL version and cluster:"
pg_lsclusters 2>/dev/null || echo "pg_lsclusters not available"

echo ""
echo "5. Attempting to start PostgreSQL cluster manually:"
if command -v pg_ctlcluster >/dev/null 2>&1; then
    echo "Starting main cluster..."
    pg_ctlcluster 16 main start || echo "Cluster start failed"
else
    echo "pg_ctlcluster not available, trying systemctl..."
    systemctl start postgresql
fi

echo ""
echo "6. Final status check:"
systemctl is-active postgresql && echo "PostgreSQL is now active" || echo "PostgreSQL still not active"

echo ""
echo "7. Testing connection:"
sudo -u postgres psql -c "SELECT version();" 2>/dev/null && echo "Connection works!" || echo "Connection still failed"