# Ejemplo productivo: CMK para disco y logs, acceso a Aurora por IAM, lectura de secretos propios.

terraform {
  required_version = ">= 1.15.8, < 1.16.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.47.0, < 7.0.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Environment        = "prod"
      Scope              = "diners"
      Domain             = "diners"
      Workload           = "merchants"
      Owner              = "equipo-comercios"
      CostCenter         = "410230"
      DataClassification = "confidential"
      Compliance         = "lpdp"
      ManagedBy          = "terraform"
      Application        = "merchant-portal"
      Repository         = "dcp-terraform-modules"
      TerraformStack     = "examples/compute/ec2-instance/production"
    }
  }
}

data "aws_kms_alias" "data" {
  name = "alias/dcp/diners/prod/merchants/data"
}

module "portal" {
  source = "../.."

  environment         = "prod"
  workload            = "merchants"
  purpose             = "portal"
  region_code         = "use1"
  ordinal             = "01"
  subnet_index        = 0
  instance_type       = "m7i.large"
  root_volume_size_gb = 50
  ami_id_parameter    = "/dcp/platform/ami/al2023-hardened/id"
  ebs_kms_key_arn     = data.aws_kms_alias.data.target_key_arn
  log_kms_key_arn     = data.aws_kms_alias.data.target_key_arn
  log_retention_days  = 365

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

  rds_iam_db_users   = ["merchant_portal_app"]
  secrets_read_paths = ["/dcp/diners/prod/merchants/"]

  tags = {
    Criticality  = "tier-2"
    BackupPolicy = "standard"
  }
}
