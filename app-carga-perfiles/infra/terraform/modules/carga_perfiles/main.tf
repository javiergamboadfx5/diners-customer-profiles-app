data "aws_caller_identity" "actual" {}
data "aws_region" "actual" {}

locals {
  prefijo     = "${var.nombre}-${var.ambiente}"
  cuenta      = data.aws_caller_identity.actual.account_id
  region      = data.aws_region.actual.name
  raiz_app    = abspath("${path.module}/../../../..")
  tags        = merge({ Proyecto = "diners-carga-perfiles", Ambiente = var.ambiente, GestionadoPor = "terraform" }, var.tags)
  dominio     = length(aws_customerprofiles_domain.socios) > 0 ? aws_customerprofiles_domain.socios[0].domain_name : var.dominio_perfiles
  dominio_arn = "arn:aws:profile:${local.region}:${local.cuenta}:domains/${local.dominio}"

  # Campos del object type. Las claves deben coincidir con CAMPO_OBJECT_TYPE en backend/src/carga/reglas.py.
  campos_object_type = {
    account_number   = { target = "_profile.AccountNumber", tipo = "STRING" }
    first_name       = { target = "_profile.FirstName", tipo = "STRING" }
    last_name        = { target = "_profile.LastName", tipo = "STRING" }
    phone_number     = { target = "_profile.PhoneNumber", tipo = "PHONE_NUMBER" }
    mobile_phone     = { target = "_profile.MobilePhoneNumber", tipo = "PHONE_NUMBER" }
    personal_email   = { target = "_profile.PersonalEmailAddress", tipo = "EMAIL_ADDRESS" }
    birth_date       = { target = "_profile.BirthDate", tipo = "STRING" }
    profile_type     = { target = "_profile.ProfileType", tipo = "STRING" }
    segmento_valor   = { target = "_profile.Attributes.SegmentoValor", tipo = "STRING" }
    marca_retener    = { target = "_profile.Attributes.MarcaRetener", tipo = "STRING" }
    tiene_oferta     = { target = "_profile.Attributes.TieneOferta", tipo = "STRING" }
    tea              = { target = "_profile.Attributes.Tea", tipo = "NUMBER" }
    fecha_afiliacion = { target = "_profile.Attributes.FechaAfiliacion", tipo = "STRING" }
    tipo_producto    = { target = "_profile.Attributes.TipoProducto", tipo = "STRING" }
  }
}

# ---------- Cifrado ----------

resource "aws_kms_key" "app" {
  description             = "${local.prefijo}: archivos de carga, tabla y cola"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = local.tags
}

resource "aws_kms_alias" "app" {
  name          = "alias/${local.prefijo}"
  target_key_id = aws_kms_key.app.key_id
}

# ---------- Tabla: cargas, lock y esquema ----------

resource "aws_dynamodb_table" "app" {
  name         = local.prefijo
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"

  attribute {
    name = "pk"
    type = "S"
  }
  attribute {
    name = "sk"
    type = "S"
  }
  attribute {
    name = "gsi1pk"
    type = "S"
  }
  attribute {
    name = "gsi1sk"
    type = "S"
  }

  global_secondary_index {
    name            = "gsi1"
    hash_key        = "gsi1pk"
    range_key       = "gsi1sk"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "expira"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.app.arn
  }

  deletion_protection_enabled = var.ambiente == "prod"
  tags                        = local.tags
}

# Esquema inicial. Despues lo administra la app (pantalla "Esquema de destino").
resource "aws_dynamodb_table_item" "esquema_inicial" {
  table_name = aws_dynamodb_table.app.name
  hash_key   = aws_dynamodb_table.app.hash_key
  range_key  = aws_dynamodb_table.app.range_key
  item = jsonencode({
    pk      = { S = "ESQUEMA" }
    sk      = { S = "ACTUAL" }
    version = { N = "1" }
    esquema = { S = jsonencode(jsondecode(file("${local.raiz_app}/backend/esquema-inicial.json"))) }
  })
  lifecycle {
    ignore_changes = [item]
  }
}

# ---------- Cola de escritura ----------

resource "aws_sqs_queue" "dlq" {
  name                      = "${local.prefijo}-escritura-dlq"
  message_retention_seconds = 1209600
  kms_master_key_id         = aws_kms_key.app.arn
  tags                      = local.tags
}

resource "aws_sqs_queue" "escritura" {
  name                       = "${local.prefijo}-escritura"
  visibility_timeout_seconds = 720 # 6 x timeout del escritor
  message_retention_seconds  = 345600
  kms_master_key_id          = aws_kms_key.app.arn
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 8
  })
  tags = local.tags
}

# ---------- Customer Profiles ----------

resource "aws_customerprofiles_domain" "socios" {
  count                   = var.habilitar_customer_profiles && var.crear_dominio_perfiles ? 1 : 0
  domain_name             = var.dominio_perfiles
  default_expiration_days = var.dias_expiracion_perfiles
  default_encryption_key  = aws_kms_key.app.arn
  matching {
    # Una sola fuente y DNI unico: el auto-merge solo agrega riesgo (ver 3P-APP-CARGA, seccion 5).
    enabled = false
  }
  tags = local.tags

  # Borrar o reemplazar el dominio elimina todos los perfiles de socios.
  # Para hacerlo a proposito, quitar esta linea en un cambio revisado.
  lifecycle {
    prevent_destroy = true
  }
}

resource "awscc_customerprofiles_object_type" "socio" {
  count = var.habilitar_customer_profiles ? 1 : 0

  # Cambiar object_type_name o domain_name obliga a reemplazarlo, y eso borra los objetos de todos los socios:
  # el agente dejaria de reconocerlos hasta la proxima carga. Terraform rechaza el plan en ese caso.
  lifecycle {
    prevent_destroy = true
  }
  domain_name            = local.dominio
  object_type_name       = var.object_type_name
  description            = "Socio Diners cargado desde la app de carga de perfiles."
  allow_profile_creation = true
  expiration_days        = var.dias_expiracion_perfiles

  fields = [
    for nombre, campo in local.campos_object_type : {
      name = nombre
      object_type_field = {
        source       = "_source.${nombre}"
        target       = campo.target
        content_type = campo.tipo
      }
    }
  ]

  keys = [
    {
      # DNI: identifica un unico perfil. Busqueda del agente en WhatsApp.
      name = "_account"
      object_type_key_list = [
        {
          field_names          = ["account_number"]
          standard_identifiers = ["PROFILE", "UNIQUE"]
        }
      ]
    },
    {
      # TELEFONO_1: busqueda por el numero que llama en voz (definido el 23 de octubre).
      # Sin UNIQUE: un celular puede repetirse entre socios y no debe fusionarlos.
      name = "_phone"
      object_type_key_list = [
        {
          field_names          = ["mobile_phone"]
          standard_identifiers = ["PROFILE"]
        }
      ]
    }
  ]
}
