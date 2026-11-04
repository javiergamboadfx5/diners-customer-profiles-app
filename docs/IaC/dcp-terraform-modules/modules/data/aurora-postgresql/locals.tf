locals {
  base_name = join("-", ["dcp", var.domain, var.environment, var.workload])

  # dcp-<domain>-<environment>-<workload>-aurora-<purpose>-<region>
  cluster_name = "${local.base_name}-aurora-${var.purpose}-${var.region_code}"

  # dcp-<domain>-<environment>-<workload>-dbsubnet-<region>
  subnet_group_name = "${local.base_name}-dbsubnet-${var.region_code}"

  engine_major = split(".", var.engine_version)[0]

  # dcp-<domain>-<environment>-<workload>-aurora-pg-<major-version>
  parameter_group_name = "${local.base_name}-aurora-pg-${local.engine_major}"

  sg_name = var.purpose == "core" ? "${local.base_name}-sg-aurora" : "${local.base_name}-sg-aurora-${var.purpose}"

  # alias/dcp/<scope>/<environment>/<workload>/<purpose>
  kms_alias = "alias/dcp/${var.domain}/${var.environment}/${var.workload}/data"
  kms_arn   = var.create_kms_key ? aws_kms_key.data[0].arn : var.kms_key_arn

  log_group_name = "/aws/rds/cluster/${local.cluster_name}/postgresql"

  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  subnet_ids = split(",", data.aws_ssm_parameter.subnet_ids.insecure_value)
}
