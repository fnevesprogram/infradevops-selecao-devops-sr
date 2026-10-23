variable "project_id" {
  description = "ID do projeto no Google Cloud"
  type        = string
}

variable "pool_id" {
  description = "ID da Workload Identity Pool"
  type        = string
  default     = "github-actions-pool"
}

variable "provider_id" {
  description = "ID do Workload Identity Provider"
  type        = string
  default     = "github-provider-v2"
}

variable "github_repo" {
  description = "Repositório GitHub autorizado (formato: usuario/repo)"
  type        = string
  default     = "rparana/infradevops-selecao-devops-sr"
}
