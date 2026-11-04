# Ejemplo básico: instancia en dev, sin entrada, salida solo a la VPC por HTTPS.

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
      Environment        = "dev"
      Scope              = "diners"
      Domain             = "diners"
      Workload           = "merchants"
      Owner              = "equipo-comercios"
      CostCenter         = "410230"
      DataClassification = "internal"
      Compliance         = "general"
      ManagedBy          = "terraform"
      Application        = "merchant-portal"
      Repository         = "dcp-terraform-modules"
      TerraformStack     = "examples/compute/ec2-instance/basic"
    }
  }
}

module "portal" {
  source = "../.."

  environment      = "dev"
  workload         = "merchants"
  purpose          = "portal"
  region_code      = "use1"
  instance_type    = "t3.small"
  ami_id_parameter = "/dcp/platform/ami/al2023-hardened/id"

  egress_rules = [
    {
      description                = "VPC endpoints y Nexus por HTTPS"
      port                       = 443
      destination_cidr_parameter = "/dcp/networking/vpc/cidr"
    }
  ]
}

output "instance_id" {
  value = module.portal.instance_id
}
