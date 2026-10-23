output "repository_id" {
  description = "ID do repositório Artifact Registry"
  value       = google_artifact_registry_repository.docker.repository_id
}

output "repository_url" {
  description = "URL base para imagens Docker (sem tag)"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker.repository_id}"
}
