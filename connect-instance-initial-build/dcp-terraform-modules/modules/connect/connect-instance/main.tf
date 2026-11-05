# -----------------------------------------------------------------------------
# connect/connect-instance — main (andamiaje, tarea 1.1)
#
# Las implementaciones por componente llegan en tareas posteriores:
#   - component = "kms"      -> kms.tf       (tarea 2.1)
#   - component = "storage"  -> storage.tf   (tarea 2.3)
#   - component = "instance" -> instance.tf  (tarea 2.5)
#
# Este archivo solo deja los data sources de contexto que comparten los
# componentes. No crea recursos todavía.
# -----------------------------------------------------------------------------

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}
