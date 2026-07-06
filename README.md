# URL Shortener

Small URL shortener for the Scalability Engineering prototype.

## What Runs

- `services/api`: FastAPI service on port `8080`
- `services/db`: FastAPI in-memory stores, run as five DB shards locally
- Cloud deployment: one public Nginx load balancer VM, configurable private API
  VM count, and configurable private DB shard VM count
- OpenTelemetry Collector, Prometheus, and Grafana for metrics

The API talks to the DB service over HTTP. The DB stores data in Python hash
maps, so all URLs are lost when the DB container restarts.

Note on standard sharding: when `DB_URLS` is configured with multiple comma-
separated DB URLs, the API routes each short code to one DB shard using a stable
hash. `DB_URL` remains supported for single-DB deployments.

## Setup

```bash
gcloud auth login
gcloud config set project scale-eng-prototyping

python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt -r requirements-dev.txt
```

Docker, Terraform, and `gcloud` are required for cloud deployment. The Artifact
Registry repository must exist before pushing images.

## Local Deployment

Run everything with Docker:

```bash
make local
```

Endpoints:

- API: `http://localhost:8080`
- DB shards: `http://localhost:9001` through `http://localhost:9005`
- Grafana: `http://localhost:3000`
- Prometheus: `http://localhost:9090`

## Cloud Deployment

Defaults:

- `PROJECT_ID`: active `gcloud` project
- `REGION`: `europe-west3`
- `ZONE`: `europe-west3-a`
- `REPO_NAME`: `url-shortener`
- `TAG`: output of `whoami`
- `API_SERVER_COUNT`: `5`
- `DB_SERVER_COUNT`: `5`

Build, push, deploy, and wait:

```bash
make build-all
make push-all
make deploy
make wait
```

Print deployment outputs:

```bash
make outputs
```

Run integration tests against the deployed API:

```bash
make test-integration
```

After pushing new images, restart all VMs:

```bash
make restart-all
```

Per-service build, push, and restart targets are also available, for example
`make build-api`, `make push-api`, and `make restart-api`.

Destroy infrastructure:

```bash
make undeploy
```

Terraform manages VMs, networking, firewall rules, service account, and IAM.

## Usage

Set the API URL for local or cloud:

```bash
export API_URL=http://localhost:8080
# or
export API_URL="$(terraform -chdir=infra output -raw base_url)"
```

Create a short URL:

```bash
curl -X POST "$API_URL/create" \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://example.com/some/long/url"}'
```

Response:

```json
{
  "shortUrl": "http://some.domain/a1B2c3D4"
}
```

Follow a short URL:

```bash
curl -i "$API_URL/a1B2c3D4"
```

Known codes return `302`. Unknown codes return `404`. Invalid create payloads
return `400`.

## Load Testing

Install k6, start the service locally or deploy it to cloud, and set `API_URL`.
The wrapper requires one load profile, the target and one test mode:

```bash
./load-tests/run.sh --spike --read --constant-distribution
```

Available profiles:

- `--steady`: moderate constant load.
- `--spike`: fast ramp to high load, then ramp down.
- `--breakpoint`: slowly increases load until thresholds fail or the configured
  maximum is reached.

Available targets:
- `--query`: Test creating short urls
- `--read`: Test reading short urls
- `--mixed`: Test reading & creating short urls

Available read distributions:

- `--constant-distribution`: always reads the same seeded code.
- `--uniform-distribution`: reads evenly across seeded codes.
- `--hotspot-distribution`: skews reads toward a small hot set.

For cloud runs, you may want to run `make restart-db` between load-test runs to
clear the in-memory DB state.

The headline scaling metric is the maximum sustained throughput at the SLO,
measured by the breakpoint profile. To run the core scaling suite (three
breakpoint runs, ~30 min), labelled with the node count:

```bash
./load-tests/run-core.sh 3-node
```

Spike-based overload tests live in a separate suite:

```bash
./load-tests/run-resilience.sh 3-node
```

To run the full matrix of all combinations (~2 h):
```bash
./load-tests/run-all.sh 3-node
```

See [load-tests/README.md](load-tests/README.md) for what each benchmark measures
and how to calibrate the breakpoint ramp.

### Visualize Results

To visualize the results you can run:
```bash
python analyze.py
```

## Development

Validate and auto-fix Python code:

```bash
make validate
```

Integration tests:

```bash
python -m pytest tests_integration
```

## Observability

The Python services start through `opentelemetry-instrument`. Metrics are sent
to the Collector with OTLP over HTTP. Traces and logs are disabled. The metric
export interval is `10000` ms.

To update the Grafana dashboard, make changes in the Grafana UI, export the JSON,
and replace `observability/grafana/dashboards/url-shortener-metrics.json`.

## Testing Sharding 
- run docker
- creating urls ( e.g 
curl -X POST http://localhost:8080/create \
  -H "Content-Type: application/json" \
  -d '{"url":"https://example.com/a"}' )
- call each shard with the value of the created short-url at the end (e.g. curl -i http://localhost:9001/7Dw8Ew42)
- try with different localhost ports and if the url is not there then "404 Not Found" will pop up or else "200 OK" if it's there
- test redirect via API with the value of your short-url at the end again 
curl -i http://localhost:8080/7Dw8Ew42

# Documentation

## Overload Protection

Scaling the API tier out multiplies the load on each DB shard: `N` independent
API nodes can each fan out to the same shard, so a shard's aggregate concurrency
grows linearly with the node count. The DB tier is sharded (URLs are routed by a
hash of the code), so the guards are held **per shard** — a slow or dead shard
must not affect the healthy ones. Every DB call is guarded by self-implemented
primitives in [`services/api/overload.py`](services/api/overload.py):

- **Bulkhead (per shard)** — caps concurrent calls a node makes to *one shard*
  (`DB_SHARD_CONCURRENCY`). Terraform splits each shard's capacity across the
  deployed nodes (`DB_SHARD_CONCURRENCY = ceil(db_shard_capacity /
  api_server_count)`), so `api_server_count * DB_SHARD_CONCURRENCY` stays within
  what one shard can serve, regardless of node count. When no slot frees up
  within `DB_SHARD_ACQUIRE_TIMEOUT` the call is shed, not queued. Because each
  shard has its own bulkhead, a slow shard can only exhaust its own slots, never
  those of healthy shards.
- **Circuit breaker (per shard)** — after `BREAKER_THRESHOLD` consecutive
  failures to a shard it opens and fails fast for `BREAKER_COOLDOWN` seconds
  (then probes once), so a slow or dead shard cannot block API workers on calls
  to it — and only *that* shard is short-circuited.

The shared httpx connection pool is sized to `len(shards) * DB_SHARD_CONCURRENCY`
so a stalled shard cannot starve the pool and reintroduce cross-shard coupling.

## Functional Requirements

These are just some functional requirements we came up with before we started with the development.

### Create Short URL

The system shall provide:

```http
POST /create
```

Request body:

```json
{
  "url": "https://example.com/some/long/url"
}
```

The `url` query parameter is required and must contain a valid absolute URL.

The system shall generate a unique 8-character alphanumeric code, store it with the original URL, and return:

```json
{
  "shortUrl": "https://domain.com/a1B2c3D4"
}
```

### Access Short URL

The system shall provide:

```http
GET /<code>
```

If `<code>` exists, the system shall redirect to the stored original URL:

```http
302 Found
Location: <original-url>
```

If `<code>` does not exist, the system shall return:

```http
404 Not Found
```
