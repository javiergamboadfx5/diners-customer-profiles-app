# Stack: instancia EC2 del portal de comercios
# Estado:  diners/qa/us-east-1/workloads/merchants/compute/terraform.tfstate
# Módulo:  compute/ec2-instance v1.0.0 (NUEVO; SHA según compatibility.yaml)

include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

terraform {
  source = "git::ssh://git@github.com/Diners/dcp-terraform-modules.git//modules/compute/ec2-instance?ref=4e1c9a7d2b8f0e3a5c6d7b9e1f2a3c4d5e6f7a8b"
}

inputs = {
  purpose             = "portal"
  ordinal             = "01"
  instance_type       = "t3.small"
  root_volume_size_gb = 30
  ami_id_parameter    = "/dcp/platform/ami/al2023-hardened/id"

  # Orígenes y destinos: contratos de Networking en Parameter Store, nunca CIDR literales.
  ingress_rules = [
    {
      description           = "HTTPS interno desde la VPC"
      port                  = 8443
      source_cidr_parameter = "/dcp/networking/vpc/cidr"
    }
  ]

  egress_rules = [
    {
      description                = "Aurora en subredes de datos"
      port                       = 5432
      destination_cidr_parameter = "/dcp/networking/subnets/data-private/cidrs"
    },
    {
      description                = "VPC endpoints y Nexus por HTTPS"
      port                       = 443
      destination_cidr_parameter = "/dcp/networking/vpc/cidr"
    }
  ]

  # La app entra a Aurora por IAM (sin contraseña) y solo lee sus propios secretos.
  rds_iam_db_users   = ["merchant_portal_app"]
  secrets_read_paths = ["/dcp/diners/${include.root.locals.environment}/merchants/"]

  log_retention_days = 90
}
