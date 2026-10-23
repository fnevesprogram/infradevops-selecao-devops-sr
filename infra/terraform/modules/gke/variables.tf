variable "project_id" {
  description = "ID do projeto no Google Cloud"
  type        = string
}

variable "region" {
  description = "Região do cluster GKE Autopilot"
  type        = string
  default     = "us-central1"
}

variable "cluster_name" {
  description = "Nome do cluster GKE Autopilot"
  type        = string
  default     = "comments-gke-cluster"
}

variable "network_id" {
  description = "ID da VPC Network"
  type        = string
}

variable "subnet_id" {
  description = "ID da sub-rede do GKE"
  type        = string
}

variable "pods_range_name" {
  description = "Nome do range secundário para pods"
  type        = string
  default     = "gke-pods"
}

variable "services_range_name" {
  description = "Nome do range secundário para services"
  type        = string
  default     = "gke-services"
}
