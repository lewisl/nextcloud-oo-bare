#!/bin/bash

# Run the database setup script with debug output

echo "=== Running Database Setup with Debug Output ==="
echo ""
echo "This will show each command as it executes."
echo "Look for the last command that runs before the script stops."
echo ""
read -p "Press Enter to continue..."

# Run with debug output
bash -x /srv/collab/src/02_database_setup_dual_domain.sh
