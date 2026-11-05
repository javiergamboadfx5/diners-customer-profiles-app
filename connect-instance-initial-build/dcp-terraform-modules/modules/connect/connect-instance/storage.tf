# -----------------------------------------------------------------------------
# connect/connect-instance — componente storage (tarea 2.3)
#
# Bucket S3 de almacenamiento de Connect (grabaciones de llamada y transcripciones
# de chat) y su endurecimiento. Se activa solo cuando component = "storage"
# (local.is_storage).
#
# Requisitos cubiertos:
#   - 5.1  Bucket local.bucket_name (<= 63 caracteres, nombre determinista).
#   - 5.2  Los 4 ajustes de Block Public Access en true, ownership
#          BucketOwnerEnforced, versionado Enabled, SSE-KMS por defecto con
#          bucket key usando la CMK de almacenamiento leída del contrato SSM
#          connect-kms-key-arn (sin literal, sin fallback a SSE-S3 o llave
#          gestionada por AWS).
#   - 5.3  El ARN de la CMK se lee del contrato SSM sin default: un parámetro
#          ausente falla el plan de forma nativa.
#   - 5.4  Política de bucket que niega el transporte inseguro
#          (aws:SecureTransport = false) y los PutObject con una llave o un
#          algoritmo de cifrado distintos de la CMK de almacenamiento.
#   - 5.5  Reglas de ciclo de vida para los prefijos de grabaciones y
#          transcripciones y para las versiones no actuales, con los días de
#          retención tomados solo de las variables (OQ-7). Los valores < 1 ya
#          fallan en validations.tf.
#   - 5.7  Publica el nombre del bucket en el contrato SSM
#          connect-storage-bucket-name.
#   - 5.8  prevent_destroy = true literal sobre el bucket (recurso protegido).
#
# Guardrails (connect_guardrails.rego) y iac-security-pci (DR, §CI/CD):
#   - aws_s3_bucket_public_access_block: 4 ajustes en true.
#   - aws_s3_bucket_ownership_controls: BucketOwnerEnforced.
#   - aws_s3_bucket_server_side_encryption_configuration: aws:kms.
#   - aws_s3_bucket_policy: statement Deny con aws:SecureTransport = false.
#   - aws_s3_bucket: recurso protegido (no borrar ni reemplazar).
#
# El módulo solo añade el tag Name (Req 2.6); el resto de tags obligatorios los
# inyecta el root vía provider default_tags.
# -----------------------------------------------------------------------------

locals {
  storage_count = local.is_storage ? 1 : 0

  # Prefijos de objeto normalizados (sin barra inicial, con barra final) para
  # acotar las reglas de ciclo de vida a cada tipo de contenido.
  prefix_recordings  = "${trimsuffix(var.bucket_prefix_recordings, "/")}/"
  prefix_transcripts = "${trimsuffix(var.bucket_prefix_transcripts, "/")}/"

  # Valor técnico, no una decisión de retención: aborta subidas multiparte
  # incompletas pasados 7 días (constante del módulo).
  abort_multipart_days = 7
}

# --- Contrato externo: CMK de almacenamiento (Req 5.2, 5.3) ------------------
# Sin default: un parámetro ausente falla el plan de forma nativa, sin fallback
# a SSE-S3 ni a una llave gestionada por AWS.
data "aws_ssm_parameter" "storage_kms_key_arn" {
  count = local.storage_count
  name  = local.ssm_name_kms_key_arn
}

locals {
  storage_kms_key_arn = local.is_storage ? data.aws_ssm_parameter.storage_kms_key_arn[0].value : null

  # ARNs del bucket y de sus objetos (se calculan una sola vez).
  bucket_arn         = local.is_storage ? aws_s3_bucket.storage[0].arn : null
  bucket_objects_arn = local.is_storage ? "${aws_s3_bucket.storage[0].arn}/*" : null
}

# --- Bucket de almacenamiento ------------------------------------------------
resource "aws_s3_bucket" "storage" {
  count = local.storage_count

  bucket = local.bucket_name

  # Req 5.8 / Property 13 — recurso protegido: literal, no admite variable.
  lifecycle {
    prevent_destroy = true

    # Req 5.3 — refuerza el mensaje si el contrato llega vacío (el data source
    # ya falla de forma nativa si el parámetro no existe).
    precondition {
      condition     = try(length(trimspace(data.aws_ssm_parameter.storage_kms_key_arn[0].value)) > 0, false)
      error_message = "El contrato SSM connect-kms-key-arn está vacío o no existe; el bucket no puede cifrarse con la CMK de almacenamiento (Req 5.3)."
    }
  }

  tags = {
    Name = local.name_tag_bucket
  }
}

# --- Block Public Access: los 4 ajustes en true (Req 5.2) --------------------
resource "aws_s3_bucket_public_access_block" "storage" {
  count = local.storage_count

  bucket = aws_s3_bucket.storage[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Ownership controls: BucketOwnerEnforced (Req 5.2) -----------------------
resource "aws_s3_bucket_ownership_controls" "storage" {
  count = local.storage_count

  bucket = aws_s3_bucket.storage[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# --- Versionado Enabled (Req 5.2) --------------------------------------------
resource "aws_s3_bucket_versioning" "storage" {
  count = local.storage_count

  bucket = aws_s3_bucket.storage[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

# --- Cifrado por defecto SSE-KMS con bucket key (Req 5.2) --------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "storage" {
  count = local.storage_count

  bucket = aws_s3_bucket.storage[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = local.storage_kms_key_arn
    }
    bucket_key_enabled = true
  }
}

# --- Política de bucket (Req 5.4) --------------------------------------------
# Tres statements Deny con Principal "*": transporte inseguro, llave KMS
# incorrecta y algoritmo de cifrado distinto de aws:kms. Los Deny con
# Principal "*" son correctos (la regla de wildcard del guardrail aplica solo a
# los Allow de las políticas KMS).
data "aws_iam_policy_document" "storage_bucket" {
  count = local.storage_count

  # DenyInsecureTransport — niega todo si no viaja por TLS.
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["s3:*"]
    resources = [local.bucket_arn, local.bucket_objects_arn]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # DenyWrongKmsKey — niega PutObject que declare una llave KMS distinta de la
  # CMK de almacenamiento.
  statement {
    sid    = "DenyWrongKmsKey"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["s3:PutObject"]
    resources = [local.bucket_objects_arn]

    condition {
      test     = "StringNotEqualsIfExists"
      variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
      values   = [local.storage_kms_key_arn]
    }
  }

  # DenyNonKmsEncryption — niega PutObject cuyo algoritmo de cifrado no sea
  # aws:kms.
  statement {
    sid    = "DenyNonKmsEncryption"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["s3:PutObject"]
    resources = [local.bucket_objects_arn]

    condition {
      test     = "StringNotEqualsIfExists"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["aws:kms"]
    }
  }
}

resource "aws_s3_bucket_policy" "storage" {
  count = local.storage_count

  bucket = aws_s3_bucket.storage[0].id
  policy = data.aws_iam_policy_document.storage_bucket[0].json

  # La política de denegación de transporte inseguro depende de que el bucket
  # bloquee el acceso público primero.
  depends_on = [aws_s3_bucket_public_access_block.storage]
}

# --- Ciclo de vida (Req 5.5) -------------------------------------------------
# Expiración por prefijo de grabaciones y transcripciones, expiración de
# versiones no actuales y aborto de subidas multiparte incompletas. Los días de
# retención vienen de las variables (OQ-7); validations.tf ya garantiza >= 1.
resource "aws_s3_bucket_lifecycle_configuration" "storage" {
  count = local.storage_count

  bucket = aws_s3_bucket.storage[0].id

  # El versionado debe existir antes de aplicar reglas sobre versiones no
  # actuales.
  depends_on = [aws_s3_bucket_versioning.storage]

  rule {
    id     = "expire-call-recordings"
    status = "Enabled"

    filter {
      prefix = local.prefix_recordings
    }

    expiration {
      days = var.recordings_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = local.abort_multipart_days
    }
  }

  rule {
    id     = "expire-chat-transcripts"
    status = "Enabled"

    filter {
      prefix = local.prefix_transcripts
    }

    expiration {
      days = var.transcripts_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = local.abort_multipart_days
    }
  }

  # Expiración de versiones no actuales para cualquier otro objeto del bucket.
  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = local.abort_multipart_days
    }
  }
}

# --- Contrato SSM: connect-storage-bucket-name (Req 5.7) ---------------------
# String con metadatos de contrato en la descripción (L11 fija las claves de
# tag permitidas, por eso owner/classification/contract van en description).
resource "aws_ssm_parameter" "connect_storage_bucket_name" {
  count = local.storage_count

  name        = local.ssm_name_bucket_name
  type        = "String"
  value       = aws_s3_bucket.storage[0].id
  description = "owner=contactcenter;classification=restricted;contract=v1"

  tags = {
    Name = local.ssm_name_bucket_name
  }
}
