output "cluster_identifier" {
  description = "Nombre del cluster."
  value       = aws_rds_cluster.this.cluster_identifier
}

output "cluster_resource_id" {
  description = "ID de recurso; se usa en políticas rds-db:connect si se quiere acotar por cluster."
  value       = aws_rds_cluster.this.cluster_resource_id
}

output "writer_endpoint" {
  description = "Endpoint de escritura."
  value       = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  description = "Endpoint de lectura."
  value       = aws_rds_cluster.this.reader_endpoint
}

output "port" {
  value = aws_rds_cluster.this.port
}

output "security_group_id" {
  value = aws_security_group.this.id
}

output "master_user_secret_arn" {
  description = "ARN del secreto administrado por RDS (solo DBA y break-glass)."
  value       = try(aws_rds_cluster.this.master_user_secret[0].secret_arn, null)
}

output "kms_key_arn" {
  value = local.kms_arn
}
