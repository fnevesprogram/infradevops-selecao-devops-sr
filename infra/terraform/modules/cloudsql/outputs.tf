output "instance_name" {
  description = "Nome da instância Cloud SQL"
  value       = google_sql_database_instance.postgres.name
}

output "instance_connection_name" {
  description = "Connection name para Cloud SQL Auth Proxy"
  value       = google_sql_database_instance.postgres.connection_name
}

output "private_ip_address" {
  description = "IP Privado da instância PostgreSQL"
  value       = google_sql_database_instance.postgres.private_ip_address
}

output "database_name" {
  description = "Nome da base de dados"
  value       = google_sql_database.database.name
}

output "database_user" {
  description = "Usuário do banco de dados"
  value       = google_sql_user.user.name
}

output "database_password" {
  description = "Senha gerada para o banco"
  value       = random_password.db_password.result
  sensitive   = true
}

output "connection_url" {
  description = "Database URL completa formatada para asyncpg"
  value       = "postgresql+asyncpg://${google_sql_user.user.name}:${random_password.db_password.result}@${google_sql_database_instance.postgres.private_ip_address}:5432/${google_sql_database.database.name}"
  sensitive   = true
}
