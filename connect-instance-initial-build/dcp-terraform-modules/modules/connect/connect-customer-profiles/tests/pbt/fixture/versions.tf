# -----------------------------------------------------------------------------
# PBT fixture — connect/connect-customer-profiles
#
# Provider-free root used only by the property-test harness (task 1.5). It
# links the module's provider-free logic (naming.tf, validations.tf, copied in
# by harness.py) and exposes the computed locals as outputs.
#
# The module's own versions.tf pins `>= 1.15.8, < 1.16.0` and requires aws +
# awscc. That file is NOT copied into the fixture: the fixture declares no
# provider (so `terraform plan` needs no credentials and downloads nothing) and
# relaxes the version bound so the harness runs on any Terraform >= 1.15.8.
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.15.8"
}
