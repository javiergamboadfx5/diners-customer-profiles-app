# -----------------------------------------------------------------------------
# connect/connect-saml-federation — outputs (tarea 4.1)
#
# Contrato de salida del módulo (Req 10.6):
#   - admin_provider_arn / agent_provider_arn: ARNs de los proveedores SAML.
#   - role_arn: ARN del rol de federación.
#   - admin_role_claim / agent_role_claim: claim "<role-arn>,<provider-arn>" que
#     Entra ID emite en el atributo Role.
#   - admin_relay_state_url / agent_relay_state_url: relay state de la consola de
#     federación de Connect (destinos %2Fconnect y %2Fagent-app-v2), tomadas de
#     naming.tf.
#
# Los claims se construyen solo cuando existe el proveedor correspondiente (los
# proveedores son condicionales a la presencia de metadatos); en caso contrario
# devuelven null para no fabricar un claim incompleto.
# -----------------------------------------------------------------------------

output "admin_provider_arn" {
  description = "ARN del proveedor IAM SAML de la app admin (null si no hay metadatos)."
  value       = local.has_admin_metadata ? aws_iam_saml_provider.admin[0].arn : null
}

output "agent_provider_arn" {
  description = "ARN del proveedor IAM SAML de la app agente (null si no hay metadatos)."
  value       = local.has_agent_metadata ? aws_iam_saml_provider.agent[0].arn : null
}

output "role_arn" {
  description = "ARN del rol de federación de Connect."
  value       = aws_iam_role.federation.arn
}

output "admin_role_claim" {
  description = "Claim Role de Entra ID para la app admin: \"<role-arn>,<provider-arn>\"."
  value       = local.has_admin_metadata ? "${aws_iam_role.federation.arn},${aws_iam_saml_provider.admin[0].arn}" : null
}

output "agent_role_claim" {
  description = "Claim Role de Entra ID para la app agente: \"<role-arn>,<provider-arn>\"."
  value       = local.has_agent_metadata ? "${aws_iam_role.federation.arn},${aws_iam_saml_provider.agent[0].arn}" : null
}

output "admin_relay_state_url" {
  description = "Relay state de la consola de federación de Connect para la app admin (destination=%2Fconnect)."
  value       = local.admin_relay_state_url
}

output "agent_relay_state_url" {
  description = "Relay state de la consola de federación de Connect para la app agente (destination=%2Fagent-app-v2)."
  value       = local.agent_relay_state_url
}

# ---------------------------------------------------------------------------
# Salidas auxiliares de nombres (diagnóstico y pruebas). No forman parte del
# contrato de Req 10.6 pero ayudan a los tests de propiedad y de Terraform.
# ---------------------------------------------------------------------------
output "role_federation_name" {
  description = "Nombre del rol de federación."
  value       = local.role_federation
}

output "policy_federation_name" {
  description = "Nombre de la política de federación."
  value       = local.policy_federation
}

output "ssm_base" {
  description = "Base de los contratos SSM del workload."
  value       = local.ssm_base
}

# ---------------------------------------------------------------------------
# Salidas deterministas de la política y el trust (diagnóstico y pruebas).
#
# Exponen el contenido que la política de una sola acción y el trust SAML
# fijan por configuración, SIN depender del atributo `json`/`statement` que el
# provider calcula para aws_iam_policy_document (no observable de forma estable
# bajo un provider simulado). Permiten que los tests afirmen el privilegio
# mínimo (Req 10.2) y la condición SAML:aud (Req 10.1) con command = plan.
# ---------------------------------------------------------------------------
output "federation_action" {
  description = "Única acción IAM concedida por la política de federación (Req 10.2)."
  value       = "connect:GetFederationToken"
}

output "federation_resource" {
  description = "Único recurso de la política de federación: instance/<id>/user/* (Req 10.2)."
  value       = local.federation_resource
}

output "trust_assume_action" {
  description = "Acción de confianza del rol de federación (Req 10.1)."
  value       = "sts:AssumeRoleWithSAML"
}

output "trust_saml_audience" {
  description = "Valor de la condición StringEquals SAML:aud del trust (Req 10.1)."
  value       = local.saml_audience
}
