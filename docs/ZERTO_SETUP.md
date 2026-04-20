# Zerto ZVM Syslog Configuration

This guide covers how to configure your Zerto Virtual Manager (ZVM) to forward syslog events to the Zerto SIEM Bridge.

---

## Prerequisites

- Zerto Virtual Manager 9.0 or later (9.5+ recommended for encryption detection alerts)
- Network connectivity from ZVM to the bridge host on port 514 (TCP/UDP) or 6514 (TLS)
- The Zerto SIEM Bridge container running and healthy

Verify the bridge is reachable from the ZVM network:

```powershell
# From ZVM server or a host on the same network
Test-NetConnection -ComputerName <bridge-host> -Port 6514
```

---

## Configure Syslog in the ZVM UI

### Zerto 9.5+ (Keycloak / ZVM Appliance)

1. Log in to the **Zerto Virtual Manager** web interface
2. Navigate to **Setup > General**
3. Scroll to the **Syslog** section
4. Configure the following:

| Setting | Value |
|---|---|
| **Enable Syslog** | Checked |
| **Server Address** | IP or FQDN of the bridge host |
| **Port** | `6514` (TLS) or `514` (plain) |
| **Protocol** | `TLS` (recommended) or `TCP` / `UDP` |
| **Format** | `CEF` |

5. Click **Save**

### Zerto 9.0 - 9.4

1. Log in to ZVM
2. Navigate to **Monitoring > Settings** (or **Administration > Settings** depending on version)
3. Under **Syslog Configuration**, enable syslog forwarding
4. Set the server address, port, and protocol as above

---

## Configure via Zerto REST API

For automated deployments, configure syslog via the ZVM API:

```bash
# Authenticate
TOKEN=$(curl -s -X POST "https://<zvm>/v1/session/add" \
  -H "Content-Type: application/json" \
  -d '{"AuthenticationMethod":1}' \
  -u "admin@vsphere.local:password" | jq -r '.Token')

# Enable syslog
curl -s -X PUT "https://<zvm>/v1/localsite/settings" \
  -H "Content-Type: application/json" \
  -H "x-zerto-session: $TOKEN" \
  -d '{
    "SyslogSettings": {
      "IsEnabled": true,
      "ServerName": "<bridge-host>",
      "ServerPort": 6514,
      "Protocol": "Tls",
      "CefFormat": true
    }
  }'
```

---

## TLS Configuration

### Using bridge-generated self-signed cert (dev/test only)

No extra ZVM configuration is needed. The bridge generates a self-signed cert on first start. Some ZVM versions may require you to disable certificate verification for syslog, or import the self-signed CA.

### Using CA-signed cert (production)

1. Generate the cert on the bridge host:

```bash
./scripts/gen-certs.sh syslog.corp.local 10.0.0.50
```

2. Submit the CSR to your internal CA and place the signed cert in `./certs/`
3. If ZVM requires the CA cert for TLS verification, import your CA's root certificate into the ZVM trust store:

**Windows-hosted ZVM:**

```powershell
Import-Certificate -FilePath "C:\path\to\ca.crt" -CertStoreLocation Cert:\LocalMachine\Root
```

**Linux appliance ZVM:**

```bash
cp ca.crt /usr/local/share/ca-certificates/zerto-siem-bridge-ca.crt
update-ca-certificates
```

---

## Choosing a Protocol

| Protocol | Port | Use case | Notes |
|---|---|---|---|
| **TLS** (TCP) | 6514 | Production | Encrypted, reliable delivery. Recommended. |
| **TCP** | 514 | Staging | Reliable delivery, no encryption. |
| **UDP** | 514 | Dev / high-volume testing | Fast but may drop messages under load. |

For production environments, always use TLS on port 6514.

---

## What Events are Forwarded

When syslog is enabled, ZVM forwards all alert and event types, including:

- **VPG lifecycle**: creation, deletion, status changes, protection state changes
- **RPO violations**: RPO threshold exceeded, SLA breaches
- **DR operations**: failover, move, test failover (start, complete, fail)
- **Journal events**: hard/soft limit reached, journal full
- **Authentication**: user login/logout, login failures, role changes
- **Configuration changes**: settings, licensing, site pairing
- **Encryption detection**: ENC0001 alerts when anomalous encryption activity is detected
- **VRA lifecycle**: install, upgrade, disconnect
- **Replication state**: pause, resume, sync, errors
- **Connectivity**: site connect/disconnect, VRA connect/disconnect

---

## Validation

### Send test events manually

From the ZVM or any host on the same network:

```bash
# Quick test with netcat (plain syslog)
echo '<134>Apr 20 2026 10:15:00 ZVM-TEST CEF:0|Zerto|ZVM|9.5|VPG_RPO_VIOLATION|VPG RPO Violation|8|vpgName=Test-VPG rpoInSeconds=120 msg=Test event' \
  | nc -u <bridge-host> 514
```

### Check the bridge received it

```bash
docker logs zerto-siem-bridge | tail -10
```

You should see the event with ECS fields in the stdout output.

### Use the test suite

```bash
./tests/test_syslog.sh <bridge-host> 514
```

---

## Firewall Rules

Ensure the following network paths are open:

| Source | Destination | Port | Protocol | Purpose |
|---|---|---|---|---|
| ZVM | Bridge host | 6514 | TCP | Syslog over TLS |
| ZVM | Bridge host | 514 | TCP + UDP | Plain syslog (non-TLS) |
| Bridge host | SIEM targets | Varies | TCP | Event forwarding |

---

## Troubleshooting

### ZVM says "syslog server unreachable"

- Verify network connectivity: `Test-NetConnection -ComputerName <host> -Port 6514`
- Check that the bridge container is running: `docker compose ps`
- Check container healthcheck: `docker inspect zerto-siem-bridge --format='{{.State.Health.Status}}'`

### Events not appearing in SIEM

1. Check bridge stdout for incoming events: `docker logs zerto-siem-bridge | grep zerto`
2. If events reach the bridge but not the SIEM, the issue is in the output config. See [SIEM_SETUP.md](SIEM_SETUP.md).
3. If no events reach the bridge, verify the ZVM syslog config and firewall rules.

### TLS handshake failures

- Check the bridge cert is valid: `openssl s_client -connect <host>:6514`
- Ensure the ZVM trusts the CA that signed the bridge cert
- Check for clock skew between ZVM and bridge host
