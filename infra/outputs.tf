output "lb_external_ip" {
  description = "Public external IPv4 address of the Nginx load balancer VM."
  value       = google_compute_address.lb.address
}

output "api_internal_ips" {
  description = "Internal IPv4 addresses of the private API VMs."
  value       = google_compute_instance.api[*].network_interface[0].network_ip
}

output "db_internal_ip" {
  description = "Internal IPv4 address of the first DB shard VM."
  value       = google_compute_instance.db[0].network_interface[0].network_ip
}

output "db_internal_ips" {
  description = "Internal IPv4 addresses of the DB shard VMs."
  value       = google_compute_instance.db[*].network_interface[0].network_ip
}

output "observability_external_ip" {
  description = "Public external IPv4 address of the observability VM."
  value       = google_compute_address.observability.address
}

output "observability_internal_ip" {
  description = "Internal IPv4 address of the observability VM."
  value       = google_compute_instance.observability.network_interface[0].network_ip
}

output "lb_vm_name" {
  description = "Compute Engine instance name for the load balancer VM."
  value       = google_compute_instance.lb.name
}

output "api_vm_names" {
  description = "Compute Engine instance names for the API VMs."
  value       = google_compute_instance.api[*].name
}

output "db_vm_name" {
  description = "Compute Engine instance name for the first DB shard VM."
  value       = google_compute_instance.db[0].name
}

output "db_vm_names" {
  description = "Compute Engine instance names for the DB shard VMs."
  value       = google_compute_instance.db[*].name
}

output "observability_vm_name" {
  description = "Compute Engine instance name for the observability VM."
  value       = google_compute_instance.observability.name
}

output "base_url" {
  description = "Default HTTP base URL for the public API."
  value       = "http://${google_compute_address.lb.address}"
}

output "grafana_url" {
  description = "Public Grafana URL for metrics dashboards."
  value       = "http://${google_compute_address.observability.address}:3000"
}
