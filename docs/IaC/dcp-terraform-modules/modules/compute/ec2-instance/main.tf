data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Los volúmenes no heredan default_tags del provider; el módulo los copia.
data "aws_default_tags" "current" {}

# -----------------------------------------------------------------------------
# Contratos leídos de Parameter Store (publicados por Networking y Platform)
# -----------------------------------------------------------------------------

data "aws_ssm_parameter" "vpc_id" {
  name = var.vpc_id_parameter
}

data "aws_ssm_parameter" "subnet_ids" {
  name = var.subnet_ids_parameter
}

data "aws_ssm_parameter" "ami_id" {
  name = var.ami_id_parameter
}

data "aws_ssm_parameter" "ingress_cidrs" {
  for_each = { for r in var.ingress_rules : r.description => r if r.source_cidr_parameter != null }
  name     = each.value.source_cidr_parameter
}

data "aws_ssm_parameter" "egress_cidrs" {
  for_each = { for r in var.egress_rules : r.description => r if r.destination_cidr_parameter != null }
  name     = each.value.destination_cidr_parameter
}

# -----------------------------------------------------------------------------
# Security Group: describe al recurso protegido (la instancia), no al origen.
# Terraform elimina la regla de salida "allow all" que AWS crea por defecto.
# -----------------------------------------------------------------------------

resource "aws_security_group" "this" {
  name        = local.sg_name
  description = "SG de ${local.instance_name}"
  vpc_id      = data.aws_ssm_parameter.vpc_id.insecure_value

  tags = merge(var.tags, { Name = local.sg_name })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "cidr" {
  for_each = local.ingress_cidr_rules

  security_group_id = aws_security_group.this.id
  description       = each.value.description
  ip_protocol       = each.value.protocol
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = each.value.cidr

  tags = merge(var.tags, { Name = "${local.sg_name}-in-${each.value.port}" })

  lifecycle {
    precondition {
      condition     = each.value.cidr != "0.0.0.0/0"
      error_message = "Entrada desde 0.0.0.0/0 prohibida en cuentas de workload."
    }
  }
}

resource "aws_vpc_security_group_ingress_rule" "sg" {
  for_each = local.ingress_sg_rules

  security_group_id            = aws_security_group.this.id
  description                  = each.value.description
  ip_protocol                  = each.value.protocol
  from_port                    = each.value.port
  to_port                      = each.value.port
  referenced_security_group_id = each.value.source_security_group_id

  tags = merge(var.tags, { Name = "${local.sg_name}-in-${each.value.port}" })
}

resource "aws_vpc_security_group_egress_rule" "cidr" {
  for_each = local.egress_cidr_rules

  security_group_id = aws_security_group.this.id
  description       = each.value.description
  ip_protocol       = each.value.protocol
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = each.value.cidr

  tags = merge(var.tags, { Name = "${local.sg_name}-out-${each.value.port}" })

  lifecycle {
    precondition {
      condition     = each.value.cidr != "0.0.0.0/0"
      error_message = "La salida a internet usa el egress central de Networking, no una regla 0.0.0.0/0."
    }
  }
}

resource "aws_vpc_security_group_egress_rule" "sg" {
  for_each = local.egress_sg_rules

  security_group_id            = aws_security_group.this.id
  description                  = each.value.description
  ip_protocol                  = each.value.protocol
  from_port                    = each.value.port
  to_port                      = each.value.port
  referenced_security_group_id = each.value.destination_security_group_id

  tags = merge(var.tags, { Name = "${local.sg_name}-out-${each.value.port}" })
}

# -----------------------------------------------------------------------------
# IAM: rol propio de mínimo privilegio, con permission boundary obligatorio.
# Acceso a la consola de la instancia solo por Session Manager (sin SSH ni llaves).
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = local.role_name
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  permissions_boundary = "arn:${local.partition}:iam::${local.account_id}:policy/${var.permissions_boundary_name}"

  tags = merge(var.tags, { Name = local.role_name })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"
}

data "aws_iam_policy_document" "runtime" {
  dynamic "statement" {
    for_each = length(var.rds_iam_db_users) > 0 ? [1] : []

    content {
      sid     = "RdsIamAuth"
      actions = ["rds-db:connect"]
      resources = [
        for u in var.rds_iam_db_users :
        "arn:${local.partition}:rds-db:${local.region}:${local.account_id}:dbuser:*/${u}"
      ]
    }
  }

  dynamic "statement" {
    for_each = length(var.secrets_read_paths) > 0 ? [1] : []

    content {
      sid     = "ReadOwnSecrets"
      actions = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      resources = [
        for p in var.secrets_read_paths :
        "arn:${local.partition}:secretsmanager:${local.region}:${local.account_id}:secret:${p}*"
      ]
    }
  }
}

resource "aws_iam_policy" "runtime" {
  count = local.runtime_policy_needed ? 1 : 0

  name   = local.policy_name
  policy = data.aws_iam_policy_document.runtime.json

  tags = merge(var.tags, { Name = local.policy_name })
}

resource "aws_iam_role_policy_attachment" "runtime" {
  count = local.runtime_policy_needed ? 1 : 0

  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.runtime[0].arn
}

resource "aws_iam_instance_profile" "this" {
  name = local.role_name
  role = aws_iam_role.this.name

  tags = merge(var.tags, { Name = local.role_name })
}

# -----------------------------------------------------------------------------
# Logs de la aplicación
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "app" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn

  tags = merge(var.tags, { Name = local.log_group_name })
}

# -----------------------------------------------------------------------------
# Instancia
# -----------------------------------------------------------------------------

resource "aws_instance" "this" {
  ami                     = data.aws_ssm_parameter.ami_id.insecure_value
  instance_type           = var.instance_type
  subnet_id               = local.subnet_ids[var.subnet_index]
  vpc_security_group_ids  = [aws_security_group.this.id]
  iam_instance_profile    = aws_iam_instance_profile.this.name
  monitoring              = var.detailed_monitoring
  ebs_optimized           = true
  disable_api_termination = var.environment == "prod"
  user_data               = var.user_data

  # IMDSv2 obligatorio (L14 §9).
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    encrypted             = true
    kms_key_id            = var.ebs_kms_key_arn
    delete_on_termination = true
    tags = merge(
      data.aws_default_tags.current.tags,
      var.tags,
      { Name = "${local.instance_name}-root" }
    )
  }

  tags = merge(var.tags, { Name = local.instance_name })

  lifecycle {
    # Una AMI nueva se adopta con un reemplazo planificado (-replace), no en cada
    # publicación del parámetro de Platform.
    ignore_changes = [ami]

    precondition {
      condition     = length(local.instance_name) <= 63
      error_message = "El nombre ${local.instance_name} supera el límite interno de 63 caracteres."
    }

    precondition {
      condition     = var.subnet_index < length(local.subnet_ids)
      error_message = "subnet_index fuera de rango para ${var.subnet_ids_parameter}."
    }
  }
}

# -----------------------------------------------------------------------------
# Contrato publicado: otros stacks del workload (por ejemplo la base de datos)
# leen el SG desde aquí, nunca desde el estado de este stack.
# -----------------------------------------------------------------------------

resource "aws_ssm_parameter" "security_group_id" {
  count = var.publish_security_group_id ? 1 : 0

  name        = local.sg_parameter_name
  description = "Contrato v1: SG de ${local.instance_name}. Lo consumen stacks del workload ${var.workload}."
  type        = "String"
  value       = aws_security_group.this.id

  tags = merge(var.tags, {
    Name            = local.sg_parameter_name
    ContractVersion = "1"
  })
}
