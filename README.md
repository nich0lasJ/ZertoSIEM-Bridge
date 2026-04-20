# Zerto SIEM Bridge

[![Build & Push](https://github.com/nich0lasJ/ZertoSIEM-Bridge/actions/workflows/ci.yml/badge.svg)](https://github.com/nich0lasJ/ZertoSIEM-Bridge/actions/workflows/ci.yml)
[![Docker Image](https://img.shields.io/badge/ghcr.io-zerto--siem--bridge-blue?logo=docker)](https://ghcr.io/nich0lasj/zertosiem-bridge)
[![License](https://img.shields.io/badge/License-Apache_2.0-green.svg)](LICENSE)

A FluentD-based Docker container that ingests Zerto ZVM syslog events (CEF format), normalises them to [Elastic Common Schema (ECS)](https://www.elastic.co/guide/en/ecs/current/index.html), and forwards them to one or more SIEM platforms.

Inspired by [HPEAlletraStorageMP-SyslogAggregator](https://github.com/HewlettPackard/HPEAlletraStorageMP-SyslogAggregator) -- same FluentD + ECS approach, extended with multi-SIEM push delivery and Docker deployment.

---

## Architecture

```
                          +-------------------------------------------+
  +-------------+         |          Zerto SIEM Bridge                |
  |  Zerto ZVM  |         |  (Docker / FluentD)                      |
  |             |         |                                          |
  | Syslog CEF  +-------->|  :514/udp,tcp   +-------------------+   |    +-----------------+
  | (RFC 5424)  |         |  :6514/tcp(TLS) | CEF Parser        |   +--->| Elasticsearch   |
  +-------------+         |                 |   |                |   |    +-----------------+
                          |                 |   v                |   |
                          |                 | ECS Normaliser     |   |    +-----------------+
                          |                 |   |                |   +--->| Splunk HEC      |
                          |                 |   v                |   |    +-----------------+
                          |                 | Tag Router         |   |
                          |                 |   |                |   |    +-----------------+
                          |                 |   +- vpg.lifecycle |   +--->| MS Sentinel     |
                          |                 |   +- vpg.rpo      |   |    +-----------------+
                          |                 |   +- dr.operation  |   |
                          |                 |   +- auth          |   |    +-----------------+
                          |                 |   +- security.enc  |   +--->| SentinelOne     |
                          |                 |   +- ...           |   |    +-----------------+
                          |                 +-------------------+   |
                          |                                          |
                          |  :24231/tcp  Prometheus /metrics          |
                          +-------------------------------------------+
```

### Data flow

```
ZVM syslog ──> FluentD source (:514 or :6514)
                 |
                 v
              [Step 1]  Regex parse CEF envelope
                 |       (PRI, timestamp, host, CEF header + extensions)
                 v
              [Step 2]  Grep filter — drop non-Zerto messages
                 |
                 v
              [Step 3]  Parse CEF key=value extensions
                 |
                 v
              [Step 4]  Map to ECS fields
                 |       (@timestamp, event.*, host.name, labels.*, source.*)
                 v
              [Step 5]  Rewrite-tag-filter routes by event.code
                 |       (vpg.lifecycle, dr.operation, security.encryption, ...)
                 v
              [Step 6]  Enrich with event.kind / event.category per tag
                 |
                 v
              [Output]  Copy to all enabled SIEM stores
                        + stdout fallback
```

---

## Supported SIEM Outputs

| SIEM | Protocol | Auth | Enable variable |
|---|---|---|---|
| Elasticsearch / Elastic Security | Bulk API (HTTPS) | API key or user/password | `SIEM_ELASTIC_ENABLED` |
| Splunk | HTTP Event Collector (HEC) | HEC token | `SIEM_SPLUNK_ENABLED` |
| Microsoft Sentinel | Log Analytics Data Collector API | Workspace key | `SIEM_SENTINEL_ENABLED` |
| SentinelOne XDR | HTTP ingest API | Bearer token | `SIEM_SENTINELONE_ENABLED` |

---

## Quick Start

### Prerequisites

- Docker Engine 20.10+ and Docker Compose v2
- Network access from Zerto ZVM to this host on port 514 or 6514
- Credentials for at least one target SIEM

### 1. Clone the repository

```bash
git clone https://github.com/nich0lasJ/ZertoSIEM-Bridge.git
cd ZertoSIEM-Bridge
```

### 2. Create your environment file

```bash
cp .env.example .env
```

Edit `.env` to enable at least one SIEM output and provide credentials. See [docs/CONFIGURATION.md](docs/CONFIGURATION.md) for a complete variable reference.

Example -- enabling Splunk only:

```env
SIEM_SPLUNK_ENABLED=true
SPLUNK_HEC_URL=https://splunk.corp.local:8088
SPLUNK_HEC_TOKEN=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

### 3. TLS certificates (production)

```bash
./scripts/gen-certs.sh syslog.mycompany.com 10.0.0.50
```

Submit the CSR (`certs/server.csr`) to your CA, then place the signed cert and CA bundle:

```
certs/
  server.key   # generated by gen-certs.sh
  server.crt   # signed by your CA
  ca.crt       # CA certificate chain
```

Add the passphrase to your `.env`:

```env
FLUENTD_TLS_KEY_PASSPHRASE=<contents of certs/.passphrase>
```

> For dev/test, skip this step -- the container auto-generates a self-signed cert on first start.

### 4. Start the container

```bash
docker compose up -d
```

Verify it's healthy:

```bash
docker compose ps          # status should be "healthy"
docker logs zerto-siem-bridge | head -20
curl -s http://localhost:24231/metrics | head -5
```

### 5. Configure Zerto ZVM

Point ZVM syslog output to this container:

| Setting | Value |
|---|---|
| Syslog server | `<host-ip>` |
| Protocol | TLS (production) or TCP/UDP (dev) |
| Port | `6514` (TLS) or `514` (plain) |
| Format | CEF / RFC 5424 |

See [docs/ZERTO_SETUP.md](docs/ZERTO_SETUP.md) for detailed ZVM configuration steps.

### 6. Validate

```bash
# Send sample events
nc -u localhost 514 < tests/fixtures/zerto_sample.log

# Run the full test suite
./tests/test_syslog.sh
```

---

## Parsed Event Types

| Tag | Event codes | ECS event.kind |
|---|---|---|
| `zerto.event.vpg.lifecycle` | VPG_CREATED, VPG_DELETED, VPG_UPDATED, VPG_STATUS_CHANGED, VPG_PAUSED, VPG_RESUMED, ... | event |
| `zerto.event.vpg.rpo_violation` | VPG_RPO_VIOLATION, VPG_RPO_WARNING, SLA_VIOLATION, VPG_RPO_RESTORED | alert |
| `zerto.event.journal.limit` | JOURNAL_HARD_LIMIT_REACHED, JOURNAL_SOFT_LIMIT_REACHED, JOURNAL_FULL, JOURNAL_BREACH | alert |
| `zerto.event.dr.operation` | FAILOVER_*, MOVE_*, TEST_FAILOVER_*, FAILOVER_COMMIT, FAILOVER_ROLLBACK | event |
| `zerto.event.dr.restore` | RESTORE_*, CLONE_*, FLR_*, SCRATCH_VOLUME_* | event |
| `zerto.event.auth` | USER_LOGIN, USER_LOGIN_FAILED, USER_CREATED, USER_DELETED, USER_LOCKED, ... | event/alert |
| `zerto.event.config` | CONFIG_CHANGED, LICENSE_*, ZVM_UPGRADED, RETENTION_POLICY_CHANGED, ... | event |
| `zerto.event.security.encryption` | ENC0001+ (ransomware/encryption detection) | alert |
| `zerto.event.alert` | ALERT_RAISED, ALERT_CLEARED, WARNING_RAISED | alert |
| `zerto.event.vra` | VRA_INSTALLED, VRA_UNINSTALLED, VRA_UPGRADED, VRA_NOT_RESPONDING, ... | event |
| `zerto.event.connectivity` | SITE_CONNECTED, SITE_DISCONNECTED, SITE_PAIRED, PEER_SITE_*, VRA_CONNECTED, ... | event |
| `zerto.event.replication` | REPLICATION_PAUSED, REPLICATION_RESUMED, INITIAL_SYNC_*, REPLICATION_ERROR | event |
| `zerto.event.ltr` | LTR_BACKUP_*, LTR_RESTORE_*, LTR_RETENTION_EXPIRED, REPOSITORY_FULL | event |
| `zerto.event.task` | TASK_STARTED, TASK_COMPLETED, TASK_FAILED, TASK_CANCELLED | event/alert |
| `zerto.event.other` | *(catch-all)* | event |

---

## ECS Fields Produced

| ECS field | Source |
|---|---|
| `@timestamp` | Syslog timestamp |
| `ecs.version` | `8.11.0` |
| `event.module` | `zerto` |
| `event.dataset` | `zerto.event` |
| `event.code` | CEF DeviceEventClassID (e.g. `VPG_RPO_VIOLATION`, `ENC0001`) |
| `event.action` | CEF Name |
| `event.severity` | CEF Severity x 10 |
| `event.kind` | `alert` or `event` (derived by category) |
| `event.category` | Derived: `malware`, `authentication`, `storage`, `network`, etc. |
| `event.outcome` | `success` / `failure` (auth and task events) |
| `log.level` | `informational` / `warning` / `error` / `critical` |
| `host.name` | ZVM hostname from syslog envelope |
| `observer.vendor` | `Zerto` |
| `observer.product` | `ZVM` |
| `observer.version` | ZVM version |
| `source.ip` | CEF `src` extension |
| `destination.ip` | CEF `dst` extension |
| `source.user.name` | CEF `suser` extension |
| `labels.vpg_name` | CEF `vpgName` |
| `labels.vm_name` | CEF `vmName` |
| `labels.site_name` | CEF `siteName` |
| `labels.alert_type` | CEF `alertType` |
| `labels.rpo_seconds` | CEF `rpoInSeconds` |
| `labels.journal_used_gb` | CEF `journalUsedStorageGb` |
| `labels.affected_volumes` | CEF `volumes` (encryption alerts) |
| `rule.category` | `encryption_detection`, `rpo_violation`, `journal_limit` |
| `rule.reference` | Zerto docs URL (encryption alerts) |
| `threat.indicator.type` | `encryption-anomaly` (ENC alerts) |
| `threat.technique.name` | `Data Encrypted for Impact` (ENC alerts) |

---

## Monitoring

Prometheus metrics are exposed on port `24231/tcp` at `/metrics`.

Key metrics to watch:

- `fluentd_output_status_buffer_total_bytes` -- buffer backlog per SIEM
- `fluentd_output_status_retry_count` -- delivery failures
- `fluentd_output_status_emit_count` -- events forwarded

---

## Certificate Management

| Scenario | Steps |
|---|---|
| **Dev / test** | Do nothing -- container generates a self-signed cert on first start |
| **Production** | Run `./scripts/gen-certs.sh <FQDN> [IP_SAN]`, submit CSR to CA, mount signed certs |
| **Pre-existing certs** | Place `server.key`, `server.crt`, `ca.crt` in `./certs/` |

---

## Documentation

- [Configuration Reference](docs/CONFIGURATION.md) -- every `.env` variable
- [SIEM Setup Guides](docs/SIEM_SETUP.md) -- per-SIEM configuration
- [Zerto ZVM Setup](docs/ZERTO_SETUP.md) -- configuring ZVM syslog
- [Contributing](CONTRIBUTING.md) -- adding new SIEM outputs

---

## License

Apache License 2.0 -- see [LICENSE](LICENSE)
