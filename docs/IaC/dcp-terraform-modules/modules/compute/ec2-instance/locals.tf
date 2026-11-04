locals {
  # dcp-<domain>-<environment>-<workload>
  base_name = join("-", ["dcp", var.domain, var.environment, var.workload])

  # dcp-<domain>-<environment>-<workload>-ec2-<purpose>-<region>-<ordinal>
  # El código "ec2" se agrega al catálogo de recursos en el mismo PR que este módulo.
  instance_name = join("-", [local.base_name, "ec2", var.purpose, var.region_code, var.ordinal])

  # dcp-<domain>-<environment>-<workload>-sg-<purpose>
  sg_name = "${local.base_name}-sg-${var.purpose}"

  # dcp-<domain>-<environment>-<workload>-role-<purpose>; el instance profile usa el mismo nombre.
  role_name   = "${local.base_name}-role-ec2-${var.purpose}"
  policy_name = "${local.base_name}-policy-${var.purpose}-runtime"

  # /dcp/<domain>/<environment>/<workload>/<service>
  log_group_name = "/dcp/${var.domain}/${var.environment}/${var.workload}/${var.purpose}"

  # /dcp/<domain>/<environment>/<workload>/config/<parameter>
  sg_parameter_name = "/dcp/${var.domain}/${var.environment}/${var.workload}/config/${var.purpose}-sg-id"

  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  subnet_ids = split(",", data.aws_ssm_parameter.subnet_ids.insecure_value)

  # Una regla por cada CIDR del parámetro; la clave es estable mientras no cambie description ni CIDR.
  ingress_cidr_rules = merge([
    for r in var.ingress_rules : {
      for cidr in split(",", data.aws_ssm_parameter.ingress_cidrs[r.description].insecure_value) :
      "${r.description}|${cidr}" => merge(r, { cidr = trimspace(cidr) })
    } if r.source_cidr_parameter != null
  ]...)

  ingress_sg_rules = {
    for r in var.ingress_rules : r.description => r if r.source_security_group_id != null
  }

  egress_cidr_rules = merge([
    for r in var.egress_rules : {
      for cidr in split(",", data.aws_ssm_parameter.egress_cidrs[r.description].insecure_value) :
      "${r.description}|${cidr}" => merge(r, { cidr = trimspace(cidr) })
    } if r.destination_cidr_parameter != null
  ]...)

  egress_sg_rules = {
    for r in var.egress_rules : r.description => r if r.destination_security_group_id != null
  }

  runtime_policy_needed = length(var.rds_iam_db_users) > 0 || length(var.secrets_read_paths) > 0
}
