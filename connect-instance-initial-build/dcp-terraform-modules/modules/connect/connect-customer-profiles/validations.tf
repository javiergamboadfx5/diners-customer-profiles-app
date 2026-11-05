# -----------------------------------------------------------------------------
# connect/connect-customer-profiles — validations (tarea 1.3)
#
# Reglas de validación de entradas, libres de proveedor. Fallan en tiempo de
# plan y el mensaje nombra la regla violada, de modo que ningún recurso se
# planifique con un valor inválido o irreversible (Req 3).
#
# Las variables estructurales/comunes (component, domain, workload, region_code,
# matching_enabled, bind_domain_arn, cde_scope, tags) viven en variables.tf.
# La construcción de nombres vive en naming.tf.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# environment — allowlist dev|qa|stg|prod (Req 3.4)
# -----------------------------------------------------------------------------
# El módulo es genérico y acepta los cuatro ambientes para que las fases qa/stg/
# prod lo reutilicen sin cambios (promoción, Req 13). El mensaje enumera los
# valores permitidos.
variable "environment" {
  type        = string
  description = "Ambiente de despliegue. Uno de: dev, qa, stg, prod."

  validation {
    condition     = contains(["dev", "qa", "stg", "prod"], var.environment)
    error_message = "environment debe ser uno de los ambientes permitidos: dev, qa, stg, prod."
  }
}

# -----------------------------------------------------------------------------
# domain_name — reglas de Customer Profiles (Req 3.7, 8.1)
# -----------------------------------------------------------------------------
# AWS exige el prefijo amazon-connect-; longitud <= 64; solo [A-Za-z0-9_-].
# Si es null, naming.tf lo computa de forma determinista y ese valor también
# satisface estas reglas (Property 4). Se validan las tres reglas por separado
# para que el mensaje nombre la regla violada.
variable "domain_name" {
  type        = string
  description = "Nombre del dominio de Customer Profiles. Prefijo obligatorio amazon-connect- (constraint de AWS). Si es null se computa desde domain/environment/workload."
  default     = null

  validation {
    condition     = var.domain_name == null ? true : startswith(var.domain_name, "amazon-connect-")
    error_message = "domain_name debe comenzar con el prefijo amazon-connect- exigido por AWS (AmazonConnectServiceLinkedRolePolicy)."
  }

  validation {
    condition     = var.domain_name == null ? true : length(var.domain_name) <= 64
    error_message = "domain_name debe tener como máximo 64 caracteres (límite de Customer Profiles)."
  }

  validation {
    condition     = var.domain_name == null ? true : can(regex("^[A-Za-z0-9_-]+$", var.domain_name))
    error_message = "domain_name solo puede contener letras, dígitos, guion bajo (_) y guion (-)."
  }
}

# -----------------------------------------------------------------------------
# default_expiration_days — cota numérica 1..1098 (Req 3.8)
# -----------------------------------------------------------------------------
# OQ-10: valor aprobado por Cumplimiento. Debe ser un entero entre 1 y 1098
# (máximo de Customer Profiles). Sin default: el plan falla si no se provee.
variable "default_expiration_days" {
  type        = number
  description = "Días de expiración por defecto de los perfiles (OQ-10). Entero entre 1 y 1098."
  default     = null

  validation {
    condition = var.default_expiration_days == null ? true : (
      floor(var.default_expiration_days) == var.default_expiration_days &&
      var.default_expiration_days >= 1 &&
      var.default_expiration_days <= 1098
    )
    error_message = "default_expiration_days debe ser un entero entre 1 y 1098."
  }
}

# -----------------------------------------------------------------------------
# enable_data_store / data_store_approval_ref — regla de aprobación (Req 8.3, 8.4)
# -----------------------------------------------------------------------------
# El data store queda desactivado por defecto (retención de 10 años, LPDP).
# Solo puede habilitarse si se provee una referencia de aprobación de
# Cumplimiento no vacía. La validación cruzada vive en enable_data_store para
# poder referenciar ambas variables en una sola condición.
variable "enable_data_store" {
  type        = bool
  description = "Habilita el data store de Customer Profiles. Por defecto desactivado (retención de 10 años, LPDP)."
  default     = false

  validation {
    condition     = var.enable_data_store == false || trimspace(var.data_store_approval_ref) != ""
    error_message = "enable_data_store = true requiere data_store_approval_ref no vacío (referencia de aprobación de Cumplimiento, Req 8.4)."
  }
}

variable "data_store_approval_ref" {
  type        = string
  description = "Referencia de aprobación de Cumplimiento, obligatoria cuando enable_data_store = true (Req 8.4)."
  default     = ""
}

# -----------------------------------------------------------------------------
# exception_id — identificador de excepción cuando se requiere (Req 3.5, 3.6,
# 11.4, iac-core-rules §9)
# -----------------------------------------------------------------------------
# Formato obligatorio exc-cloud-NNNN-NNNN cuando se declara una excepción.
# En el Profiles_Module la excepción se usa, por ejemplo, para el prefijo
# amazon-connect- si Arquitectura exige registro (OQ-14). Cuando require_exception
# es true, exception_id debe cumplir el patrón; cuando es false, puede quedar
# vacío. require_exception se deja como entrada explícita para no inventar la
# condición de negocio en el módulo genérico.
variable "require_exception" {
  type        = bool
  description = "Indica que el stack declara una excepción exc-cloud-* (p. ej. OQ-14 para el prefijo amazon-connect-). Fuerza la validación de exception_id."
  default     = false
}

variable "exception_id" {
  type        = string
  description = "Identificador de excepción exc-cloud-NNNN-NNNN. Obligatorio cuando require_exception = true (iac-core-rules §9)."
  default     = ""

  validation {
    condition     = var.exception_id == "" || can(regex("^exc-cloud-[0-9]{4}-[0-9]{4}$", var.exception_id))
    error_message = "exception_id debe coincidir con el patrón ^exc-cloud-[0-9]{4}-[0-9]{4}$ (p. ej. exc-cloud-2026-0001)."
  }

  validation {
    condition     = var.require_exception == false || can(regex("^exc-cloud-[0-9]{4}-[0-9]{4}$", var.exception_id))
    error_message = "require_exception = true exige un exception_id con el patrón ^exc-cloud-[0-9]{4}-[0-9]{4}$."
  }
}
