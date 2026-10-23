variable "project_id" {
  description = "ID do projeto no Google Cloud"
  type        = string
}

variable "secret_id" {
  description = "ID do segredo no Secret Manager"
  type        = string
  default     = "comments-db-url"
}

variable "secret_data" {
  description = "Conteúdo sensível a ser armazenado"
  type        = string
  sensitive   = true
}

variable "accessor_member" {
  description = "Identidade IAM com permissão de leitura do segredo"
  type        = string
  default     = ""
}
