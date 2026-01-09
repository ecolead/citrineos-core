#!/bin/bash

# Script to obtain Let's Encrypt certificates and update CitrineOS
# This script will:
# 1. Use certbot to get Let's Encrypt certificates
# 2. Copy them to the CitrineOS certificate directory
# 3. Automatically call the update-certs-api.sh script

set -e

# ============================================
# CONFIGURATION - Edit these variables
# ============================================
DOMAIN="csms.yourdomain.com"
EMAIL="your-email@example.com"
# ============================================

CERT_DIR="Server/dist/assets/certificates"
LETSENCRYPT_DIR="/etc/letsencrypt/live/$DOMAIN"

echo "🔐 Let's Encrypt Certificate Setup for CitrineOS"
echo "=================================================="
echo ""
echo "Domain: $DOMAIN"
echo "Email: $EMAIL"
echo ""

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then 
    echo "⚠️  This script needs sudo privileges to run certbot"
    echo "    Re-running with sudo..."
    echo ""
    sudo "$0" "$@"
    exit $?
fi

# Check if certbot is installed
if ! command -v certbot &> /dev/null; then
    echo "📦 Certbot not found. Installing..."
    apt update
    apt install -y certbot
    echo "✅ Certbot installed"
    echo ""
fi

# Check if domain and email are configured
if [ "$DOMAIN" = "csms.yourdomain.com" ] || [ "$EMAIL" = "your-email@example.com" ]; then
    echo "❌ Error: Please edit this script and set your DOMAIN and EMAIL"
    echo ""
    echo "Edit the variables at the top of the script:"
    echo "  DOMAIN=\"your-actual-domain.com\""
    echo "  EMAIL=\"your-actual-email@example.com\""
    exit 1
fi

# Stop any service using port 80 (required for certbot standalone)
echo "🔍 Checking if port 80 is available..."
if lsof -Pi :80 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "⚠️  Port 80 is in use. Certbot standalone mode requires port 80."
    echo "    You may need to temporarily stop your web server."
    read -p "    Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Obtain or renew certificate (RSA for OCPP cipher suite compatibility)
echo "📜 Obtaining Let's Encrypt RSA certificate..."
echo "   (RSA certificate required for all 4 OCPP 2.0.1 cipher suites)"
echo ""

certbot certonly --standalone \
    -d "$DOMAIN" \
    --email "$EMAIL" \
    --agree-tos \
    --non-interactive \
    --preferred-challenges http \
    --cert-name "$DOMAIN" \
    --key-type rsa \
    --rsa-key-size 2048 \
    || {
        echo ""
        echo "❌ Failed to obtain certificate from Let's Encrypt"
        echo ""
        echo "Common issues:"
        echo "  1. Domain doesn't point to this server"
        echo "  2. Port 80 is blocked by firewall"
        echo "  3. Domain is not publicly accessible"
        echo ""
        echo "For testing, you can use the staging server:"
        echo "  Add --staging flag to certbot command"
        exit 1
    }

echo ""
echo "✅ Certificate obtained successfully!"
echo ""

# Create backup of existing certificates
if [ -d "$CERT_DIR" ]; then
    BACKUP_DIR="${CERT_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
    echo "💾 Backing up existing certificates to $BACKUP_DIR"
    cp -r "$CERT_DIR" "$BACKUP_DIR"
fi

# Create certificate directory if it doesn't exist
mkdir -p "$CERT_DIR"

# Copy Let's Encrypt certificates to CitrineOS directory
echo "📋 Copying certificates to CitrineOS..."

cp "$LETSENCRYPT_DIR/privkey.pem" "$CERT_DIR/leafKey.pem"
cp "$LETSENCRYPT_DIR/fullchain.pem" "$CERT_DIR/certChain.pem"

# Download Let's Encrypt root CA
echo "📥 Downloading Let's Encrypt root CA..."
wget -q -O "$CERT_DIR/rootCertificate.pem" \
    https://letsencrypt.org/certs/isrgrootx1.pem

# Extract individual certificates from fullchain
echo "✂️  Extracting leaf and intermediate certificates..."

# Extract leaf certificate (first cert in chain)
openssl x509 -in "$CERT_DIR/certChain.pem" -out "$CERT_DIR/leafCertificate.pem"

# Extract intermediate certificate (rest of chain)
awk '/BEGIN CERTIFICATE/{n++} n>1' "$LETSENCRYPT_DIR/fullchain.pem" > "$CERT_DIR/subCACertificate.pem"

# Fix ownership (change to the actual user running the script originally)
ACTUAL_USER=$(logname 2>/dev/null || echo $SUDO_USER)
if [ -n "$ACTUAL_USER" ]; then
    chown -R "$ACTUAL_USER:$ACTUAL_USER" "$CERT_DIR"
fi

echo ""
echo "✅ Certificates copied successfully!"
echo ""
echo "Certificate details:"
openssl x509 -in "$CERT_DIR/leafCertificate.pem" -noout -subject -dates
echo ""

# Run the update script to push certificates to CitrineOS
echo "🔄 Updating CitrineOS with new certificates..."
echo ""

# Switch back to the original user to run the update script
if [ -n "$ACTUAL_USER" ]; then
    sudo -u "$ACTUAL_USER" bash -c "cd /home/$ACTUAL_USER/obelisk/citrineos-core && ./update-certs-api.sh"
else
    cd "$(dirname "$0")"
    ./update-certs.sh
fi

echo ""
echo "✨ All done!"
echo ""
echo "� OCPP 2.0.1 Cipher Suite Configuration"
echo "========================================"
echo ""
echo "The RSA certificate supports all 4 required OCPP cipher suites:"
echo "  ✅ TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
echo "  ✅ TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
echo "  ✅ TLS_RSA_WITH_AES_128_GCM_SHA256"
echo "  ✅ TLS_RSA_WITH_AES_256_GCM_SHA384"
echo ""
echo "�📝 Configure CitrineOS WebSocket Server:"
echo ""
echo "   Edit: Server/src/config/envs/production.ts (or your config file)"
echo "   Add to websocket server configuration:"
echo ""
echo "   ciphers: 'ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:AES128-GCM-SHA256:AES256-GCM-SHA384'"
echo "   minVersion: 'TLSv1.2'"
echo ""
echo "📝 Next steps:"
echo "   1. Restart CitrineOS to apply new certificates"
echo "   2. Update charging stations to connect to: wss://$DOMAIN:8443"
echo "   3. Set up auto-renewal with cron:"
echo "      sudo crontab -e"
echo "      Add: 0 2 * * * $(realpath "$0") && $(realpath "$(dirname "$0")/update-certs-api.sh")"
echo ""
echo "   4. Test renewal manually:"
echo "      sudo certbot renew --dry-run"
echo ""
echo "🧪 Test cipher suites after CitrineOS restart:"
echo "   openssl s_client -connect $DOMAIN:8443 -cipher 'ECDHE-RSA-AES128-GCM-SHA256' -tls1_2"
echo "   openssl s_client -connect $DOMAIN:8443 -cipher 'AES128-GCM-SHA256' -tls1_2"
echo ""

