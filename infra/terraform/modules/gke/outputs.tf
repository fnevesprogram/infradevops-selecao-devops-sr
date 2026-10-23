output "cluster_name" {
  description = "Nome do cluster GKE Autopilot"
  value       = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  description = "Endpoint do cluster GKE"
  value       = google_container_cluster.primary.endpoint
}

output "cluster_ca_certificate" {
  description = "Certificado CA do cluster GKE"
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "Workload Identity Pool do GKE (nativo no Autopilot)"
  value       = "${var.project_id}.svc.id.goog"
}

output "enable_autopilot" {
  description = "Indica que o cluster opera em modo Autopilot"
  value       = true
}
