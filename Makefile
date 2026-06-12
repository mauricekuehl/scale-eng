PROJECT_ID ?= $(shell gcloud config get-value project 2>/dev/null)
REGION ?= europe-west3
ZONE ?= europe-west3-a
REPO_NAME ?= url-shortener
TF_DIR ?= infra
TAG := $(shell whoami)
TF_AUTH := GOOGLE_OAUTH_ACCESS_TOKEN="$$(gcloud auth print-access-token)"

ARTIFACT_HOST := $(REGION)-docker.pkg.dev
API_IMAGE := $(ARTIFACT_HOST)/$(PROJECT_ID)/$(REPO_NAME)/api:$(TAG)
API_LATEST_IMAGE := $(ARTIFACT_HOST)/$(PROJECT_ID)/$(REPO_NAME)/api:latest
DB_IMAGE := $(ARTIFACT_HOST)/$(PROJECT_ID)/$(REPO_NAME)/db:$(TAG)
DB_LATEST_IMAGE := $(ARTIFACT_HOST)/$(PROJECT_ID)/$(REPO_NAME)/db:latest
LOCAL_API_IMAGE := url-shortener-api:local
LOCAL_DB_IMAGE := url-shortener-db:local
LOCAL_NETWORK := url-shortener-local
PLATFORM ?= linux/amd64

.PHONY: deploy undeploy build-api build-db build-all push-api push-db push-all run-local restart-api restart-db restart-all wait outputs

deploy:
	gcloud services enable serviceusage.googleapis.com compute.googleapis.com artifactregistry.googleapis.com iam.googleapis.com --project=$(PROJECT_ID)
	$(TF_AUTH) terraform -chdir=$(TF_DIR) init
	$(TF_AUTH) terraform -chdir=$(TF_DIR) apply \
		-var="project_id=$(PROJECT_ID)" \
		-var="region=$(REGION)" \
		-var="zone=$(ZONE)" \
		-var="repo_name=$(REPO_NAME)" \
		-var="image_tag=$(TAG)"

undeploy:
	$(TF_AUTH) terraform -chdir=$(TF_DIR) destroy \
		-var="project_id=$(PROJECT_ID)" \
		-var="region=$(REGION)" \
		-var="zone=$(ZONE)" \
		-var="repo_name=$(REPO_NAME)" \
		-var="image_tag=$(TAG)"

build-api:
	docker build --platform $(PLATFORM) -f services/api/Dockerfile \
		-t $(API_IMAGE) \
		-t $(API_LATEST_IMAGE) \
		.

build-db:
	docker build --platform $(PLATFORM) -f services/db/Dockerfile \
		-t $(DB_IMAGE) \
		-t $(DB_LATEST_IMAGE) \
		.

build-all: build-api build-db

push-api:
	gcloud auth configure-docker $(ARTIFACT_HOST) --quiet
	docker push $(API_IMAGE)
	docker push $(API_LATEST_IMAGE)

push-db:
	gcloud auth configure-docker $(ARTIFACT_HOST) --quiet
	docker push $(DB_IMAGE)
	docker push $(DB_LATEST_IMAGE)

push-all: push-api push-db

run-local:
	docker build -f services/db/Dockerfile -t $(LOCAL_DB_IMAGE) .
	docker build -f services/api/Dockerfile -t $(LOCAL_API_IMAGE) .
	docker network create $(LOCAL_NETWORK) >/dev/null 2>&1 || true
	docker rm -f url-shortener-db url-shortener-api >/dev/null 2>&1 || true
	docker run -d --name url-shortener-db --network $(LOCAL_NETWORK) -p 9000:9000 -e HTTP_ADDR=:9000 $(LOCAL_DB_IMAGE)
	@echo "API running at http://localhost:8080"
	@echo "Press Ctrl+C to stop local containers"
	@trap 'docker rm -f url-shortener-api url-shortener-db >/dev/null 2>&1 || true' INT TERM EXIT; \
	docker run --rm --name url-shortener-api --network $(LOCAL_NETWORK) -p 8080:8080 \
		-e HTTP_ADDR=:8080 \
		-e BASE_URL=http://localhost:8080 \
		-e DB_URL=http://url-shortener-db:9000 \
		$(LOCAL_API_IMAGE)

restart-api:
	gcloud compute instances reset "$$(terraform -chdir=$(TF_DIR) output -raw api_vm_name)" \
		--project=$(PROJECT_ID) \
		--zone=$(ZONE)

restart-db:
	gcloud compute instances reset "$$(terraform -chdir=$(TF_DIR) output -raw db_vm_name)" \
		--project=$(PROJECT_ID) \
		--zone=$(ZONE)

restart-all: restart-db restart-api

wait:
	@API_URL="$$(terraform -chdir=$(TF_DIR) output -raw base_url)"; \
	echo "Waiting for $$API_URL ..."; \
	for i in $$(seq 1 60); do \
		status="$$(curl -s -o /dev/null -w '%{http_code}' "$$API_URL/unknown1" || true)"; \
		if [ "$$status" = "404" ]; then \
			echo "Ready: $$API_URL"; \
			exit 0; \
		fi; \
		echo "Still starting ($$status)"; \
		sleep 5; \
	done; \
	echo "Timed out waiting for $$API_URL"; \
	exit 1

outputs:
	terraform -chdir=$(TF_DIR) output
