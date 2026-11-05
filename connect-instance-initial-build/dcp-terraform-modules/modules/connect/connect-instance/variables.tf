# -----------------------------------------------------------------------------
# connect/connect-instance — variables (tarea 1.2)
#
# Un solo módulo sirve a tres stacks (kms, storage, instance) mediante el switch
# `component`. Este archivo declara las variables estructurales y los flags sin
# reglas de negocio cruzadas. Las validaciones detalladas (alias, tipo de
# identidad, excepciones, retención, aprobación del data store) viven en
# `validations.tf`, y los nombres físicos en `naming.tf`. Ambos archivos son
# libres de proveedor para que las pruebas de propiedad (tarea 1.5) los ejerzan
# sin credenciales.
# -----------------------------------------------------------------------------

variable "component" {
  type        = string
  description = "Componente que activa el stack: kms, storage o instance."

  validation {
    condition     = contains(["kms", "storage", "instance"], var.component)
    error_message = "component debe ser uno de: kms, storage, instance."
  }
}

# -----------------------------------------------------------------------------
# Naming (comunes desde el root)
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
    error_message = "workload debe empezar con letra y tener entre 2 y 10 caracteres [a-z0-9] (límite de longitud del bucket, Req 5.1)."
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

# -----------------------------------------------------------------------------
# Contexto de cuenta y organización (entradas, no proveedor)
#
# El sufijo único del bucket (Req 5.1) es determinista:
#   substr(sha256("<org-id>:<account-id>:connect-storage"), 0, 12)
# Para que `naming.tf` sea libre de proveedor y las pruebas de propiedad puedan
# calcular el nombre sin credenciales, `org_id` y `account_id` entran como
# variables. El stack las resuelve desde el catálogo / data sources del root.
# -----------------------------------------------------------------------------

variable "org_id" {
  type        = string
  description = "Identificador de la organización AWS (o-xxxxxxxxxx). Entra determinista del root/catálogo."

  validation {
    condition     = can(regex("^o-[a-z0-9]{10,32}$", var.org_id))
    error_message = "org_id debe tener el formato o-xxxxxxxxxx."
  }
}

variable "account_id" {
  type        = string
  description = "Identificador de 12 dígitos de la cuenta contactcenter-dev. Entra del root/catálogo."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id debe tener 12 dígitos."
  }
}

# -----------------------------------------------------------------------------
# Flags de la instancia (Req 6.1) y prefijos de almacenamiento
# -----------------------------------------------------------------------------

variable "inbound_calls_enabled" {
  type        = bool
  description = "Llamadas entrantes habilitadas."
  default     = true
}

variable "outbound_calls_enabled" {
  type        = bool
  description = "Llamadas salientes habilitadas."
  default     = true
}

variable "contact_flow_logs_enabled" {
  type        = bool
  description = "Logs de flujos de contacto habilitados."
  default     = true
}

variable "contact_lens_enabled" {
  type        = bool
  description = "Contact Lens habilitado."
  default     = true
}

variable "bucket_prefix_recordings" {
  type        = string
  description = "Prefijo S3 de grabaciones, sin barra inicial."
  default     = "connect/call-recordings"

  validation {
    condition     = length(var.bucket_prefix_recordings) > 0 && !startswith(var.bucket_prefix_recordings, "/")
    error_message = "bucket_prefix_recordings no puede estar vacío ni empezar con '/'."
  }
}

variable "bucket_prefix_transcripts" {
  type        = string
  description = "Prefijo S3 de transcripciones, sin barra inicial."
  default     = "connect/chat-transcripts"

  validation {
    condition     = length(var.bucket_prefix_transcripts) > 0 && !startswith(var.bucket_prefix_transcripts, "/")
    error_message = "bucket_prefix_transcripts no puede estar vacío ni empezar con '/'."
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
