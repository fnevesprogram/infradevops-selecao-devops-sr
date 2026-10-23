variable "project_id" {
  description = "ID do projeto GCP onde os recursos serão provisionados"
  type        = string
}

variable "region" {
  description = "Região principal do GCP"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Identificador do ambiente"
  type        = string
  default     = "dev"
}

variable "github_repo" {
  description = "Repositório GitHub para OIDC Workload Identity Federation"
  type        = string
  default     = "rparana/infradevops-selecao-devops-sr"
}

variable "provider_id" {
  description = "ID do Workload Identity Provider"
  type        = string
  default     = "github-provider-v2"
}
