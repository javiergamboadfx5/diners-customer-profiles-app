# -----------------------------------------------------------------------------
# connect/connect-instance — outputs
#
# Las bases de naming libres de proveedor se exponen siempre. Los valores por
# componente se conectan a medida que se implementan (kms: tarea 2.1; storage:
# 2.3; instance: 2.5). Los outputs de un componente inactivo devuelven null.
# -----------------------------------------------------------------------------

output "name_prefix" {
  description = "Prefijo de naming dcp-<domain>-<env>-<workload>."
  value       = local.prefix
}

output "kms_alias" {
  description = "Alias de la CMK de almacenamiento."
  value       = local.kms_alias_storage
}

output "ssm_base" {
  description = "Base de los contratos SSM del workload."
  value       = local.ssm_base
}

# --- Componente kms (tarea 2.1) ---------------------------------------------
output "kms_key_arn" {
  description = "ARN de la CMK de almacenamiento (null si el componente no es kms)."
  value       = local.is_kms ? aws_kms_key.storage[0].arn : null
}

output "kms_key_id" {
  description = "ID de la CMK de almacenamiento (null si el componente no es kms)."
  value       = local.is_kms ? aws_kms_key.storage[0].key_id : null
}

# --- Componente storage (tarea 2.3) -----------------------------------------
output "bucket_name" {
  description = "Nombre del bucket de almacenamiento (null si el componente no es storage)."
  value       = local.is_storage ? aws_s3_bucket.storage[0].id : null
}

output "bucket_arn" {
  description = "ARN del bucket de almacenamiento (null si el componente no es storage)."
  value       = local.is_storage ? aws_s3_bucket.storage[0].arn : null
}

# --- Componente instance (tarea 2.5) ----------------------------------------
output "instance_id" {
  description = "ID de la instancia Connect (null si el componente no es instance)."
  value       = local.is_instance ? aws_connect_instance.this[0].id : null
}

output "instance_arn" {
  description = "ARN de la instancia Connect (null si el componente no es instance)."
  value       = local.is_instance ? aws_connect_instance.this[0].arn : null
}

output "instance_alias" {
  description = "Alias de la instancia Connect (null si el componente no es instance)."
  value       = local.is_instance ? aws_connect_instance.this[0].instance_alias : null
}

output "log_group_name" {
  description = "Nombre del log group de flujos de contacto (null si el componente no es instance)."
  value       = local.is_instance ? aws_cloudwatch_log_group.flow_logs[0].name : null
}

output "ssm_parameter_names" {
  description = "Contratos SSM publicados por el módulo según el componente activo."
  value = local.is_kms ? {
    connect_kms_key_arn = aws_ssm_parameter.connect_kms_key_arn[0].name
    } : local.is_storage ? {
    connect_storage_bucket_name = aws_ssm_parameter.connect_storage_bucket_name[0].name
    } : local.is_instance ? {
    connect_instance_id    = aws_ssm_parameter.connect_instance_id[0].name
    connect_instance_arn   = aws_ssm_parameter.connect_instance_arn[0].name
    connect_instance_alias = aws_ssm_parameter.connect_instance_alias[0].name
  } : {}
}
