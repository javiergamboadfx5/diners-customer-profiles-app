# Objeto unico que lee scripts/publicar-frontend.ps1.
output "app" {
  value = {
    ambiente             = var.ambiente
    url_app              = module.carga_perfiles.url_app
    redirect_uri         = module.carga_perfiles.redirect_uri
    bucket_sitio         = module.carga_perfiles.bucket_sitio
    distribucion_id      = module.carga_perfiles.distribucion_id
    dominio_perfiles     = module.carga_perfiles.dominio_perfiles
    object_type          = module.carga_perfiles.object_type
    nombre_app_connect   = module.carga_perfiles.nombre_app_connect
    cognito_user_pool_id = module.carga_perfiles.cognito_user_pool_id
  }
}

# Para el stack de Connect (acceso de perfiles de seguridad a la app, key policy del dominio).
output "application_arn" {
  value = module.carga_perfiles.application_arn
}

output "lambda_role_arn" {
  value = module.carga_perfiles.lambda_role_arn
}
