output "network_id" {
  description = "ID da VPC criada"
  value       = google_compute_network.vpc.id
}

output "network_name" {
  description = "Nome da VPC criada"
  value       = google_compute_network.vpc.name
}

output "subnet_id" {
  description = "ID da sub-rede principal"
  value       = google_compute_subnetwork.subnet.id
}

output "subnet_name" {
  description = "Nome da sub-rede principal"
  value       = google_compute_subnetwork.subnet.name
}

output "pods_range_name" {
  description = "Nome do range secundário para pods"
  value       = "gke-pods"
}

output "services_range_name" {
  description = "Nome do range secundário para services"
  value       = "gke-services"
}

output "private_vpc_connection" {
  description = "Conexão de peering com o Service Networking"
  value       = google_service_networking_connection.private_vpc_connection.id
}
