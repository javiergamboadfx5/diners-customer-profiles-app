# =============================================================================
# env.hcl — ambiente contactcenter-dev.
#
# DD-3: los valores que varian por Environment (retencion, cde_scope, alias,
# identity_management_type, expiracion de perfiles, etc.) viven aqui, en el
# archivo de mayor alcance que los gobierna. El root terragrunt.hcl los fusiona
# en inputs (local.stack_inputs), de modo que ningun archivo de stack escribe un
# valor especifico del Environment (Requisito 13.2). Asi los terragrunt.hcl de los
# stacks quedan byte-identicos entre contactcenter-<env> y el codigo dev es
# promovible sin cambios (Requisito 13).
#
# Los valores pendientes de decision quedan como placeholders <OQ-n>: el modulo
# los valida y el plan falla hasta que la pregunta abierta se resuelva. No se
# inventan valores de catalogo ni de cumplimiento.
# =============================================================================
locals {
  environment = "dev"

  # ---------------------------------------------------------------------------
  # stack_inputs (DD-3): se fusionan al final de inputs en el root.
  # ---------------------------------------------------------------------------
  stack_inputs = {
    # --- Instancia / identidad -----------------------------------------------
    # OQ-8: alias de la instancia dev (sugerido "dinersclub-dev"). Debe cumplir
    # ^[a-z0-9]([a-z0-9-]{0,60}[a-z0-9])?$ (lo valida Connect_Module).
    instance_alias = "<OQ-8>"

    # Federacion SAML con Entra ID desde el primer apply (Requisito 6.1). Valor
    # fijo, no es una decision pendiente.
    identity_management_type = "SAML"

    # exception_id solo se usa si identity_management_type no fuese SAML en dev
    # (Requisito 3.6). Con SAML no se requiere; se deja vacio.
    exception_id = ""

    # --- Federacion SAML: codigo de recurso del proveedor IAM SAML (OQ-3) ----
    # saml_resource_code es obligatorio para SAML_Module (Requisito 10.1); el
    # modulo no lo inventa y falla el plan si no se define. No tiene fuente en el
    # root (no es tag ni valor de catalogo publicado), asi que llega por aqui,
    # desde stack_inputs, como placeholder <OQ-3>. Codigo propuesto "saml",
    # pendiente de registro en catalogos-cloud.yaml. TODO(OQ-3): reemplazar por el
    # codigo aprobado una vez registrado en el catalogo.
    saml_resource_code = "<OQ-3>"

    # --- Retencion del bucket de grabaciones/transcripciones (OQ-7) ----------
    # Dias de retencion aprobados por Cumplimiento. Enteros >= 1 (Requisito 5.5).
    # TODO(OQ-7): reemplazar los placeholders por los dias aprobados.
    recordings_retention_days  = "<OQ-7>"
    transcripts_retention_days = "<OQ-7>"
    noncurrent_retention_days  = "<OQ-7>"

    # --- Logs de flujo de contacto y alcance CDE (OQ-6) ----------------------
    # flow_log_retention_days: valor L14 segun DataClassification, nunca 0
    # ("never expire" prohibido, Requisito 6.5). Debe ser un valor permitido por
    # CloudWatch Logs. TODO(OQ-6): fijar segun la decision de Ciberseguridad.
    flow_log_retention_days = "<OQ-6>"

    # cde_scope: si las llamadas o chats pueden portar PAN (Requisito 11.3, DR). Lo
    # decide Ciberseguridad. TODO(OQ-6): true/false. Requerido: el plan falla hasta
    # que se defina.
    cde_scope = "<OQ-6>"

    # security_coverage_ref: referencia al PR en dcp-aws-security-live que habilita
    # CloudTrail data events y Macie para el bucket (DD-2). Obligatorio no vacio
    # solo cuando cde_scope = true. Vacio si cde_scope = false.
    security_coverage_ref = ""

    # --- Customer Profiles (OQ-10) -------------------------------------------
    # default_expiration_days: entero 1..1098 aprobado por Cumplimiento
    # (Requisito 3.8, 8.1). TODO(OQ-10): fijar el valor aprobado.
    default_expiration_days = "<OQ-10>"

    # Data store desactivado por defecto (Requisito 8.3; conflicto documentado con
    # DFX5). Se habilita solo con una referencia de aprobacion de Cumplimiento.
    enable_data_store       = false
    data_store_approval_ref = ""
  }

  # ---------------------------------------------------------------------------
  # adopt (DD-4): mapa opcional por stack. Cuando define adopt.<stack>, el root
  # genera import.tf con los pares to/id para adoptar recursos existentes
  # (Requisitos 6.8, 8.6). Vacio = no se genera import.tf en ningun stack.
  # ---------------------------------------------------------------------------
  adopt = {}
}
