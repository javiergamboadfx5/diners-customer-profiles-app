# -----------------------------------------------------------------------------
# PBT fixture — connect/connect-instance
#
# Provider-free root used only by the property-test harness (task 1.5). It
# links the module's provider-free logic (naming.tf, validations.tf, copied in
# by harness.py) and exposes the computed locals as outputs so the Hypothesis
# tests can read them.
#
# The module's own versions.tf pins `>= 1.15.8, < 1.16.0` and requires the aws
# provider. That file is NOT copied into the fixture: the fixture declares no
# provider (so `terraform plan` needs no credentials and downloads nothing) and
# relaxes the version bound so the harness runs on any Terraform >= 1.15.8,
# including the runner/dev versions above 1.16.
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.15.8"
}
