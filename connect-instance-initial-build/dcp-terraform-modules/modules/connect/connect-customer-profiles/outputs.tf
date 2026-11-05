# -----------------------------------------------------------------------------
# connect/connect-customer-profiles — outputs
#
# El valor de la llave (customer-profiles-kms-key-arn) se conecta en la tarea
# 3.1; los del dominio (customer-profiles-domain-name/-arn) en la tarea 3.3.
# -----------------------------------------------------------------------------

output "kms_key_arn" {
  description = "ARN de la CMK dedicada de Customer Profiles (null si component != kms)."
  value       = local.is_kms ? aws_kms_key.profiles[0].arn : null
}

output "kms_key_id" {
  description = "ID de la CMK dedicada de Customer Profiles (null si component != kms)."
  value       = local.is_kms ? aws_kms_key.profiles[0].key_id : null
}

output "profiles_app_statement_present" {
  description = "true si la política de la llave incluye el statement ProfilesApp (contrato profiles-app-role-arn publicado, Req 7.4)."
  value       = local.is_kms ? local.profiles_app_present : null
}

output "profiles_domain_name" {
  description = "Nombre del dominio de Customer Profiles (nombre efectivo del recurso cuando component = domain; nombre computado en otro caso)."
  value       = local.is_domain ? aws_customerprofiles_domain.this[0].domain_name : local.profiles_domain
}

output "profiles_domain_arn" {
  description = "ARN del dominio de Customer Profiles (null si component != domain)."
  value       = local.is_domain ? aws_customerprofiles_domain.this[0].arn : null
}

output "profiles_object_type_name" {
  description = "Nombre del tipo de objeto de Customer Profiles (null si component != domain)."
  value       = local.is_domain ? awscc_customerprofiles_object_type.ctr[0].object_type_name : null
}

output "profiles_integration_uri" {
  description = "URI de la integración de la instancia (ARN de la instancia; null si component != domain)."
  value       = local.is_domain ? awscc_customerprofiles_integration.ctr[0].uri : null
  # El uri deriva del valor de un data source aws_ssm_parameter, que Terraform
  # marca como sensible. El output debe declararse sensible para no filtrarlo.
  sensitive = true
}

output "kms_alias" {
  description = "Alias de la CMK dedicada de Customer Profiles."
  value       = local.kms_alias_profiles
}

output "ssm_base" {
  description = "Base de los contratos SSM del workload."
  value       = local.ssm_base
}
