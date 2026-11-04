# -----------------------------------------------------------------------------
# Naming (L07 a L10). El módulo arma los nombres; el stack solo entrega piezas.
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

variable "environment" {
  type        = string
  description = "Ambiente de despliegue."

  validation {
    condition     = contains(["dev", "qa", "stg", "prod"], var.environment)
    error_message = "El ambiente no pertenece al catálogo aprobado (dev, qa, stg, prod)."
  }
}

variable "workload" {
  type        = string
  description = "Capacidad funcional registrada en catalogos-cloud.yaml (payments, merchants, ...)."

  validation {
    condition = (
      can(regex("^[a-z][a-z0-9-]{1,20}$", var.workload)) &&
      !contains(["shared", "unknown", "n-a", "na", "temp", "test"], var.workload)
    )
    error_message = "workload debe ser kebab-case, existir en el catálogo y no puede ser shared, unknown, n-a, temp ni test."
  }
}

variable "purpose" {
  type        = string
  description = "Uso específico de la instancia; forma parte del nombre (ej. portal, batch)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.purpose))
    error_message = "purpose debe ser kebab-case de 2 a 21 caracteres."
  }
}

variable "region_code" {
  type        = string
  description = "Código corto corporativo de la región."

  validation {
    condition     = contains(["use1", "use2", "usw2", "sae1"], var.region_code)
    error_message = "La región no pertenece al catálogo aprobado."
  }
}

variable "ordinal" {
  type        = string
  description = "Secuencia cuando existe más de una instancia con el mismo propósito."
  default     = "01"

  validation {
    condition     = can(regex("^[0-9]{2}$", var.ordinal))
    error_message = "ordinal debe tener dos dígitos (01, 02, ...)."
  }
}

# -----------------------------------------------------------------------------
# Red: contratos publicados por Networking en el Parameter Store de la cuenta.
# El módulo nunca recibe IDs literales de VPC o subredes.
# -----------------------------------------------------------------------------

variable "vpc_id_parameter" {
  type        = string
  description = "Parámetro SSM con el ID de la VPC compartida."
  default     = "/dcp/networking/vpc/id"
}

variable "subnet_ids_parameter" {
  type        = string
  description = "Parámetro SSM (StringList) con las subredes app-private compartidas por RAM."
  default     = "/dcp/networking/subnets/app-private/ids"
}

variable "subnet_index" {
  type        = number
  description = "Posición de la subred (AZ) dentro de la lista del parámetro."
  default     = 0

  validation {
    condition     = var.subnet_index >= 0 && floor(var.subnet_index) == var.subnet_index
    error_message = "subnet_index debe ser un entero mayor o igual a 0."
  }
}

# -----------------------------------------------------------------------------
# Instancia
# -----------------------------------------------------------------------------

variable "ami_id_parameter" {
  type        = string
  description = "Parámetro SSM con la AMI endurecida publicada por Platform. Nunca un ID literal."

  validation {
    condition     = startswith(var.ami_id_parameter, "/dcp/platform/ami/")
    error_message = "La AMI debe venir de un parámetro publicado por Platform bajo /dcp/platform/ami/."
  }
}

variable "instance_type" {
  type        = string
  description = "Tipo de instancia."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type no tiene un formato válido (ej. t3.small)."
  }
}

variable "root_volume_size_gb" {
  type        = number
  description = "Tamaño del volumen raíz gp3 en GiB."
  default     = 30

  validation {
    condition     = var.root_volume_size_gb >= 8 && var.root_volume_size_gb <= 1024
    error_message = "root_volume_size_gb debe estar entre 8 y 1024."
  }
}

variable "ebs_kms_key_arn" {
  type        = string
  description = "ARN de la CMK para el volumen raíz. Obligatoria si DataClassification es restricted o pci."
  default     = null
}

variable "detailed_monitoring" {
  type        = bool
  description = "Habilita métricas de CloudWatch cada minuto."
  default     = true
}

variable "user_data" {
  type        = string
  description = "Script de arranque. Nunca contiene secretos: la instancia los lee de Secrets Manager con su rol."
  default     = null

  validation {
    condition     = var.user_data == null || !can(regex("(?i)(password|secret|token|apikey)\\s*=", var.user_data))
    error_message = "user_data parece contener un secreto. Léalo en tiempo de ejecución desde Secrets Manager."
  }
}

# -----------------------------------------------------------------------------
# Reglas del Security Group. Los orígenes y destinos salen de parámetros SSM o
# de otros SG; nunca 0.0.0.0/0.
# -----------------------------------------------------------------------------

variable "ingress_rules" {
  type = list(object({
    description              = string
    port                     = number
    protocol                 = optional(string, "tcp")
    source_cidr_parameter    = optional(string)
    source_security_group_id = optional(string)
  }))
  description = "Reglas de entrada. Cada regla tiene exactamente un origen."
  default     = []

  validation {
    condition = alltrue([
      for r in var.ingress_rules :
      (r.source_cidr_parameter == null) != (r.source_security_group_id == null)
    ])
    error_message = "Cada regla de entrada debe tener exactamente un origen: source_cidr_parameter o source_security_group_id."
  }

  validation {
    condition     = length(var.ingress_rules) == length(distinct([for r in var.ingress_rules : r.description]))
    error_message = "description debe ser única por regla: se usa como clave estable del estado."
  }
}

variable "egress_rules" {
  type = list(object({
    description                   = string
    port                          = number
    protocol                      = optional(string, "tcp")
    destination_cidr_parameter    = optional(string)
    destination_security_group_id = optional(string)
  }))
  description = "Reglas de salida. Sin reglas, la instancia no tiene salida."
  default     = []

  validation {
    condition = alltrue([
      for r in var.egress_rules :
      (r.destination_cidr_parameter == null) != (r.destination_security_group_id == null)
    ])
    error_message = "Cada regla de salida debe tener exactamente un destino."
  }

  validation {
    condition     = length(var.egress_rules) == length(distinct([for r in var.egress_rules : r.description]))
    error_message = "description debe ser única por regla."
  }
}

# -----------------------------------------------------------------------------
# IAM
# -----------------------------------------------------------------------------

variable "permissions_boundary_name" {
  type        = string
  description = "Permission boundary obligatorio para todo rol creado por Terraform (L06)."
  default     = "dcp-platform-permission-boundary"
}

variable "rds_iam_db_users" {
  type        = list(string)
  description = "Usuarios de base de datos con los que la app se conecta por autenticación IAM (sin contraseña)."
  default     = []
}

variable "secrets_read_paths" {
  type        = list(string)
  description = "Prefijos de Secrets Manager que la app puede leer, por ejemplo /dcp/diners/dev/merchants/."

  default = []

  validation {
    condition     = alltrue([for p in var.secrets_read_paths : startswith(p, "/dcp/") && endswith(p, "/")])
    error_message = "Cada prefijo debe empezar con /dcp/ y terminar en /."
  }
}

# -----------------------------------------------------------------------------
# Contratos y logs
# -----------------------------------------------------------------------------

variable "publish_security_group_id" {
  type        = bool
  description = "Publica el ID del SG en /dcp/<domain>/<env>/<workload>/config/<purpose>-sg-id para otros stacks del workload."
  default     = true
}

variable "log_retention_days" {
  type        = number
  description = "Retención del log group de la aplicación."
  default     = 90

  validation {
    condition     = contains([30, 60, 90, 180, 365, 400, 545, 731], var.log_retention_days)
    error_message = "Use una retención soportada por CloudWatch (30, 60, 90, 180, 365, 400, 545 o 731)."
  }
}

variable "log_kms_key_arn" {
  type        = string
  description = "CMK para cifrar el log group. Obligatoria si los logs pueden tener datos confidenciales."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Solo tags complementarios (Criticality, BackupPolicy, ExceptionId, Service). Los obligatorios llegan por default_tags del provider."
  default     = {}

  validation {
    condition = alltrue([
      for k in keys(var.tags) : contains(["Criticality", "BackupPolicy", "ExpiryDate", "ExceptionId", "Service"], k)
    ])
    error_message = "Solo se aceptan tags complementarios del catálogo: Criticality, BackupPolicy, ExpiryDate, ExceptionId, Service."
  }
}
