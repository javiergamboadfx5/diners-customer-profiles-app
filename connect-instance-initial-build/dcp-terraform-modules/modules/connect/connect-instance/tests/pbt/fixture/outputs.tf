# -----------------------------------------------------------------------------
# PBT fixture outputs — connect/connect-instance
#
# Exposes the deterministic locals built in the module's naming.tf so the
# Hypothesis harness can read them from `terraform output -json`. When an input
# is rejected by a validation in validations.tf, `terraform plan` fails before
# evaluating these outputs and the harness records the rejection (with the
# error message) instead.
#
# These outputs reference only provider-free locals; they never touch a
# resource or a data source.
# -----------------------------------------------------------------------------

output "bucket_name" {
  description = "Nombre físico del bucket de almacenamiento (naming.tf)."
  value       = local.bucket_name
}

output "bucket_unique" {
  description = "Sufijo único determinista del bucket."
  value       = local.bucket_unique
}

output "kms_alias_storage" {
  description = "Alias de la CMK de almacenamiento (naming.tf)."
  value       = local.kms_alias_storage
}

output "ssm_base" {
  description = "Base de los contratos SSM del workload."
  value       = local.ssm_base
}

output "flow_log_group_name" {
  description = "Nombre del log group nativo de Connect (null si no hay alias)."
  value       = local.flow_log_group_name
}

output "name_tag_instance" {
  description = "Valor del tag Name de la instancia (= alias)."
  value       = local.name_tag_instance
}

output "bucket_name_ok" {
  description = "Comprobación de longitud del bucket (<= 63)."
  value       = local.bucket_name_ok
}

output "kms_alias_ok" {
  description = "Comprobación de longitud del alias KMS (<= 256)."
  value       = local.kms_alias_ok
}
