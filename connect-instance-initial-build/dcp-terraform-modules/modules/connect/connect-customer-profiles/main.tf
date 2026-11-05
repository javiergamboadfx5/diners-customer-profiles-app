# -----------------------------------------------------------------------------
# connect/connect-customer-profiles — main (andamiaje, tarea 1.1)
#
# Las implementaciones por componente llegan en tareas posteriores:
#   - component = "kms"    -> kms.tf     (tarea 3.1)
#   - component = "domain" -> domain.tf  (tarea 3.3, requiere awscc, [Blocked: OQ-12])
#
# Este archivo deja los data sources de contexto.
# -----------------------------------------------------------------------------

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}
