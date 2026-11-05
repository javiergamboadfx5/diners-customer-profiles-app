# -----------------------------------------------------------------------------
# PBT fixture stubs — connect/connect-customer-profiles
#
# The module's naming.tf builds the `profiles_domain_arn` local from three AWS
# data sources (aws_partition, aws_region, aws_caller_identity) that are
# declared in the module's main.tf and require the AWS provider at plan time.
#
# To keep the harness provider-free and offline, harness.py copies naming.tf and
# rewrites those three data-source references to the fixture variables below
# (see harness.py -> _patch_naming). The ARN local then becomes a pure,
# deterministic function of its inputs, which is exactly what the property test
# needs. The committed module file is never modified; only the throwaway copy
# is rewritten. The real data-source wiring is exercised by the module's
# `terraform test` suite with a mock_provider (task 3.4), not by PBT.
# -----------------------------------------------------------------------------

variable "stub_partition" {
  type        = string
  description = "Stand-in for data.aws_partition.current.partition in the fixture."
  default     = "aws"
}

variable "stub_region" {
  type        = string
  description = "Stand-in for data.aws_region.current.name in the fixture."
  default     = "us-east-1"
}

variable "stub_account_id" {
  type        = string
  description = "Stand-in for data.aws_caller_identity.current.account_id in the fixture."
  default     = "123456789012"
}
