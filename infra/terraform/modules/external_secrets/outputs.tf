output "namespace" {
  description = "Namespace onde o External Secrets Operator foi instalado"
  value       = helm_release.external_secrets.namespace
}

output "release_name" {
  description = "Nome do release do Helm para o External Secrets Operator"
  value       = helm_release.external_secrets.name
}

output "service_account_email" {
  description = "Email da Service Account GCP associada ao ESO via Workload Identity"
  value       = google_service_account.eso_sa.email
}
