# -----------------------------------------------------------------------------
# connect/connect-instance — locals auxiliares (tarea 1.2)
#
# Los locals de nombres físicos viven ahora en `naming.tf` (libre de proveedor).
# Este archivo queda para locals auxiliares de orquestación entre componentes
# que no son nombres (p. ej. banderas derivadas). Hoy no define ninguno; se
# mantiene como punto de extensión para las tareas 2.1, 2.3 y 2.5.
# -----------------------------------------------------------------------------

locals {
  # Banderas de activación por componente (las usan kms.tf / storage.tf /
  # instance.tf en tareas posteriores para condicionar count/for_each).
  is_kms      = var.component == "kms"
  is_storage  = var.component == "storage"
  is_instance = var.component == "instance"
}
