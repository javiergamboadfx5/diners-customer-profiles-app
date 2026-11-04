# Stack: Aurora PostgreSQL del portal de comercios
# Estado:  diners/prod/us-east-1/workloads/merchants/database/terraform.tfstate
# Módulo:  data/aurora-postgresql v1.3.0 (EXISTENTE; SHA según compatibility.yaml)

include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

terraform {
  source = "git::ssh://git@github.com/Diners/dcp-terraform-modules.git//modules/data/aurora-postgresql?ref=9c2e4f7a1b3d5e6f708192a3b4c5d6e7f8091a2b"
}

# Solo orden de ejecución: compute publica el SG del portal en Parameter Store.
# No se leen outputs ni estado de compute (L05).
dependencies {
  paths = ["../compute"]
}

inputs = {
  purpose         = "core"
  engine_version  = "16.6"
  instance_class  = "db.r7g.large"
  instance_count  = 2
  database_name   = "merchants"
  master_username = "dbadmin"

  allowed_security_group_id_parameters = [
    "/dcp/diners/${include.root.locals.environment}/merchants/config/portal-sg-id",
  ]

  deletion_protection   = true
  backup_retention_days = 35
  log_retention_days    = 365

  tags = {
    Criticality  = "tier-2"
    BackupPolicy = "critical"
  }
}
