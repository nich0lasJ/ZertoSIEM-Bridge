# Zerto SIEM Bridge

A FluentD-based Docker container that ingests Zerto ZVM syslog events (CEF format), normalises them to [Elastic Common Schema (ECS)](https://www.elastic.co/guide/en/ecs/current/index.html), and forwards them to one or more SIEM platforms.

Inspired by [HPEAlletraStorageMP-SyslogAggregator](https://github.com/HewlettPackard/HPEAlletraStorageMP-SyslogAggregator) — same FluentD + ECS approach, extended with multi-SIEM push delivery and Docker deployment.

## Supported outputs

| SIEM | Protocol | Auth |
|---|---|---|
| Elastic / Elastic Security | Elasticsearch API (bulk) | API key or user/password |
| Splunk | HTTP Event Collector (HEC) | HEC token |
| Microsoft Sentinel | Log Analytics Data Collector API | Workspace key |
| SentinelOne XDR | HTTP ingest API | Bearer token |

## Quick start

```bash
# 1. Clone
git clone https://github.com/your-org/zerto-siem-bridge
cd zerto-siem-bridge

# 2. Configure
cp .env.example .env
# Edit .env — set SIEM_*_ENABLED=true and fill credentials for each target SIEM

# 3. TLS (production)
./scripts/gen-certs.sh syslog.mycompany.com 10.0.0.50
# Submit the CSR to your CA, then place server.crt and ca.crt in ./certs/
# Add FLUENTD_TLS_KEY_PASSPHRASE to .env

# 4. Start
docker compose up -d

# 5. Point Zerto ZVM syslog output to this host:
#    Protocol: TLS   Port: 6514
#    (or TCP/UDP 514 for dev environments)
```

## Architecture

```
Zerto ZVM ──syslog (TLS 6514)──► FluentD ──► CEF parser
                                             │
                                             ├──► ECS normaliser
                                             │
                                             └──► Router
                                                  ├── Elastic
                                                  ├── Splunk HEC
                                                  ├── Sentinel
                                                  └── SentinelOne
```

## Parsed event types

| Tag | Zerto event codes |
|---|---|
| `zerto.event.vpg.rpo_violation` | VPG_RPO_VIOLATION, VPG_RPO_WARNING, SLA_VIOLATION |
| `zerto.event.vpg.lifecycle` | VPG_CREATED, VPG_DELETED, VPG_UPDATED, VPG_PROTECTION_STATE_CHANGED |
| `zerto.event.journal.limit` | JOURNAL_HARD_LIMIT_REACHED, JOURNAL_SOFT_LIMIT_REACHED, JOURNAL_FULL |
| `zerto.event.dr.operation` | FAILOVER_STARTED/COMPLETED/FAILED, MOVE_*, TEST_FAILOVER_* |
| `zerto.event.auth` | USER_LOGIN, USER_LOGIN_FAILED, USER_CREATED, USER_DELETED |
| `zerto.event.config` | CONFIG_CHANGED, LICENSE_CHANGED, SITE_PAIRING_CHANGED |
| `zerto.event.alert` | ALERT_RAISED, ALERT_CLEARED, WARNING_RAISED |
| `zerto.event.connectivity` | SITE_CONNECTED/DISCONNECTED, VRA_CONNECTED/DISCONNECTED |

## ECS fields produced

| ECS field | Source |
|---|---|
| `@timestamp` | Syslog timestamp |
| `host.name` | ZVM hostname from syslog envelope |
| `event.code` | CEF DeviceEventClassID |
| `event.action` | CEF Name |
| `event.severity` | CEF Severity × 10 |
| `event.kind` | Derived (alert / event) |
| `event.category` | Derived by event type |
| `source.ip` | CEF `src` extension |
| `source.user.name` | CEF `suser` extension |
| `labels.vpg_name` | CEF `vpgName` |
| `labels.vm_name` | CEF `vmName` |
| `labels.site_name` | CEF `siteName` |
| `labels.rpo_seconds` | CEF `rpoInSeconds` |
| `labels.journal_used_gb` | CEF `journalUsedStorageGb` |

## Metrics

Prometheus metrics are exposed on port `24231/tcp` at `/metrics`.

## Certificate management

For production, generate a CA-signed cert with:

```bash
./scripts/gen-certs.sh <FQDN> [IP_SAN]
```

The script generates a 4096-bit RSA key and CSR. Submit the CSR to your CA,
place the signed cert at `./certs/server.crt` and the CA cert at `./certs/ca.crt`.

For dev/test the container auto-generates a self-signed cert on first start.

## Testing

Send sample events to the plain syslog port:

```bash
nc -u localhost 514 < tests/fixtures/zerto_sample.log
```

## License

Apache License 2.0 — see [LICENSE](LICENSE)
