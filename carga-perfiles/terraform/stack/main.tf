# Stack de la app de carga de perfiles. Depende del stack de Connect (instancia y dominio de Customer
# Profiles); sus outputs llegan como variables. Para leerlos de su estado en lugar de tfvars, ver
# docs/CONTRATO-STACK-CONNECT.md (seccion "Cableado").

module "carga_perfiles" {
  source = "../modules/carga_perfiles"

  directorio_backend = "${path.root}/../../app/backend"

  nombre   = var.nombre
  ambiente = var.ambiente
  tags     = var.tags

  connect_instance_arn     = var.connect_instance_arn
  connect_instance_alias   = var.connect_instance_alias
  dominio_perfiles         = var.dominio_perfiles
  kms_dominio_perfiles_arn = var.kms_dominio_perfiles_arn

  crear_cognito_pruebas            = var.crear_cognito_pruebas
  oidc_issuer                      = var.oidc_issuer
  oidc_client_id                   = var.oidc_client_id
  oidc_audiences                   = var.oidc_audiences
  oidc_scope                       = var.oidc_scope
  grupos_carga                     = var.grupos_carga
  grupos_admin                     = var.grupos_admin
  perfiles_enrutamiento_permitidos = var.perfiles_enrutamiento_permitidos

  object_type_name         = var.object_type_name
  dias_expiracion_perfiles = var.dias_expiracion_perfiles
  concurrencia_escritura   = var.concurrencia_escritura
  dias_retencion_archivos  = var.dias_retencion_archivos
  dias_retencion_logs      = var.dias_retencion_logs
  sns_alarmas_arn          = var.sns_alarmas_arn
}
