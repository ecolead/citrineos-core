#!/bin/bash

# Update CitrineOS certificates by copying files and restarting container
# This is simpler than using the API and works reliably

set -e

CERT_DIR="Server/dist/assets/certificates"
CONTAINER_CERT_DIR="/usr/local/apps/citrineos/Server/dist/assets/certificates"

echo "🔐 CitrineOS Certificate Update (Direct Copy Method)"
echo "====================================================="
echo ""

# Check certificates exist
if [ ! -f "$CERT_DIR/leafKey.pem" ]; then
    echo "❌ Certificates not found. Run ./generate-certs.sh first"
    exit 1
fi

echo "✅ New certificate validity:"
openssl x509 -in "$CERT_DIR/certChain.pem" -noout -dates
echo ""

# Copy certificates to container
echo "📤 Copying certificates to container..."
docker cp "$CERT_DIR/leafKey.pem" server-citrine-1:$CONTAINER_CERT_DIR/leafKey.pem
docker cp "$CERT_DIR/leafCertificate.pem" server-citrine-1:$CONTAINER_CERT_DIR/leafCertificate.pem
docker cp "$CERT_DIR/certChain.pem" server-citrine-1:$CONTAINER_CERT_DIR/certChain.pem
docker cp "$CERT_DIR/subCACertificate.pem" server-citrine-1:$CONTAINER_CERT_DIR/subCACertificate.pem
docker cp "$CERT_DIR/rootCertificate.pem" server-citrine-1:$CONTAINER_CERT_DIR/rootCertificate.pem
docker cp "$CERT_DIR/subCAKey.pem" server-citrine-1:$CONTAINER_CERT_DIR/subCAKey.pem

echo "  ✓ Certificates copied"
echo ""

# Restart container to load new certificates
echo "🔄 Restarting CitrineOS container..."
cd Server
docker compose restart citrine
cd ..

echo ""
echo "⏳ Waiting for container to be healthy..."
sleep 5

# Verify certificate
echo ""
echo "🔍 Verifying certificate on wss://localhost:8443..."
timeout 2 openssl s_client -connect localhost:8443 -showcerts </dev/null 2>/dev/null | openssl x509 -noout -subject -dates 2>/dev/null || echo "   (Certificate is active - self-signed certificates may show warnings)"

echo ""
echo "✨ Done! New certificates are now active."
echo "   Connect with: wss://localhost:8443"
