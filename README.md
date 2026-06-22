# URL Shortener

Small URL shortener for the Scalability Engineering prototype.

## What Runs

- `services/api`: FastAPI service on port `8080`
- `services/db`: FastAPI in-memory store on port `9000`
- OpenTelemetry Collector, Prometheus, and Grafana for metrics

The API talks to the DB service over HTTP. The DB stores data in Python hash
maps, so all URLs are lost when the DB container restarts.

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
- Grafana: `http://localhost:3000`
- Prometheus: `http://localhost:9090`

## Cloud Deployment

Defaults:

- `PROJECT_ID`: active `gcloud` project
- `REGION`: `europe-west3`
- `ZONE`: `europe-west3-a`
- `REPO_NAME`: `url-shortener`
- `TAG`: output of `whoami`

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

## Functional Requirements

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
