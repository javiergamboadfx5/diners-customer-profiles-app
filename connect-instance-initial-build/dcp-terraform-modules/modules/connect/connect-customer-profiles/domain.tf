# -----------------------------------------------------------------------------
# connect/connect-customer-profiles — componente domain (tarea 3.3)
#
# Dominio de Amazon Connect Customer Profiles, su tipo de objeto CTR y la
# integración con la instancia. Se activa solo cuando component = "domain"
# (local.is_domain). La CMK del dominio NO se crea aquí: se lee del contrato SSM
# customer-profiles-kms-key-arn publicado por el componente kms (tarea 3.1), de
# modo que no hay ARN literal de clave en el módulo (Req 8.5, DD-5).
#
# Requisitos cubiertos:
#   - 8.1  Dominio local.profiles_domain con matching desactivado
#          (var.matching_enabled fijado en false por validations/variables).
#   - 8.2  default_encryption_key = CMK dedicada de perfiles leída de SSM, sin
#          literal; expiración por defecto = var.default_expiration_days.
#   - 8.5  Tipo de objeto CTR desde la plantilla CTR-AutoAssociateOnly y una
#          única integración con uri = ARN de la instancia (SSM
#          connect-instance-arn) y object_type_name = CTR.
#   - 8.6  La adopción de una integración existente usa el mecanismo DD-4
#          (bloque generate "import" en el root terragrunt.hcl, driven por
#          env.hcl adopt.customer-profiles); el módulo no crea import blocks.
#   - 8.8  prevent_destroy = true literal sobre el dominio (recurso protegido,
#          Property 13).
#   - 8.10 Ni el dominio ni el tipo de objeto definen campos para PAN, CVV, PIN,
#          track data ni ningún otro SAD. El tipo de objeto se crea solo desde
#          la plantilla (template_id), que aporta sus propios Fields/Keys; el
#          módulo NO declara ningún Fields propio (guardrail PAN/SAD).
#
# Guardrails (connect_guardrails.rego): dominio protegido (no borrar ni
# reemplazar, Property 13); sin nombres de campo PAN/SAD (Property 16);
# DataClassification en confidential|restricted|pci y Compliance en lpdp|pci-dss
# (los aporta el root vía default_tags).
#
# El módulo solo añade el tag Name (Req 2.6); el resto de tags obligatorios los
# inyecta el root vía provider default_tags.
#
# [Blocked: OQ-12] Los recursos awscc_customerprofiles_object_type y
# awscc_customerprofiles_integration requieren el proveedor hashicorp/awscc.
# El proveedor hashicorp/aws (>= 6.47.0) expone aws_customerprofiles_domain,
# pero NO expone recursos para el mapeo de tipo de objeto ni para la integración
# de la instancia. La entrada de awscc en compatibility.yaml con el espejo de
# Nexus debe aprobarse antes de que este componente pueda mezclarse en el
# pipeline. El código se deja completo y funcional; el bloqueo es de registro,
# no de implementación.
# -----------------------------------------------------------------------------

locals {
  domain_count = local.is_domain ? 1 : 0

  # Nombre del tipo de objeto fijado por el diseño (Req 8.5). La plantilla
  # CTR-AutoAssociateOnly aporta los Fields y Keys del CTR: el módulo no declara
  # campos propios, de modo que es imposible introducir un nombre de campo
  # PAN/SAD (Req 8.10, guardrail Property 16).
  profiles_object_type_name = "CTR"
  profiles_template_id      = "CTR-AutoAssociateOnly"
}

# --- Contrato externo: ARN de la CMK de perfiles (publicado por el kms stack) -
# Sin default: un parámetro ausente falla el plan de forma nativa, de modo que
# el dominio no se planifica sin su clave (Req 8.2, Error Handling "Missing
# customer-profiles-kms-key-arn ... Plan fails, no domain planned").
data "aws_ssm_parameter" "profiles_kms_key_arn" {
  count = local.domain_count
  name  = local.ssm_profiles_kms_key_arn
}

# --- Contrato externo: ARN de la instancia de Connect ------------------------
# Lo publica el instance stack (connect-instance-arn). Sin default: su ausencia
# falla el plan antes de crear la integración (Req 8.2, 8.5). La integración usa
# este ARN como uri (Req 8.5).
data "aws_ssm_parameter" "connect_instance_arn" {
  count = local.domain_count
  name  = local.ssm_connect_instance_arn
}

# --- Dominio de Customer Profiles --------------------------------------------
# matching desactivado (Req 8.1, var.matching_enabled fijado en false);
# default_encryption_key = CMK de perfiles leída de SSM (Req 8.2, sin literal);
# default_expiration_days de la entrada validada (1..1098). El tag Name es el
# único tag del módulo; el resto llega por default_tags del root.
resource "aws_customerprofiles_domain" "this" {
  count = local.domain_count

  domain_name             = local.profiles_domain
  default_encryption_key  = data.aws_ssm_parameter.profiles_kms_key_arn[0].value
  default_expiration_days = var.default_expiration_days

  # Req 8.1 — matching de perfiles desactivado por el diseño de la app. El
  # bloque matching se omite por completo (ausente = desactivado); no se activa
  # ni rule_based_matching. var.matching_enabled está fijado en false por su
  # validación, de modo que no hay rama que lo habilite.

  # Req 8.8 / Property 13 — recurso protegido: literal, no admite variable.
  lifecycle {
    prevent_destroy = true

    # Req 8.2 — el dominio no se planifica sin su CMK. Un parámetro SSM ausente
    # falla la lectura del data source de forma nativa; esta precondition cubre
    # además el caso de un contrato publicado pero vacío.
    precondition {
      condition     = trimspace(data.aws_ssm_parameter.profiles_kms_key_arn[0].value) != ""
      error_message = "customer-profiles-kms-key-arn no publicado o vacío; el dominio no puede planificarse (Req 8.2)."
    }
  }

  tags = {
    Name = local.name_profiles_domain
  }
}

# --- Tipo de objeto CTR (awscc, [Blocked: OQ-12]) ----------------------------
# Creado SOLO desde la plantilla CTR-AutoAssociateOnly (template_id). Cuando un
# tipo de objeto se crea desde una plantilla, AWS prohíbe declarar Fields o Keys
# propios: la plantilla los aporta. Por eso el recurso no define ningún campo,
# lo que satisface de forma estructural el guardrail PAN/SAD (Req 8.10,
# Property 16): no hay forma de introducir un nombre de campo prohibido.
resource "awscc_customerprofiles_object_type" "ctr" {
  count = local.domain_count

  domain_name      = aws_customerprofiles_domain.this[0].domain_name
  object_type_name = local.profiles_object_type_name
  template_id      = local.profiles_template_id
  description      = "CTR object type from template ${local.profiles_template_id}"

  # Sin fields ni keys: la plantilla CTR-AutoAssociateOnly los provee (Req 8.10).
  # El tag Name es el único del módulo.
  tags = [{
    key   = "Name"
    value = "${local.name_profiles_domain}-objtype-ctr"
  }]
}

# --- Integración de la instancia (awscc, [Blocked: OQ-12]) -------------------
# Exactamente una integración (Req 8.5): uri = ARN de la instancia (SSM) y
# object_type_name = CTR. Si la instancia ya tiene una integración, se adopta
# por import (DD-4) vía env.hcl adopt.customer-profiles; el plan debe mostrar 0
# integraciones a crear (Req 8.6). Este módulo no declara import blocks.
resource "awscc_customerprofiles_integration" "ctr" {
  count = local.domain_count

  domain_name      = aws_customerprofiles_domain.this[0].domain_name
  uri              = data.aws_ssm_parameter.connect_instance_arn[0].value
  object_type_name = local.profiles_object_type_name

  lifecycle {
    # Req 8.5 — la integración no se planifica sin el ARN de la instancia. Un
    # parámetro SSM ausente falla de forma nativa; esta precondition cubre
    # además el contrato publicado pero vacío.
    precondition {
      condition     = trimspace(data.aws_ssm_parameter.connect_instance_arn[0].value) != ""
      error_message = "connect-instance-arn no publicado o vacío; la integración no puede planificarse (Req 8.5)."
    }
  }

  tags = [{
    key   = "Name"
    value = "${local.name_profiles_domain}-integration-ctr"
  }]
}

# --- Contrato SSM: customer-profiles-domain-name (Req 8.7) -------------------
# String con metadatos de contrato en la descripción (L11 fija las claves de
# tag permitidas, por eso owner/classification/contract van en description).
resource "aws_ssm_parameter" "profiles_domain_name" {
  count = local.domain_count

  name        = local.ssm_profiles_domain_name
  type        = "String"
  value       = aws_customerprofiles_domain.this[0].domain_name
  description = "owner=contactcenter;classification=restricted;contract=v1"

  tags = {
    Name = local.ssm_profiles_domain_name
  }
}

# --- Contrato SSM: customer-profiles-domain-arn (Req 8.7) --------------------
resource "aws_ssm_parameter" "profiles_domain_arn" {
  count = local.domain_count

  name        = local.ssm_profiles_domain_arn
  type        = "String"
  value       = aws_customerprofiles_domain.this[0].arn
  description = "owner=contactcenter;classification=restricted;contract=v1"

  tags = {
    Name = local.ssm_profiles_domain_arn
  }
}
