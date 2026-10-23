output "workload_identity_provider" {
  description = "Nome do Provider OIDC para uso no GitHub Actions"
  value       = google_iam_workload_identity_pool_provider.provider.name
}

output "service_account_email" {
  description = "Email da Service Account utilizada pelo CI/CD"
  value       = google_service_account.github_actions_sa.email
}
