output "url_app" {
  description = "URL HTTPS de la app (access URL de la integracion en Connect)."
  value       = "https://${aws_cloudfront_distribution.app.domain_name}"
}

output "bucket_sitio" {
  value = aws_s3_bucket.sitio.id
}

output "distribucion_id" {
  value = aws_cloudfront_distribution.app.id
}

output "redirect_uri" {
  description = "Registrar como Redirect URI (SPA) en el app registration de Entra ID."
  value       = "https://${aws_cloudfront_distribution.app.domain_name}/"
}

output "dominio_perfiles" {
  value = local.dominio
}

output "object_type" {
  value = var.habilitar_customer_profiles ? var.object_type_name : "(deshabilitado)"
}

output "cognito_user_pool_id" {
  description = "User pool de pruebas (vacio si se usa Entra ID). Los usuarios se crean por CLI."
  value       = var.crear_cognito_pruebas ? aws_cognito_user_pool.pruebas[0].id : ""
}
