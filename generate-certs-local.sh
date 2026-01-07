#!/bin/bash

# Script to generate self-signed certificates for CitrineOS testing
# This creates a certificate chain with Root CA -> Sub CA -> Leaf Certificate

CERT_DIR="Server/dist/assets/certificates"
DAYS_VALID=365

echo "Generating certificates for CitrineOS..."

# # Create backup of existing certificates
# if [ -d "$CERT_DIR" ]; then
#     BACKUP_DIR="${CERT_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
#     echo "Backing up existing certificates to $BACKUP_DIR"
#     cp -r "$CERT_DIR" "$BACKUP_DIR"
# fi

mkdir -p "$CERT_DIR"
cd "$CERT_DIR"

# 1. Generate Root CA private key (EC P-256)
echo "1. Generating Root CA private key..."
openssl ecparam -name prime256v1 -genkey -noout -out rootKey.pem

# 2. Generate Root CA certificate
echo "2. Generating Root CA certificate..."
openssl req -new -x509 -key rootKey.pem -out rootCertificate.pem -days $DAYS_VALID \
    -subj "/C=US/O=CitrineOS/CN=CitrineOS Root CA"

# 3. Generate Sub CA private key
echo "3. Generating Sub CA private key..."
openssl ecparam -name prime256v1 -genkey -noout -out subCAKey.pem

# 4. Generate Sub CA certificate signing request
echo "4. Generating Sub CA CSR..."
openssl req -new -key subCAKey.pem -out subCA.csr \
    -subj "/C=US/O=CitrineOS/CN=CitrineOS Sub CA"

# 5. Sign Sub CA certificate with Root CA
echo "5. Signing Sub CA certificate..."
cat > subca_ext.cnf << EOF
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
EOF

openssl x509 -req -in subCA.csr -CA rootCertificate.pem -CAkey rootKey.pem \
    -CAcreateserial -out subCACertificate.pem -days $DAYS_VALID \
    -extfile subca_ext.cnf

# 6. Generate Leaf (Server) private key
echo "6. Generating Leaf certificate private key..."
openssl ecparam -name prime256v1 -genkey -noout -out leafKey.pem

# 7. Generate Leaf certificate signing request
echo "7. Generating Leaf CSR..."
openssl req -new -key leafKey.pem -out leaf.csr \
    -subj "/C=US/O=CitrineOS/CN=localhost"

# 8. Sign Leaf certificate with Sub CA
echo "8. Signing Leaf certificate..."
cat > leaf_ext.cnf << EOF
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment,keyCertSign
extendedKeyUsage = serverAuth,clientAuth
subjectAltName = DNS:localhost,DNS:*.localhost,IP:127.0.0.1
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
EOF

openssl x509 -req -in leaf.csr -CA subCACertificate.pem -CAkey subCAKey.pem \
    -CAcreateserial -out leafCertificate.pem -days $DAYS_VALID \
    -extfile leaf_ext.cnf

# 9. Create certificate chain (Leaf + Sub CA)
echo "9. Creating certificate chain..."
cat leafCertificate.pem subCACertificate.pem > certChain.pem

# Clean up temporary files
rm -f subCA.csr leaf.csr subca_ext.cnf leaf_ext.cnf *.srl

echo ""
echo "✅ Certificate generation complete!"
echo ""
echo "Generated files:"
echo "  - rootKey.pem                    (Root CA private key)"
echo "  - rootCertificate.pem            (Root CA certificate)"
echo "  - subCAKey.pem                   (Sub CA private key - for mTLS)"
echo "  - subCACertificate.pem           (Sub CA certificate)"
echo "  - leafKey.pem                    (Server private key)"
echo "  - leafCertificate.pem            (Server certificate)"
echo "  - certChain.pem                  (Server cert + Sub CA chain)"
echo ""
echo "Certificate validity:"
openssl x509 -in certChain.pem -noout -dates
echo ""
echo "To verify the chain:"
echo "  openssl verify -CAfile rootCertificate.pem -untrusted subCACertificate.pem leafCertificate.pem"
echo ""

# Automatically update CitrineOS with new certificates
echo "🔄 Updating CitrineOS with new certificates..."
echo ""

cd ../../../..
if [ -f "./update-certs-simple.sh" ]; then
    ./update-certs.sh
else
    echo "⚠️  update-certs-simple.sh not found in current directory"
    echo "   You can manually update CitrineOS by running:"
    echo "   ./update-certs-api.sh"
fi
