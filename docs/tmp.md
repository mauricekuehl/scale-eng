## MVP

- 1 API server Node
    - GO
- 1 DB Node
    - GO 

## Benchmarking

- K6
- Test write and read seperatly (Focus on Read)
- Track:
    - throughput
    - latency
- Use realistic access distribution of url (May use different distrubution)

## Random ideas

- If time:
    - Benchmark performance on Node going down
- load shredding
- use circsut breaker
- caching
- sharding

## Deployment

Updated summary for the agent:

Use **GCP Compute Engine + Terraform + Artifact Registry + Cloud Build + Docker + Makefile**.

Goal: deploy different Docker apps to different explicitly declared GCP VM node types, with simple commands.

Architecture:

* Terraform creates infrastructure only:

  * Compute Engine VMs
  * explicit machine/node types per VM, e.g. `e2-micro`, `e2-small`
  * Artifact Registry Docker repo
  * firewall rules
  * service account + IAM permission to pull images
* Do **not** use startup scripts for app deployment.
* Optional startup script is okay only for base setup, like installing Docker.
* Docker app deployment happens via SSH commands from a Makefile/script.
* Each VM runs one specific container image:

  * `uni-frontend` → `frontend`
  * `uni-backend` → `backend`
  * `uni-worker` → `worker`

Terraform should explicitly declare node types, for example:

```hcl
nodes = {
  frontend = {
    machine_type = "e2-micro"
    image_name   = "frontend"
    host_port    = 80
    container_port = 80
  }

  backend = {
    machine_type = "e2-micro"
    image_name   = "backend"
    host_port    = 8080
    container_port = 8080
  }

  worker = {
    machine_type = "e2-micro"
    image_name   = "worker"
    host_port    = 9000
    container_port = 9000
  }
}
```

Desired commands:

```bash
make infra        # terraform init/apply
make build-all    # build and push all Docker images to Artifact Registry
make deploy-all   # SSH into each VM, docker pull, stop old container, run new one
```

For individual updates:

```bash
make build-backend
make deploy-backend
```

Use the **local OS username** as the Docker image tag instead of Git commit tags, to avoid creating many unique image versions:

```makefile
TAG := $(shell whoami)
```

Image format:

```bash
REGION-docker.pkg.dev/PROJECT_ID/REPO_NAME/APP_NAME:$(whoami)
```

Deployment command pattern:

```bash
docker pull IMAGE_URI
docker rm -f APP_NAME || true
docker run -d --name APP_NAME --restart unless-stopped -p HOST_PORT:CONTAINER_PORT IMAGE_URI
```

Keep responsibilities separated:

```text
Terraform:
  infrastructure, explicit VM node types, networking, IAM, registry

Makefile/scripts:
  build images, push images, hot deploy containers
```

Use cheap VM types such as `e2-micro` by default unless a specific service needs more resources.
