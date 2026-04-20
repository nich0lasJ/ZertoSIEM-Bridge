#!/usr/bin/env bash
# gen-certs.sh — Generate a production-ready TLS cert for Zerto SIEM Bridge
# Run this outside Docker, then mount ./certs into the container.
#
# Usage: ./scripts/gen-certs.sh [CN] [IP_SAN]
# Example: ./scripts/gen-certs.sh syslog.mycompany.com 10.0.0.50
set -euo pipefail

CN="${1:-zerto-siem-bridge}"
IP_SAN="${2:-}"
CERT_DIR="$(dirname "$0")/../certs"
mkdir -p "$CERT_DIR"

log()  { printf "[+] %s\n" "$*"; }
warn() { printf "[!] %s\n" "$*" >&2; }

# ---------------------------------------------------------------
# Passphrase
# ---------------------------------------------------------------
if [ -f "$CERT_DIR/.passphrase" ]; then
  PASSPHRASE=$(cat "$CERT_DIR/.passphrase")
  log "Using existing passphrase from $CERT_DIR/.passphrase"
else
  PASSPHRASE=$(openssl rand -base64 48 | tr -d '\n')
  echo "$PASSPHRASE" > "$CERT_DIR/.passphrase"
  chmod 0600 "$CERT_DIR/.passphrase"
  log "Generated new passphrase, saved to $CERT_DIR/.passphrase"
fi

# ---------------------------------------------------------------
# Private key (4096-bit RSA, AES-256 encrypted)
# ---------------------------------------------------------------
log "Generating 4096-bit RSA private key..."
openssl genpkey -algorithm RSA \
  -pkeyopt rsa_keygen_bits:4096 \
  -aes256 -pass pass:"$PASSPHRASE" \
  -out "$CERT_DIR/server.key" 2>/dev/null
chmod 0600 "$CERT_DIR/server.key"

# ---------------------------------------------------------------
# CSR config with SANs
# ---------------------------------------------------------------
SAN_LINE="DNS:${CN}"
[ -n "$IP_SAN" ] && SAN_LINE="${SAN_LINE},IP:${IP_SAN}"

cat > "$CERT_DIR/csr.conf" <<EOF
[req]
distinguished_name = dn
req_extensions = v3_req
prompt = no

[dn]
CN = $CN
O  = Zerto SIEM Bridge
OU = Security

[v3_req]
subjectAltName = $SAN_LINE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
EOF

# ---------------------------------------------------------------
# CSR
# ---------------------------------------------------------------
log "Generating CSR for CN=$CN (SANs: $SAN_LINE)..."
openssl req -new -sha256 \
  -key "$CERT_DIR/server.key" \
  -passin pass:"$PASSPHRASE" \
  -config "$CERT_DIR/csr.conf" \
  -out "$CERT_DIR/server.csr"

log "CSR written to $CERT_DIR/server.csr"
log ""
log "Next steps:"
log "  1. Submit $CERT_DIR/server.csr to your CA"
log "  2. Save the signed cert as $CERT_DIR/server.crt"
log "  3. Save the CA cert as $CERT_DIR/ca.crt"
log "  4. Add FLUENTD_TLS_KEY_PASSPHRASE=$(cat "$CERT_DIR/.passphrase") to your .env"
log "  5. Run: docker compose up -d"
