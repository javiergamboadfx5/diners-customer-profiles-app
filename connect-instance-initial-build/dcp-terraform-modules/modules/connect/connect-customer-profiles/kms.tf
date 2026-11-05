# -----------------------------------------------------------------------------
# connect/connect-customer-profiles — componente kms (tarea 3.1)
#
# CMK dedicada de Customer Profiles y su alias. Se activa solo cuando
# component = "kms" (local.is_kms). La llave es distinta de la CMK de
# almacenamiento de Connect, de modo que Profiles_App nunca alcanza grabaciones
# ni transcripciones (Req 7.1, iac-security-pci DR-4).
#
# Requisitos cubiertos:
#   - 7.1  CMK simétrica dedicada, rotación 365 d, ventana de borrado 30 d,
#          alias local.kms_alias_profiles.
#   - 7.2  Statements separados: KeyAdministration (solo administración),
#          ProfileService (profile.amazonaws.com con aws:SourceAccount y, cuando
#          bind_domain_arn, aws:SourceArn del dominio computado — DD-5),
#          ConnectService (connect.amazonaws.com, solo Decrypt, con
#          aws:SourceAccount) y DeployRole (TerraformApplyRole, aws:PrincipalArn).
#   - 7.3  Statement opcional ProfilesApp cuando el contrato SSM
#          profiles-app-role-arn existe; concede Encrypt/Decrypt/GenerateDataKey/
#          DescribeKey con aws:PrincipalArn = rol y kms:ViaService =
#          profile.us-east-1.amazonaws.com.
#   - 7.4  Si profiles-app-role-arn no está publicado, el statement se omite y
#          el plan sigue adelante (OQ-11 queda pendiente en el PR).
#   - 7.5  La política no otorga a Profiles_App_Role permiso sobre la llave de
#          almacenamiento (esa llave vive en otro módulo) y no contiene ningún
#          Allow con Principal "*" sin Condition. El statement de administración
#          no lleva acciones de datos.
#   - 7.6  Los ARN del rol key-admin y del rol de la app se leen solo de SSM; no
#          hay ARN literal en el módulo.
#   - 7.7  prevent_destroy = true literal sobre la llave.
#   - 7.8  Publica el ARN de la llave en el contrato SSM
#          customer-profiles-kms-key-arn, con metadatos owner/classification/
#          contract en la descripción.
#   - 7.9  prevent_destroy literal (recurso protegido, Property 13).
#
# Guardrails (connect_guardrails.rego): rotación on; admin sin acciones de datos
# (se identifica por kms:ScheduleKeyDeletion); principales de servicio con
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

  # kms:ViaService del plano de datos de Customer Profiles en la región actual
  # (statement opcional ProfilesApp, Req 7.3).
  profiles_via_service = "profile.${local.region}.amazonaws.com"

  # Contrato opcional profiles-app-role-arn (Req 7.3, 7.4). Se lee con
  # aws_ssm_parameters_by_path para que su ausencia NO falle el plan: cuando el
  # parámetro no existe la lista queda vacía y el statement ProfilesApp se omite.
  # El filtro por el nombre exacto del parámetro evita incluir otros contratos
  # del mismo path (p. ej. key-admin-role-arn).
  profiles_app_role_arns = local.is_kms ? [
    for i, name in data.aws_ssm_parameters_by_path.config[0].names :
    data.aws_ssm_parameters_by_path.config[0].values[i]
    if name == local.ssm_profiles_app_role_arn
  ] : []

  profiles_app_present = length(local.profiles_app_role_arns) > 0
}

# --- Contrato externo: rol key-admin (OQ-13) --------------------------------
# Sin default: un parámetro ausente falla el plan de forma nativa (Req 7.6). La
# precondition da el mensaje explícito de OQ-13 (Req 7.7 del Connect_Module /
# Req 7 aquí: "error indicating the missing key-admin role").
data "aws_ssm_parameter" "key_admin_role" {
  count = local.kms_count
  name  = local.ssm_key_admin_role_arn

  lifecycle {
    postcondition {
      condition     = trimspace(self.value) != ""
      error_message = "key-admin role not published (OQ-13)"
    }
  }
}

# --- Contrato externo opcional: rol de la app de perfiles (OQ-11) -----------
# Se consulta todo el path de config y luego se filtra por nombre en locals.
# aws_ssm_parameters_by_path devuelve lista vacía (no error) si el path o el
# parámetro no existen, de modo que el statement ProfilesApp es opcional (7.4).
data "aws_ssm_parameters_by_path" "config" {
  count = local.kms_count
  path  = local.ssm_base
}

# --- Política de la llave (aws_iam_policy_document) --------------------------
# Cada statement lleva un Sid único. Ningún Allow usa Principal "*" sin
# Condition (Req 7.5). El statement de administración no incluye acciones de
# datos (Req 7.2). El statement ProfilesApp se añade con dynamic solo si el
# contrato está publicado (Req 7.3, 7.4).
data "aws_iam_policy_document" "profiles_key" {
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

  # ProfileService — el servicio Customer Profiles cifra los perfiles con esta
  # CMK. Principal de servicio -> aws:SourceAccount obligatorio. Cuando
  # bind_domain_arn, se enlaza además aws:SourceArn al ARN del dominio computado
  # de forma determinista (DD-5), de modo que la condición rige desde el primer
  # apply sin requerir que el dominio ya exista.
  statement {
    sid    = "ProfileService"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["profile.amazonaws.com"]
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

    # aws:SourceArn del dominio computado solo cuando bind_domain_arn (DD-5).
    dynamic "condition" {
      for_each = var.bind_domain_arn ? [1] : []
      content {
        test     = "StringEquals"
        variable = "aws:SourceArn"
        values   = [local.profiles_domain_arn]
      }
    }
  }

  # ConnectService — Connect descifra perfiles para mostrarlos al agente.
  # Solo Decrypt. Principal de servicio -> aws:SourceAccount obligatorio.
  statement {
    sid    = "ConnectService"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["connect.amazonaws.com"]
    }

    actions = ["kms:Decrypt"]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
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

  # ProfilesApp (opcional) — la app de gestión de perfiles de terceros usa la
  # llave solo cuando su rol está publicado en SSM (Req 7.3). Se condiciona por
  # aws:PrincipalArn (el rol) y kms:ViaService del plano de datos de Profiles,
  # de modo que el rol no puede usar la llave fuera de ese servicio. Si el
  # contrato no existe, el statement se omite y el plan sigue (Req 7.4).
  dynamic "statement" {
    for_each = local.profiles_app_present ? [1] : []
    content {
      sid    = "ProfilesApp"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = local.profiles_app_role_arns
      }

      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey",
      ]

      resources = ["*"]

      condition {
        test     = "ArnEquals"
        variable = "aws:PrincipalArn"
        values   = local.profiles_app_role_arns
      }

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = [local.profiles_via_service]
      }
    }
  }
}

# --- CMK dedicada de Customer Profiles ---------------------------------------
resource "aws_kms_key" "profiles" {
  count = local.kms_count

  description             = "CMK dedicada de Amazon Connect Customer Profiles — ${local.prefix}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  rotation_period_in_days = 365
  policy                  = data.aws_iam_policy_document.profiles_key[0].json

  # Req 7.7 / 7.9 / Property 13 — recurso protegido: literal, no admite variable.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = local.name_kms_profiles
  }
}

# --- Alias de la CMK ---------------------------------------------------------
resource "aws_kms_alias" "profiles" {
  count = local.kms_count

  name          = local.kms_alias_profiles
  target_key_id = aws_kms_key.profiles[0].key_id
}

# --- Contrato SSM: customer-profiles-kms-key-arn (Req 7.8) -------------------
# String con metadatos de contrato en la descripción (L11 fija las claves de
# tag permitidas, por eso owner/classification/contract van en description).
resource "aws_ssm_parameter" "profiles_kms_key_arn" {
  count = local.kms_count

  name        = local.ssm_profiles_kms_key_arn
  type        = "String"
  value       = aws_kms_key.profiles[0].arn
  description = "owner=contactcenter;classification=restricted;contract=v1"

  tags = {
    Name = local.ssm_profiles_kms_key_arn
  }
}
