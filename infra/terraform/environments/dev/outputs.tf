output "gke_cluster_name" {
  description = "Nome do cluster GKE Autopilot criado"
  value       = module.gke.cluster_name
}

output "gke_cluster_endpoint" {
  description = "Endpoint do cluster GKE"
  value       = module.gke.cluster_endpoint
}

output "gke_autopilot_enabled" {
  description = "Cluster provisionado em modo Autopilot"
  value       = module.gke.enable_autopilot
}

output "cloudsql_instance_name" {
  description = "Nome da instância Cloud SQL"
  value       = module.cloudsql.instance_name
}

output "cloudsql_private_ip" {
  description = "IP Privado do Cloud SQL"
  value       = module.cloudsql.private_ip_address
}

output "secret_manager_id" {
  description = "ID do Secret no Secret Manager"
  value       = module.secrets.secret_id
}

output "workload_identity_provider" {
  description = "Provider OIDC para configurar no GitHub Actions"
  value       = module.workload_identity_federation.workload_identity_provider
}

output "github_actions_sa_email" {
  description = "Service Account do GitHub Actions"
  value       = module.workload_identity_federation.service_account_email
}

output "artifact_registry_repository" {
  description = "ID do repositório Docker no Artifact Registry"
  value       = module.artifact_registry.repository_id
}

output "artifact_registry_url" {
  description = "URL base das imagens (região-docker.pkg.dev/project/repo)"
  value       = module.artifact_registry.repository_url
}
