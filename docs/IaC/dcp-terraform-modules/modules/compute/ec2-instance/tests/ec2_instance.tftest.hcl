# Pruebas sin tocar AWS: provider simulado. Se ejecutan con `terraform test` en el PR del módulo.

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

  mock_data "aws_default_tags" {
    defaults = { tags = { Environment = "dev" } }
  }

  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }

  mock_resource "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::111111111111:policy/mock" }
  }
}

override_data {
  target = data.aws_ssm_parameter.vpc_id
  values = { insecure_value = "vpc-0123456789abcdef0" }
}

override_data {
  target = data.aws_ssm_parameter.subnet_ids
  values = { insecure_value = "subnet-0aaaaaaaaaaaaaaa1,subnet-0bbbbbbbbbbbbbbb2" }
}

override_data {
  target = data.aws_ssm_parameter.ami_id
  values = { insecure_value = "ami-0123456789abcdef0" }
}

override_data {
  target = data.aws_ssm_parameter.egress_cidrs
  values = { insecure_value = "10.20.32.0/22,10.20.36.0/22" }
}

variables {
  environment      = "dev"
  workload         = "merchants"
  purpose          = "portal"
  region_code      = "use1"
  instance_type    = "t3.small"
  ami_id_parameter = "/dcp/platform/ami/al2023-hardened/id"

  egress_rules = [
    {
      description                = "Aurora en subredes de datos"
      port                       = 5432
      destination_cidr_parameter = "/dcp/networking/subnets/data-private/cidrs"
    }
  ]

  rds_iam_db_users   = ["merchant_portal_app"]
  secrets_read_paths = ["/dcp/diners/dev/merchants/"]
}

run "nombres_siguen_la_convencion" {
  command = plan

  assert {
    condition     = aws_instance.this.tags["Name"] == "dcp-diners-dev-merchants-ec2-portal-use1-01"
    error_message = "Nombre de instancia fuera del patrón."
  }

  assert {
    condition     = aws_security_group.this.name == "dcp-diners-dev-merchants-sg-portal"
    error_message = "Nombre de SG fuera del patrón."
  }

  assert {
    condition     = aws_iam_role.this.name == "dcp-diners-dev-merchants-role-ec2-portal"
    error_message = "Nombre de rol fuera del patrón."
  }

  assert {
    condition     = aws_cloudwatch_log_group.app.name == "/dcp/diners/dev/merchants/portal"
    error_message = "Log group fuera del patrón."
  }

  assert {
    condition     = aws_ssm_parameter.security_group_id[0].name == "/dcp/diners/dev/merchants/config/portal-sg-id"
    error_message = "Parámetro de contrato fuera del patrón."
  }
}

run "controles_de_seguridad" {
  command = plan

  assert {
    condition     = aws_instance.this.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 debe ser obligatorio."
  }

  assert {
    condition     = aws_instance.this.root_block_device[0].encrypted
    error_message = "El volumen raíz debe estar cifrado."
  }

  assert {
    condition     = aws_iam_role.this.permissions_boundary == "arn:aws:iam::111111111111:policy/dcp-platform-permission-boundary"
    error_message = "Falta el permission boundary obligatorio."
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.cidr) == 2
    error_message = "Se espera una regla de salida por cada CIDR del parámetro."
  }

  assert {
    condition     = !aws_instance.this.disable_api_termination
    error_message = "En dev la protección de terminación va desactivada."
  }
}

run "prod_protege_la_instancia" {
  command = plan

  variables {
    environment = "prod"
  }

  assert {
    condition     = aws_instance.this.disable_api_termination
    error_message = "En prod la instancia debe tener protección de terminación."
  }
}

run "rechaza_workload_generico" {
  command = plan

  variables {
    workload = "shared"
  }

  expect_failures = [var.workload]
}

run "rechaza_ami_literal" {
  command = plan

  variables {
    ami_id_parameter = "ami-0123456789abcdef0"
  }

  expect_failures = [var.ami_id_parameter]
}

run "rechaza_tags_fuera_de_catalogo" {
  command = plan

  variables {
    tags = { Proyecto = "x" }
  }

  expect_failures = [var.tags]
}
