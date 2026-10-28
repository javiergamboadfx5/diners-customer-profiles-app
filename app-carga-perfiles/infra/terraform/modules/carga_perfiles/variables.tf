variable "nombre" {
  description = "Prefijo de los recursos."
  type        = string
  default     = "diners-carga-perfiles"
  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.nombre))
    error_message = "Solo minusculas, numeros y guiones (3 a 32)."
  }
}

variable "ambiente" {
  description = "dev, qa o prod."
  type        = string
  validation {
    condition     = contains(["dev", "qa", "prod"], var.ambiente)
    error_message = "ambiente debe ser dev, qa o prod."
  }
}

# ---------- Identidad (Entra ID u otro proveedor OIDC) ----------

variable "crear_cognito_pruebas" {
  description = "true crea un user pool de Cognito como proveedor OIDC de pruebas (cuando aun no hay app registration en Entra ID). Las variables oidc_* se ignoran."
  type        = bool
  default     = false
}

variable "oidc_issuer" {
  description = "Issuer del token. Entra ID: https://login.microsoftonline.com/<tenant-id>/v2.0"
  type        = string
  default     = ""
}

variable "oidc_client_id" {
  description = "Client ID del app registration de la SPA (OIDC + PKCE)."
  type        = string
  default     = ""
}

variable "oidc_audiences" {
  description = "Audiencias aceptadas por el autorizador JWT (normalmente el client ID de la API)."
  type        = list(string)
  default     = []
}

variable "oidc_scope" {
  description = "Scopes que pide la SPA. Ej.: openid profile email api://<client-id>/Cargas.Write"
  type        = string
  default     = ""
}

variable "habilitar_customer_profiles" {
  description = "false omite el dominio y el object type (cuentas donde un SCP bloquea profile:*). La app valida, pero la escritura falla."
  type        = bool
  default     = true
}

variable "grupos_carga" {
  description = "IDs de grupo (claim groups) que pueden cargar. Vacio = cualquier usuario autenticado."
  type        = list(string)
  default     = []
}

variable "grupos_admin" {
  description = "IDs de grupo que pueden publicar el esquema. Vacio = mismos que grupos_carga."
  type        = list(string)
  default     = []
}

# ---------- Amazon Connect y Customer Profiles ----------

variable "connect_instance_alias" {
  description = "Alias de la instancia (para frame-ancestors). Ej.: diners-peru"
  type        = string
}

variable "perfiles_enrutamiento_permitidos" {
  description = "Perfiles de enrutamiento (nombre, ID o ARN) que ven la app dentro de Connect. Vacio = todos. Es un control de interfaz: la API sigue exigiendo el token OIDC."
  type        = list(string)
  default     = []
}

variable "connect_instance_arn" {
  description = "ARN de la instancia. Si se informa, se registra la app como integracion de Connect."
  type        = string
  default     = ""
}

variable "crear_dominio_perfiles" {
  description = "true crea el dominio de Customer Profiles; false usa uno existente (dominio_perfiles)."
  type        = bool
  default     = false
}

variable "dominio_perfiles" {
  description = "Nombre del dominio de Customer Profiles (existente o a crear)."
  type        = string
}

variable "plantilla_contactos" {
  description = "Plantilla de Connect para los registros de contacto: CTR, CTR-NoInferred o CTR-AutoAssociateOnly."
  type        = string
  default     = "CTR-AutoAssociateOnly"
  validation {
    condition     = contains(["CTR", "CTR-NoInferred", "CTR-AutoAssociateOnly"], var.plantilla_contactos)
    error_message = "Usa CTR, CTR-NoInferred o CTR-AutoAssociateOnly."
  }
}

variable "kms_dominio_perfiles_arn" {
  description = "ARN de la KMS con que esta cifrado un dominio existente (DefaultEncryptionKey). PutProfileObject la usa con las credenciales del escritor. Vacio si el dominio lo crea este modulo o no esta cifrado con CMK."
  type        = string
  default     = ""
}

variable "dias_expiracion_perfiles" {
  description = "DefaultExpirationDays del dominio y del object type."
  type        = number
  default     = 1000
}

variable "object_type_name" {
  description = "Nombre del object type de socios."
  type        = string
  default     = "DinersSocio"
}

# ---------- Operacion ----------

variable "concurrencia_escritura" {
  description = "Lambdas escritoras en paralelo (controla las TPS sobre PutProfileObject)."
  type        = number
  default     = 5
  validation {
    condition     = var.concurrencia_escritura >= 2 && var.concurrencia_escritura <= 50
    error_message = "Entre 2 y 50 (minimo de SQS maximum_concurrency)."
  }
}

variable "dias_retencion_archivos" {
  description = "Dias que se conservan los archivos subidos y sus reportes (contienen datos personales)."
  type        = number
  default     = 30
}

variable "dias_retencion_logs" {
  type    = number
  default = 90
}

variable "sns_alarmas_arn" {
  description = "Topico SNS para alarmas. Vacio = sin notificacion."
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
