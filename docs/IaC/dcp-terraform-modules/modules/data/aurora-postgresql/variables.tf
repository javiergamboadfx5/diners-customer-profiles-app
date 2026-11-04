# -----------------------------------------------------------------------------
# Naming
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
    error_message = "El ambiente no pertenece al catálogo aprobado."
  }
}

variable "workload" {
  type        = string
  description = "Capacidad funcional registrada en el catálogo."

  validation {
    condition = (
      can(regex("^[a-z][a-z0-9-]{1,20}$", var.workload)) &&
      !contains(["shared", "unknown", "n-a", "na", "temp", "test"], var.workload)
    )
    error_message = "workload inválido o genérico."
  }
}

variable "purpose" {
  type        = string
  description = "Uso del cluster (core, reporting, ...)."
  default     = "core"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,15}$", var.purpose))
    error_message = "purpose debe ser kebab-case de 2 a 16 caracteres."
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
# Motor y capacidad
# -----------------------------------------------------------------------------

variable "engine_version" {
  type        = string
  description = "Versión de Aurora PostgreSQL (major.minor)."
  default     = "16.6"

  validation {
    condition     = can(regex("^[0-9]{2}\\.[0-9]+$", var.engine_version))
    error_message = "engine_version debe tener formato major.minor (ej. 16.6)."
  }
}

variable "instance_class" {
  type        = string
  description = "Clase de las instancias del cluster."

  validation {
    condition     = startswith(var.instance_class, "db.")
    error_message = "instance_class debe empezar con db."
  }
}

variable "instance_count" {
  type        = number
  description = "Número de instancias (1 writer + réplicas)."
  default     = 2

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 5
    error_message = "instance_count debe estar entre 1 y 5."
  }
}

variable "database_name" {
  type        = string
  description = "Base de datos inicial."

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{1,62}$", var.database_name))
    error_message = "database_name debe ser snake_case en minúsculas."
  }
}

variable "master_username" {
  type        = string
  description = "Usuario maestro. La contraseña la genera y rota RDS en Secrets Manager."
  default     = "dbadmin"
}

variable "port" {
  type        = number
  description = "Puerto de PostgreSQL."
  default     = 5432
}

# -----------------------------------------------------------------------------
# Red y acceso
# -----------------------------------------------------------------------------

variable "vpc_id_parameter" {
  type        = string
  description = "Parámetro SSM con el ID de la VPC compartida."
  default     = "/dcp/networking/vpc/id"
}

variable "subnet_ids_parameter" {
  type        = string
  description = "Parámetro SSM (StringList) con las subredes data-private."
  default     = "/dcp/networking/subnets/data-private/ids"
}

variable "allowed_security_group_id_parameters" {
  type        = list(string)
  description = "Parámetros SSM con los SG que pueden conectarse (contratos publicados por otros stacks del workload)."
  default     = []

  validation {
    condition     = alltrue([for p in var.allowed_security_group_id_parameters : startswith(p, "/dcp/")])
    error_message = "Los SG permitidos se leen de contratos /dcp/...; no se aceptan IDs literales."
  }
}

# -----------------------------------------------------------------------------
# Protección y operación
# -----------------------------------------------------------------------------

variable "deletion_protection" {
  type        = bool
  description = "Protege el cluster contra borrado."
  default     = true
}

variable "backup_retention_days" {
  type        = number
  description = "Días de retención de backups automáticos."
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "backup_retention_days debe estar entre 1 y 35."
  }
}

variable "preferred_backup_window" {
  type        = string
  description = "Ventana de backup en UTC."
  default     = "07:00-08:00" # 02:00-03:00 hora de Lima
}

variable "preferred_maintenance_window" {
  type        = string
  description = "Ventana de mantenimiento en UTC."
  default     = "sun:08:30-sun:09:30"
}

variable "log_retention_days" {
  type        = number
  description = "Retención del log group de PostgreSQL."
  default     = 30

  validation {
    condition     = contains([30, 60, 90, 180, 365, 400, 545, 731], var.log_retention_days)
    error_message = "Use una retención soportada por CloudWatch."
  }
}

variable "create_kms_key" {
  type        = bool
  description = "Crea la CMK alias/dcp/<domain>/<env>/<workload>/data. Si es false, use kms_key_arn."
  default     = true
}

variable "kms_key_arn" {
  type        = string
  description = "CMK existente cuando create_kms_key = false."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Solo tags complementarios."
  default     = {}

  validation {
    condition = alltrue([
      for k in keys(var.tags) : contains(["Criticality", "BackupPolicy", "ExpiryDate", "ExceptionId", "Service"], k)
    ])
    error_message = "Solo se aceptan tags complementarios del catálogo."
  }
}
