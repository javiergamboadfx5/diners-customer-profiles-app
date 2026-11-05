# -----------------------------------------------------------------------------
# connect/connect-instance — componente kms (tarea 2.1)
#
# CMK dedicada de almacenamiento de Connect (grabaciones y transcripciones) y su
# alias. Se activa solo cuando component = "kms" (local.is_kms).
#
# Requisitos cubiertos:
#   - 4.1  CMK simétrica, rotación 365 d, ventana de borrado 30 d, alias
#          local.kms_alias_storage, prevent_destroy literal.
#   - 4.2  El statement de administración (KeyAdministration) no lleva ninguna
#          acción de datos (Encrypt/Decrypt/GenerateDataKey*/ReEncrypt*); el uso
#          va en statements separados (admin separado de users, iac-security-pci
#          DR-3).
#   - 4.3  Todo statement con principal de servicio lleva aws:SourceAccount; no
#          existe ningún Allow con Principal "*" sin Condition.
#   - 4.4  Publica el ARN de la llave en el contrato SSM connect-kms-key-arn,
#          con metadatos owner/classification/contract en la descripción.
#   - 4.5  prevent_destroy = true literal sobre la llave.
#   - 4.6  El ARN del rol key-admin se lee del contrato SSM sin fallback; una
#          precondition falla el plan con el mensaje de OQ-13 si falta.
#   - 6.5 / DD-1  Statement LogsService para que el log group de flujos de
#          contacto (/aws/connect/<alias>) cifre con esta misma CMK.
#
# Guardrails (connect_guardrails.rego): rotación on; admin sin acciones de
# datos (se identifica por kms:ScheduleKeyDeletion); principales de servicio con
# aws:SourceAccount; sin Allow con Principal "*" sin Condition; recurso
# protegido (no borrar ni reemplazar).
#
# El módulo solo añade el tag Name (Req 2.6); el resto de tags obligatorios los
# inyecta el root vía provider default_tags.
# -----------------------------------------------------------------------------

# --- Contexto (region/account/partition) ------------------------------------
locals {
  kms_count = local.is_kms ? 1 : 0

  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.name

  # Rol de despliegue del propio stack (DeployRole). No es un principal de
  # servicio: se condiciona por aws:PrincipalArn, no por aws:SourceAccount.
  deploy_role_arn = "arn:${local.partition}:iam::${local.account_id}:role/TerraformApplyRole"

  # Principal de servicio de CloudWatch Logs de la región (DD-1).
  logs_service_principal = "logs.${local.region}.amazonaws.com"

  # Patrón de instancias Connect de la cuenta (aws:SourceArn del servicio).
  connect_instance_arn_pattern = "arn:${local.partition}:connect:${local.region}:${local.account_id}:instance/*"

  # Patrón de log groups de flujos de contacto (EncryptionContext de Logs, DD-1).
  connect_log_group_arn_pattern = "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/aws/connect/*"
}

# --- Contrato externo: rol key-admin (OQ-13) --------------------------------
# Sin default: un parámetro ausente falla el plan de forma nativa (Req 4.6).
data "aws_ssm_parameter" "key_admin_role" {
  count = local.kms_count
  name  = local.ssm_name_key_admin_role
}

# --- Política de la llave (aws_iam_policy_document) --------------------------
# Cada statement lleva un Sid único. Ningún Allow usa Principal "*" sin
# Condition (Req 4.3). El statement de administración no incluye acciones de
# datos (Req 4.2).
data "aws_iam_policy_document" "storage_key" {
  count = local.kms_count

  # KeyAdministration — administración de la llave, sin acciones de datos.
  statement {
    sid    = "KeyAdministration"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [data.aws_ssm_parameter.key_admin_role[0].value]
    }

    actions = [
      "kms:Create*",
      "kms:Describe*",
      "kms:Enable*",
      "kms:List*",
      "kms:Put*",
      "kms:Update*",
      "kms:Revoke*",
      "kms:Disable*",
      "kms:Get*",
      "kms:Delete*",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion",
    ]

    resources = ["*"]
  }

  # DeployRole — el TerraformApplyRole crea grants durante el apply.
  # Principal AWS (no servicio): se condiciona por aws:PrincipalArn.
  statement {
    sid    = "DeployRole"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [local.deploy_role_arn]
    }

    actions = [
      "kms:CreateGrant",
      "kms:DescribeKey",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalArn"
      values   = [local.deploy_role_arn]
    }
  }

  # ConnectService — el servicio Connect usa la llave para grabaciones y
  # transcripciones. Principal de servicio -> aws:SourceAccount obligatorio.
  statement {
    sid    = "ConnectService"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["connect.amazonaws.com"]
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
      "kms:CreateGrant",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.connect_instance_arn_pattern]
    }
  }

  # LogsService — CloudWatch Logs cifra el log group de flujos de contacto con
  # esta CMK (DD-1). Principal de servicio -> aws:SourceAccount obligatorio.
  statement {
    sid    = "LogsService"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = [local.logs_service_principal]
    }

    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = [local.connect_log_group_arn_pattern]
    }
  }
}

# --- CMK de almacenamiento ---------------------------------------------------
resource "aws_kms_key" "storage" {
  count = local.kms_count

  description             = "CMK de almacenamiento de Amazon Connect (grabaciones y transcripciones) — ${local.prefix}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  rotation_period_in_days = 365
  policy                  = data.aws_iam_policy_document.storage_key[0].json

  # Req 4.5 / Property 13 — recurso protegido: literal, no admite variable.
  lifecycle {
    prevent_destroy = true

    # Req 4.6 / OQ-13 — el data source ya falla de forma nativa si el parámetro
    # no existe; esta precondition añade el mensaje explícito exigido por el
    # diseño cuando el valor llega vacío.
    precondition {
      condition     = try(length(trimspace(data.aws_ssm_parameter.key_admin_role[0].value)) > 0, false)
      error_message = "key-admin role not published (OQ-13)"
    }
  }

  tags = {
    Name = local.name_tag_kms_key
  }
}

# --- Alias de la CMK ---------------------------------------------------------
resource "aws_kms_alias" "storage" {
  count = local.kms_count

  name          = local.kms_alias_storage
  target_key_id = aws_kms_key.storage[0].key_id
}

# --- Contrato SSM: connect-kms-key-arn (Req 4.4) -----------------------------
# String con metadatos de contrato en la descripción (L11 fija las claves de
# tag permitidas, por eso owner/classification/contract van en description).
resource "aws_ssm_parameter" "connect_kms_key_arn" {
  count = local.kms_count

  name        = local.ssm_name_kms_key_arn
  type        = "String"
  value       = aws_kms_key.storage[0].arn
  description = "owner=contactcenter;classification=restricted;contract=v1"

  tags = {
    Name = local.ssm_name_kms_key_arn
  }
}
