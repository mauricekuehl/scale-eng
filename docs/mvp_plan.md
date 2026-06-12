# URL Shortener MVP Implementation Plan

## Summary
Build the README URL shortener as two Go services: one public API node and one private in-memory DB node. Deploy both to GCP Compute Engine with Terraform-managed infrastructure, Artifact Registry images, Cloud Build-based builds, and Makefile commands for build/push/deploy workflows.

## Key Changes
- Add Go services:
  - `api`: public HTTP service on container port `8080`.
  - `db`: private HTTP service on container port `9000`, backed by a `map[string]string` protected by `sync.RWMutex`.
- Public API:
  - `POST /create` accepts JSON body `{ "url": "https://..." }`.
  - Return `400` for missing, malformed, or non-absolute URLs.
  - Generate unique 8-character alphanumeric codes, store via DB node, return `{ "shortUrl": "<BASE_URL>/<code>" }`.
  - `GET /{code}` returns `302 Location: <original-url>` when found, otherwise `404`.
- Internal DB API:
  - `GET /{code}` returns `{ "url": "..." }` or `404`.
  - No persistence, replication, auth, sharding, or caching for MVP.
- Deployment:
  - Terraform creates Artifact Registry, two Compute Engine VMs, firewall rules, service account/IAM for image pulls, and outputs public API IP.
  - API VM has public HTTP ingress on port `80`; DB VM only allows internal traffic from the API VM on port `9000`.
  - Docker containers run one service per VM with `--restart unless-stopped`.
  - API container receives `BASE_URL` and `DB_URL=http://<db-internal-ip>:9000`.
- allow https and https

## Build And Deploy Commands
- Add Make targets:
  - `make infra`: `terraform init` and `terraform apply`.
  - `make build-api`, `make build-db`, `make build-all`.
  - `make deploy-api`, `make deploy-db`, `make deploy-all`.
- Use:
  - `TAG := $(shell whoami)`.
  - Push both `:$(TAG)` and `:latest` for each image.
  - Image format: `REGION-docker.pkg.dev/PROJECT_ID/REPO_NAME/APP_NAME:TAG`.
- Use Cloud Build for image builds, with Dockerfiles per service and Artifact Registry as the destination.

## Domain Handling
- Default MVP access is `http://<api-external-ip>` from Terraform output.
- If a custom domain is provided, document adding an `A` record to the API VM external IP through Cloud DNS or the user’s DNS provider.
- Do not assume a free Google-provided public subdomain for Compute Engine; Google’s docs describe using external IPs and custom domain DNS records for VM-hosted apps.

Sources: [Cloud DNS domain setup](https://docs.cloud.google.com/dns/docs/tutorials/create-domain-tutorial), [Compute Engine internal DNS/custom hostname note](https://docs.cloud.google.com/compute/docs/internal-dns).

## Test Plan
- Deployment smoke test:
  - After `make deploy-all`, run `curl -X POST http://<api-ip>/create ...`.
  - Follow returned short URL and verify redirect.

## Assumptions
- README’s JSON request body is the source of truth; the sentence saying "`url` query parameter" is treated as a typo.
- Region defaults to `europe-west3`, with `PROJECT_ID`, `REGION`, and repo name configurable.
- `e2-micro` is the default VM type for both API and DB unless performance testing later requires larger nodes.
- Persistent storage, multiple DB nodes, load balancing, Cloud DNS automation, and benchmarking are out of MVP scope.
