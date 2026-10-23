terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.15"
    }
  }

  # Configuração de Backend remoto (descomente e substitua o bucket para uso em equipe)
  # backend "gcs" {
  #   bucket = "meu-tfstate-comments-api"
  #   prefix = "terraform/state/dev"
  # }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${module.gke.cluster_endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = "https://${module.gke.cluster_endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
  }
}

# 1. Módulo de Rede (VPC, Subnets privadas, Cloud NAT e Private IP Peering)
module "vpc" {
  source       = "../../modules/vpc"
  project_id   = var.project_id
  region       = var.region
  network_name = "${var.environment}-comments-vpc"
}

# 2. Módulo GKE Autopilot (nós, scaling e hardening gerenciados pelo Google)
module "gke" {
  source              = "../../modules/gke"
  project_id          = var.project_id
  region              = var.region
  cluster_name        = "${var.environment}-comments-gke"
  network_id          = module.vpc.network_id
  subnet_id           = module.vpc.subnet_id
  pods_range_name     = module.vpc.pods_range_name
  services_range_name = module.vpc.services_range_name
}

# 3. Módulo Cloud SQL PostgreSQL 16 (Private IP, sem IP público)
module "cloudsql" {
  source                 = "../../modules/cloudsql"
  project_id             = var.project_id
  region                 = var.region
  instance_name          = "${var.environment}-comments-db"
  tier                   = "db-f1-micro"
  network_id             = module.vpc.network_id
  private_vpc_connection = module.vpc.private_vpc_connection
  db_name                = "comments"
  db_user                = "comments_app"
}

# 4. Módulo Secret Manager (connection string; acesso via ESO + Workload Identity)
module "secrets" {
  source          = "../../modules/secrets"
  project_id      = var.project_id
  secret_id       = "${var.environment}-comments-db-url"
  secret_data     = module.cloudsql.connection_url
  accessor_member = "" # ESO GSA já possui roles/secretmanager.secretAccessor no projeto
}

# 5. Módulo Workload Identity Federation (Autenticação keyless para GitHub Actions OIDC)
module "workload_identity_federation" {
  source      = "../../modules/workload_identity_federation"
  project_id  = var.project_id
  github_repo = var.github_repo
  provider_id = var.provider_id
}

# 6. Módulo External Secrets Operator (Operador de plataforma, CRDs e Workload Identity)
module "external_secrets" {
  source     = "../../modules/external_secrets"
  project_id = var.project_id
  depends_on = [module.gke]
}

