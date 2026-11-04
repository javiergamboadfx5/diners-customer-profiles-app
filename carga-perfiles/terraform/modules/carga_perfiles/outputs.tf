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
  value = awscc_customerprofiles_object_type.socio.object_type_name
}

output "nombre_app_connect" {
  description = "Nombre de la app registrada en Connect. Es el valor de App Name en el componente External Application de la view."
  value       = var.connect_instance_arn == "" ? "" : awscc_appintegrations_application.app[0].name
}

output "application_arn" {
  description = "ARN de la app en AppIntegrations (para dar acceso desde perfiles de seguridad en el stack de Connect)."
  value       = var.connect_instance_arn == "" ? "" : awscc_appintegrations_application.app[0].application_arn
}

output "lambda_role_arn" {
  description = "Rol de las Lambdas. Util si la KMS del dominio usa key policy explicita."
  value       = aws_iam_role.lambda.arn
}

output "cognito_user_pool_id" {
  description = "User pool de pruebas (vacio si se usa Entra ID). Los usuarios se crean por CLI."
  value       = var.crear_cognito_pruebas ? aws_cognito_user_pool.pruebas[0].id : ""
}
