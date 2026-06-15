# URL Shortener MVP

## Summary
Two Python FastAPI services:

- `api`: public service, creates short URLs and redirects known codes.
- `db`: private in-memory hash map service.

Docker is the only supported runtime path. Local development uses:

```bash
make local
```

Deployment uses Terraform-managed GCP Compute Engine VMs. Images are built and
pushed with Docker, then pulled by VM startup scripts.

OpenTelemetry metrics use Python autoinstrumentation, OTLP over HTTP, and a
10-second metric export interval.

Out of scope for the MVP: persistence, replication, auth, sharding, caching,
TLS automation, and custom domain automation.
