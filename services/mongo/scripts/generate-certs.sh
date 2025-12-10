#!/bin/bash
# =============================================================================
# Generate MongoDB TLS Certificates
# =============================================================================
# Creates self-signed certificates for MongoDB TLS and keyfile for replica auth.
#
# Usage:
#   ./scripts/generate-certs.sh [domain]
#
# Examples:
#   ./scripts/generate-certs.sh                    # Uses 'mongodb.local'
#   ./scripts/generate-certs.sh mongo.example.com  # Uses custom domain
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONGO_DIR="$(dirname "$SCRIPT_DIR")"
CERTS_DIR="$MONGO_DIR/certs"

DOMAIN="${1:-mongodb.local}"
DAYS=3650  # 10 years for self-signed

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=============================================="
echo "MongoDB Certificate Generator"
echo "=============================================="
echo ""
echo "Domain: $DOMAIN"
echo "Output: $CERTS_DIR"
echo ""

# Create certs directory
mkdir -p "$CERTS_DIR"

# Check for existing certs
if [[ -f "$CERTS_DIR/mongodb.pem" ]]; then
    echo -e "${YELLOW}Certificates already exist!${NC}"
    read -p "Overwrite? (y/N) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled"
        exit 0
    fi
fi

echo "Generating keyfile for replica set authentication..."
openssl rand -base64 756 > "$CERTS_DIR/keyfile"
echo -e "${GREEN}Created: keyfile${NC}"

echo ""
echo "Generating CA certificate..."
openssl genrsa -out "$CERTS_DIR/ca.key" 4096 2>/dev/null
openssl req -x509 -new -nodes \
    -key "$CERTS_DIR/ca.key" \
    -sha256 \
    -days $DAYS \
    -out "$CERTS_DIR/ca.pem" \
    -subj "/CN=$DOMAIN/O=MongoDB/C=US" 2>/dev/null
echo -e "${GREEN}Created: ca.key, ca.pem${NC}"

echo ""
echo "Generating server certificate..."
openssl genrsa -out "$CERTS_DIR/mongodb.key" 4096 2>/dev/null

# Create CSR with SAN
cat > "$CERTS_DIR/mongodb.cnf" << EOF
[req]
default_bits = 4096
distinguished_name = req_distinguished_name
req_extensions = req_ext
prompt = no

[req_distinguished_name]
CN = $DOMAIN
O = MongoDB
C = US

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = $DOMAIN
DNS.2 = localhost
DNS.3 = mongo-primary
DNS.4 = mongo-secondary
DNS.5 = mongo-arbiter
IP.1 = 127.0.0.1
EOF

openssl req -new \
    -key "$CERTS_DIR/mongodb.key" \
    -out "$CERTS_DIR/mongodb.csr" \
    -config "$CERTS_DIR/mongodb.cnf" 2>/dev/null

openssl x509 -req \
    -in "$CERTS_DIR/mongodb.csr" \
    -CA "$CERTS_DIR/ca.pem" \
    -CAkey "$CERTS_DIR/ca.key" \
    -CAcreateserial \
    -out "$CERTS_DIR/mongodb.crt" \
    -days $DAYS \
    -sha256 \
    -extensions req_ext \
    -extfile "$CERTS_DIR/mongodb.cnf" 2>/dev/null

# Create combined PEM file
cat "$CERTS_DIR/mongodb.key" "$CERTS_DIR/mongodb.crt" > "$CERTS_DIR/mongodb.pem"
echo -e "${GREEN}Created: mongodb.key, mongodb.csr, mongodb.crt, mongodb.pem${NC}"

# Clean up temp files
rm -f "$CERTS_DIR/mongodb.cnf"

echo ""
echo "Setting permissions..."
chmod 600 "$CERTS_DIR/keyfile"
chmod 600 "$CERTS_DIR"/*.key
chmod 644 "$CERTS_DIR"/*.pem "$CERTS_DIR"/*.crt 2>/dev/null || true
echo -e "${GREEN}Permissions set${NC}"

echo ""
echo "=============================================="
echo -e "${GREEN}Certificates generated successfully!${NC}"
echo "=============================================="
echo ""
echo "Files created:"
ls -la "$CERTS_DIR"
echo ""
echo "Next steps:"
echo "  1. Copy .env.example to .env and configure"
echo "  2. Start the replica set: docker compose up -d"
echo "  3. Initialize: ./scripts/init-replica.sh"
