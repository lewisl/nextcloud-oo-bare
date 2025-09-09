#!/bin/bash

# Step 5: Let's Encrypt SSL Certificate Setup
# Installs certbot and generates SSL certificates

set -e

echo "=== Step 5: Let's Encrypt SSL Setup ==="
echo "This installs certbot and generates SSL certificates"
echo ""

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

# Check prerequisites
if [ ! -f "/etc/nginx/sites-available/nextcloud" ]; then
    echo "Error: Nginx not configured. Run 04-nginx-config.sh first."
    exit 1
fi

if ! systemctl is-active --quiet nginx; then
    echo "Error: Nginx is not running. Check 04-nginx-config.sh"
    exit 1
fi

# Get domain name(s) from user
read -p "Enter your domain(s) separated by spaces (e.g. nextcloud.yourdomain.com www.nextcloud.yourdomain.com): " DOMAIN_INPUT

if [[ -z "$DOMAIN_INPUT" ]]; then
    echo "Error: At least one domain name is required"
    exit 1
fi

# Parse domains into array
read -ra DOMAINS <<< "$DOMAIN_INPUT"

echo "Domains to be configured:"
for domain in "${DOMAINS[@]}"; do
    if [[ -z "$domain" ]]; then
        echo "Error: Empty domain found in input"
        exit 1
    fi
    echo "  - $domain"
done

# Use first domain as primary for configuration
PRIMARY_DOMAIN="${DOMAINS[0]}"

# Get email for Let's Encrypt
read -p "Enter email for Let's Encrypt notifications: " LETSENCRYPT_EMAIL

if [[ -z "$LETSENCRYPT_EMAIL" ]]; then
    echo "Error: Email is required for Let's Encrypt"
    exit 1
fi

echo "Email: $LETSENCRYPT_EMAIL"
echo ""

# Verify domain resolves to this server
SERVER_IP=$(curl -4 -s ifconfig.me)
PRIMARY_DOMAIN_IP=$(dig +short $PRIMARY_DOMAIN | tail -n1)

echo "Server IP: $SERVER_IP"
echo "Primary domain IP: $PRIMARY_DOMAIN_IP"

if [[ "$SERVER_IP" != "$PRIMARY_DOMAIN_IP" ]]; then
    echo ""
    echo "WARNING: Primary domain $PRIMARY_DOMAIN does not resolve to this server ($SERVER_IP)"
    echo "Let's Encrypt will fail if the domain doesn't point here."
    
    # Check other domains too
    DOMAIN_MISMATCH=false
    for domain in "${DOMAINS[@]}"; do
        DOMAIN_IP=$(dig +short $domain | tail -n1)
        if [[ "$SERVER_IP" != "$DOMAIN_IP" ]]; then
            echo "Domain $domain resolves to: $DOMAIN_IP (should be: $SERVER_IP)"
            DOMAIN_MISMATCH=true
        fi
    done
    
    if [[ "$DOMAIN_MISMATCH" == "true" ]]; then
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Cancelled. Update your DNS first."
            exit 1
        fi
    fi
fi

echo ""
echo "Installing certbot..."
apt update
apt install -y certbot python3-certbot-nginx

echo "Backing up current nginx configuration..."
cp /etc/nginx/sites-available/nextcloud /etc/nginx/sites-available/nextcloud.backup.$(date +%s)

echo "Updating nginx configuration for primary domain..."
# Update server_name in nginx config with all domains
NGINX_DOMAINS=""
for domain in "${DOMAINS[@]}"; do
    NGINX_DOMAINS="$NGINX_DOMAINS $domain"
done

sed -i "s/server_name _;/server_name$NGINX_DOMAINS;/g" /etc/nginx/sites-available/nextcloud

echo "Testing nginx configuration..."
nginx -t

echo "Reloading nginx..."
systemctl reload nginx

echo ""
echo "Obtaining Let's Encrypt certificate..."
echo "Domains: ${DOMAINS[*]}"
echo "This may take a moment..."

# Build certbot command with multiple -d flags
CERTBOT_DOMAINS=""
for domain in "${DOMAINS[@]}"; do
    CERTBOT_DOMAINS="$CERTBOT_DOMAINS -d $domain"
done

echo "Running: certbot --nginx $CERTBOT_DOMAINS --email $LETSENCRYPT_EMAIL --agree-tos --non-interactive --redirect"

# Get certificate using nginx plugin
if certbot --nginx $CERTBOT_DOMAINS --email "$LETSENCRYPT_EMAIL" --agree-tos --non-interactive --redirect; then
    echo "✓ Certificate obtained successfully for all domains!"
else
    echo "✗ Certificate generation failed!"
    echo ""
    echo "Common issues:"
    echo "- Domain doesn't resolve to this server"
    echo "- Port 80/443 not accessible from internet" 
    echo "- Firewall blocking access"
    echo "- Rate limiting (too many attempts)"
    echo ""
    echo "Check the log: /var/log/letsencrypt/letsencrypt.log"
    echo ""
    echo "Restoring original configuration..."
    BACKUP=$(ls /etc/nginx/sites-available/nextcloud.backup.* | tail -1)
    cp "$BACKUP" /etc/nginx/sites-available/nextcloud
    systemctl reload nginx
    exit 1
fi

echo ""
echo "Setting up automatic renewal..."

# Create renewal script
cat > /usr/local/bin/renew-letsencrypt.sh << 'RENEW_EOF'
#!/bin/bash

# Let's Encrypt renewal script
# Run this monthly via cron

LOG_FILE="/var/log/letsencrypt-renewal.log"

echo "$(date): Starting certificate renewal check" >> "$LOG_FILE"

# Try to renew certificates
if certbot renew --quiet --nginx >> "$LOG_FILE" 2>&1; then
    echo "$(date): Renewal check completed successfully" >> "$LOG_FILE"
    # Test nginx config after renewal
    if nginx -t >> "$LOG_FILE" 2>&1; then
        systemctl reload nginx >> "$LOG_FILE" 2>&1
        echo "$(date): Nginx reloaded successfully" >> "$LOG_FILE"
    else
        echo "$(date): ERROR - Nginx config test failed after renewal" >> "$LOG_FILE"
    fi
else
    echo "$(date): ERROR - Certificate renewal failed" >> "$LOG_FILE"
    exit 1
fi

echo "$(date): Certificate renewal process completed" >> "$LOG_FILE"
RENEW_EOF

chmod +x /usr/local/bin/renew-letsencrypt.sh

# Create cron job for renewal (runs 1st of every month at 2 AM)
cat > /etc/cron.d/letsencrypt-renewal << 'CRON_EOF'
# Let's Encrypt certificate renewal
# Runs monthly on the 1st at 2 AM
0 2 1 * * root /usr/local/bin/renew-letsencrypt.sh
CRON_EOF

echo "Testing renewal process..."
if /usr/local/bin/renew-letsencrypt.sh; then
    echo "✓ Renewal script test successful"
else
    echo "✗ Renewal script test failed"
fi

# Save configuration info
cat > /root/letsencrypt-info.txt << EOL
Let's Encrypt SSL Configuration
===============================
Date: $(date)
Domains: ${DOMAINS[*]}
Primary Domain: $PRIMARY_DOMAIN
Email: $LETSENCRYPT_EMAIL

Certificate Files:
- Certificate: /etc/letsencrypt/live/$PRIMARY_DOMAIN/fullchain.pem
- Private Key: /etc/letsencrypt/live/$PRIMARY_DOMAIN/privkey.pem
- Expires: $(certbot certificates | grep "Expiry Date" | head -1)

Renewal:
- Script: /usr/local/bin/renew-letsencrypt.sh
- Cron: /etc/cron.d/letsencrypt-renewal (monthly on 1st at 2 AM)
- Log: /var/log/letsencrypt-renewal.log

Manual Renewal:
- Test: certbot renew --dry-run
- Force: certbot renew --force-renewal

Nginx Configuration:
- File: /etc/nginx/sites-available/nextcloud
- Backup: /etc/nginx/sites-available/nextcloud.backup.*
- Modified by certbot: YES

Access URLs:
$(for domain in "${DOMAINS[@]}"; do echo "- https://$domain"; done)

Next Steps:
1. Test access at any of the URLs above
2. Run step6_onlyoffice_install.sh for document editing
EOL

echo ""
echo "✓ Step 5 Complete!"
echo "Let's Encrypt SSL configured for: ${DOMAINS[*]}"
echo "Certificate expires in ~90 days (auto-renewal configured)"
echo ""
echo "Configuration saved to: /root/letsencrypt-info.txt"
echo ""
echo "Test your SSL certificates:"
for domain in "${DOMAINS[@]}"; do
    echo "curl -I https://$domain"
done
echo ""
echo "Next: Run step6_onlyoffice_install.sh"