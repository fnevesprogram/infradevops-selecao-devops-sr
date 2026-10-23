resource "random_password" "db_password" {
  length  = 24
  special = false
}

resource "random_id" "db_name_suffix" {
  byte_length = 4
}

resource "google_sql_database_instance" "postgres" {
  name             = "${var.instance_name}-${random_id.db_name_suffix.hex}"
  database_version = var.database_version
  region           = var.region
  project          = var.project_id

  depends_on = [var.private_vpc_connection]

  settings {
    tier              = var.tier
    availability_type = "ZONAL"
    disk_size         = 10
    disk_type         = "PD_SSD"
    edition           = "ENTERPRISE"

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = var.network_id
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      start_time                     = "03:00"
      point_in_time_recovery_enabled = true
    }

    database_flags {
      name  = "log_connections"
      value = "on"
    }

    database_flags {
      name  = "log_disconnections"
      value = "on"
    }

    database_flags {
      name  = "log_checkpoints"
      value = "on"
    }

    database_flags {
      name  = "log_lock_waits"
      value = "on"
    }

    database_flags {
      name  = "log_duration"
      value = "on"
    }

    database_flags {
      name  = "log_min_duration_statement"
      value = "-1"
    }

    database_flags {
      name  = "log_temp_files"
      value = "0"
    }

    database_flags {
      name  = "cloudsql.enable_pgaudit"
      value = "on"
    }

    database_flags {
      name  = "log_hostname"
      value = "on"
    }

    database_flags {
      name  = "log_min_error_statement"
      value = "error"
    }

    database_flags {
      name  = "log_statement"
      value = "all"
    }

    insights_config {
      query_insights_enabled = true
    }
  }

  # checkov:skip=CKV_GCP_6:Enforce SSL encryption in transit using ENCRYPTED_ONLY for private IP connections without requiring mTLS client certificates
  # checkov:skip=CKV_GCP_79:PostgreSQL 16 is latest supported GA version; POSTGRES_18 is not available in GCP Cloud SQL
  deletion_protection = false
}

resource "google_sql_database" "database" {
  name     = var.db_name
  instance = google_sql_database_instance.postgres.name
  project  = var.project_id
}

resource "google_sql_user" "user" {
  name     = var.db_user
  instance = google_sql_database_instance.postgres.name
  password = random_password.db_password.result
  project  = var.project_id
}
