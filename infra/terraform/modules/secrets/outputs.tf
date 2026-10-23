output "secret_id" {
  description = "ID do Secret no Secret Manager"
  value       = google_secret_manager_secret.secret.secret_id
}

output "secret_name" {
  description = "Nome do resource Secret no GCP"
  value       = google_secret_manager_secret.secret.name
}
