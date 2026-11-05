# -----------------------------------------------------------------------------
# connect/connect-customer-profiles — locals
#
# La lógica de construcción de nombres y contratos (prefix, profiles_domain,
# kms_alias_profiles, profiles_domain_arn, ssm_base y los contratos SSM) se
# movió a naming.tf en la tarea 1.3, para mantener la lógica pura libre de
# proveedor en un único archivo exportable a las pruebas de propiedades.
#
# Los locals derivados por componente (kms, domain) se añaden junto a cada
# componente. Las banderas de activación viven aquí para condicionar count.
# -----------------------------------------------------------------------------

locals {
  # Banderas de activación por componente. Las usan kms.tf (tarea 3.1) y
  # domain.tf (tarea 3.3) para condicionar count/for_each.
  is_kms    = var.component == "kms"
  is_domain = var.component == "domain"
}
