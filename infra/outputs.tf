output "api_external_ip" {
  description = "Public external IPv4 address of the API VM."
  value       = google_compute_address.api.address
}

output "api_internal_ip" {
  description = "Internal IPv4 address of the API VM."
  value       = google_compute_instance.api.network_interface[0].network_ip
}

output "db_internal_ip" {
  description = "Internal IPv4 address of the DB VM."
  value       = google_compute_instance.db.network_interface[0].network_ip
}

output "api_vm_name" {
  description = "Compute Engine instance name for the API VM."
  value       = google_compute_instance.api.name
}

output "db_vm_name" {
  description = "Compute Engine instance name for the DB VM."
  value       = google_compute_instance.db.name
}

output "base_url" {
  description = "Default HTTP base URL for the public API."
  value       = "http://${google_compute_address.api.address}"
}
