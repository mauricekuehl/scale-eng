variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region for Artifact Registry and regional resources."
  type        = string
  default     = "europe-west3"
}

variable "zone" {
  description = "GCP zone for Compute Engine VMs."
  type        = string
  default     = "europe-west3-a"
}

variable "repo_name" {
  description = "Artifact Registry Docker repository name."
  type        = string
  default     = "url-shortener"
}

variable "api_machine_type" {
  description = "Compute Engine machine type for the public API VM."
  type        = string
  # Use non-shared 1-vCPU VMs for more predictable perf-test results.
  default = "t2d-standard-1"
}

variable "db_machine_type" {
  description = "Compute Engine machine type for the private DB VM."
  type        = string
  # Use non-shared 1-vCPU VMs for more predictable perf-test results.
  default = "t2d-standard-1"
}

variable "observability_machine_type" {
  description = "Compute Engine machine type for the observability VM."
  type        = string
  default     = "e2-micro"
}

variable "image_tag" {
  description = "Docker image tag to run on the VMs."
  type        = string
  default     = "latest"
}
