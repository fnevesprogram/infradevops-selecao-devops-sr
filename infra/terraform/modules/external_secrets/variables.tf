variable "project_id" {
  description = "ID do projeto no Google Cloud"
  type        = string
}

variable "namespace" {
  description = "Namespace do Kubernetes para o External Secrets Operator"
  type        = string
  default     = "external-secrets"
}

variable "chart_version" {
  description = "Versão do Helm chart do External Secrets Operator"
  type        = string
  default     = "0.14.3"
}

variable "service_account_name" {
  description = "Nome da Kubernetes Service Account para o ESO"
  type        = string
  default     = "external-secrets"
}

variable "gsa_name" {
  description = "Nome da Google Service Account (GSA) para o ESO"
  type        = string
  default     = "external-secrets-sa"
}

