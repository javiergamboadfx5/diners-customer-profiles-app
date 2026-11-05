# -----------------------------------------------------------------------------
# connect/connect-instance — componente instance (tarea 2.5)
#
# Instancia de Amazon Connect, su log group de flujos de contacto y las dos
# configuraciones de almacenamiento (grabaciones de llamada y transcripciones de
# chat). Se activa solo cuando component = "instance" (local.is_instance).
#
# Requisitos cubiertos:
#   - 6.1  aws_connect_instance con identity_management_type = var.identity_management_type,
#          inbound_calls_enabled, outbound_calls_enabled, contact_flow_logs_enabled
#          y contact_lens_enabled = true, con el alias var.instance_alias.
#   - 6.2  Los contact-type tasks funcionan con los valores por defecto de la
#          instancia; no se crea ningún recurso adicional para tasks.
#   - 6.3  Dos aws_connect_instance_storage_config: CALL_RECORDINGS (prefijo
#          var.bucket_prefix_recordings) y CHAT_TRANSCRIPTS (prefijo
#          var.bucket_prefix_transcripts), ambos de tipo S3, usando el bucket del
#          contrato SSM connect-storage-bucket-name y cifrado KMS con la llave del
#          contrato SSM connect-kms-key-arn.
#   - 6.4  Ambos contratos SSM se leen con data sources sin default: un parámetro
#          ausente falla el plan de forma nativa. Una precondition en el log group
#          falla el plan ANTES de planear la instancia si cualquiera de los dos
#          contratos llega vacío.
#   - 6.5 / DD-6  Log group /aws/connect/<alias> creado ANTES de la instancia,
#          cifrado con la CMK de almacenamiento (contrato SSM connect-kms-key-arn)
#          y con la retención de var.flow_log_retention_days.
#   - 6.6  prevent_destroy = true literal sobre la instancia (recurso protegido).
#   - 6.7  Publica connect-instance-id, connect-instance-arn y
#          connect-instance-alias en los contratos SSM del workload.
#
# El módulo solo añade el tag Name (Req 2.6); el resto de tags obligatorios los
# inyecta el root vía provider default_tags.
# -----------------------------------------------------------------------------

locals {
  instance_count = local.is_instance ? 1 : 0
}

# --- Contratos externos: bucket y CMK de almacenamiento (Req 6.3, 6.4) -------
# Sin default: un parámetro ausente falla el plan de forma nativa. Los publican
# los stacks storage (connect-storage-bucket-name) y kms (connect-kms-key-arn).
data "aws_ssm_parameter" "instance_storage_bucket_name" {
  count = local.instance_count
  name  = local.ssm_name_bucket_name
}

data "aws_ssm_parameter" "instance_kms_key_arn" {
  count = local.instance_count
  name  = local.ssm_name_kms_key_arn
}

locals {
  instance_bucket_name = local.is_instance ? data.aws_ssm_parameter.instance_storage_bucket_name[0].value : null
  instance_kms_key_arn = local.is_instance ? data.aws_ssm_parameter.instance_kms_key_arn[0].value : null

  # Prefijos de objeto normalizados (sin barra inicial ni final) para las
  # configuraciones de almacenamiento de Connect.
  instance_prefix_recordings  = trimsuffix(trimprefix(var.bucket_prefix_recordings, "/"), "/")
  instance_prefix_transcripts = trimsuffix(trimprefix(var.bucket_prefix_transcripts, "/"), "/")
}

# --- Log group de flujos de contacto (Req 6.5 / DD-6) ------------------------
# Nombre fijo /aws/connect/<alias>. Se crea antes de la instancia para que
# Terraform controle KMS, retención y tags. La precondition falla el plan antes
# de planear la instancia si cualquiera de los contratos de almacenamiento llega
# vacío (Req 6.4); el data source ya falla de forma nativa si no existe.
resource "aws_cloudwatch_log_group" "flow_logs" {
  count = local.instance_count

  name              = local.flow_log_group_name
  retention_in_days = var.flow_log_retention_days
  kms_key_id        = local.instance_kms_key_arn

  lifecycle {
    precondition {
      condition     = try(length(trimspace(data.aws_ssm_parameter.instance_kms_key_arn[0].value)) > 0, false)
      error_message = "El contrato SSM connect-kms-key-arn está vacío o no existe; el log group de flujos de contacto no puede cifrarse con la CMK de almacenamiento (Req 6.4, 6.5)."
    }

    precondition {
      condition     = try(length(trimspace(data.aws_ssm_parameter.instance_storage_bucket_name[0].value)) > 0, false)
      error_message = "El contrato SSM connect-storage-bucket-name está vacío o no existe; las configuraciones de almacenamiento de la instancia no pueden resolverse (Req 6.4)."
    }
  }

  tags = {
    Name = local.name_tag_log_group
  }
}

# --- Instancia de Amazon Connect (Req 6.1, 6.2, 6.6) -------------------------
# El log group /aws/connect/<alias> debe existir antes que la instancia (DD-6),
# por eso el depends_on explícito. No se crea ningún recurso adicional para
# contact-type tasks (Req 6.2): funcionan con los valores por defecto.
resource "aws_connect_instance" "this" {
  count = local.instance_count

  instance_alias           = var.instance_alias
  identity_management_type = var.identity_management_type

  inbound_calls_enabled     = var.inbound_calls_enabled
  outbound_calls_enabled    = var.outbound_calls_enabled
  contact_flow_logs_enabled = var.contact_flow_logs_enabled

  # Req 6.1 — Contact Lens siempre habilitado en esta instancia.
  contact_lens_enabled = true

  # Directorio existente solo cuando el tipo de identidad lo exige (validations.tf
  # ya garantiza directory_id en EXISTING_DIRECTORY, Req 3.3).
  directory_id = var.identity_management_type == "EXISTING_DIRECTORY" ? var.directory_id : null

  depends_on = [aws_cloudwatch_log_group.flow_logs]

  # Req 6.6 / Property 13 — recurso protegido: literal, no admite variable.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = local.name_tag_instance
  }
}

# --- Configuración de almacenamiento: grabaciones de llamada (Req 6.3) -------
resource "aws_connect_instance_storage_config" "call_recordings" {
  count = local.instance_count

  instance_id   = aws_connect_instance.this[0].id
  resource_type = "CALL_RECORDINGS"

  storage_config {
    storage_type = "S3"

    s3_config {
      bucket_name   = local.instance_bucket_name
      bucket_prefix = local.instance_prefix_recordings

      encryption_config {
        encryption_type = "KMS"
        key_id          = local.instance_kms_key_arn
      }
    }
  }
}

# --- Configuración de almacenamiento: transcripciones de chat (Req 6.3) ------
resource "aws_connect_instance_storage_config" "chat_transcripts" {
  count = local.instance_count

  instance_id   = aws_connect_instance.this[0].id
  resource_type = "CHAT_TRANSCRIPTS"

  storage_config {
    storage_type = "S3"

    s3_config {
      bucket_name   = local.instance_bucket_name
      bucket_prefix = local.instance_prefix_transcripts

      encryption_config {
        encryption_type = "KMS"
        key_id          = local.instance_kms_key_arn
      }
    }
  }
}

# --- Contrato SSM: connect-instance-id (Req 6.7) -----------------------------
# String con metadatos de contrato en la descripción (L11 fija las claves de
# tag permitidas, por eso owner/classification/contract van en description).
resource "aws_ssm_parameter" "connect_instance_id" {
  count = local.instance_count

  name        = local.ssm_name_instance_id
  type        = "String"
  value       = aws_connect_instance.this[0].id
  description = "owner=contactcenter;classification=restricted;contract=v1"

  tags = {
    Name = local.ssm_name_instance_id
  }
}

# --- Contrato SSM: connect-instance-arn (Req 6.7) ----------------------------
resource "aws_ssm_parameter" "connect_instance_arn" {
  count = local.instance_count

  name        = local.ssm_name_instance_arn
  type        = "String"
  value       = aws_connect_instance.this[0].arn
  description = "owner=contactcenter;classification=restricted;contract=v1"

  tags = {
    Name = local.ssm_name_instance_arn
  }
}

# --- Contrato SSM: connect-instance-alias (Req 6.7) --------------------------
resource "aws_ssm_parameter" "connect_instance_alias" {
  count = local.instance_count

  name        = local.ssm_name_instance_alias
  type        = "String"
  value       = aws_connect_instance.this[0].instance_alias
  description = "owner=contactcenter;classification=restricted;contract=v1"

  tags = {
    Name = local.ssm_name_instance_alias
  }
}
