# GKE Autopilot: nós, patches, scaling e hardening de runtime são gerenciados pelo Google.
# Cobrança por recurso solicitado dos pods (não por VM ociosa). Workload Identity é nativo.

resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id

  enable_autopilot = true

  network    = var.network_id
  subnetwork = var.subnet_id

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # Workload Identity é sempre habilitado em Autopilot; o bloco é idempotente/explícito.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "Internet (ou configure seu IP de saída)"
    }
  }

  release_channel {
    channel = "REGULAR"
  }

  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  resource_labels = {
    environment = "dev"
    application = "comments-api"
    mode        = "autopilot"
  }

  # checkov:skip=CKV_GCP_18:Dev cluster requires authorized network access for GitHub Actions and developer access
  # checkov:skip=CKV_GCP_65:Google Groups RBAC requires Google Workspace domain not available in dev sandbox
  # checkov:skip=CKV_GCP_69:GKE Autopilot enables Workload Identity and GKE Metadata Server by default (no custom node pool)
  # checkov:skip=CKV_GCP_12:Autopilot uses Dataplane V2 with NetworkPolicy support managed by the platform
  # checkov:skip=CKV_GCP_61:Intranode visibility / dataplane telemetry is managed by GKE Autopilot
  deletion_protection = false
}
