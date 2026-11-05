# -----------------------------------------------------------------------------
# connect/connect-customer-profiles — ejemplo básico
#
# Componente `kms` en dev: la CMK dedicada de Customer Profiles, su alias y el
# contrato SSM `customer-profiles-kms-key-arn`. Es el primer stack del orden de
# apply (kms-customer-profiles -> customer-profiles), porque publica el contrato
# que consume el dominio.
#
# Este ejemplo documenta la interfaz del módulo. No se aplica desde un portátil
# (los applies ocurren en el Pipeline tras merge a `main`, entorno `diners-dev`).
# El rol key-admin (OQ-13) debe existir en el contrato SSM
# `/dcp/diners/dev/<workload>/config/key-admin-role-arn` antes del apply real.
#
# Los placeholders `<OQ-n>` se resuelven con valores del Catálogo; mientras no
# existan, la sincronización de catálogo del Pipeline falla a propósito.
# -----------------------------------------------------------------------------

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

  # En los stacks reales estos tags los inyecta el root `terragrunt.hcl` vía
  # provider default_tags; aquí se listan para que el ejemplo sea autocontenido.
  default_tags {
    tags = {
      Environment        = "dev"
      Scope              = "diners"
      Domain             = "diners"
      Workload           = "<OQ-1>"
      Owner              = "<OQ-5>"
      CostCenter         = "<OQ-5>"
      DataClassification = "confidential" # <OQ-6>
      Compliance         = "lpdp"         # <OQ-6>
      ManagedBy          = "terraform"
      Application        = "<OQ-5>"
      Repository         = "dcp-terraform-modules"
      TerraformStack     = "examples/connect/connect-customer-profiles/basic"
    }
  }
}

module "profiles_kms" {
  source = "../.."

  component   = "kms"
  domain      = "diners"
  environment = "dev"
  workload    = "<OQ-1>"
  region_code = "use1"

  # Dev no está en alcance CDE.
  cde_scope = false
}

output "kms_alias" {
  description = "Alias de la CMK dedicada de Customer Profiles."
  value       = module.profiles_kms.kms_alias
}

output "kms_key_arn" {
  description = "ARN de la CMK dedicada de Customer Profiles."
  value       = module.profiles_kms.kms_key_arn
}

output "profiles_app_statement_present" {
  description = "true si la política de la clave incluye el statement ProfilesApp (OQ-11)."
  value       = module.profiles_kms.profiles_app_statement_present
}

output "ssm_base" {
  description = "Base de los contratos SSM del workload."
  value       = module.profiles_kms.ssm_base
}
