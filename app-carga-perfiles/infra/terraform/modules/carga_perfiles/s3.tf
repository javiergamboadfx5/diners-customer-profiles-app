# ---------- Bucket de archivos de carga (datos personales) ----------

resource "aws_s3_bucket" "cargas" {
  bucket        = "${local.prefijo}-${local.cuenta}-cargas"
  force_destroy = var.ambiente != "prod"
  tags          = local.tags
}

resource "aws_s3_bucket_public_access_block" "cargas" {
  bucket                  = aws_s3_bucket.cargas.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "cargas" {
  bucket = aws_s3_bucket.cargas.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cargas" {
  bucket = aws_s3_bucket.cargas.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.app.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cargas" {
  bucket = aws_s3_bucket.cargas.id
  rule {
    id     = "expirar-archivos"
    status = "Enabled"
    filter {
      prefix = "cargas/"
    }
    expiration {
      days = var.dias_retencion_archivos
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# El navegador sube el archivo directo a S3 con un POST prefirmado.
resource "aws_s3_bucket_cors_configuration" "cargas" {
  bucket = aws_s3_bucket.cargas.id
  cors_rule {
    allowed_methods = ["POST", "GET"]
    allowed_origins = ["https://${aws_cloudfront_distribution.app.domain_name}"]
    allowed_headers = ["*"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_policy" "cargas" {
  bucket = aws_s3_bucket.cargas.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "SoloTLS"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.cargas.arn, "${aws_s3_bucket.cargas.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.cargas]
}

resource "aws_s3_bucket_notification" "cargas" {
  bucket = aws_s3_bucket.cargas.id
  lambda_function {
    lambda_function_arn = aws_lambda_function.fn["validador"].arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "cargas/"
    filter_suffix       = "original.csv"
  }
  depends_on = [aws_lambda_permission.s3_validador]
}

# ---------- Bucket del sitio (frontend) ----------

resource "aws_s3_bucket" "sitio" {
  bucket        = "${local.prefijo}-${local.cuenta}-sitio"
  force_destroy = true
  tags          = local.tags
}

resource "aws_s3_bucket_public_access_block" "sitio" {
  bucket                  = aws_s3_bucket.sitio.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "sitio" {
  bucket = aws_s3_bucket.sitio.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sitio" {
  bucket = aws_s3_bucket.sitio.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "sitio" {
  bucket = aws_s3_bucket.sitio.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "SoloCloudFront"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.sitio.arn}/*"
        Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.app.arn } }
      },
      {
        Sid       = "SoloTLS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.sitio.arn, "${aws_s3_bucket.sitio.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }
    ]
  })
  depends_on = [aws_s3_bucket_public_access_block.sitio]
}

# Configuracion en tiempo de ejecucion: el mismo build sirve para todos los ambientes.
resource "aws_s3_object" "config" {
  bucket        = aws_s3_bucket.sitio.id
  key           = "config.json"
  content_type  = "application/json"
  cache_control = "no-cache"
  content = jsonencode({
    modo      = "api"
    apiBase   = "/api"
    instancia = "${var.connect_instance_alias}.my.connect.aws"
    ambiente  = var.ambiente
    oidc = {
      authority = var.oidc_issuer
      clientId  = var.oidc_client_id
      scope     = var.oidc_scope
    }
  })
}
