# URL Shortener
> Part of Prototyping assignment in SoSe2026 Scalability Engineering  

## Implementation

This repository contains the MVP as two Go HTTP services:

- `services/api`: public API on container port `8080`
- `services/db`: private in-memory DB on container port `9000`

The API stores generated codes through the private DB service and redirects known
codes to their original URLs. The DB keeps data in memory only.

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

The `url` field is required and must contain a valid absolute URL.

The system shall generate a unique 8-character alphanumeric code, store it with
the original URL, and return:

```json
{
  "shortUrl": "https://domain.com/a1B2c3D4"
}
```

Invalid JSON, missing URLs, malformed URLs, relative URLs, and non-HTTP(S) URLs
return `400 Bad Request`.

Creating the same URL again returns the same short URL while the DB node is
running.

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

## Local Development

Run both services locally with Docker:

```bash
make run-local
```

The API is then available at `http://localhost:8080`. Press Ctrl+C in the
`make run-local` terminal to stop the local containers.

You can also run the services directly in separate terminals:

```bash
HTTP_ADDR=:9000 go run ./services/db
HTTP_ADDR=:8080 DB_URL=http://localhost:9000 BASE_URL=http://localhost:8080 go run ./services/api
```

## Usage

Create a short URL:

```bash
curl -X POST http://localhost:8080/create \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://example.com/some/long/url"}'
```

Example response:

```json
{
  "shortUrl": "http://localhost:8080/a1B2c3D4"
}
```

Calling `POST /create` again with the same `url` returns the same `shortUrl`.

Open the short URL in a browser or follow it with curl:

```bash
curl -i http://localhost:8080/a1B2c3D4
```

Expected response:

```http
HTTP/1.1 302 Found
Location: https://example.com/some/long/url
```

Create and immediately follow a short URL from the shell:

```bash
SHORT_URL="$(curl -s -X POST http://localhost:8080/create \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://example.com/some/long/url"}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["shortUrl"])')"

curl -L "$SHORT_URL"
```

Invalid URLs return `400`:

```bash
curl -i -X POST http://localhost:8080/create \
  -H 'Content-Type: application/json' \
  -d '{"url":"not-a-url"}'
```

Unknown short codes return `404`:

```bash
curl -i http://localhost:8080/unknown1
```

## GCP Deployment

The deployment uses GCP Compute Engine, Artifact Registry, Docker, Terraform,
and `gcloud`.

Defaults:

- `PROJECT_ID`: active `gcloud` project
- `REGION`: `europe-west3`
- `ZONE`: `europe-west3-a`
- `REPO_NAME`: `url-shortener`
- `TAG`: local OS username from `whoami`
- `PLATFORM`: `linux/amd64`

Create or update infrastructure:

```bash
make deploy
make wait
```

The VMs run their containers from Terraform-managed startup scripts. On boot,
each VM pulls its configured image from Artifact Registry and starts Docker.
Terraform manages the VMs, network, firewall rules, service account, and IAM.
The Docker registry was created once with `gcloud artifacts repositories create`.

Build both images locally:

```bash
make build-all
```

Push both images to Artifact Registry:

```bash
make push-all
```

Restart both VMs so their startup scripts pull the pushed images:

```bash
make restart-all
make wait
```

Or restart only one component:

```bash
make restart-api
make restart-db
```

Full API update:

```bash
make build-api
make push-api
make restart-api
```

Full DB update:

```bash
make build-db
make push-db
make restart-db
```

Show Terraform outputs:

```bash
make outputs
```

Destroy the Terraform-managed infrastructure:

```bash
make undeploy
```

This removes the VMs, network, firewall rules, service account, NAT/router, and
static IP. It does not delete the Artifact Registry repository or pushed images.

After deployment, set `API_URL` to the public service URL:

```bash
API_URL="$(terraform -chdir=infra output -raw base_url)"
```

Then use the deployed service the same way as the local service:

```bash
curl -X POST "$API_URL/create" \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://example.com/some/long/url"}'
```

`make deploy` applies Terraform infrastructure. `make build-api` and `make
build-db` only build local Docker images. `make push-api` and `make push-db`
only push images to Artifact Registry. `make restart-api` and `make restart-db`
only reset the relevant VM. The reset reruns that VM's startup script, which
pulls the current image for your `TAG`.

## Custom Domain

By default the service is reachable at `http://<api-external-ip>`. For a custom
domain, create an `A` record pointing the domain to the API VM external IP, then
deploy the API with a matching `BASE_URL` value. The MVP does not automate DNS or
TLS certificates.
