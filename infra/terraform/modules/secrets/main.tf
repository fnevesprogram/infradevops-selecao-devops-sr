resource "google_secret_manager_secret" "secret" {
  secret_id = var.secret_id
  project   = var.project_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "version" {
  secret      = google_secret_manager_secret.secret.id
  secret_data = var.secret_data
}

resource "google_secret_manager_secret_iam_member" "accessor" {
  count     = var.accessor_member != "" ? 1 : 0
  project   = var.project_id
  secret_id = google_secret_manager_secret.secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = var.accessor_member
}
