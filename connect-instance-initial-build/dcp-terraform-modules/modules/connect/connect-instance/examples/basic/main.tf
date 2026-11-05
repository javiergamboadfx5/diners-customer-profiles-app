# -----------------------------------------------------------------------------
# connect/connect-instance — ejemplo básico
#
# Componente `kms` en dev: la CMK de almacenamiento de Connect, su alias y el
# contrato SSM `connect-kms-key-arn`. Es el primer stack del orden de apply
# (kms -> storage -> instance), porque publica el contrato que consumen los
# demás.
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
      DataClassification = "<OQ-6>"
      Compliance         = "<OQ-6>"
      ManagedBy          = "terraform"
      Application        = "<OQ-5>"
      Repository         = "dcp-terraform-modules"
      TerraformStack     = "examples/connect/connect-instance/basic"
    }
  }
}

module "connect_kms" {
  source = "../.."

  component   = "kms"
  domain      = "diners"
  environment = "dev"
  workload    = "<OQ-1>"
  region_code = "use1"

  # Entran deterministas del root/catálogo; el módulo los usa solo para el
  # nombre del bucket (componente storage), pero son entradas del módulo.
  org_id     = "o-example00"  # <catálogo>
  account_id = "000000000000" # <OQ-4>

  # Dev no está en alcance CDE: sin referencia de cobertura de seguridad.
  cde_scope = false
}

output "kms_alias" {
  description = "Alias de la CMK de almacenamiento."
  value       = module.connect_kms.kms_alias
}

output "kms_key_arn" {
  description = "ARN de la CMK de almacenamiento."
  value       = module.connect_kms.kms_key_arn
}

output "ssm_parameter_names" {
  description = "Contratos SSM publicados por el stack kms."
  value       = module.connect_kms.ssm_parameter_names
}
