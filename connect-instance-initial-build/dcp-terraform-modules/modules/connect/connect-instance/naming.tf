# -----------------------------------------------------------------------------
# connect/connect-instance — nombres físicos (tarea 1.2)
#
# Locals deterministas y libres de proveedor. Construyen los nombres a partir de
# environment / workload / purpose / region_code (Req 2.6, iac-naming-tags L07).
# Las pruebas de propiedad (tarea 1.12) comprueban límites y determinismo.
#
# Límites aplicados:
#   - Bucket S3: <= 63 caracteres (estándar).
#   - Alias KMS: el segmento <purpose> <= 32 (código compacto); el alias total
#     se mantiene muy por debajo de 256.
# -----------------------------------------------------------------------------

locals {
  # Prefijo de workload: dcp-<domain>-<environment>-<workload>  (L07)
  prefix = "dcp-${var.domain}-${var.environment}-${var.workload}"

  # Propósitos (purpose) de este módulo.
  purpose_storage = "connect-storage"

  # ---------------------------------------------------------------------------
  # S3: dcp-<domain>-<env>-<workload>-s3-<purpose>-<region_code>-<unique>
  #
  # unique = substr(sha256("<org-id>:<account-id>:<purpose>"), 0, 12)
  # Determinista: mismas entradas -> mismo nombre. Sin puntos (Req 5.1, L10).
  # ---------------------------------------------------------------------------
  bucket_unique = substr(sha256("${var.org_id}:${var.account_id}:${local.purpose_storage}"), 0, 12)
  bucket_name   = "${local.prefix}-s3-${local.purpose_storage}-${var.region_code}-${local.bucket_unique}"

  # ---------------------------------------------------------------------------
  # Alias KMS: alias/dcp/<scope>/<env>/<workload>/<purpose>  (L08)
  # scope = domain para resources de workload.
  # ---------------------------------------------------------------------------
  kms_alias_storage = "alias/dcp/${var.domain}/${var.environment}/${var.workload}/${local.purpose_storage}"

  # ---------------------------------------------------------------------------
  # Base de contratos SSM: /dcp/<domain>/<env>/<workload>/config  (L10)
  # ---------------------------------------------------------------------------
  ssm_base = "/dcp/${var.domain}/${var.environment}/${var.workload}/config"

  # Nombres de contratos SSM publicados por este módulo (Req 4.4, 5.7, 6.7).
  ssm_name_kms_key_arn    = "${local.ssm_base}/connect-kms-key-arn"
  ssm_name_bucket_name    = "${local.ssm_base}/connect-storage-bucket-name"
  ssm_name_instance_id    = "${local.ssm_base}/connect-instance-id"
  ssm_name_instance_arn   = "${local.ssm_base}/connect-instance-arn"
  ssm_name_instance_alias = "${local.ssm_base}/connect-instance-alias"
  ssm_name_key_admin_role = "${local.ssm_base}/key-admin-role-arn"

  # ---------------------------------------------------------------------------
  # Log group nativo de Connect (DD-6): /aws/connect/<alias>
  # Solo se resuelve cuando hay alias (componente instance).
  # ---------------------------------------------------------------------------
  flow_log_group_name = var.instance_alias != null ? "/aws/connect/${var.instance_alias}" : null

  # ---------------------------------------------------------------------------
  # Valores del tag Name por recurso (Req 2.6: el módulo solo añade Name).
  # ---------------------------------------------------------------------------
  name_tag_kms_key   = "${local.prefix}-kms-${local.purpose_storage}"
  name_tag_bucket    = local.bucket_name
  name_tag_log_group = local.flow_log_group_name
  name_tag_instance  = var.instance_alias

  # ---------------------------------------------------------------------------
  # Comprobaciones de longitud deterministas. Se exponen como locals para que
  # las pruebas de propiedad (tarea 1.12) y los tests de Terraform las usen.
  # ---------------------------------------------------------------------------
  bucket_name_ok = length(local.bucket_name) <= 63
  kms_alias_ok   = length(local.kms_alias_storage) <= 256
}
