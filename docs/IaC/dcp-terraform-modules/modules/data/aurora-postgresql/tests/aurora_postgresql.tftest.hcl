mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }

  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }

  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }

  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }

  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
  }
}

override_data {
  target = data.aws_ssm_parameter.vpc_id
  values = { insecure_value = "vpc-0123456789abcdef0" }
}

override_data {
  target = data.aws_ssm_parameter.subnet_ids
  values = { insecure_value = "subnet-0ccccccccccccccc1,subnet-0ddddddddddddddd2" }
}

override_data {
  target = data.aws_ssm_parameter.allowed_sg
  values = { insecure_value = "sg-0123456789abcdef0" }
}

variables {
  environment    = "dev"
  workload       = "merchants"
  region_code    = "use1"
  instance_class = "db.t4g.medium"
  instance_count = 1
  database_name  = "merchants"

  allowed_security_group_id_parameters = ["/dcp/diners/dev/merchants/config/portal-sg-id"]
}

run "nombres_siguen_la_convencion" {
  command = plan

  assert {
    condition     = aws_rds_cluster.this.cluster_identifier == "dcp-diners-dev-merchants-aurora-core-use1"
    error_message = "Nombre de cluster fuera del patrón."
  }

  assert {
    condition     = aws_rds_cluster_instance.this[0].identifier == "dcp-diners-dev-merchants-aurora-core-use1-instance-01"
    error_message = "Nombre de instancia fuera del patrón."
  }

  assert {
    condition     = aws_rds_cluster_parameter_group.this.name == "dcp-diners-dev-merchants-aurora-pg-16"
    error_message = "Nombre de parameter group fuera del patrón."
  }

  assert {
    condition     = aws_kms_alias.data[0].name == "alias/dcp/diners/dev/merchants/data"
    error_message = "Alias KMS fuera del patrón."
  }
}

run "cifrado_y_acceso_privado" {
  command = plan

  assert {
    condition     = aws_rds_cluster.this.storage_encrypted && aws_rds_cluster.this.manage_master_user_password
    error_message = "El cluster debe ir cifrado y con contraseña administrada por RDS."
  }

  assert {
    condition     = !aws_rds_cluster_instance.this[0].publicly_accessible
    error_message = "Las instancias no pueden ser públicas."
  }
}

run "prod_exige_alta_disponibilidad" {
  command = plan

  variables {
    environment    = "prod"
    instance_count = 1
  }

  expect_failures = [aws_rds_cluster.this]
}
