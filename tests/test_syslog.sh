#!/usr/bin/env bash
# test_syslog.sh — Send fixture CEF messages and validate container output
# Usage: ./tests/test_syslog.sh [host] [port]
#
# Prerequisites:
#   docker compose up -d   (container must be running)
#   nc (netcat)            (for sending UDP syslog)
set -euo pipefail

HOST="${1:-127.0.0.1}"
PORT="${2:-514}"
CONTAINER="${CONTAINER_NAME:-zerto-siem-bridge}"
FIXTURE_FILE="$(cd "$(dirname "$0")" && pwd)/fixtures/zerto_sample.log"
WAIT_SECONDS="${WAIT_SECONDS:-8}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass=0
fail=0
total=0

log()  { printf "${GREEN}[+]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[!]${NC} %s\n" "$*"; }
err()  { printf "${RED}[-]${NC} %s\n" "$*"; }

# -------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------
assert_log_contains() {
  local description="$1"
  local pattern="$2"
  total=$((total + 1))

  if echo "$LOGS" | grep -qiE "$pattern"; then
    log "PASS: $description"
    pass=$((pass + 1))
  else
    err "FAIL: $description"
    err "  pattern: $pattern"
    fail=$((fail + 1))
  fi
}

# -------------------------------------------------------------------
# Pre-flight checks
# -------------------------------------------------------------------
if [ ! -f "$FIXTURE_FILE" ]; then
  err "Fixture file not found: $FIXTURE_FILE"
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
  err "Container '$CONTAINER' is not running. Start it with: docker compose up -d"
  exit 1
fi

if ! command -v nc &>/dev/null; then
  err "'nc' (netcat) is required but not found"
  exit 1
fi

# -------------------------------------------------------------------
# Clear previous logs so we only validate new output
# -------------------------------------------------------------------
log "Capturing log baseline..."
BASELINE_LINES=$(docker logs "$CONTAINER" 2>&1 | wc -l)

# -------------------------------------------------------------------
# Send fixture messages (one per line, skip comments and blanks)
# -------------------------------------------------------------------
log "Sending fixture messages to ${HOST}:${PORT}/udp..."
SENT=0
while IFS= read -r line; do
  # Skip comments and empty lines
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line// /}" ]] && continue

  echo "$line" | nc -w1 -u "$HOST" "$PORT"
  SENT=$((SENT + 1))
done < "$FIXTURE_FILE"

log "Sent $SENT syslog messages"
log "Waiting ${WAIT_SECONDS}s for FluentD to process..."
sleep "$WAIT_SECONDS"

# -------------------------------------------------------------------
# Capture new container logs
# -------------------------------------------------------------------
LOGS=$(docker logs "$CONTAINER" 2>&1 | tail -n +$((BASELINE_LINES + 1)))

if [ -z "$LOGS" ]; then
  err "No new log output from container after sending fixtures"
  exit 1
fi

log "Captured $(echo "$LOGS" | wc -l) new log lines"
echo ""
log "=== Validation ==="
echo ""

# -------------------------------------------------------------------
# Validate ECS core fields are present
# -------------------------------------------------------------------
assert_log_contains "ECS version field present"        '"ecs\.version":"8\.11\.0"'
assert_log_contains "event.module is zerto"            '"event\.module":"zerto"'
assert_log_contains "event.dataset is zerto.event"     '"event\.dataset":"zerto\.event"'
assert_log_contains "observer.vendor is Zerto"         '"observer\.vendor":"Zerto"'
assert_log_contains "observer.product is ZVM"          '"observer\.product":"ZVM"'

# -------------------------------------------------------------------
# Validate event routing by event.code
# -------------------------------------------------------------------
assert_log_contains "VPG_RPO_VIOLATION parsed"         'VPG_RPO_VIOLATION'
assert_log_contains "VPG_CREATED parsed"               'VPG_CREATED'
assert_log_contains "FAILOVER_STARTED parsed"          'FAILOVER_STARTED'
assert_log_contains "USER_LOGIN_FAILED parsed"         'USER_LOGIN_FAILED'
assert_log_contains "USER_LOGIN parsed"                'USER_LOGIN[^_]'
assert_log_contains "JOURNAL_HARD_LIMIT_REACHED parsed" 'JOURNAL_HARD_LIMIT_REACHED'
assert_log_contains "SITE_DISCONNECTED parsed"         'SITE_DISCONNECTED'
assert_log_contains "CONFIG_CHANGED parsed"            'CONFIG_CHANGED'
assert_log_contains "VRA_INSTALLED parsed"             'VRA_INSTALLED'
assert_log_contains "RESTORE_COMPLETED parsed"         'RESTORE_COMPLETED'
assert_log_contains "REPLICATION_PAUSED parsed"        'REPLICATION_PAUSED'
assert_log_contains "LTR_BACKUP_COMPLETED parsed"      'LTR_BACKUP_COMPLETED'
assert_log_contains "TASK_FAILED parsed"               'TASK_FAILED'
assert_log_contains "ALERT_RAISED parsed"              'ALERT_RAISED'
assert_log_contains "ENC0001 encryption alert parsed"   'ENC0001'

# -------------------------------------------------------------------
# Validate ECS enrichment fields
# -------------------------------------------------------------------
assert_log_contains "RPO event has event.kind=alert"           '"event\.kind":"alert".*VPG_RPO'
assert_log_contains "Auth failure has event.outcome=failure"   '"event\.outcome":"failure"'
assert_log_contains "DR operation has event.category=process"  '"event\.category":\["process"\].*FAILOVER'
assert_log_contains "Zerto labels: vpg_name present"           '"labels\.vpg_name":"Production-VPG"'
assert_log_contains "Zerto labels: site_name present"          '"labels\.site_name":"Site-'
assert_log_contains "source.ip extracted"                      '"source\.ip":"192\.168\.1\.'
assert_log_contains "source.user.name extracted"               '"source\.user\.name":"admin"'
assert_log_contains "ENC0001 has event.kind=alert"             '"event\.kind":"alert".*ENC0001|ENC0001.*"event\.kind":"alert"'
assert_log_contains "ENC0001 has malware category"             '"event\.category":\["malware"'
assert_log_contains "ENC0001 has rule.category=encryption"     '"rule\.category":"encryption_detection"'
assert_log_contains "ENC0001 has threat technique"             '"threat\.technique\.name":"Data Encrypted for Impact"'
assert_log_contains "ENC0001 affected_volumes extracted"       '"labels\.affected_volumes":"C:'

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------
echo ""
echo "========================================"
printf "  Total: %d  |  Pass: ${GREEN}%d${NC}  |  Fail: ${RED}%d${NC}\n" "$total" "$pass" "$fail"
echo "========================================"

if [ "$fail" -gt 0 ]; then
  echo ""
  warn "Some checks failed. Inspect container logs:"
  warn "  docker logs $CONTAINER | tail -50"
  exit 1
fi

log "All checks passed!"
exit 0
