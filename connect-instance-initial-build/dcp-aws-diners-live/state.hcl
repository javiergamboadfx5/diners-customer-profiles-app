# =============================================================================
# ARCHIVO PUBLICADO POR dcp-terraform-bootstrap. No se edita a mano.
# El bootstrap calcula <unique> = substr(sha256("<org-id>:<account-id>:terraform-state"), 0, 12)
# y publica aquí el nombre final de cada bucket y el ARN de la llave KMS.
# =============================================================================
locals {
  aws_region = "us-east-1"

  bucket_by_tier = {
    nonprod = "dcp-platform-shared-terraform-s3-state-nonprod-use1-<unique-publicado>"
    prod    = "dcp-platform-shared-terraform-s3-state-prod-use1-<unique-publicado>"
  }

  kms_key_arn = "<arn-kms-publicado-por-bootstrap>"
}
