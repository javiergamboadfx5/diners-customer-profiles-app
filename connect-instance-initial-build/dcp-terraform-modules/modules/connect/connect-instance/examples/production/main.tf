# -----------------------------------------------------------------------------
# connect/connect-instance — ejemplo producción
#
# Componente `instance`: la instancia de Amazon Connect con federación SAML y
# Contact Lens, su log group de flujos `/aws/connect/<alias>` cifrado con la CMK
# de almacenamiento (DD-1 / DD-6), las dos configuraciones de almacenamiento
# (CALL_RECORDINGS, CHAT_TRANSCRIPTS) y los contratos SSM
# `connect-instance-id/-arn/-alias`.
#
# El componente `instance` LEE dos contratos SSM que deben existir antes del
# apply (los publican los stacks kms y storage):
#   - /dcp/diners/<env>/<workload>/config/connect-kms-key-arn
#   - /dcp/diners/<env>/<workload>/config/connect-storage-bucket-name
# Si falta cualquiera, el plan falla ANTES de planear la instancia (Req 6.4).
#
# Cambiar `instance_alias` o `identity_management_type` reemplaza la instancia;
# `prevent_destroy` convierte ese cambio en un plan fallido (Req 6.6).
#
# Este ejemplo documenta la interfaz del módulo. No se aplica desde un portátil.
# Los placeholders `<OQ-n>` se resuelven con valores del Catálogo.
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
      Environment        = "prod"
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
      TerraformStack     = "examples/connect/connect-instance/production"
    }
  }
}

module "connect_instance" {
  source = "../.."

  component   = "instance"
  domain      = "diners"
  environment = "prod"
  workload    = "<OQ-1>"
  region_code = "use1"

  # Entran deterministas del root/catálogo.
  org_id     = "o-example00"  # <catálogo>
  account_id = "000000000000" # <OQ-4>

  # Identidad: SAML (único valor sin excepción en qa/stg/prod, Req 3.5).
  instance_alias           = "<OQ-8>"
  identity_management_type = "SAML"

  # Flags de la instancia (Req 6.1). Contact Lens siempre va habilitado por el
  # módulo; el resto son true por defecto y se muestran explícitos aquí.
  inbound_calls_enabled     = true
  outbound_calls_enabled    = true
  contact_flow_logs_enabled = true

  # Prefijos de almacenamiento (valores por defecto del módulo).
  bucket_prefix_recordings  = "connect/call-recordings"
  bucket_prefix_transcripts = "connect/chat-transcripts"

  # Retención del log group de flujos: valor permitido por CloudWatch, nunca 0.
  flow_log_retention_days = 365

  # Alcance CDE: Ciberseguridad habilita CloudTrail data events y Macie por un
  # PR en dcp-aws-security-live (DD-2). El módulo exige la referencia de
  # cobertura cuando cde_scope = true; no crea esos controles.
  cde_scope             = true
  security_coverage_ref = "<security-coverage-ref>"
}

output "instance_arn" {
  description = "ARN de la instancia Connect."
  value       = module.connect_instance.instance_arn
}

output "instance_id" {
  description = "ID de la instancia Connect."
  value       = module.connect_instance.instance_id
}

output "log_group_name" {
  description = "Log group de flujos de contacto (/aws/connect/<alias>)."
  value       = module.connect_instance.log_group_name
}

output "ssm_parameter_names" {
  description = "Contratos SSM publicados por el stack instance."
  value       = module.connect_instance.ssm_parameter_names
}
