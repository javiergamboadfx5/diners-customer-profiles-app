# Ejemplo básico (andamiaje). El ejemplo definitivo se completa en la tarea 4.x.

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
      Workload           = "<OQ-1>"
      Owner              = "<OQ-5>"
      CostCenter         = "<OQ-5>"
      DataClassification = "<OQ-6>"
      Compliance         = "<OQ-6>"
      ManagedBy          = "terraform"
      Application        = "<OQ-5>"
      Repository         = "dcp-terraform-modules"
      TerraformStack     = "examples/connect/connect-saml-federation/basic"
    }
  }
}

module "connect_saml" {
  source = "../.."

  environment        = "dev"
  workload           = "<OQ-1>"
  region_code        = "use1"
  saml_resource_code = "saml" # [Blocked: OQ-3]
}

output "role_federation_name" {
  value = module.connect_saml.role_federation_name
}
