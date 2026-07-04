locals {
  name_prefix   = "url-shortener"
  api_name      = "${local.name_prefix}-api"
  lb_name       = "${local.name_prefix}-lb"
  db_name       = "${local.name_prefix}-db"
  obs_name      = "${local.name_prefix}-observability"
  artifact_host = "${var.region}-docker.pkg.dev"
  api_image     = "${local.artifact_host}/${var.project_id}/${var.repo_name}/api:${var.image_tag}"
  db_image      = "${local.artifact_host}/${var.project_id}/${var.repo_name}/db:${var.image_tag}"
}

resource "google_project_service" "required" {
  for_each = toset([
    "artifactregistry.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
  ])

  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

resource "google_service_account" "vm" {
  account_id   = "${local.name_prefix}-vm"
  display_name = "URL shortener VM service account"

  depends_on = [google_project_service.required]
}

resource "google_project_iam_member" "vm_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.vm.email}"
}

resource "google_compute_network" "main" {
  name                    = "${local.name_prefix}-net"
  auto_create_subnetworks = false

  depends_on = [google_project_service.required]
}

resource "google_compute_subnetwork" "main" {
  name          = "${local.name_prefix}-subnet"
  ip_cidr_range = "10.10.0.0/24"
  region        = var.region
  network       = google_compute_network.main.id
}

resource "google_compute_router" "main" {
  name    = "${local.name_prefix}-router"
  region  = var.region
  network = google_compute_network.main.id
}

resource "google_compute_router_nat" "main" {
  name                               = "${local.name_prefix}-nat"
  router                             = google_compute_router.main.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_compute_firewall" "lb_http" {
  name    = "${local.name_prefix}-lb-http"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["url-shortener-lb"]
}

resource "google_compute_firewall" "api_http_internal" {
  name    = "${local.name_prefix}-api-http-internal"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_tags = ["url-shortener-lb"]
  target_tags = ["url-shortener-api"]
}

resource "google_compute_firewall" "db_internal" {
  name    = "${local.name_prefix}-db-internal"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["9000"]
  }

  source_tags = ["url-shortener-api"]
  target_tags = ["url-shortener-db"]
}

resource "google_compute_firewall" "observability_otlp_internal" {
  name    = "${local.name_prefix}-observability-otlp-internal"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["4318"]
  }

  source_tags = ["url-shortener-api", "url-shortener-db"]
  target_tags = ["url-shortener-observability"]
}

resource "google_compute_firewall" "observability_grafana" {
  name    = "${local.name_prefix}-observability-grafana"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["3000"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["url-shortener-observability"]
}

resource "google_compute_firewall" "lb_metrics_internal" {
  name    = "${local.name_prefix}-lb-metrics-internal"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["9113", "9100"]
  }

  source_tags = ["url-shortener-observability"]
  target_tags = ["url-shortener-lb"]
}

resource "google_compute_address" "lb" {
  name   = "${local.name_prefix}-lb-ip"
  region = var.region
}

resource "google_compute_address" "observability" {
  name   = "${local.name_prefix}-observability-ip"
  region = var.region
}

resource "google_compute_instance" "observability" {
  name         = local.obs_name
  machine_type = var.observability_machine_type
  zone         = var.zone
  tags         = ["url-shortener-observability"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.main.id

    access_config {
      nat_ip = google_compute_address.observability.address
    }
  }

  metadata_startup_script = templatefile("${path.module}/startup-observability.sh.tftpl", {
    dashboard_json    = file("${path.module}/../observability/grafana/dashboards/url-shortener-metrics.json")
    lb_metrics_target = "${local.lb_name}.${var.zone}.c.${var.project_id}.internal:9113"
    lb_node_target    = "${local.lb_name}.${var.zone}.c.${var.project_id}.internal:9100"
  })

  service_account {
    email  = google_service_account.vm.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  depends_on = [
    google_project_iam_member.vm_artifact_reader,
  ]
}

resource "google_compute_instance" "lb" {
  name         = local.lb_name
  machine_type = var.lb_machine_type
  zone         = var.zone
  tags         = ["url-shortener-lb"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.main.id

    access_config {
      nat_ip = google_compute_address.lb.address
    }
  }

  metadata_startup_script = templatefile("${path.module}/startup-lb.sh.tftpl", {
    api_upstreams = google_compute_instance.api[*].network_interface[0].network_ip
  })

  service_account {
    email  = google_service_account.vm.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
}

resource "google_compute_instance" "api" {
  count        = var.api_server_count
  name         = "${local.api_name}-${count.index + 1}"
  machine_type = var.api_machine_type
  zone         = var.zone
  tags         = ["url-shortener-api"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.main.id
  }

  metadata_startup_script = templatefile("${path.module}/startup-api.sh.tftpl", {
    artifact_host  = local.artifact_host
    image_uri      = local.api_image
    base_url       = "http://${google_compute_address.lb.address}"
    db_url         = "http://${google_compute_instance.db.network_interface[0].network_ip}:9000"
    otel_endpoint  = "http://${google_compute_instance.observability.network_interface[0].network_ip}:4318"
    cache_capacity = var.cache_capacity
    # Split the DB's global concurrency budget across the deployed API nodes so
    # that api_server_count * db_concurrency stays within what the DB can serve.
    db_concurrency     = ceil(var.db_total_concurrency / var.api_server_count)
    db_acquire_timeout = var.db_acquire_timeout
    breaker_threshold  = var.breaker_threshold
    breaker_cooldown   = var.breaker_cooldown
  })

  service_account {
    email  = google_service_account.vm.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  depends_on = [
    google_project_iam_member.vm_artifact_reader,
  ]
}

resource "google_compute_instance" "db" {
  name         = local.db_name
  machine_type = var.db_machine_type
  zone         = var.zone
  tags         = ["url-shortener-db"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.main.id
  }

  metadata_startup_script = templatefile("${path.module}/startup-db.sh.tftpl", {
    artifact_host = local.artifact_host
    image_uri     = local.db_image
    otel_endpoint = "http://${google_compute_instance.observability.network_interface[0].network_ip}:4318"
  })

  service_account {
    email  = google_service_account.vm.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  depends_on = [
    google_project_iam_member.vm_artifact_reader,
  ]
}
