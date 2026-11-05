# -----------------------------------------------------------------------------
# connect/connect-instance — pruebas `terraform test` (tarea 2.6)
#
# Pruebas sin tocar AWS: provider simulado (`mock_provider "aws"`). Se ejecutan
# con `terraform test` en el PR del módulo (Req 3.9). No hay apply: todos los
# runs usan `command = plan` y los recursos se evalúan contra el mock.
#
# Estructura:
#   1. Un run `expect_failures` por regla de validación de entrada (Req 3):
#      alias inválido, tipo de identidad inválido, EXISTING_DIRECTORY sin
#      directory_id, environment inválido, qa/stg/prod no-SAML sin excepción,
#      dev CONNECT_MANAGED sin excepción, retención < 1, y las tres
#      precondiciones de contrato SSM (key ARN, bucket name, key-admin role),
#      y cde_scope = true sin security_coverage_ref.
#   2. Runs positivos que comprueban el comportamiento esperado por componente:
#      patrones de nombre, rotación y ventana de 30 días de la CMK,
#      endurecimiento del bucket S3, flags de la instancia, ambas
#      configuraciones de almacenamiento, contratos SSM publicados y que el
#      módulo solo añade el tag Name (Req 2.5, 4.1, 5.2, 6.1, 6.3, 6.7).
#
# Las búsquedas SSM se simulan con `override_data` por dirección de data source.
# Los runs de precondición de contrato (key ARN / bucket name / key-admin role)
# sobreescriben `value = ""` para que la precondición del recurso falle y se
# captura esa dirección de recurso en `expect_failures`.
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

  # El mock genera un valor aleatorio para el atributo calculado `json` de los
  # policy documents, que luego rompe la validación JSON de aws_kms_key.policy y
  # aws_s3_bucket_policy.policy durante el plan. Fijamos un JSON válido por
  # defecto; el atributo de entrada `statement` viene de la configuración del
  # módulo, así que los asserts que lo inspeccionan siguen funcionando.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

# Entradas base válidas compartidas por los runs. Cada run ajusta solo lo que
# necesita. org_id y account_id son deterministas para el sufijo del bucket.
variables {
  component   = "kms"
  environment = "dev"
  workload    = "connectwl"
  region_code = "use1"
  org_id      = "o-abcde12345"
  account_id  = "111111111111"
  cde_scope   = false
}

# =============================================================================
# 1. Runs de fallo — una regla de validación por run (Req 3)
# =============================================================================

# --- Req 3.2 — component fuera de la lista ----------------------------------
run "component_invalido_falla" {
  command = plan

  variables {
    component = "flujos"
  }

  expect_failures = [var.component]
}

# --- Req 3.1 — alias que no cumple la regla de alias ------------------------
run "alias_invalido_falla" {
  command = plan

  variables {
    component      = "instance"
    instance_alias = "Connect_Alias" # mayúsculas y guion bajo no permitidos
  }

  expect_failures = [var.instance_alias]
}

# --- Req 3.2 — identity_management_type fuera de la lista -------------------
run "identity_type_invalido_falla" {
  command = plan

  variables {
    identity_management_type = "ACTIVE_DIRECTORY"
  }

  expect_failures = [var.identity_management_type]
}

# --- Req 3.3 — EXISTING_DIRECTORY sin directory_id --------------------------
run "existing_directory_sin_directory_id_falla" {
  command = plan

  variables {
    identity_management_type = "EXISTING_DIRECTORY"
    directory_id             = null
  }

  expect_failures = [var.directory_id]
}

# --- Req 3.4 — environment fuera de la lista blanca -------------------------
run "environment_invalido_falla" {
  command = plan

  variables {
    environment = "prd"
  }

  expect_failures = [var.environment]
}

# --- Req 3.5 — qa/stg/prod no-SAML sin excepción válida ---------------------
run "prod_no_saml_sin_excepcion_falla" {
  command = plan

  variables {
    environment              = "prod"
    identity_management_type = "EXISTING_DIRECTORY"
    directory_id             = "d-1234567890"
    exception_id             = "" # falta la excepción obligatoria
  }

  expect_failures = [var.exception_id]
}

# --- Req 3.6 — dev CONNECT_MANAGED sin excepción válida ---------------------
run "dev_connect_managed_sin_excepcion_falla" {
  command = plan

  variables {
    environment              = "dev"
    identity_management_type = "CONNECT_MANAGED"
    exception_id             = "" # falta la excepción obligatoria
  }

  expect_failures = [var.exception_id]
}

# --- Req 5.5 / 6.5 — retención por debajo de 1 ------------------------------
run "retencion_por_debajo_de_uno_falla" {
  command = plan

  variables {
    component                 = "storage"
    recordings_retention_days = 0
  }

  expect_failures = [var.recordings_retention_days]
}

# --- Req 5.6 / DD-2 — cde_scope = true sin security_coverage_ref ------------
run "cde_scope_sin_cobertura_falla" {
  command = plan

  variables {
    cde_scope             = true
    security_coverage_ref = "" # obligatoria cuando cde_scope = true
  }

  expect_failures = [var.security_coverage_ref]
}

# --- Req 4.6 / OQ-13 — contrato SSM key-admin-role ausente (vacío) ----------
# El data source devuelve value vacío -> la precondition de la CMK falla.
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

  expect_failures = [aws_kms_key.storage]
}

# --- Req 5.3 — contrato SSM connect-kms-key-arn ausente (vacío) -------------
# En el componente storage, el ARN de la CMK llega vacío -> precondition del
# bucket falla antes de crear nada.
run "storage_key_arn_ausente_falla" {
  command = plan

  variables {
    component = "storage"
  }

  override_data {
    target = data.aws_ssm_parameter.storage_kms_key_arn[0]
    values = {
      value = ""
    }
  }

  expect_failures = [aws_s3_bucket.storage]
}

# --- Req 6.4 — contrato SSM connect-storage-bucket-name ausente (vacío) -----
# En el componente instance, el nombre del bucket llega vacío -> precondition
# del log group falla antes de planear la instancia.
run "instance_bucket_name_ausente_falla" {
  command = plan

  variables {
    component      = "instance"
    instance_alias = "dcp-diners-dev-connect"
  }

  override_data {
    target = data.aws_ssm_parameter.instance_kms_key_arn[0]
    values = {
      value = "arn:aws:kms:us-east-1:111111111111:key/abcd-1234"
    }
  }

  override_data {
    target = data.aws_ssm_parameter.instance_storage_bucket_name[0]
    values = {
      value = ""
    }
  }

  expect_failures = [aws_cloudwatch_log_group.flow_logs]
}

# =============================================================================
# 2. Runs positivos — comportamiento esperado por componente
# =============================================================================

# --- Componente kms: rotación, ventana de 30 días, alias y contrato SSM -----
# Req 4.1 (rotación on, 365 d, ventana 30 d, alias), 4.4 (contrato SSM),
# 2.6 (solo tag Name).
run "kms_crea_cmk_con_rotacion_y_ventana" {
  command = plan

  variables {
    component = "kms"
  }

  override_data {
    target = data.aws_ssm_parameter.key_admin_role[0]
    values = {
      value = "arn:aws:iam::111111111111:role/dcp-diners-dev-connect-role-key-admin"
    }
  }

  # Rotación habilitada con periodo de 365 días (Req 4.1).
  assert {
    condition     = aws_kms_key.storage[0].enable_key_rotation == true
    error_message = "La CMK de almacenamiento debe tener la rotación habilitada (Req 4.1)."
  }

  assert {
    condition     = aws_kms_key.storage[0].rotation_period_in_days == 365
    error_message = "La CMK de almacenamiento debe rotar cada 365 días (Req 4.1)."
  }

  # Ventana de borrado de 30 días (Req 4.1).
  assert {
    condition     = aws_kms_key.storage[0].deletion_window_in_days == 30
    error_message = "La ventana de borrado de la CMK debe ser de 30 días (Req 4.1)."
  }

  # Alias con el patrón esperado alias/dcp/<scope>/<env>/<workload>/<purpose>.
  assert {
    condition     = aws_kms_alias.storage[0].name == "alias/dcp/diners/dev/connectwl/connect-storage"
    error_message = "El alias de la CMK no sigue el patrón alias/dcp/<domain>/<env>/<workload>/connect-storage (Req 4.1, L08)."
  }

  # Contrato SSM connect-kms-key-arn publicado con el nombre esperado (Req 4.4).
  assert {
    condition     = aws_ssm_parameter.connect_kms_key_arn[0].name == "/dcp/diners/dev/connectwl/config/connect-kms-key-arn"
    error_message = "El contrato SSM connect-kms-key-arn no tiene la ruta esperada (Req 4.4)."
  }

  # El módulo solo añade el tag Name (Req 2.6).
  assert {
    condition     = length(keys(aws_kms_key.storage[0].tags)) == 1 && contains(keys(aws_kms_key.storage[0].tags), "Name")
    error_message = "La CMK solo debe llevar el tag Name; el resto los inyecta el root (Req 2.6)."
  }

  assert {
    condition     = aws_kms_key.storage[0].tags["Name"] == "dcp-diners-dev-connectwl-kms-connect-storage"
    error_message = "El tag Name de la CMK no sigue el patrón de naming (Req 2.6, L07)."
  }
}

# --- Componente storage: endurecimiento del bucket, nombre y contrato SSM ---
# Req 5.1 (nombre determinista), 5.2 (BPA, ownership, versionado, SSE-KMS),
# 5.7 (contrato SSM), 2.6 (solo tag Name).
run "storage_endurece_bucket_y_publica_contrato" {
  command = plan

  variables {
    component                  = "storage"
    recordings_retention_days  = 30
    transcripts_retention_days = 30
    noncurrent_retention_days  = 30
  }

  override_data {
    target = data.aws_ssm_parameter.storage_kms_key_arn[0]
    values = {
      value = "arn:aws:kms:us-east-1:111111111111:key/abcd-1234"
    }
  }

  # Nombre del bucket determinista con el patrón de naming (Req 5.1).
  assert {
    condition     = startswith(aws_s3_bucket.storage[0].bucket, "dcp-diners-dev-connectwl-s3-connect-storage-use1-")
    error_message = "El nombre del bucket no sigue el patrón dcp-<domain>-<env>-<workload>-s3-connect-storage-<region>-<unique> (Req 5.1)."
  }

  assert {
    condition     = length(aws_s3_bucket.storage[0].bucket) <= 63
    error_message = "El nombre del bucket supera 63 caracteres (Req 5.1)."
  }

  # Los 4 ajustes de Block Public Access en true (Req 5.2).
  assert {
    condition = (
      aws_s3_bucket_public_access_block.storage[0].block_public_acls &&
      aws_s3_bucket_public_access_block.storage[0].block_public_policy &&
      aws_s3_bucket_public_access_block.storage[0].ignore_public_acls &&
      aws_s3_bucket_public_access_block.storage[0].restrict_public_buckets
    )
    error_message = "Los 4 ajustes de Block Public Access deben estar en true (Req 5.2)."
  }

  # Ownership BucketOwnerEnforced (Req 5.2). `rule` es un set: se extrae con one().
  assert {
    condition     = one(aws_s3_bucket_ownership_controls.storage[0].rule).object_ownership == "BucketOwnerEnforced"
    error_message = "El ownership del bucket debe ser BucketOwnerEnforced (Req 5.2)."
  }

  # Versionado Enabled (Req 5.2). versioning_configuration es un set: one().
  assert {
    condition     = one(aws_s3_bucket_versioning.storage[0].versioning_configuration).status == "Enabled"
    error_message = "El versionado del bucket debe estar Enabled (Req 5.2)."
  }

  # SSE-KMS con la CMK del contrato y bucket key (Req 5.2). rule y
  # apply_server_side_encryption_by_default son sets: se extraen con one().
  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.storage[0].rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "El cifrado por defecto del bucket debe ser aws:kms (Req 5.2)."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.storage[0].rule).bucket_key_enabled == true
    error_message = "El bucket key debe estar habilitado para SSE-KMS (Req 5.2)."
  }

  # Contrato SSM connect-storage-bucket-name publicado (Req 5.7).
  assert {
    condition     = aws_ssm_parameter.connect_storage_bucket_name[0].name == "/dcp/diners/dev/connectwl/config/connect-storage-bucket-name"
    error_message = "El contrato SSM connect-storage-bucket-name no tiene la ruta esperada (Req 5.7)."
  }

  # El módulo solo añade el tag Name al bucket (Req 2.6).
  assert {
    condition     = length(keys(aws_s3_bucket.storage[0].tags)) == 1 && contains(keys(aws_s3_bucket.storage[0].tags), "Name")
    error_message = "El bucket solo debe llevar el tag Name; el resto los inyecta el root (Req 2.6)."
  }
}

# --- Componente storage: la política de bucket niega transporte y llave -----
# Req 5.4 — DenyInsecureTransport, DenyWrongKmsKey, DenyNonKmsEncryption.
run "storage_politica_niega_transporte_y_llave" {
  command = plan

  variables {
    component                  = "storage"
    recordings_retention_days  = 30
    transcripts_retention_days = 30
    noncurrent_retention_days  = 30
  }

  override_data {
    target = data.aws_ssm_parameter.storage_kms_key_arn[0]
    values = {
      value = "arn:aws:kms:us-east-1:111111111111:key/abcd-1234"
    }
  }

  assert {
    condition = length([
      for s in data.aws_iam_policy_document.storage_bucket[0].statement : s.sid
      if s.sid == "DenyInsecureTransport" && s.effect == "Deny"
    ]) == 1
    error_message = "La política del bucket debe incluir un Deny DenyInsecureTransport (Req 5.4)."
  }

  assert {
    condition = length([
      for s in data.aws_iam_policy_document.storage_bucket[0].statement : s.sid
      if s.sid == "DenyWrongKmsKey" && s.effect == "Deny"
    ]) == 1
    error_message = "La política del bucket debe incluir un Deny DenyWrongKmsKey (Req 5.4)."
  }

  assert {
    condition = length([
      for s in data.aws_iam_policy_document.storage_bucket[0].statement : s.sid
      if s.sid == "DenyNonKmsEncryption" && s.effect == "Deny"
    ]) == 1
    error_message = "La política del bucket debe incluir un Deny DenyNonKmsEncryption (Req 5.4)."
  }
}

# --- Componente instance: flags, ambas storage configs y contratos SSM ------
# Req 6.1 (flags), 6.3 (dos storage configs S3+KMS), 6.7 (3 contratos SSM),
# 2.6 (solo tag Name).
run "instance_flags_storage_configs_y_contratos" {
  command = plan

  variables {
    component      = "instance"
    instance_alias = "dcp-diners-dev-connect"
  }

  override_data {
    target = data.aws_ssm_parameter.instance_kms_key_arn[0]
    values = {
      value = "arn:aws:kms:us-east-1:111111111111:key/abcd-1234"
    }
  }

  override_data {
    target = data.aws_ssm_parameter.instance_storage_bucket_name[0]
    values = {
      value = "dcp-diners-dev-connectwl-s3-connect-storage-use1-abcdef123456"
    }
  }

  # Flags de la instancia (Req 6.1): SAML, llamadas entrantes/salientes, logs de
  # flujos y Contact Lens habilitados.
  assert {
    condition     = aws_connect_instance.this[0].identity_management_type == "SAML"
    error_message = "La instancia debe usar identity_management_type = SAML por defecto (Req 6.1)."
  }

  assert {
    condition = (
      aws_connect_instance.this[0].inbound_calls_enabled &&
      aws_connect_instance.this[0].outbound_calls_enabled &&
      aws_connect_instance.this[0].contact_flow_logs_enabled &&
      aws_connect_instance.this[0].contact_lens_enabled
    )
    error_message = "La instancia debe tener llamadas entrantes/salientes, logs de flujos y Contact Lens habilitados (Req 6.1)."
  }

  assert {
    condition     = aws_connect_instance.this[0].instance_alias == "dcp-diners-dev-connect"
    error_message = "El alias de la instancia no coincide con el valor de entrada (Req 6.1)."
  }

  # Configuración de grabaciones de llamada: S3 + KMS (Req 6.3).
  assert {
    condition     = aws_connect_instance_storage_config.call_recordings[0].resource_type == "CALL_RECORDINGS"
    error_message = "Debe existir una storage config CALL_RECORDINGS (Req 6.3)."
  }

  assert {
    condition     = aws_connect_instance_storage_config.call_recordings[0].storage_config[0].s3_config[0].encryption_config[0].encryption_type == "KMS"
    error_message = "La storage config de grabaciones debe cifrar con KMS (Req 6.3)."
  }

  # Configuración de transcripciones de chat: S3 + KMS (Req 6.3).
  assert {
    condition     = aws_connect_instance_storage_config.chat_transcripts[0].resource_type == "CHAT_TRANSCRIPTS"
    error_message = "Debe existir una storage config CHAT_TRANSCRIPTS (Req 6.3)."
  }

  assert {
    condition     = aws_connect_instance_storage_config.chat_transcripts[0].storage_config[0].s3_config[0].encryption_config[0].encryption_type == "KMS"
    error_message = "La storage config de transcripciones debe cifrar con KMS (Req 6.3)."
  }

  # Los tres contratos SSM de la instancia publicados (Req 6.7).
  assert {
    condition     = aws_ssm_parameter.connect_instance_id[0].name == "/dcp/diners/dev/connectwl/config/connect-instance-id"
    error_message = "Falta el contrato SSM connect-instance-id o su ruta es incorrecta (Req 6.7)."
  }

  assert {
    condition     = aws_ssm_parameter.connect_instance_arn[0].name == "/dcp/diners/dev/connectwl/config/connect-instance-arn"
    error_message = "Falta el contrato SSM connect-instance-arn o su ruta es incorrecta (Req 6.7)."
  }

  assert {
    condition     = aws_ssm_parameter.connect_instance_alias[0].name == "/dcp/diners/dev/connectwl/config/connect-instance-alias"
    error_message = "Falta el contrato SSM connect-instance-alias o su ruta es incorrecta (Req 6.7)."
  }

  # El módulo solo añade el tag Name a la instancia (Req 2.6).
  assert {
    condition     = length(keys(aws_connect_instance.this[0].tags)) == 1 && contains(keys(aws_connect_instance.this[0].tags), "Name")
    error_message = "La instancia solo debe llevar el tag Name; el resto los inyecta el root (Req 2.6)."
  }
}

# --- Componente instance: log group con CMK y retención (Req 6.5 / DD-6) ----
run "instance_log_group_con_cmk_y_retencion" {
  command = plan

  variables {
    component               = "instance"
    instance_alias          = "dcp-diners-dev-connect"
    flow_log_retention_days = 365
  }

  override_data {
    target = data.aws_ssm_parameter.instance_kms_key_arn[0]
    values = {
      value = "arn:aws:kms:us-east-1:111111111111:key/abcd-1234"
    }
  }

  override_data {
    target = data.aws_ssm_parameter.instance_storage_bucket_name[0]
    values = {
      value = "dcp-diners-dev-connectwl-s3-connect-storage-use1-abcdef123456"
    }
  }

  # Nombre nativo /aws/connect/<alias> (DD-6).
  assert {
    condition     = aws_cloudwatch_log_group.flow_logs[0].name == "/aws/connect/dcp-diners-dev-connect"
    error_message = "El log group de flujos debe llamarse /aws/connect/<alias> (Req 6.5, DD-6)."
  }

  # Retención tomada del input (Req 6.5).
  assert {
    condition     = aws_cloudwatch_log_group.flow_logs[0].retention_in_days == 365
    error_message = "La retención del log group debe venir de flow_log_retention_days (Req 6.5)."
  }

  # Cifrado con la CMK de almacenamiento del contrato SSM (Req 6.5).
  assert {
    condition     = aws_cloudwatch_log_group.flow_logs[0].kms_key_id == "arn:aws:kms:us-east-1:111111111111:key/abcd-1234"
    error_message = "El log group debe cifrarse con la CMK del contrato connect-kms-key-arn (Req 6.5)."
  }
}
