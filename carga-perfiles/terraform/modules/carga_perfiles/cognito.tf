# Proveedor OIDC de pruebas. Solo mientras no exista el app registration en Entra ID de Diners.
# Los usuarios se crean por CLI despues del apply, para que las contrasenas no queden en el estado.

resource "aws_cognito_user_pool" "pruebas" {
  count                    = var.crear_cognito_pruebas ? 1 : 0
  name                     = "${local.prefijo}-pruebas"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  deletion_protection      = "INACTIVE"
  mfa_configuration        = "OFF"

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 3
  }

  tags = local.tags
}

resource "aws_cognito_user_pool_domain" "pruebas" {
  count        = var.crear_cognito_pruebas ? 1 : 0
  domain       = "${local.prefijo}-${local.cuenta}"
  user_pool_id = aws_cognito_user_pool.pruebas[0].id
}

resource "aws_cognito_user_pool_client" "spa" {
  count                                = var.crear_cognito_pruebas ? 1 : 0
  name                                 = "${local.prefijo}-spa"
  user_pool_id                         = aws_cognito_user_pool.pruebas[0].id
  generate_secret                      = false # SPA publica con PKCE
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = ["https://${aws_cloudfront_distribution.app.domain_name}/"]
  logout_urls                          = ["https://${aws_cloudfront_distribution.app.domain_name}/"]
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation              = true
  access_token_validity                = 60
  id_token_validity                    = 60
  refresh_token_validity               = 8
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "hours"
  }
}

resource "aws_cognito_user_group" "carga" {
  count        = var.crear_cognito_pruebas ? 1 : 0
  name         = "carga-perfiles"
  user_pool_id = aws_cognito_user_pool.pruebas[0].id
  description  = "Pueden cargar y publicar el esquema (equivale al grupo de Entra ID)."
}

locals {
  oidc_issuer    = var.crear_cognito_pruebas ? "https://cognito-idp.${local.region}.amazonaws.com/${aws_cognito_user_pool.pruebas[0].id}" : var.oidc_issuer
  oidc_client_id = var.crear_cognito_pruebas ? aws_cognito_user_pool_client.spa[0].id : var.oidc_client_id
  # Los access tokens de Cognito no traen "aud"; el autorizador JWT de HTTP API valida client_id.
  oidc_audiences = var.crear_cognito_pruebas ? [aws_cognito_user_pool_client.spa[0].id] : var.oidc_audiences
  oidc_scope     = var.crear_cognito_pruebas ? "openid email profile" : var.oidc_scope
  grupos_carga   = var.crear_cognito_pruebas ? ["carga-perfiles"] : var.grupos_carga
  grupos_admin   = var.crear_cognito_pruebas ? ["carga-perfiles"] : var.grupos_admin
  # Hosts que la CSP debe permitir para el login (metadata, token y pagina de login).
  hosts_oidc = compact([
    regex("^https://[^/]+", var.crear_cognito_pruebas ? "https://cognito-idp.${local.region}.amazonaws.com" : var.oidc_issuer),
    var.crear_cognito_pruebas ? "https://${local.prefijo}-${local.cuenta}.auth.${local.region}.amazoncognito.com" : "",
  ])
}
