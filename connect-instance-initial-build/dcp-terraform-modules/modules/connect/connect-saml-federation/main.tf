# -----------------------------------------------------------------------------
# connect/connect-saml-federation — main (tarea 4.1)
#
# Implementa la federación SAML de Amazon Connect con Entra ID:
#   - Dos proveedores IAM SAML (admin y agente), creados condicionalmente según
#     la presencia de metadatos (locals.has_admin_metadata / has_agent_metadata).
#   - El rol de federación con permission boundary obligatorio, duración de
#     sesión <= 3600 s y trust SAML acotado a la audiencia de AWS.
#   - Una única política de una sola acción (connect:GetFederationToken) acotada
#     al recurso instance/<id>/user/* y adjunta al rol.
#
# Reglas aplicadas (iac-core-rules, iac-security-pci):
#   - Permission boundary dcp-platform-permission-boundary en todo rol creado
#     por Terraform (Req 10.3).
#   - Privilegio mínimo: una sola acción, un solo recurso (Req 10.2).
#   - max_session_duration fijado en 3600 en validations.tf (techo PCI = piso
#     de IAM, Req 10.3).
#   - El módulo solo añade el tag Name; los tags obligatorios llegan por
#     default_tags del provider (Req 2.6, 11).
# -----------------------------------------------------------------------------

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# ARN del permission boundary, construido con el nombre canónico de naming.tf y
# el account del caller (Req 10.3, iac-security-pci). Nunca hardcodeado.
#   arn:<partition>:iam::<account>:policy/dcp-platform-permission-boundary
# -----------------------------------------------------------------------------
locals {
  permission_boundary_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/${local.permission_boundary_name}"
}

# -----------------------------------------------------------------------------
# Proveedores IAM SAML (admin y agente).
#
# Se crean solo cuando hay metadatos para cada app (OQ-9). En dev se admiten
# metadatos de marcador; el stack queda sin fusionar hasta tener los reales.
# El tag Name identifica la app de Entra ID (único tag que añade el módulo).
# -----------------------------------------------------------------------------
resource "aws_iam_saml_provider" "admin" {
  count = local.has_admin_metadata ? 1 : 0

  name                   = local.saml_provider_admin
  saml_metadata_document = var.metadata_admin

  tags = {
    Name = local.name_tag_provider_admin
  }
}

resource "aws_iam_saml_provider" "agent" {
  count = local.has_agent_metadata ? 1 : 0

  name                   = local.saml_provider_agent
  saml_metadata_document = var.metadata_agent

  tags = {
    Name = local.name_tag_provider_agent
  }
}

# -----------------------------------------------------------------------------
# Trust policy del rol de federación (Req 10.1).
#
#   - Acción única sts:AssumeRoleWithSAML.
#   - Principals = ARNs de ambos proveedores SAML (los que existan).
#   - Condición StringEquals SAML:aud = https://signin.aws.amazon.com/saml.
# -----------------------------------------------------------------------------
locals {
  saml_provider_arns = concat(
    local.has_admin_metadata ? [aws_iam_saml_provider.admin[0].arn] : [],
    local.has_agent_metadata ? [aws_iam_saml_provider.agent[0].arn] : [],
  )
}

data "aws_iam_policy_document" "trust" {
  statement {
    sid     = "AssumeWithSaml"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithSAML"]

    principals {
      type        = "Federated"
      identifiers = local.saml_provider_arns
    }

    condition {
      test     = "StringEquals"
      variable = "SAML:aud"
      values   = [local.saml_audience]
    }
  }
}

# -----------------------------------------------------------------------------
# Rol de federación (Req 10.1, 10.3).
#
#   - Nombre local.role_federation (contiene "connect-federation").
#   - Permission boundary obligatorio (iac-security-pci).
#   - max_session_duration fijado en 3600 (Req 10.3).
# -----------------------------------------------------------------------------
resource "aws_iam_role" "federation" {
  name                 = local.role_federation
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  permissions_boundary = local.permission_boundary_arn
  max_session_duration = var.max_session_duration

  tags = {
    Name = local.name_tag_role
  }
}

# -----------------------------------------------------------------------------
# Política de una sola acción (Req 10.2).
#
#   - Exactamente connect:GetFederationToken.
#   - Recurso exactamente instance/<id>/user/* (local.federation_resource).
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "federation" {
  statement {
    sid       = "GetFederationToken"
    effect    = "Allow"
    actions   = ["connect:GetFederationToken"]
    resources = [local.federation_resource]
  }
}

resource "aws_iam_policy" "federation" {
  name   = local.policy_federation
  policy = data.aws_iam_policy_document.federation.json

  tags = {
    Name = local.name_tag_policy
  }
}

resource "aws_iam_role_policy_attachment" "federation" {
  role       = aws_iam_role.federation.name
  policy_arn = aws_iam_policy.federation.arn
}
