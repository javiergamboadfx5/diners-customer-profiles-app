# -----------------------------------------------------------------------------
# connect/connect-customer-profiles — ejemplo producción
#
# Componente `domain`: el dominio de Amazon Connect Customer Profiles, el tipo
# de objeto `CTR` desde la plantilla `CTR-AutoAssociateOnly` y la única
# integración con la instancia, más los contratos SSM
# `customer-profiles-domain-name/-arn`.
#
# El componente `domain` LEE dos contratos SSM que deben existir antes del
# apply:
#   - /dcp/diners/<env>/<workload>/config/customer-profiles-kms-key-arn
#     (lo publica el stack kms-customer-profiles)
#   - /dcp/diners/<env>/<workload>/config/connect-instance-arn
#     (lo publica el stack instance)
# Si falta cualquiera, el plan falla ANTES de planear el dominio (Req 8.2).
#
# El data store queda apagado (enable_data_store = false) por la retención de
# 10 años que impone (LPDP). Habilitarlo exige una data_store_approval_ref no
# vacía (OQ-10, Req 8.4).
#
# Cambiar `domain_name` o la clave KMS reemplaza el dominio; `prevent_destroy`
# convierte ese cambio en un plan fallido (Req 8.8).
#
# Requiere el proveedor `awscc` para el tipo de objeto y la integración
# [Blocked: OQ-12]. Este ejemplo documenta la interfaz del módulo; no se aplica
# desde un portátil. Los placeholders `<OQ-n>` se resuelven con el Catálogo.
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.15.8, < 1.16.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.47.0, < 7.0.0"
    }
    awscc = {
      source  = "hashicorp/awscc"
      version = ">= 1.0.0, < 2.0.0" # [Blocked: OQ-12]
    }
  }
}

provider "aws" {
  region = "us-east-1"

  # En los stacks reales estos tags los inyecta el root `terragrunt.hcl` vía
  # provider default_tags; aquí se listan para que el ejemplo sea autocontenido.
  default_tags {
    tags = {
      Environment        = "prod"
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
      TerraformStack     = "examples/connect/connect-customer-profiles/production"
    }
  }
}

provider "awscc" {
  region = "us-east-1"
}

module "profiles_domain" {
  source = "../.."

  component   = "domain"
  domain      = "diners"
  environment = "prod"
  workload    = "<OQ-1>"
  region_code = "use1"

  # Expiración de perfiles aprobada por Cumplimiento (OQ-10): entero 1..1098.
  default_expiration_days = 1098 # <OQ-10>

  # Data store apagado por la retención de 10 años (LPDP). Habilitarlo exige
  # enable_data_store = true y data_store_approval_ref no vacío (Req 8.4).
  enable_data_store = false

  cde_scope = true
}

output "profiles_domain_name" {
  description = "Nombre del dominio de Customer Profiles."
  value       = module.profiles_domain.profiles_domain_name
}

output "profiles_domain_arn" {
  description = "ARN del dominio de Customer Profiles."
  value       = module.profiles_domain.profiles_domain_arn
}

output "profiles_object_type_name" {
  description = "Nombre del tipo de objeto de Customer Profiles (CTR)."
  value       = module.profiles_domain.profiles_object_type_name
}

output "profiles_integration_uri" {
  description = "URI de la integración (ARN de la instancia)."
  value       = module.profiles_domain.profiles_integration_uri
}

output "ssm_base" {
  description = "Base de los contratos SSM del workload."
  value       = module.profiles_domain.ssm_base
}
