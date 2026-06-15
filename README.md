# URL Shortener

Small URL shortener for the Scalability Engineering prototype.

## What Runs

- `services/api`: FastAPI service on port `8080`
- `services/db`: FastAPI in-memory store on port `9000`
- OpenTelemetry Collector, Prometheus, and Grafana for metrics

The API talks to the DB service over HTTP. The DB stores everything in Python
hash maps, so data is lost when the DB container restarts.

## Local

Run everything with Docker:

```bash
make local
```

Open:

- API: `http://localhost:8080`
- Grafana: `http://localhost:3000`
- Prometheus: `http://localhost:9090`

Validate Python code:

```bash
python3 -m pip install -r requirements-dev.txt
make validate
```

## API

Create a short URL:

```bash
curl -X POST http://localhost:8080/create \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://example.com/some/long/url"}'
```

Response:

```json
{
  "shortUrl": "http://localhost:8080/a1B2c3D4"
}
```

Follow a short URL:

```bash
curl -i http://localhost:8080/a1B2c3D4
```

Known codes return `302`. Unknown codes return `404`. Invalid create payloads
return `400`.

## Observability

The Python services start through `opentelemetry-instrument`. Metrics are sent
to the Collector with OTLP over HTTP. Traces and logs are disabled. The metric
export interval is `10000` ms.

## Deployment

The deployment uses GCP Compute Engine, Artifact Registry, Docker, Terraform,
and `gcloud`. Defaults:

- `PROJECT_ID`: active `gcloud` project
- `REGION`: `europe-west3`
- `ZONE`: `europe-west3-a`
- `REPO_NAME`: `url-shortener`
- `TAG`: output of `whoami`

Build and push images:

```bash
make build-all
make push-all
```

Create or update infrastructure:

```bash
make deploy
make wait
```

Print URLs:

```bash
make outputs
```

Run integration tests against the deployed API:

```bash
make test-cloud
```

Restart VMs after pushing new images:

```bash
make restart-all
```

Destroy infrastructure:

```bash
make undeploy
```

Terraform manages VMs, networking, firewall rules, service account, and IAM. The
Artifact Registry repository must exist before pushing images.

Use the deployed API:

```bash
API_URL="$(terraform -chdir=infra output -raw base_url)"
curl -X POST "$API_URL/create" \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://example.com/some/long/url"}'
```
