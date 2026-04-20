# Contributing to Zerto SIEM Bridge

Thank you for your interest in contributing. This guide walks through the process of adding a new SIEM output, which is the most common type of contribution.

---

## Adding a New SIEM Output

The bridge uses a plugin architecture where each SIEM output is a self-contained FluentD `<store>` block. Adding a new output requires changes in 4 files.

### Step 1: Create the output config

Create a new file at `config/outputs/<siem_name>.conf`.

The file must contain a single `<store>` block using a FluentD output plugin. Use environment variables for all credentials and connection details.

```xml
<store>
  @type http
  @id   out_mynewsiem

  endpoint "#{ENV['MYNEWSIEM_URL']}"

  # Auth
  headers {"Authorization": "Bearer #{ENV['MYNEWSIEM_TOKEN']}"}

  content_type application/json
  json_array true

  <buffer>
    @type file
    path /var/log/fluentd/buffer/mynewsiem
    flush_mode interval
    flush_interval 10s
    flush_at_shutdown true
    retry_type exponential_backoff
    retry_wait 5s
    retry_max_interval 120s
    chunk_limit_size 8m
    total_limit_size 256m
    overflow_action block
  </buffer>
</store>
```

Guidelines:
- Always use a file-based buffer (not memory) for durability
- Set `flush_at_shutdown true` to avoid data loss
- Use exponential backoff for retries
- Use `@id` with a unique name prefixed by `out_`
- Reference credentials via `ENV[]`, never hardcode them

### Step 2: Add the enable toggle to `scripts/entrypoint.sh`

Add a line to the output assembly section (around line 67):

```bash
[ "${SIEM_MYNEWSIEM_ENABLED:-false}" = "true" ] && cat /etc/fluent/outputs/mynewsiem.conf >> "$OUTPUTS_ACTIVE"
```

Also add the variable to the validation loop (around line 52):

```bash
for v in SIEM_ELASTIC_ENABLED SIEM_SPLUNK_ENABLED SIEM_SENTINEL_ENABLED SIEM_SENTINELONE_ENABLED SIEM_MYNEWSIEM_ENABLED; do
```

### Step 3: Add environment variables to `docker-compose.yml`

Add a new section under `environment:`:

```yaml
      # --- MyNewSIEM ---
      SIEM_MYNEWSIEM_ENABLED: "${SIEM_MYNEWSIEM_ENABLED:-false}"
      MYNEWSIEM_URL: "${MYNEWSIEM_URL:-}"
      MYNEWSIEM_TOKEN: "${MYNEWSIEM_TOKEN:-}"
```

### Step 4: Install the FluentD plugin (if needed)

If your SIEM requires a FluentD plugin not already included, add it to the `Dockerfile`:

```dockerfile
RUN fluent-gem install \
    fluent-plugin-mynewsiem \
    ...
```

### Step 5: Document it

1. Add a row to the **Supported SIEM Outputs** table in `README.md`
2. Add a setup section in `docs/SIEM_SETUP.md`
3. Add the variables to `docs/CONFIGURATION.md`
4. Update `.env.example` if it exists

### Step 6: Test it

1. Add a fixture or verify the existing fixtures cover your output
2. Run the test script: `./tests/test_syslog.sh`
3. Verify events arrive in your SIEM

---

## Development Workflow

### Prerequisites

- Docker Engine 20.10+ and Docker Compose v2
- bash, nc (netcat), and jq for testing

### Build and run locally

```bash
docker compose build
docker compose up -d
```

### Run tests

```bash
./tests/test_syslog.sh
```

### Check FluentD config validity

```bash
docker run --rm zerto-siem-bridge fluentd --dry-run -c /etc/fluent/fluent.conf
```

---

## Submitting a Pull Request

1. Fork the repository and create a feature branch from `main`
2. Make your changes following the patterns above
3. Test locally with `docker compose up` and the test script
4. Ensure `docker build` succeeds
5. Open a PR against `main` with:
   - A clear description of the SIEM being added
   - Screenshots or logs showing events arriving in the target SIEM
   - Any new environment variables documented

---

## Code Style

- FluentD configs: 2-space indentation, comments above each block
- Shell scripts: `set -euo pipefail`, quote all variables, use `log()` / `warn()` helpers
- Environment variables: `SCREAMING_SNAKE_CASE`, prefixed by SIEM name

---

## Reporting Issues

- Use the [bug report template](https://github.com/nich0lasJ/ZertoSIEM-Bridge/issues/new?template=bug_report.yml) for bugs
- Use the [feature request template](https://github.com/nich0lasJ/ZertoSIEM-Bridge/issues/new?template=feature_request.yml) for new features or SIEM requests
