# Configuration Reference

All configuration is done through environment variables, either in a `.env` file or passed directly to `docker compose`.

---

## TLS Settings

| Variable | Required | Default | Description |
|---|---|---|---|
| `TLS_ENABLED` | No | `true` | Enable TLS on the syslog listener (port 6514). Set to `false` to disable. |
| `TLS_CERT_PATH` | No | `/etc/fluent/certs/server.crt` | Path to the TLS certificate inside the container. |
| `TLS_KEY_PATH` | No | `/etc/fluent/certs/server.key` | Path to the TLS private key inside the container. |
| `TLS_CA_PATH` | No | `/etc/fluent/certs/ca.crt` | Path to the CA certificate inside the container. |
| `FLUENTD_TLS_KEY_PASSPHRASE` | When TLS enabled | *(auto-generated)* | Passphrase for the TLS private key. If not set and no certs are mounted, a random passphrase is generated at startup. |

### Example

```env
TLS_ENABLED=true
FLUENTD_TLS_KEY_PASSPHRASE=my-secure-passphrase-here
```

> When `TLS_ENABLED=true` and no certs are found in `./certs/`, the container generates a self-signed certificate on first start. For production, run `./scripts/gen-certs.sh` and mount your CA-signed certs.

---

## SIEM Output Toggles

Each SIEM output is independently enabled. You can enable multiple outputs simultaneously.

| Variable | Default | Description |
|---|---|---|
| `SIEM_ELASTIC_ENABLED` | `false` | Enable Elasticsearch / Elastic Security output |
| `SIEM_SPLUNK_ENABLED` | `false` | Enable Splunk HEC output |
| `SIEM_SENTINEL_ENABLED` | `false` | Enable Microsoft Sentinel output |
| `SIEM_SENTINELONE_ENABLED` | `false` | Enable SentinelOne XDR output |

Accepted values: `true` or `false` (case-sensitive).

If no outputs are enabled, events are written to stdout only (useful for debugging).

### Example

```env
SIEM_ELASTIC_ENABLED=true
SIEM_SPLUNK_ENABLED=true
SIEM_SENTINEL_ENABLED=false
SIEM_SENTINELONE_ENABLED=false
```

---

## Elasticsearch Settings

Required when `SIEM_ELASTIC_ENABLED=true`.

| Variable | Required | Default | Description |
|---|---|---|---|
| `ELASTIC_HOST` | Yes | *(none)* | Elasticsearch host (FQDN or IP). Do not include protocol or port. |
| `ELASTIC_PORT` | No | `9200` | Elasticsearch port. |
| `ELASTIC_SCHEME` | No | `https` | `http` or `https`. |
| `ELASTIC_INDEX` | No | `zerto-siem-bridge` | Base index name. ILM rollover appends a numeric suffix. |
| `ELASTIC_USER` | Conditional | *(none)* | Basic auth username. Not needed if using `ELASTIC_API_KEY`. |
| `ELASTIC_PASSWORD` | Conditional | *(none)* | Basic auth password. Not needed if using `ELASTIC_API_KEY`. |
| `ELASTIC_API_KEY` | Conditional | *(none)* | Elasticsearch API key (base64-encoded `id:api_key`). Takes precedence over user/password. |

### Authentication

Choose **one** of these methods:

**API key (recommended):**

```env
ELASTIC_HOST=elastic.corp.local
ELASTIC_API_KEY=bXktaWQ6bXktYXBpLWtleQ==
```

**Username / password:**

```env
ELASTIC_HOST=elastic.corp.local
ELASTIC_USER=zerto-ingest
ELASTIC_PASSWORD=changeme
```

### ILM Policy

The Elasticsearch output automatically creates an ILM policy:

- **Hot phase**: rollover at 10 GB or 7 days
- **Warm phase**: shrink to 1 shard after 7 days
- **Delete phase**: delete after 90 days

To use a custom ILM policy, create it in Elasticsearch first and update the `ilm_policy_id` in `config/outputs/elastic.conf`.

---

## Splunk HEC Settings

Required when `SIEM_SPLUNK_ENABLED=true`.

| Variable | Required | Default | Description |
|---|---|---|---|
| `SPLUNK_HEC_URL` | Yes | *(none)* | Full URL of the Splunk HEC endpoint (e.g. `https://splunk.corp.local:8088`). |
| `SPLUNK_HEC_TOKEN` | Yes | *(none)* | HEC authentication token. |
| `SPLUNK_INDEX` | No | `zerto` | Target Splunk index. |
| `SPLUNK_SOURCE` | No | `zerto:syslog` | Source metadata field. |
| `SPLUNK_SOURCETYPE` | No | `zerto:event` | Sourcetype metadata field. |

### Example

```env
SIEM_SPLUNK_ENABLED=true
SPLUNK_HEC_URL=https://splunk.corp.local:8088
SPLUNK_HEC_TOKEN=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
SPLUNK_INDEX=zerto
SPLUNK_SOURCE=zerto:syslog
SPLUNK_SOURCETYPE=zerto:event
```

---

## Microsoft Sentinel Settings

Required when `SIEM_SENTINEL_ENABLED=true`.

| Variable | Required | Default | Description |
|---|---|---|---|
| `SENTINEL_WORKSPACE_ID` | Yes | *(none)* | Log Analytics workspace ID (GUID). Found in Azure Portal > Log Analytics workspace > Agents. |
| `SENTINEL_WORKSPACE_KEY` | Yes | *(none)* | Primary or secondary workspace key. Found in the same location. |
| `SENTINEL_LOG_TYPE` | No | `ZertoEvents` | Custom log table name. Sentinel appends `_CL` automatically (e.g. `ZertoEvents_CL`). |

### Example

```env
SIEM_SENTINEL_ENABLED=true
SENTINEL_WORKSPACE_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
SENTINEL_WORKSPACE_KEY=base64encodedkey==
SENTINEL_LOG_TYPE=ZertoEvents
```

---

## SentinelOne Settings

Required when `SIEM_SENTINELONE_ENABLED=true`.

| Variable | Required | Default | Description |
|---|---|---|---|
| `S1_INGEST_URL` | Yes | *(none)* | SentinelOne ingest endpoint URL. Provided by your SentinelOne admin (e.g. `https://<tenant>.sentinelone.net/web/api/v2.1/cloud-funnel/...`). |
| `S1_API_TOKEN` | Yes | *(none)* | SentinelOne API token with ingest permissions. |

### Example

```env
SIEM_SENTINELONE_ENABLED=true
S1_INGEST_URL=https://usea1.sentinelone.net/web/api/v2.1/cloud-funnel/ingest
S1_API_TOKEN=eyJhbGciOiJSUzI1NiIs...
```

---

## Network Ports

These are configured in `docker-compose.yml` and are not environment variables, but are documented here for reference.

| Port | Protocol | Purpose |
|---|---|---|
| `514` | UDP + TCP | Plain syslog (dev / non-TLS environments) |
| `6514` | TCP | Syslog over TLS (production) |
| `24231` | TCP | Prometheus metrics endpoint (`/metrics`) |

---

## Complete `.env` Example

```env
# --- TLS ---
TLS_ENABLED=true
FLUENTD_TLS_KEY_PASSPHRASE=my-secure-passphrase

# --- SIEM toggles ---
SIEM_ELASTIC_ENABLED=false
SIEM_SPLUNK_ENABLED=true
SIEM_SENTINEL_ENABLED=true
SIEM_SENTINELONE_ENABLED=false

# --- Splunk ---
SPLUNK_HEC_URL=https://splunk.corp.local:8088
SPLUNK_HEC_TOKEN=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
SPLUNK_INDEX=zerto
SPLUNK_SOURCE=zerto:syslog
SPLUNK_SOURCETYPE=zerto:event

# --- Sentinel ---
SENTINEL_WORKSPACE_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
SENTINEL_WORKSPACE_KEY=base64encodedkey==
SENTINEL_LOG_TYPE=ZertoEvents
```
