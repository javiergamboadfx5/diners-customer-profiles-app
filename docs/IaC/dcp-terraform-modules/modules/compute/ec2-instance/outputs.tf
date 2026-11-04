output "instance_id" {
  description = "ID de la instancia."
  value       = aws_instance.this.id
}

output "instance_name" {
  description = "Nombre físico de la instancia."
  value       = local.instance_name
}

output "private_ip" {
  description = "IP privada de la instancia."
  value       = aws_instance.this.private_ip
}

output "security_group_id" {
  description = "ID del SG de la instancia."
  value       = aws_security_group.this.id
}

output "security_group_parameter_name" {
  description = "Parámetro SSM donde se publica el SG (null si no se publica)."
  value       = var.publish_security_group_id ? aws_ssm_parameter.security_group_id[0].name : null
}

output "role_arn" {
  description = "ARN del rol de la instancia."
  value       = aws_iam_role.this.arn
}

output "log_group_name" {
  description = "Log group de la aplicación."
  value       = aws_cloudwatch_log_group.app.name
}
