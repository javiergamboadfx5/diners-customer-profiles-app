# -----------------------------------------------------------------------------
# connect/connect-saml-federation — locals auxiliares (tarea 1.4)
#
# Los locals de nombres físicos, claims y relay state viven ahora en `naming.tf`
# (libre de proveedor). Este archivo queda como punto de extensión para locals
# auxiliares de orquestación que no son nombres (p. ej. banderas derivadas que
# usará main.tf en la tarea 4.1). Hoy no define ninguno.
# -----------------------------------------------------------------------------

locals {
  # Indica si hay metadatos para ambos proveedores (lo usará main.tf en 4.1 para
  # condicionar la creación de los dos aws_iam_saml_provider).
  has_admin_metadata = var.metadata_admin != null && try(length(trimspace(var.metadata_admin)) > 0, false)
  has_agent_metadata = var.metadata_agent != null && try(length(trimspace(var.metadata_agent)) > 0, false)
}
