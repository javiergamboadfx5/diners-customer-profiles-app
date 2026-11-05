# -----------------------------------------------------------------------------
# PBT fixture outputs — connect/connect-saml-federation
#
# Exposes the deterministic locals built in the module's naming.tf so the
# Hypothesis harness can read them from the planned outputs. When an input is
# rejected by a validation in validations.tf, `terraform plan` fails before
# evaluating these outputs and the harness records the rejection instead.
#
# These outputs reference only provider-free locals; they never touch a
# resource or a data source.
# -----------------------------------------------------------------------------

output "role_federation" {
  description = "Nombre del rol de federación (naming.tf)."
  value       = local.role_federation
}

output "policy_federation" {
  description = "Nombre de la política de federación."
  value       = local.policy_federation
}

output "saml_provider_admin" {
  description = "Name del proveedor IAM SAML admin."
  value       = local.saml_provider_admin
}

output "saml_provider_agent" {
  description = "Name del proveedor IAM SAML agente."
  value       = local.saml_provider_agent
}

output "saml_audience" {
  description = "Audiencia SAML fija del endpoint de AWS."
  value       = local.saml_audience
}

output "instance_region" {
  description = "Región extraída del ARN de la instancia (null si no hay ARN)."
  value       = local.instance_region
}

output "instance_id" {
  description = "ID extraído del ARN de la instancia (null si no hay ARN)."
  value       = local.instance_id
}

output "federation_resource" {
  description = "Recurso de connect:GetFederationToken (instance/<id>/user/*)."
  value       = local.federation_resource
}

output "admin_relay_state_url" {
  description = "Relay state URL de la app admin (destination=%2Fconnect)."
  value       = local.admin_relay_state_url
}

output "agent_relay_state_url" {
  description = "Relay state URL de la app agente (destination=%2Fagent-app-v2)."
  value       = local.agent_relay_state_url
}

output "role_federation_ok" {
  description = "Comprobación de longitud del rol (<= 64)."
  value       = local.role_federation_ok
}

output "policy_federation_ok" {
  description = "Comprobación de longitud de la política (<= 128)."
  value       = local.policy_federation_ok
}

output "provider_admin_ok" {
  description = "Comprobación de longitud del Name del proveedor admin (<= 128)."
  value       = local.provider_admin_ok
}

output "provider_agent_ok" {
  description = "Comprobación de longitud del Name del proveedor agente (<= 128)."
  value       = local.provider_agent_ok
}
