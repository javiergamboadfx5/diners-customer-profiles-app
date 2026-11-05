# -----------------------------------------------------------------------------
# connect/connect-instance — validaciones (tarea 1.2)
#
# Reglas de entrada del módulo, libres de proveedor. Fallan en tiempo de plan
# antes de planear cualquier recurso (Req 3). Las validaciones que cruzan varias
# variables se declaran en la variable "ancla" correspondiente, apoyándose en el
# soporte de validaciones con referencias cruzadas de Terraform >= 1.15.8.
#
# Cobertura:
#   - environment: lista blanca dev|qa|stg|prod           (Req 3.4)
#   - instance_alias: regex de alias                       (Req 3.1)
#   - identity_management_type: lista de valores           (Req 3.2)
#   - directory_id obligatorio en EXISTING_DIRECTORY       (Req 3.3)
#   - exception_id: matriz de excepción exc-cloud-NNNN-NNNN (Req 3.5, 3.6, 11.4)
#   - retención de almacenamiento >= 1                     (Req 5.5, 6.5)
#   - flow_log_retention_days: valores CloudWatch, nunca 0 (Req 6.5)
#   - security_coverage_ref obligatorio con cde_scope       (DD-2, Req 5.6)
# -----------------------------------------------------------------------------

# --- Ambiente ----------------------------------------------------------------
variable "environment" {
  type        = string
  description = "Ambiente de despliegue."

  validation {
    condition     = contains(["dev", "qa", "stg", "prod"], var.environment)
    error_message = "environment debe ser uno de: dev, qa, stg, prod."
  }
}

# --- Identidad de la instancia ----------------------------------------------
variable "instance_alias" {
  type        = string
  description = "Alias de la instancia Connect (OQ-8). Debe cumplir ^[a-z0-9]([a-z0-9-]{0,60}[a-z0-9])?$ (1 a 62 caracteres)."
  default     = null

  # Req 3.1 — solo aplica cuando se provee alias (componente instance).
  validation {
    condition     = var.instance_alias == null || can(regex("^[a-z0-9]([a-z0-9-]{0,60}[a-z0-9])?$", var.instance_alias))
    error_message = "instance_alias debe cumplir la regla de alias ^[a-z0-9]([a-z0-9-]{0,60}[a-z0-9])?$ (1 a 62 caracteres en minúscula, dígitos y guiones, sin guion inicial ni final)."
  }
}

variable "identity_management_type" {
  type        = string
  description = "Tipo de gestión de identidad: SAML, CONNECT_MANAGED o EXISTING_DIRECTORY."
  default     = "SAML"

  # Req 3.2 — lista de valores permitidos.
  validation {
    condition     = contains(["SAML", "CONNECT_MANAGED", "EXISTING_DIRECTORY"], var.identity_management_type)
    error_message = "identity_management_type debe ser uno de: SAML, CONNECT_MANAGED, EXISTING_DIRECTORY."
  }
}

variable "directory_id" {
  type        = string
  description = "Directorio existente; obligatorio cuando identity_management_type = EXISTING_DIRECTORY."
  default     = null

  # Req 3.3 — directory_id obligatorio para EXISTING_DIRECTORY.
  validation {
    condition     = var.identity_management_type != "EXISTING_DIRECTORY" || (var.directory_id != null && try(length(var.directory_id) > 0, false))
    error_message = "directory_id es obligatorio cuando identity_management_type = EXISTING_DIRECTORY."
  }
}

variable "exception_id" {
  type        = string
  description = "Identificador de excepción exc-cloud-NNNN-NNNN cuando el tipo de identidad lo exige (Req 3.5, 3.6)."
  default     = ""

  # Formato cuando viene informado (Req 11.4).
  validation {
    condition     = var.exception_id == "" || can(regex("^exc-cloud-[0-9]{4}-[0-9]{4}$", var.exception_id))
    error_message = "exception_id debe coincidir con ^exc-cloud-[0-9]{4}-[0-9]{4}$ cuando se informa."
  }

  # Req 3.5 — qa|stg|prod no-SAML exige una excepción válida.
  validation {
    condition     = !(contains(["qa", "stg", "prod"], var.environment) && var.identity_management_type != "SAML") || can(regex("^exc-cloud-[0-9]{4}-[0-9]{4}$", var.exception_id))
    error_message = "En qa, stg o prod con identity_management_type distinto de SAML se requiere un exception_id válido (^exc-cloud-[0-9]{4}-[0-9]{4}$) (Req 3.5)."
  }

  # Req 3.6 — dev con CONNECT_MANAGED exige una excepción válida.
  validation {
    condition     = !(var.environment == "dev" && var.identity_management_type == "CONNECT_MANAGED") || can(regex("^exc-cloud-[0-9]{4}-[0-9]{4}$", var.exception_id))
    error_message = "En dev con identity_management_type = CONNECT_MANAGED se requiere un exception_id válido (^exc-cloud-[0-9]{4}-[0-9]{4}$) (Req 3.6)."
  }
}

# --- Alcance CDE y cobertura de seguridad (OQ-6, DD-2) ----------------------
variable "cde_scope" {
  type        = bool
  description = "Indica si la cuenta está en alcance CDE (OQ-6). Sin default: la decisión de Ciberseguridad bloquea el plan hasta resolverse."
}

variable "security_coverage_ref" {
  type        = string
  description = "Referencia a la cobertura de CloudTrail data events y Macie publicada por dcp-aws-security-live (DD-2). Obligatoria cuando cde_scope = true."
  default     = ""

  # Req 5.6 / DD-2 — con cde_scope = true la referencia de cobertura es obligatoria.
  validation {
    condition     = !var.cde_scope || try(length(trimspace(var.security_coverage_ref)) > 0, false)
    error_message = "security_coverage_ref es obligatoria y no vacía cuando cde_scope = true (DD-2)."
  }
}

# --- Retención de almacenamiento (OQ-7) -------------------------------------
variable "recordings_retention_days" {
  type        = number
  description = "Retención de grabaciones de llamada (OQ-7). Entero >= 1."
  default     = null

  # Req 5.5 — si se informa, debe ser entero >= 1.
  validation {
    condition     = var.recordings_retention_days == null || (floor(var.recordings_retention_days) == var.recordings_retention_days && var.recordings_retention_days >= 1)
    error_message = "recordings_retention_days debe ser un entero >= 1 (Req 5.5)."
  }
}

variable "transcripts_retention_days" {
  type        = number
  description = "Retención de transcripciones de chat (OQ-7). Entero >= 1."
  default     = null

  validation {
    condition     = var.transcripts_retention_days == null || (floor(var.transcripts_retention_days) == var.transcripts_retention_days && var.transcripts_retention_days >= 1)
    error_message = "transcripts_retention_days debe ser un entero >= 1 (Req 5.5)."
  }
}

variable "noncurrent_retention_days" {
  type        = number
  description = "Retención de versiones no actuales en el bucket (OQ-7). Entero >= 1."
  default     = null

  validation {
    condition     = var.noncurrent_retention_days == null || (floor(var.noncurrent_retention_days) == var.noncurrent_retention_days && var.noncurrent_retention_days >= 1)
    error_message = "noncurrent_retention_days debe ser un entero >= 1 (Req 5.5)."
  }
}

# --- Retención del log group de flujos de contacto (Req 6.5) ----------------
variable "flow_log_retention_days" {
  type        = number
  description = "Retención del log group de flujos de contacto. Valor permitido por CloudWatch, nunca 0 (Req 6.5)."
  default     = null

  validation {
    condition = var.flow_log_retention_days == null || contains(
      [1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653],
      var.flow_log_retention_days
    )
    error_message = "flow_log_retention_days debe ser uno de los valores de retención permitidos por CloudWatch Logs y nunca 0 (nunca 'never expire') (Req 6.5)."
  }
}

# -----------------------------------------------------------------------------
# Comprobaciones de nombres físicos (libres de proveedor).
#
# El límite de 63 caracteres del bucket ya está garantizado por la validación de
# longitud de `workload` (<= 10). Este `check` lo verifica de forma explícita y
# determinista sobre el nombre calculado en `naming.tf`, para que cualquier
# cambio futuro en la plantilla de nombre falle de inmediato (Req 2.6, 5.1).
# -----------------------------------------------------------------------------

check "physical_name_limits" {
  assert {
    condition     = local.bucket_name_ok
    error_message = "El nombre del bucket '${local.bucket_name}' supera 63 caracteres; revise el límite de longitud de workload (Req 5.1)."
  }

  assert {
    condition     = local.kms_alias_ok
    error_message = "El alias KMS '${local.kms_alias_storage}' supera el límite permitido."
  }
}
