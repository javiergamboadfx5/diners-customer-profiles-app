# -----------------------------------------------------------------------------
# PBT fixture outputs — connect/connect-customer-profiles
#
# Exposes the deterministic locals built in the module's naming.tf so the
# Hypothesis harness can read them from the planned outputs. When an input is
# rejected by a validation in validations.tf, `terraform plan` fails before
# evaluating these outputs and the harness records the rejection instead.
#
# profiles_domain_arn is included: after harness.py rewrites the three
# data-source references to the fixture stub variables, the ARN is a pure
# deterministic function of its inputs (see fixture/stubs.tf).
# -----------------------------------------------------------------------------

output "profiles_domain" {
  description = "Nombre del dominio de Customer Profiles (naming.tf)."
  value       = local.profiles_domain
}

output "kms_alias_profiles" {
  description = "Alias de la CMK dedicada de Customer Profiles."
  value       = local.kms_alias_profiles
}

output "profiles_domain_arn" {
  description = "ARN computado del dominio (con stubs de partition/region/account)."
  value       = local.profiles_domain_arn
}

output "ssm_base" {
  description = "Base de los contratos SSM del workload."
  value       = local.ssm_base
}

output "name_kms_profiles" {
  description = "Valor del tag Name de la CMK de Customer Profiles."
  value       = local.name_kms_profiles
}

output "name_profiles_domain" {
  description = "Valor del tag Name del dominio (= nombre del dominio)."
  value       = local.name_profiles_domain
}
