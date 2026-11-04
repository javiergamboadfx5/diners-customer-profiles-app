variable "region" {
  type    = string
  default = "us-east-1"
}

variable "ambiente" {
  description = "dev, qa o prod."
  type        = string
}

variable "nombre" {
  description = "Prefijo de los recursos."
  type        = string
  default     = "diners-carga-perfiles"
}

variable "tags" {
  type    = map(string)
  default = {}
}

# ---------- Entradas del stack de Connect (ver docs/CONTRATO-STACK-CONNECT.md) ----------

variable "connect_instance_arn" {
  description = "ARN de la instancia. Vacio = no se registra la app en Connect (solo CloudFront)."
  type        = string
  default     = ""
}

variable "connect_instance_alias" {
  description = "Alias de la instancia, para frame-ancestors (https://<alias>.my.connect.aws)."
  type        = string
}

variable "dominio_perfiles" {
  description = "Nombre del dominio de Customer Profiles creado por el stack de Connect."
  type        = string
}

variable "kms_dominio_perfiles_arn" {
  description = "DefaultEncryptionKey del dominio. Vacio si el dominio no usa CMK."
  type        = string
  default     = ""
}

# ---------- Identidad ----------

variable "crear_cognito_pruebas" {
  description = "true crea un user pool de Cognito de pruebas y se ignoran oidc_* y grupos_*. Solo dev."
  type        = bool
  default     = false
}

variable "oidc_issuer" {
  type    = string
  default = ""
}

variable "oidc_client_id" {
  type    = string
  default = ""
}

variable "oidc_audiences" {
  type    = list(string)
  default = []
}

variable "oidc_scope" {
  type    = string
  default = ""
}

variable "grupos_carga" {
  type    = list(string)
  default = []
}

variable "grupos_admin" {
  type    = list(string)
  default = []
}

variable "perfiles_enrutamiento_permitidos" {
  type    = list(string)
  default = []
}

# ---------- Operacion ----------

variable "object_type_name" {
  type    = string
  default = "DinersSocio"
}

variable "dias_expiracion_perfiles" {
  type    = number
  default = 1000
}

variable "concurrencia_escritura" {
  type    = number
  default = 5
}

variable "dias_retencion_archivos" {
  type    = number
  default = 30
}

variable "dias_retencion_logs" {
  type    = number
  default = 90
}

variable "sns_alarmas_arn" {
  type    = string
  default = ""
}
