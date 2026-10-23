variable "project_id" {
  description = "ID do projeto no Google Cloud"
  type        = string
}

variable "region" {
  description = "Região da instância Cloud SQL"
  type        = string
  default     = "us-central1"
}

variable "instance_name" {
  description = "Nome da instância Cloud SQL"
  type        = string
  default     = "comments-postgres-db"
}

variable "database_version" {
  description = "Versão do PostgreSQL"
  type        = string
  default     = "POSTGRES_16"
}

variable "tier" {
  description = "Tier de máquina (custo reduzido para testes)"
  type        = string
  default     = "db-f1-micro"
}

variable "network_id" {
  description = "ID da VPC Network para Private IP"
  type        = string
}

variable "private_vpc_connection" {
  description = "Dependência da conexão privada VPC (Service Networking)"
  type        = string
}

variable "db_name" {
  description = "Nome do database inicial"
  type        = string
  default     = "comments"
}

variable "db_user" {
  description = "Nome do usuário do banco"
  type        = string
  default     = "comments_user"
}
