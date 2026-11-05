# -----------------------------------------------------------------------------
# connect/connect-customer-profiles — variables estructurales
#
# Sirve a dos stacks (kms-customer-profiles, customer-profiles) mediante el
# switch `component`.
#
# Las variables con reglas de negocio y sus validaciones viven en validations.tf
# (environment, domain_name, default_expiration_days, enable_data_store,
# data_store_approval_ref, exception_id, require_exception). La construcción de
# nombres vive en naming.tf.
# -----------------------------------------------------------------------------

variable "component" {
  type        = string
  description = "Componente que activa el stack: kms o domain."

  validation {
    condition     = contains(["kms", "domain"], var.component)
    error_message = "component debe ser uno de: kms, domain."
  }
}

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

variable "matching_enabled" {
  type        = bool
  description = "Matching de perfiles. Fijado en false por el diseño de la app."
  default     = false

  validation {
    condition     = var.matching_enabled == false
    error_message = "matching_enabled debe permanecer en false por el diseño de la app (Req 8.1)."
  }
}

variable "bind_domain_arn" {
  type        = bool
  description = "Enlaza aws:SourceArn del dominio en la política de la clave desde el primer apply (DD-5)."
  default     = true
}

variable "cde_scope" {
  type        = bool
  description = "Indica si la cuenta está en alcance CDE (OQ-6). Determina el chequeo del tag Compliance."
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
