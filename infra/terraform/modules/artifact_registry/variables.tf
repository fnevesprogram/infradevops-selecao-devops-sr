variable "project_id" {
  description = "ID do projeto GCP"
  type        = string
}

variable "region" {
  description = "Região do Artifact Registry"
  type        = string
}

variable "repository_id" {
  description = "ID do repositório Docker (ex.: comments-repo)"
  type        = string
  default     = "comments-repo"
}

variable "description" {
  description = "Descrição do repositório"
  type        = string
  default     = "Comments API container images"
}
