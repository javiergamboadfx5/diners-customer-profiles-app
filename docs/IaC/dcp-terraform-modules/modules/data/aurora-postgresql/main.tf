data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_ssm_parameter" "vpc_id" {
  name = var.vpc_id_parameter
}

data "aws_ssm_parameter" "subnet_ids" {
  name = var.subnet_ids_parameter
}

data "aws_ssm_parameter" "allowed_sg" {
  for_each = toset(var.allowed_security_group_id_parameters)
  name     = each.value
}

# -----------------------------------------------------------------------------
# KMS: cifra almacenamiento, snapshots, Performance Insights, secreto maestro y logs
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "kms" {
  statement {
    sid       = "AccountAdmin"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid       = "CloudWatchLogs"
    actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${local.region}.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${local.log_group_name}"]
    }
  }
}

resource "aws_kms_key" "data" {
  count = var.create_kms_key ? 1 : 0

  description             = "Datos de ${local.cluster_name}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms.json

  tags = merge(var.tags, { Name = local.kms_alias })
}

resource "aws_kms_alias" "data" {
  count = var.create_kms_key ? 1 : 0

  name          = local.kms_alias
  target_key_id = aws_kms_key.data[0].key_id
}

# -----------------------------------------------------------------------------
# Red
# -----------------------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = local.subnet_group_name
  subnet_ids = local.subnet_ids

  tags = merge(var.tags, { Name = local.subnet_group_name })
}

resource "aws_security_group" "this" {
  name        = local.sg_name
  description = "SG de ${local.cluster_name}"
  vpc_id      = data.aws_ssm_parameter.vpc_id.insecure_value

  tags = merge(var.tags, { Name = local.sg_name })

  lifecycle {
    create_before_destroy = true
  }
}

# Solo entra quien publicó su SG como contrato. Sin reglas de salida.
resource "aws_vpc_security_group_ingress_rule" "allowed" {
  for_each = data.aws_ssm_parameter.allowed_sg

  security_group_id            = aws_security_group.this.id
  description                  = "PostgreSQL desde ${each.key}"
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  referenced_security_group_id = each.value.insecure_value

  tags = merge(var.tags, { Name = "${local.sg_name}-in-${var.port}" })
}

# -----------------------------------------------------------------------------
# Parámetros y logs
# -----------------------------------------------------------------------------

resource "aws_rds_cluster_parameter_group" "this" {
  name        = local.parameter_group_name
  family      = "aurora-postgresql${local.engine_major}"
  description = "Parámetros de ${local.cluster_name}"

  # TLS obligatorio para toda conexión.
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  tags = merge(var.tags, { Name = local.parameter_group_name })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "postgresql" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = local.kms_arn

  tags = merge(var.tags, { Name = local.log_group_name })
}

# -----------------------------------------------------------------------------
# Cluster e instancias
# -----------------------------------------------------------------------------

resource "aws_rds_cluster" "this" {
  cluster_identifier = local.cluster_name
  engine             = "aurora-postgresql"
  engine_version     = var.engine_version
  database_name      = var.database_name
  port               = var.port

  # Contraseña generada, guardada y rotada por RDS en Secrets Manager. Nunca en tfvars.
  master_username               = var.master_username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = local.kms_arn

  iam_database_authentication_enabled = true

  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.this.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name

  storage_encrypted = true
  kms_key_id        = local.kms_arn

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true
  deletion_protection          = var.deletion_protection
  skip_final_snapshot          = var.environment != "prod"
  final_snapshot_identifier    = "${local.cluster_name}-final"
  apply_immediately            = var.environment != "prod"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = merge(var.tags, { Name = local.cluster_name })

  depends_on = [aws_cloudwatch_log_group.postgresql]

  lifecycle {
    precondition {
      condition     = var.environment != "prod" || (var.instance_count >= 2 && var.deletion_protection && var.backup_retention_days >= 7)
      error_message = "En prod: al menos 2 instancias, deletion_protection activo y 7 días o más de backup."
    }

    precondition {
      condition     = local.kms_arn != null
      error_message = "Defina create_kms_key = true o entregue kms_key_arn."
    }

    precondition {
      condition     = length(local.cluster_name) <= 63
      error_message = "El nombre ${local.cluster_name} supera 63 caracteres."
    }
  }
}

resource "aws_rds_cluster_instance" "this" {
  count = var.instance_count

  # <cluster-name>-instance-01, -02, ... (el nombre no codifica writer o reader)
  identifier         = format("%s-instance-%02d", local.cluster_name, count.index + 1)
  cluster_identifier = aws_rds_cluster.this.id
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version
  instance_class     = var.instance_class

  db_subnet_group_name       = aws_db_subnet_group.this.name
  publicly_accessible        = false
  auto_minor_version_upgrade = true
  apply_immediately          = var.environment != "prod"

  performance_insights_enabled    = true
  performance_insights_kms_key_id = local.kms_arn

  tags = merge(var.tags, { Name = format("%s-instance-%02d", local.cluster_name, count.index + 1) })
}
