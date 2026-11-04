# Datos del repo de dominio. Un solo dominio cloud: diners (L07).
locals {
  domain     = "diners"
  scope      = "diners"
  repository = "dcp-aws-diners-live"

  # Centro de costo para stacks de platform/ (sin app.hcl). Valor de ejemplo.
  platform_cost_center = "400100"
}
