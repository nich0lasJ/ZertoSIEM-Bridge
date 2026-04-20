#!/usr/bin/env bash
# entrypoint.sh — Zerto SIEM Bridge
# Handles cert generation (if not pre-mounted), config templating, and FluentD launch.
set -euo pipefail

CERT_DIR=/etc/fluent/certs
SERVER_KEY=$CERT_DIR/server.key
SERVER_CRT=$CERT_DIR/server.crt
CA_CRT=$CERT_DIR/ca.crt
CONF=/etc/fluent/fluent.conf

log()  { printf "[+] %s\n" "$*"; }
warn() { printf "[!] %s\n" "$*" >&2; }

# ---------------------------------------------------------------
# 1. TLS: generate self-signed cert if not pre-mounted
# ---------------------------------------------------------------
if [ "${TLS_ENABLED:-true}" = "true" ]; then
  if [ ! -f "$SERVER_KEY" ] || [ ! -f "$SERVER_CRT" ]; then
    log "No certs found in $CERT_DIR — generating self-signed cert (not for production)"

    if [ -z "${FLUENTD_TLS_KEY_PASSPHRASE:-}" ]; then
      warn "FLUENTD_TLS_KEY_PASSPHRASE is not set — generating random passphrase"
      FLUENTD_TLS_KEY_PASSPHRASE=$(openssl rand -base64 48 | tr -d '\n')
      export FLUENTD_TLS_KEY_PASSPHRASE
    fi

    openssl genpkey -algorithm RSA \
      -pkeyopt rsa_keygen_bits:4096 \
      -aes256 -pass pass:"${FLUENTD_TLS_KEY_PASSPHRASE}" \
      -out "$SERVER_KEY" 2>/dev/null

    openssl req -new -x509 -days 3650 \
      -key "$SERVER_KEY" -passin pass:"${FLUENTD_TLS_KEY_PASSPHRASE}" \
      -subj "/CN=zerto-siem-bridge" \
      -out "$SERVER_CRT" 2>/dev/null

    cp "$SERVER_CRT" "$CA_CRT"
    log "Self-signed cert written to $CERT_DIR"
    log "For production: mount a CA-signed cert via the ./certs volume"
  else
    log "Using pre-mounted TLS certs from $CERT_DIR"
  fi

  chmod 0640 "$SERVER_KEY"
fi

# ---------------------------------------------------------------
# 2. Validate at least one SIEM output is enabled
# ---------------------------------------------------------------
ENABLED_SIEM=0
for v in SIEM_ELASTIC_ENABLED SIEM_SPLUNK_ENABLED SIEM_SENTINEL_ENABLED SIEM_SENTINELONE_ENABLED; do
  [ "${!v:-false}" = "true" ] && ENABLED_SIEM=$((ENABLED_SIEM + 1))
done

if [ "$ENABLED_SIEM" -eq 0 ]; then
  warn "No SIEM outputs are enabled. Set at least one SIEM_*_ENABLED=true in your .env"
  warn "Logs will be written to stdout only."
fi

# ---------------------------------------------------------------
# 3. Write the dynamic outputs include file from env vars
# ---------------------------------------------------------------
OUTPUTS_ACTIVE=/etc/fluent/outputs_active.conf
> "$OUTPUTS_ACTIVE"

[ "${SIEM_ELASTIC_ENABLED:-false}"      = "true" ] && cat /etc/fluent/outputs/elastic.conf      >> "$OUTPUTS_ACTIVE"
[ "${SIEM_SPLUNK_ENABLED:-false}"       = "true" ] && cat /etc/fluent/outputs/splunk.conf       >> "$OUTPUTS_ACTIVE"
[ "${SIEM_SENTINEL_ENABLED:-false}"     = "true" ] && cat /etc/fluent/outputs/sentinel.conf     >> "$OUTPUTS_ACTIVE"
[ "${SIEM_SENTINELONE_ENABLED:-false}"  = "true" ] && cat /etc/fluent/outputs/sentinelone.conf  >> "$OUTPUTS_ACTIVE"

# Always add stdout as a fallback (remove for production if noisy)
cat >> "$OUTPUTS_ACTIVE" <<'EOF'

<store>
  @type stdout
</store>
EOF

log "Active SIEM outputs: $ENABLED_SIEM"
log "Starting FluentD..."

exec fluentd -c "$CONF" --log-level info "$@"
