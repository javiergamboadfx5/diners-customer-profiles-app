# -----------------------------------------------------------------------------
# connect/connect-saml-federation — nombres físicos (tarea 1.4)
#
# Locals deterministas y libres de proveedor. Construyen los nombres a partir de
# environment / workload / purpose / region_code (Req 2.6, iac-naming-tags L07,
# L08). Las partes de los claim y de las relay state URLs que dependen de ARNs
# vivos (role_arn, provider ARNs) se ensamblan en outputs.tf (tarea 4.1); aquí se
# dejan las piezas deterministas (destinos, plantilla de URL, audiencia SAML).
#
# Límites aplicados:
#   - Rol IAM: <= 64 caracteres.
#   - Política IAM: <= 128 caracteres.
#   - Proveedor IAM SAML (Name): <= 128 caracteres.
# -----------------------------------------------------------------------------

locals {
  # ---------------------------------------------------------------------------
  # Prefijo de workload (scope = domain para recursos de workload):
  #   dcp-<domain>-<environment>-<workload>   (L07)
  # ---------------------------------------------------------------------------
  prefix = "dcp-${var.domain}-${var.environment}-${var.workload}"

  # Propósito (purpose) común a rol y política de federación. Contiene la
  # subcadena "connect-federation" que reconoce el guardrail de SAML.
  purpose_federation = "connect-federation"

  # ---------------------------------------------------------------------------
  # Rol y política de federación  (L08: role-<purpose>, policy-<permission>)
  #   dcp-<domain>-<env>-<workload>-role-connect-federation     (Req 10.1)
  #   dcp-<domain>-<env>-<workload>-policy-connect-federation   (Req 10.2)
  # ---------------------------------------------------------------------------
  role_federation   = "${local.prefix}-role-${local.purpose_federation}"
  policy_federation = "${local.prefix}-policy-${local.purpose_federation}"

  # ---------------------------------------------------------------------------
  # Nombres de los dos proveedores IAM SAML (admin y agente).
  # Usan el código de recurso del catálogo (saml_resource_code, OQ-3) para no
  # inventar el término. El Name del proveedor identifica la app de Entra ID.
  #   dcp-<domain>-<env>-<workload>-<saml_code>-admin
  #   dcp-<domain>-<env>-<workload>-<saml_code>-agent
  # ---------------------------------------------------------------------------
  saml_provider_admin = "${local.prefix}-${var.saml_resource_code}-admin"
  saml_provider_agent = "${local.prefix}-${var.saml_resource_code}-agent"

  # ---------------------------------------------------------------------------
  # Permission boundary obligatorio en todo rol creado por Terraform
  # (iac-security-pci, iac-core-rules). El ARN se completa con el account del
  # caller en main.tf; aquí se fija el nombre canónico del policy.
  # ---------------------------------------------------------------------------
  permission_boundary_name = "dcp-platform-permission-boundary"

  # ---------------------------------------------------------------------------
  # Audiencia SAML fija del endpoint de AWS (condición del trust, Req 10.1).
  # ---------------------------------------------------------------------------
  saml_audience = "https://signin.aws.amazon.com/saml"

  # ---------------------------------------------------------------------------
  # Identificadores derivados del ARN de la instancia (entrada), libres de
  # proveedor. Se usan para el recurso de la política (instance/<id>/user/*) y
  # para construir las relay state URLs.
  #   arn:aws:connect:<region>:<account>:instance/<uuid>
  # ---------------------------------------------------------------------------
  instance_arn_parts = var.instance_arn == null ? [] : regexall(
    "^arn:aws[a-z-]*:connect:(?P<region>[a-z0-9-]+):(?P<account>[0-9]{12}):instance/(?P<id>[0-9a-f-]+)$",
    var.instance_arn
  )
  instance_region = length(local.instance_arn_parts) > 0 ? local.instance_arn_parts[0].region : null
  instance_id     = length(local.instance_arn_parts) > 0 ? local.instance_arn_parts[0].id : null

  # Recurso de la única acción permitida (connect:GetFederationToken), Req 10.2.
  federation_resource = var.instance_arn == null ? null : "${var.instance_arn}/user/*"

  # ---------------------------------------------------------------------------
  # Relay state URLs de la consola de federación de Connect (Req 10.6).
  #   https://<region>.console.aws.amazon.com/connect/federate/<instance-id>?destination=<dest>
  # Destinos codificados: %2Fconnect (admin) y %2Fagent-app-v2 (agente).
  # ---------------------------------------------------------------------------
  relay_destination_admin = "%2Fconnect"
  relay_destination_agent = "%2Fagent-app-v2"

  relay_state_base = (local.instance_region == null || local.instance_id == null) ? null : "https://${local.instance_region}.console.aws.amazon.com/connect/federate/${local.instance_id}"

  admin_relay_state_url = local.relay_state_base == null ? null : "${local.relay_state_base}?destination=${local.relay_destination_admin}"
  agent_relay_state_url = local.relay_state_base == null ? null : "${local.relay_state_base}?destination=${local.relay_destination_agent}"

  # ---------------------------------------------------------------------------
  # Base de contratos SSM: /dcp/<domain>/<env>/<workload>/config  (L10)
  # ---------------------------------------------------------------------------
  ssm_base = "/dcp/${var.domain}/${var.environment}/${var.workload}/config"

  # Contratos SSM que este módulo lee (publicados por otros stacks).
  ssm_name_instance_arn   = "${local.ssm_base}/connect-instance-arn"
  ssm_name_metadata_admin = "${local.ssm_base}/saml-metadata-admin"
  ssm_name_metadata_agent = "${local.ssm_base}/saml-metadata-agent"

  # ---------------------------------------------------------------------------
  # Valores del tag Name por recurso (Req 2.6: el módulo solo añade Name).
  # ---------------------------------------------------------------------------
  name_tag_role           = local.role_federation
  name_tag_policy         = local.policy_federation
  name_tag_provider_admin = local.saml_provider_admin
  name_tag_provider_agent = local.saml_provider_agent

  # ---------------------------------------------------------------------------
  # Comprobaciones de longitud deterministas. Se exponen como locals para que
  # las pruebas de propiedad (tarea 1.5) y los tests de Terraform las usen.
  # ---------------------------------------------------------------------------
  role_federation_ok   = length(local.role_federation) <= 64
  policy_federation_ok = length(local.policy_federation) <= 128
  provider_admin_ok    = length(local.saml_provider_admin) <= 128
  provider_agent_ok    = length(local.saml_provider_agent) <= 128
}
