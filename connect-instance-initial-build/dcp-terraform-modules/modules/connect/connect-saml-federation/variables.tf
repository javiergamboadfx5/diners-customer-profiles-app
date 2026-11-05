# -----------------------------------------------------------------------------
# connect/connect-saml-federation — variables (tarea 1.4)
#
# Este archivo declara solo las variables estructurales simples (naming común y
# tags). Las variables con reglas de negocio y validación cruzada
# (environment, instance_arn, metadata_admin/agent, max_session_duration,
# saml_resource_code, exception_id) viven en `validations.tf`. Los nombres
# físicos y las piezas deterministas de claims/relay state viven en `naming.tf`.
# Todos estos archivos son libres de proveedor para que las pruebas de propiedad
# (tarea 1.5) los ejerzan sin credenciales.
# -----------------------------------------------------------------------------

variable "domain" {
  type        = string
  description = "Dominio cloud canónico."
  default     = "diners"

  validation {
    condition     = var.domain == "diners"
    error_message = "El único dominio aprobado actualmente es diners."
  }
}

variable "workload" {
  type        = string
  description = "Capacidad funcional registrada en el catálogo (OQ-1)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.workload))
    error_message = "workload debe empezar con letra y tener entre 2 y 10 caracteres [a-z0-9]."
  }
}

variable "region_code" {
  type        = string
  description = "Código corto de la región."

  validation {
    condition     = contains(["use1", "use2", "usw2", "sae1"], var.region_code)
    error_message = "La región no pertenece al catálogo aprobado."
  }
}

variable "tags" {
  type        = map(string)
  description = "Solo tags complementarios del catálogo."
  default     = {}

  validation {
    condition = alltrue([
      for k in keys(var.tags) : contains(["Criticality", "BackupPolicy", "ExpiryDate", "ExceptionId", "Service"], k)
    ])
    error_message = "Solo se aceptan tags complementarios del catálogo."
  }
}
