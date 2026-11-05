# -----------------------------------------------------------------------------
# connect/connect-customer-profiles — naming (tarea 1.3)
#
# Construcción determinista de nombres físicos y contratos, libre de proveedor.
# No lee credenciales ni data sources: solo depende de environment, workload,
# purpose y region_code (Req 2.6, iac-naming-tags L07–L10).
#
# Las validaciones de los valores de entrada viven en validations.tf.
# -----------------------------------------------------------------------------

locals {
  # Prefijo de nombre de recursos de workload:
  #   dcp-<domain>-<environment>-<workload>
  # (iac-naming-tags L07). region_code se añade solo donde el recurso físico
  # regional debe distinguirse; el dominio de Customer Profiles es lógico.
  prefix = join("-", ["dcp", var.domain, var.environment, var.workload])

  # ---------------------------------------------------------------------------
  # Nombre del dominio de Customer Profiles
  # ---------------------------------------------------------------------------
  # AWS exige el prefijo `amazon-connect-` (AmazonConnectServiceLinkedRolePolicy).
  # Bajo la regla de precedencia 1 (constraint nativo de AWS gana sobre el
  # patrón dcp-...), el nombre se construye como:
  #   amazon-connect-dcp-<domain>-<environment>-<workload>
  # Si se provee domain_name explícito, se respeta (validado en validations.tf).
  #
  # Longitud: 15 (amazon-connect-) + 11 (dcp-diners-) + <env> + '-' + <workload>
  # con workload <= 10 y environment <= 4 queda muy por debajo de 64.
  profiles_domain = var.domain_name != null ? var.domain_name : "amazon-connect-${local.prefix}"

  # ---------------------------------------------------------------------------
  # Alias de la CMK dedicada de Customer Profiles
  # ---------------------------------------------------------------------------
  # Patrón iac-naming-tags L08:
  #   alias/dcp/<scope>/<env>/<workload>/<purpose>
  # scope = domain (diners), purpose = customer-profiles.
  kms_alias_profiles = "alias/dcp/${var.domain}/${var.environment}/${var.workload}/customer-profiles"

  # ---------------------------------------------------------------------------
  # ARN computado del dominio (DD-5)
  # ---------------------------------------------------------------------------
  # Se calcula de forma determinista desde el nombre del dominio para poder
  # enlazar aws:SourceArn en la política de la clave desde el primer apply, sin
  # requerir que el dominio ya exista. Partition, region y account vienen de los
  # data sources de contexto en main.tf (no de literales).
  #   arn:<partition>:profile:<region>:<account>:domains/<domain-name>
  profiles_domain_arn = format(
    "arn:%s:profile:%s:%s:domains/%s",
    data.aws_partition.current.partition,
    data.aws_region.current.name,
    data.aws_caller_identity.current.account_id,
    local.profiles_domain,
  )

  # ---------------------------------------------------------------------------
  # Base de los contratos SSM del workload
  # ---------------------------------------------------------------------------
  # iac-naming-tags L10: /dcp/<domain>/<env>/<workload>/config/<param>
  ssm_base = "/dcp/${var.domain}/${var.environment}/${var.workload}/config"

  # Nombres de los contratos SSM publicados por este módulo (componente domain
  # publica name/arn; componente kms publica la clave). Centralizados aquí para
  # que los componentes (tareas 3.1 y 3.3) y los outputs los reutilicen.
  ssm_profiles_kms_key_arn  = "${local.ssm_base}/customer-profiles-kms-key-arn"
  ssm_profiles_domain_name  = "${local.ssm_base}/customer-profiles-domain-name"
  ssm_profiles_domain_arn   = "${local.ssm_base}/customer-profiles-domain-arn"
  ssm_connect_instance_arn  = "${local.ssm_base}/connect-instance-arn"
  ssm_key_admin_role_arn    = "${local.ssm_base}/key-admin-role-arn"
  ssm_profiles_app_role_arn = "${local.ssm_base}/profiles-app-role-arn"

  # ---------------------------------------------------------------------------
  # Valores del tag Name (único tag que añade el módulo; el resto llega por
  # provider default_tags — iac-naming-tags L11).
  # ---------------------------------------------------------------------------
  name_kms_profiles    = "${local.prefix}-kms-customer-profiles"
  name_profiles_domain = local.profiles_domain
}
