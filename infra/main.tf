locals {
  name_prefix   = "url-shortener"
  api_name      = "${local.name_prefix}-api"
  db_name       = "${local.name_prefix}-db"
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

resource "google_compute_firewall" "api_http" {
  name    = "${local.name_prefix}-api-http"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["url-shortener-api"]
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

resource "google_compute_address" "api" {
  name   = "${local.name_prefix}-api-ip"
  region = var.region
}

resource "google_compute_instance" "api" {
  name         = local.api_name
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

    access_config {
      nat_ip = google_compute_address.api.address
    }
  }

  metadata_startup_script = templatefile("${path.module}/startup-api.sh.tftpl", {
    artifact_host = local.artifact_host
    image_uri     = local.api_image
    base_url      = "http://${google_compute_address.api.address}"
    db_url        = "http://${google_compute_instance.db.network_interface[0].network_ip}:9000"
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
  })

  service_account {
    email  = google_service_account.vm.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  depends_on = [
    google_project_iam_member.vm_artifact_reader,
  ]
}
