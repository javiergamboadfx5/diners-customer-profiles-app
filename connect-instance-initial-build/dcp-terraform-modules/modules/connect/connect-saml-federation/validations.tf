# -----------------------------------------------------------------------------
# connect/connect-saml-federation — validaciones (tarea 1.4)
#
# Reglas de entrada del módulo, libres de proveedor. Fallan en tiempo de plan
# antes de planear cualquier recurso (Req 3). Las validaciones que cruzan varias
# variables se declaran en la variable "ancla" correspondiente, apoyándose en el
# soporte de validaciones con referencias cruzadas de Terraform >= 1.15.8.
#
# Cobertura:
#   - environment: lista blanca dev|qa|stg|prod            (Req 3.4)
#   - instance_arn: formato ARN de instancia Connect        (Req 10.4, diseño)
#   - metadata_admin / metadata_agent: no vacíos y con
#     EntityDescriptor                                       (Req 10.4, diseño)
#   - max_session_duration: valor único 3600                 (Req 10.3)
#   - saml_resource_code: obligatorio (no inventar, OQ-3)    (Req 10.1)
#   - exception_id: formato exc-cloud-NNNN-NNNN cuando aplica (Req 11.4)
#
# Las variables estructurales simples (domain, workload, region_code, tags)
# viven en `variables.tf`; los nombres físicos en `naming.tf`.
# -----------------------------------------------------------------------------

# --- Ambiente ----------------------------------------------------------------
variable "environment" {
  type        = string
  description = "Ambiente de despliegue."

  # Req 3.4 — lista blanca; el mensaje nombra los valores permitidos.
  validation {
    condition     = contains(["dev", "qa", "stg", "prod"], var.environment)
    error_message = "environment debe ser uno de: dev, qa, stg, prod."
  }
}

# --- ARN de la instancia Connect (contrato SSM connect-instance-arn) --------
# Formato: arn:aws:connect:<region>:<account>:instance/<uuid>
# Se valida solo cuando viene informado, porque el stack lo resuelve desde el
# contrato SSM en tiempo de plan (fail-closed en main.tf vía data source).
variable "instance_arn" {
  type        = string
  description = "ARN de la instancia Connect, leído del contrato SSM connect-instance-arn."
  default     = null

  # Req 10.4 / diseño — formato ARN de instancia Connect.
  validation {
    condition = var.instance_arn == null || can(regex(
      "^arn:aws[a-z-]*:connect:[a-z0-9-]+:[0-9]{12}:instance/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
      var.instance_arn
    ))
    error_message = "instance_arn debe tener el formato arn:aws:connect:<region>:<account>:instance/<uuid> (Req 10.4)."
  }
}

# --- Metadatos SAML de Entra ID (contratos SSM, OQ-9) -----------------------
variable "metadata_admin" {
  type        = string
  description = "Metadatos SAML de la app admin de Entra ID (contrato SSM saml-metadata-admin, OQ-9)."
  default     = null

  # Req 10.4 / diseño — no vacío y con EntityDescriptor cuando viene informado.
  validation {
    condition     = var.metadata_admin == null || (try(length(trimspace(var.metadata_admin)) > 0, false) && can(regex("EntityDescriptor", var.metadata_admin)))
    error_message = "metadata_admin no puede estar vacío y debe contener EntityDescriptor (metadatos SAML de Entra ID, Req 10.4)."
  }
}

variable "metadata_agent" {
  type        = string
  description = "Metadatos SAML de la app agente de Entra ID (contrato SSM saml-metadata-agent, OQ-9)."
  default     = null

  # Req 10.4 / diseño — no vacío y con EntityDescriptor cuando viene informado.
  validation {
    condition     = var.metadata_agent == null || (try(length(trimspace(var.metadata_agent)) > 0, false) && can(regex("EntityDescriptor", var.metadata_agent)))
    error_message = "metadata_agent no puede estar vacío y debe contener EntityDescriptor (metadatos SAML de Entra ID, Req 10.4)."
  }
}

# --- Duración máxima de sesión del rol de federación ------------------------
# Req 10.3 / iac-security-pci — el rol de federación nunca excede 3600 s.
#
# AWS IAM impone que max_session_duration de un rol esté entre 3600 y 43200 s
# (el proveedor rechaza cualquier valor < 3600 en plan/apply). El techo PCI de
# Req 10.3 es <= 3600. La única intersección entre ambos límites es exactamente
# 3600 s, así que el módulo fija ese valor único: cumple el techo PCI al piso
# que admite IAM y evita configuraciones que validan en local pero fallan al
# aplicar. La duración efectiva de la sesión del agente (incl. la sesión CDE de
# 12 h) se controla en el IdP (Entra ID SessionDuration), no en este rol.
variable "max_session_duration" {
  type        = number
  description = "Duración máxima de sesión del rol de federación, en segundos. Fijado en 3600 (único valor que cumple el techo PCI de Req 10.3 y el piso de 3600 s que exige AWS IAM para roles)."
  default     = 3600

  # Req 10.3 — valor único 3600: techo PCI y piso de IAM a la vez.
  validation {
    condition     = var.max_session_duration == 3600
    error_message = "max_session_duration debe ser exactamente 3600: es el techo PCI (Req 10.3, iac-security-pci) y a la vez el mínimo que AWS IAM admite para la duración de sesión de un rol (3600-43200 s)."
  }
}

# --- Código de recurso del proveedor IAM SAML (OQ-3) ------------------------
# No se inventa el código del catálogo: el módulo falla si no se define
# (propuesto "saml", pendiente de registro en catalogos-cloud.yaml).
variable "saml_resource_code" {
  type        = string
  description = "Código de recurso del proveedor IAM SAML (propuesto 'saml'). [Blocked: OQ-3]"
  default     = null

  # Req 10.1 — obligatorio y en kebab-case cuando se informa.
  validation {
    condition     = var.saml_resource_code != null && try(length(var.saml_resource_code) > 0, false)
    error_message = "saml_resource_code es obligatorio; no se inventa el código del catálogo (OQ-3, propuesto 'saml')."
  }

  validation {
    condition     = var.saml_resource_code == null || can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.saml_resource_code))
    error_message = "saml_resource_code debe ser kebab-case en minúscula ([a-z0-9-], sin guion inicial ni final)."
  }
}

# --- Identificador de excepción exc-cloud-NNNN-NNNN -------------------------
# El rol de federación puede llevar el tag ExceptionId cuando se registre una
# excepción (p. ej. la sesión CDE de 12 h de Connect, Req 10.10). Se valida el
# formato cuando viene informado (Req 11.4).
variable "exception_id" {
  type        = string
  description = "Identificador de excepción exc-cloud-NNNN-NNNN cuando el recurso usa una excepción (Req 11.4)."
  default     = ""

  # Req 11.4 — formato cuando viene informado.
  validation {
    condition     = var.exception_id == "" || can(regex("^exc-cloud-[0-9]{4}-[0-9]{4}$", var.exception_id))
    error_message = "exception_id debe coincidir con ^exc-cloud-[0-9]{4}-[0-9]{4}$ cuando se informa (Req 11.4)."
  }
}
