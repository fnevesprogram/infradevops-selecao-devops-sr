variable "project_id" {
  description = "ID do projeto no Google Cloud"
  type        = string
}

variable "region" {
  description = "Região principal dos recursos"
  type        = string
  default     = "us-central1"
}

variable "network_name" {
  description = "Nome da VPC Network"
  type        = string
  default     = "comments-vpc"
}

variable "subnet_cidr" {
  description = "CIDR range da subnet principal"
  type        = string
  default     = "10.0.0.0/20"
}

variable "pods_cidr" {
  description = "CIDR range secundário para pods do GKE"
  type        = string
  default     = "10.4.0.0/14"
}

variable "services_cidr" {
  description = "CIDR range secundário para services do GKE"
  type        = string
  default     = "10.8.0.0/20"
}
