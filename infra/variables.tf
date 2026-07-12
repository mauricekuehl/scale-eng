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

variable "db_zone" {
  description = "Optional GCP zone for DB VMs. Defaults to zone when unset."
  type        = string
  default     = null

  validation {
    condition     = var.db_zone == null || can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.db_zone))
    error_message = "db_zone must be a valid GCP zone, for example europe-west4-a."
  }
}

variable "repo_name" {
  description = "Artifact Registry Docker repository name."
  type        = string
  default     = "url-shortener"
}

variable "api_machine_type" {
  description = "Compute Engine machine type for each private API VM."
  type        = string
  # Use non-shared 1-vCPU VMs for more predictable perf-test results.
  default = "t2d-standard-1"
}

variable "api_server_count" {
  description = "Number of private API VMs behind the Nginx load balancer."
  type        = number
  default     = 5

  validation {
    condition     = var.api_server_count > 0
    error_message = "api_server_count must be greater than 0."
  }
}

variable "lb_machine_type" {
  description = "Compute Engine machine type for the public Nginx load balancer VM."
  type        = string
  default     = "t2d-standard-1"
}

variable "cache_capacity" {
  description = "Per-node API read-cache capacity (entries). 0 or less disables the cache."
  type        = number
  default     = 1000
}

variable "db_shard_capacity" {
  description = "Concurrency a single DB shard can serve. Split evenly across API nodes into the per-node, per-shard bulkhead limit DB_SHARD_CONCURRENCY = ceil(this / api_server_count), so scaling the API tier out cannot overload any shard."
  type        = number
  default     = 10000
}

variable "db_shard_replication_factor" {
  description = "Number of DB shards each short code is replicated to for shuffle sharding."
  type        = number
  default     = 2
}

variable "db_shard_acquire_timeout" {
  description = "Seconds an API node waits for a free per-shard slot before shedding the request (fast-fail)."
  type        = number
  default     = 0.05
}

variable "breaker_threshold" {
  description = "Consecutive failures to one shard before that shard's per-node circuit breaker opens."
  type        = number
  default     = 5
}

variable "breaker_cooldown" {
  description = "Seconds a shard's circuit breaker stays open before probing it again."
  type        = number
  default     = 2.0
}

variable "db_machine_type" {
  description = "Compute Engine machine type for the private DB VM."
  type        = string
  # Use non-shared 1-vCPU VMs for more predictable perf-test results.
  default = "t2d-standard-1"
}

variable "db_server_count" {
  description = "Number of private DB shard VMs."
  type        = number
  default     = 3

  validation {
    condition     = var.db_server_count > 0
    error_message = "db_server_count must be greater than 0."
  }
}

variable "observability_machine_type" {
  description = "Compute Engine machine type for the observability VM."
  type        = string
  default     = "t2d-standard-1"
}

variable "image_tag" {
  description = "Docker image tag to run on the VMs."
  type        = string
  default     = "latest"
}
