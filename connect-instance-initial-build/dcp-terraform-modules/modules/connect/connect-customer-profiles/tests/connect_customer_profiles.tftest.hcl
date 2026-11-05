# -----------------------------------------------------------------------------
# connect/connect-customer-profiles — pruebas `terraform test` (tarea 3.4)
#
# Pruebas sin tocar AWS: provider simulado (`mock_provider "aws"` y
# `mock_provider "awscc"`). Se ejecutan con `terraform test` en el PR del módulo
# (Req 3.9). No hay apply: todos los runs usan `command = plan` y los recursos
# se evalúan contra el mock.
#
# Estructura:
#   1. Runs de fallo — una regla por run (Req 3):
#        - domain_name sin prefijo amazon-connect-
#        - domain_name de más de 64 caracteres
#        - domain_name con un carácter inválido
#        - default_expiration_days = 0 y = 1099 (fuera de 1..1098)
#        - enable_data_store = true sin data_store_approval_ref
#        - contrato SSM customer-profiles-kms-key-arn ausente (componente domain)
#        - contrato SSM connect-instance-arn ausente (componente domain)
#        - contrato SSM key-admin-role ausente (componente kms, Req 7.x / OQ-13)
#   2. Runs positivos — comportamiento esperado (Req 7.3, 7.4, 8.2, 8.5):
#        - tipo de objeto CTR desde la plantilla CTR-AutoAssociateOnly
#        - una única integración con uri = ARN de la instancia y object_type CTR
#        - matching desactivado (bloque matching ausente)
#        - statement ProfilesApp presente/ausente según el parámetro SSM
#          profiles-app-role-arn
#
# Las búsquedas SSM se simulan con `override_data` por dirección de data source.
# Los runs de contrato ausente sobreescriben `value = ""` (o el conjunto de
# nombres de aws_ssm_parameters_by_path) para que la validación nativa o la
# postcondition del data source falle, y se captura esa dirección en
# `expect_failures`.
# -----------------------------------------------------------------------------

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }

  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }

  mock_data "aws_region" {
    defaults = { name = "us-east-1" }
  }

  # El mock genera un valor aleatorio para el atributo calculado `json` del
  # policy document, que rompe la validación JSON de aws_kms_key.policy durante
  # el plan. Fijamos un JSON válido por defecto; el atributo de entrada
  # `statement` viene de la configuración del módulo, así que los asserts que lo
  # inspeccionan siguen funcionando.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

mock_provider "awscc" {}

# Entradas base válidas compartidas por los runs. Cada run ajusta solo lo que
# necesita.
variables {
  component   = "kms"
  environment = "dev"
  workload    = "connectwl"
  region_code = "use1"
  cde_scope   = false
}

# =============================================================================
# 1. Runs de fallo — una regla de validación por run (Req 3)
# =============================================================================

# --- Req 3.2 — component fuera de la lista ----------------------------------
run "component_invalido_falla" {
  command = plan

  variables {
    component = "perfiles"
  }

  expect_failures = [var.component]
}

# --- Req 3.7 / 8.1 — domain_name sin el prefijo amazon-connect- -------------
run "domain_name_sin_prefijo_falla" {
  command = plan

  variables {
    domain_name = "dcp-diners-dev-connectwl" # falta amazon-connect-
  }

  expect_failures = [var.domain_name]
}

# --- Req 3.7 / 8.1 — domain_name de más de 64 caracteres --------------------
# Prefijo válido pero longitud total > 64 (la regla de longitud debe disparar).
run "domain_name_demasiado_largo_falla" {
  command = plan

  variables {
    domain_name = "amazon-connect-dcp-diners-dev-connectwl-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  }

  expect_failures = [var.domain_name]
}

# --- Req 3.7 / 8.1 — domain_name con un carácter inválido -------------------
# Prefijo y longitud válidos; el punto no pertenece a [A-Za-z0-9_-].
run "domain_name_caracter_invalido_falla" {
  command = plan

  variables {
    domain_name = "amazon-connect-dcp.diners"
  }

  expect_failures = [var.domain_name]
}

# --- Req 3.8 / 8.2 — default_expiration_days = 0 (por debajo de 1) ----------
run "expiracion_cero_falla" {
  command = plan

  variables {
    component               = "domain"
    default_expiration_days = 0
  }

  expect_failures = [var.default_expiration_days]
}

# --- Req 3.8 / 8.2 — default_expiration_days = 1099 (por encima de 1098) -----
run "expiracion_mil_noventa_y_nueve_falla" {
  command = plan

  variables {
    component               = "domain"
    default_expiration_days = 1099
  }

  expect_failures = [var.default_expiration_days]
}

# --- Req 8.3 / 8.4 — data store habilitado sin referencia de aprobación -----
run "data_store_sin_aprobacion_falla" {
  command = plan

  variables {
    enable_data_store       = true
    data_store_approval_ref = "" # obligatorio cuando enable_data_store = true
  }

  expect_failures = [var.enable_data_store]
}

# --- Req 8.2 / 8.5 — contrato SSM customer-profiles-kms-key-arn ausente -----
# El componente domain lee la CMK de SSM. Si el parámetro está vacío, el dominio
# no debe planificarse: la validación nativa del recurso (default_encryption_key
# no vacío) falla.
run "domain_kms_key_arn_ausente_falla" {
  command = plan

  variables {
    component               = "domain"
    default_expiration_days = 90
  }

  override_data {
    target = data.aws_ssm_parameter.profiles_kms_key_arn[0]
    values = {
      value = ""
    }
  }

  override_data {
    target = data.aws_ssm_parameter.connect_instance_arn[0]
    values = {
      value = "arn:aws:connect:us-east-1:111111111111:instance/abcd-1234"
    }
  }

  expect_failures = [aws_customerprofiles_domain.this]
}

# --- Req 8.5 — contrato SSM connect-instance-arn ausente --------------------
# La integración usa el ARN de la instancia como uri. Si el parámetro está
# vacío, la integración no debe planificarse con un uri vacío.
run "domain_instance_arn_ausente_falla" {
  command = plan

  variables {
    component               = "domain"
    default_expiration_days = 90
  }

  override_data {
    target = data.aws_ssm_parameter.profiles_kms_key_arn[0]
    values = {
      value = "arn:aws:kms:us-east-1:111111111111:key/abcd-1234"
    }
  }

  override_data {
    target = data.aws_ssm_parameter.connect_instance_arn[0]
    values = {
      value = ""
    }
  }

  expect_failures = [awscc_customerprofiles_integration.ctr]
}

# --- Req 7.x / OQ-13 — contrato SSM key-admin-role ausente (vacío) ----------
# En el componente kms, el ARN del rol key-admin llega vacío -> la postcondition
# del data source falla con "key-admin role not published (OQ-13)".
run "key_admin_role_ausente_falla" {
  command = plan

  variables {
    component = "kms"
  }

  override_data {
    target = data.aws_ssm_parameter.key_admin_role[0]
    values = {
      value = ""
    }
  }

  override_data {
    target = data.aws_ssm_parameters_by_path.config[0]
    values = {
      names  = []
      values = []
    }
  }

  expect_failures = [data.aws_ssm_parameter.key_admin_role]
}

# =============================================================================
# 2. Runs positivos — comportamiento esperado (Req 7.3, 7.4, 8.2, 8.5)
# =============================================================================

# --- Componente domain: tipo de objeto CTR, integración única y matching off -
# Req 8.5 (CTR desde la plantilla, una integración con uri = ARN de instancia),
# 8.2 (expiración de la entrada, CMK del contrato), 8.1 (matching desactivado),
# 2.6 (solo tag Name en el dominio).
run "domain_crea_ctr_integracion_y_matching_off" {
  command = plan

  variables {
    component               = "domain"
    default_expiration_days = 90
  }

  override_data {
    target = data.aws_ssm_parameter.profiles_kms_key_arn[0]
    values = {
      value = "arn:aws:kms:us-east-1:111111111111:key/abcd-1234"
    }
  }

  override_data {
    target = data.aws_ssm_parameter.connect_instance_arn[0]
    values = {
      value = "arn:aws:connect:us-east-1:111111111111:instance/abcd-1234"
    }
  }

  # Nombre del dominio computado con el prefijo amazon-connect- (Req 8.1).
  assert {
    condition     = aws_customerprofiles_domain.this[0].domain_name == "amazon-connect-dcp-diners-dev-connectwl"
    error_message = "El nombre del dominio computado no sigue amazon-connect-dcp-<domain>-<env>-<workload> (Req 8.1)."
  }

  # Expiración tomada de la entrada validada (Req 8.2).
  assert {
    condition     = aws_customerprofiles_domain.this[0].default_expiration_days == 90
    error_message = "La expiración del dominio debe venir de default_expiration_days (Req 8.2)."
  }

  # CMK del contrato SSM, sin literal (Req 8.2).
  assert {
    condition     = aws_customerprofiles_domain.this[0].default_encryption_key == "arn:aws:kms:us-east-1:111111111111:key/abcd-1234"
    error_message = "El dominio debe cifrarse con la CMK del contrato customer-profiles-kms-key-arn (Req 8.2)."
  }

  # Tipo de objeto CTR desde la plantilla CTR-AutoAssociateOnly (Req 8.5).
  assert {
    condition     = awscc_customerprofiles_object_type.ctr[0].object_type_name == "CTR"
    error_message = "El tipo de objeto debe llamarse CTR (Req 8.5)."
  }

  assert {
    condition     = awscc_customerprofiles_object_type.ctr[0].template_id == "CTR-AutoAssociateOnly"
    error_message = "El tipo de objeto CTR debe crearse desde la plantilla CTR-AutoAssociateOnly (Req 8.5)."
  }

  # Una única integración con uri = ARN de la instancia y object_type CTR
  # (Req 8.5). La integración se crea con count = 1 (una sola integración).
  assert {
    condition     = awscc_customerprofiles_integration.ctr[0].uri == "arn:aws:connect:us-east-1:111111111111:instance/abcd-1234"
    error_message = "La integración debe usar el ARN de la instancia (SSM connect-instance-arn) como uri (Req 8.5)."
  }

  assert {
    condition     = awscc_customerprofiles_integration.ctr[0].object_type_name == "CTR"
    error_message = "La integración debe apuntar al tipo de objeto CTR (Req 8.5)."
  }

  # Matching desactivado: el bloque matching se omite por completo (Req 8.1).
  assert {
    condition     = length(aws_customerprofiles_domain.this[0].matching) == 0
    error_message = "El matching de perfiles debe permanecer desactivado (bloque matching ausente, Req 8.1)."
  }

  # El módulo solo añade el tag Name al dominio (Req 2.6).
  assert {
    condition     = length(keys(aws_customerprofiles_domain.this[0].tags)) == 1 && contains(keys(aws_customerprofiles_domain.this[0].tags), "Name")
    error_message = "El dominio solo debe llevar el tag Name; el resto los inyecta el root (Req 2.6)."
  }

  # Contratos SSM del dominio publicados con la ruta esperada (Req 8.7).
  assert {
    condition     = aws_ssm_parameter.profiles_domain_name[0].name == "/dcp/diners/dev/connectwl/config/customer-profiles-domain-name"
    error_message = "El contrato SSM customer-profiles-domain-name no tiene la ruta esperada (Req 8.7)."
  }

  assert {
    condition     = aws_ssm_parameter.profiles_domain_arn[0].name == "/dcp/diners/dev/connectwl/config/customer-profiles-domain-arn"
    error_message = "El contrato SSM customer-profiles-domain-arn no tiene la ruta esperada (Req 8.7)."
  }
}

# --- Componente kms: statement ProfilesApp PRESENTE cuando el contrato existe -
# Req 7.3 — cuando profiles-app-role-arn está publicado en SSM, la política de
# la llave incluye el statement ProfilesApp.
run "kms_profiles_app_presente_con_contrato" {
  command = plan

  variables {
    component = "kms"
  }

  override_data {
    target = data.aws_ssm_parameter.key_admin_role[0]
    values = {
      value = "arn:aws:iam::111111111111:role/dcp-diners-dev-connectwl-role-key-admin"
    }
  }

  # El path devuelve el parámetro profiles-app-role-arn -> statement presente.
  override_data {
    target = data.aws_ssm_parameters_by_path.config[0]
    values = {
      names  = ["/dcp/diners/dev/connectwl/config/profiles-app-role-arn"]
      values = ["arn:aws:iam::111111111111:role/dcp-diners-dev-connectwl-role-profiles-app"]
    }
  }

  assert {
    condition     = output.profiles_app_statement_present == true
    error_message = "El statement ProfilesApp debe estar presente cuando profiles-app-role-arn está publicado (Req 7.3)."
  }

  # Rotación de la CMK dedicada de perfiles habilitada (Req 7.1).
  assert {
    condition     = aws_kms_key.profiles[0].enable_key_rotation == true
    error_message = "La CMK de Customer Profiles debe tener la rotación habilitada (Req 7.1)."
  }

  # Alias con el patrón esperado (Req 7.1, L08).
  assert {
    condition     = aws_kms_alias.profiles[0].name == "alias/dcp/diners/dev/connectwl/customer-profiles"
    error_message = "El alias de la CMK no sigue el patrón alias/dcp/<domain>/<env>/<workload>/customer-profiles (Req 7.1, L08)."
  }
}

# --- Componente kms: statement ProfilesApp AUSENTE cuando no hay contrato ----
# Req 7.4 — cuando profiles-app-role-arn no está publicado, el statement se
# omite y el plan sigue adelante.
run "kms_profiles_app_ausente_sin_contrato" {
  command = plan

  variables {
    component = "kms"
  }

  override_data {
    target = data.aws_ssm_parameter.key_admin_role[0]
    values = {
      value = "arn:aws:iam::111111111111:role/dcp-diners-dev-connectwl-role-key-admin"
    }
  }

  # El path no contiene profiles-app-role-arn -> statement ausente, plan sigue.
  override_data {
    target = data.aws_ssm_parameters_by_path.config[0]
    values = {
      names  = []
      values = []
    }
  }

  assert {
    condition     = output.profiles_app_statement_present == false
    error_message = "El statement ProfilesApp debe omitirse cuando profiles-app-role-arn no está publicado (Req 7.4)."
  }

  # Contrato SSM customer-profiles-kms-key-arn publicado con la ruta esperada
  # (Req 7.8).
  assert {
    condition     = aws_ssm_parameter.profiles_kms_key_arn[0].name == "/dcp/diners/dev/connectwl/config/customer-profiles-kms-key-arn"
    error_message = "El contrato SSM customer-profiles-kms-key-arn no tiene la ruta esperada (Req 7.8)."
  }

  # El módulo solo añade el tag Name a la CMK (Req 2.6).
  assert {
    condition     = length(keys(aws_kms_key.profiles[0].tags)) == 1 && contains(keys(aws_kms_key.profiles[0].tags), "Name")
    error_message = "La CMK solo debe llevar el tag Name; el resto los inyecta el root (Req 2.6)."
  }
}
