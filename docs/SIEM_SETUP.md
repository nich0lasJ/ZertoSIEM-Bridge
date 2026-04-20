# SIEM Setup Guides

Step-by-step instructions for configuring each supported SIEM to receive Zerto events from the bridge.

---

## Elasticsearch / Elastic Security

### 1. Create an ingest user or API key

**Option A -- API key (recommended):**

```
POST /_security/api_key
{
  "name": "zerto-siem-bridge",
  "role_descriptors": {
    "zerto_writer": {
      "cluster": ["monitor", "manage_ilm", "manage_index_templates"],
      "index": [
        {
          "names": ["zerto-siem-bridge*"],
          "privileges": ["create_index", "write", "manage"]
        }
      ]
    }
  }
}
```

Copy the `encoded` value from the response.

**Option B -- Username / password:**

Create a role with `write` and `create_index` privileges on `zerto-siem-bridge*`, then assign it to a user.

### 2. Configure the bridge

```env
SIEM_ELASTIC_ENABLED=true
ELASTIC_HOST=elastic.corp.local
ELASTIC_PORT=9200
ELASTIC_SCHEME=https
ELASTIC_API_KEY=<encoded key from step 1>
```

### 3. Verify

After starting the bridge and sending test events:

```bash
# Check the index exists
curl -s -H "Authorization: ApiKey <key>" \
  https://elastic.corp.local:9200/_cat/indices/zerto-siem-bridge*

# Search for events
curl -s -H "Authorization: ApiKey <key>" \
  https://elastic.corp.local:9200/zerto-siem-bridge*/_search?size=5 | jq .
```

### 4. Elastic Security integration (optional)

To surface Zerto encryption alerts (ENC0001) as Elastic Security alerts:

1. Go to **Security > Rules > Create new rule**
2. Choose **Custom query**
3. Query: `event.code : "ENC0001" and event.kind : "alert"`
4. Severity: **Critical**
5. Set actions (email, Slack, PagerDuty, etc.)

The ECS fields (`event.kind`, `event.category`, `threat.technique.name`) are already populated by the bridge, so Elastic Security can correlate them directly.

---

## Splunk

### 1. Create a HEC token

1. In Splunk Web, go to **Settings > Data Inputs > HTTP Event Collector**
2. Click **New Token**
3. Name: `zerto-siem-bridge`
4. Source type: `zerto:event`
5. Index: `zerto` (create this index first under **Settings > Indexes** if it doesn't exist)
6. Click **Submit** and copy the token value

### 2. Enable HEC globally

1. Go to **Settings > Data Inputs > HTTP Event Collector > Global Settings**
2. Set **All Tokens** to **Enabled**
3. Note the HTTP port (default `8088`)
4. Ensure **Enable SSL** is checked for production

### 3. Configure the bridge

```env
SIEM_SPLUNK_ENABLED=true
SPLUNK_HEC_URL=https://splunk.corp.local:8088
SPLUNK_HEC_TOKEN=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
SPLUNK_INDEX=zerto
SPLUNK_SOURCE=zerto:syslog
SPLUNK_SOURCETYPE=zerto:event
```

### 4. Verify

```bash
# Test HEC connectivity directly
curl -k https://splunk.corp.local:8088/services/collector/health \
  -H "Authorization: Splunk <token>"
```

In Splunk Web, search:

```spl
index=zerto sourcetype="zerto:event" | head 20
```

### 5. Create alerts (optional)

Example saved search for encryption detection:

```spl
index=zerto sourcetype="zerto:event" event.code="ENC0001"
| table _time, host.name, labels.vpg_name, labels.vm_name, labels.affected_volumes, message
```

Save as an alert with **Trigger when number of results > 0**.

---

## Microsoft Sentinel

### 1. Get workspace credentials

1. In the Azure Portal, go to **Log Analytics workspaces > your workspace**
2. Go to **Settings > Agents** (or **Agents management**)
3. Copy the **Workspace ID** and **Primary Key**

### 2. Configure the bridge

```env
SIEM_SENTINEL_ENABLED=true
SENTINEL_WORKSPACE_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
SENTINEL_WORKSPACE_KEY=base64encodedkey==
SENTINEL_LOG_TYPE=ZertoEvents
```

### 3. Verify

Events appear in the `ZertoEvents_CL` custom log table. In the Azure Portal:

1. Go to **Microsoft Sentinel > Logs**
2. Run:

```kql
ZertoEvents_CL
| take 20
| project TimeGenerated, event_code_s, event_action_s, host_name_s, labels_vpg_name_s, message_s
```

> Sentinel appends `_CL` to the log type and type suffixes to fields (`_s` for strings, `_d` for doubles, `_b` for booleans).

### 4. Create analytics rules (optional)

**Encryption detection rule:**

1. Go to **Microsoft Sentinel > Analytics > Create > Scheduled query rule**
2. Query:

```kql
ZertoEvents_CL
| where event_code_s == "ENC0001"
| project TimeGenerated, host_name_s, labels_vpg_name_s, labels_vm_name_s, labels_affected_volumes_s, message_s
```

3. Run every **5 minutes**, look back **5 minutes**
4. Trigger alert when **results > 0**
5. Map entities:
   - Host: `host_name_s`
   - IP: `source_ip_s`

**RPO violation rule:**

```kql
ZertoEvents_CL
| where event_code_s in ("VPG_RPO_VIOLATION", "SLA_VIOLATION")
| project TimeGenerated, host_name_s, labels_vpg_name_s, labels_rpo_seconds_s, message_s
```

---

## SentinelOne XDR

### 1. Get ingest credentials

1. Log in to the SentinelOne management console
2. Go to **Settings > Integrations > API** (or **Settings > Users > Service Users**)
3. Create a new API token with **Remote Scripting** or **Ingest** permissions
4. Note the **Ingest URL** for your tenant (e.g. `https://usea1.sentinelone.net/web/api/v2.1/cloud-funnel/ingest`)

> The exact URL varies by tenant and region. Contact your SentinelOne admin if unsure.

### 2. Configure the bridge

```env
SIEM_SENTINELONE_ENABLED=true
S1_INGEST_URL=https://usea1.sentinelone.net/web/api/v2.1/cloud-funnel/ingest
S1_API_TOKEN=eyJhbGciOiJSUzI1NiIs...
```

### 3. Verify

In the SentinelOne console:

1. Go to **Visibility > Hunting**
2. Query for events with `observer.vendor = "Zerto"`
3. You should see ECS-normalised Zerto events

### 4. Create custom detection rules (optional)

In **Singularity XDR > Custom Rules**:

```
event.code = "ENC0001" AND event.kind = "alert"
```

Set severity to **Critical** and configure response actions.

---

## Troubleshooting (all SIEMs)

### Events not arriving

1. Check the bridge is receiving syslog:

```bash
docker logs zerto-siem-bridge | grep -i "zerto"
```

2. Check buffer backlog:

```bash
curl -s http://localhost:24231/metrics | grep buffer_total_bytes
```

3. Check for retry errors:

```bash
docker logs zerto-siem-bridge | grep -i "retry\|error\|failed"
```

### Authentication errors

- Elastic: verify API key with `curl -H "Authorization: ApiKey <key>" https://host:9200/`
- Splunk: verify HEC token with `curl -k https://host:8088/services/collector/health -H "Authorization: Splunk <token>"`
- Sentinel: workspace key errors appear as HTTP 403 in the container logs
- SentinelOne: token errors appear as HTTP 401 in the container logs

### Buffer overflow

If events are produced faster than a SIEM can accept them, the file buffer fills up. Check `overflow_action` in the output config -- by default it is set to `block`, which applies backpressure. To drop excess events instead, change to `drop_oldest_chunk`.
