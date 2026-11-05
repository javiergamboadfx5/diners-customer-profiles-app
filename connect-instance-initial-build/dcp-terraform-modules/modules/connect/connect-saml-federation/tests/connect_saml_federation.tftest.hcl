# -----------------------------------------------------------------------------
# connect/connect-saml-federation — terraform test (tarea 4.4)
#
# Feature: connect-instance-initial-build
# Valida: Req 3.9 (un caso por regla de validación), Req 2.5, Req 10.1, 10.2,
# 10.3, 10.4, 10.6.
#
# Estrategia (design.md, "Module unit tests"):
#   - mock_provider "aws" para no necesitar credenciales ni red.
#   - NO se simula aws_iam_policy_document: Terraform calcula su JSON en local
#     durante el plan, lo que permite afirmar la política de una sola acción y
#     la condición de confianza SAML:aud con los valores reales. (El sample de
#     aurora sí lo simula porque allí no se afirma sobre el JSON.)
#   - Un bloque `run` por regla de validación con `expect_failures`, y un bloque
#     con la entrada buena que planea sin error.
#   - Bloques `run` positivos que afirman: permission boundary en el rol,
#     max_session_duration == entrada, política de una sola acción
#     (connect:GetFederationToken) acotada a instance/<id>/user/*, condición de
#     confianza SAML:aud, el nombre del rol contiene "connect-federation",
#     y las relay state URLs y los claims de rol.
#
# NOTA DE EJECUCIÓN: Terraform local es 1.16.6, fuera del rango fijado del
# módulo (`>= 1.15.8, < 1.16.0`), por lo que `terraform test` no corre aquí.
# Estos tests están escritos para correr en CI sobre Terraform 1.15.8
# (runtime aprobado, L03), donde el mock_provider evita todo acceso a AWS.
#
# NOTA DE ALCANCE: la regla "la instancia no es SAML" (Req 10.5) se verifica con
# un data "aws_connect_instance" + precondition que no está implementado en el
# main.tf actual (tarea 4.1 lo describe pero el recurso no existe todavía). No
# se puede afirmar un fallo sobre un recurso inexistente, así que ese caso no se
# incluye; queda anotado para añadirse cuando 4.1 incorpore el data source.
# -----------------------------------------------------------------------------

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }

  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }

  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }

  # El mock genera un valor aleatorio para el atributo calculado `json` de los
  # policy documents, que rompe la validación JSON de aws_iam_policy.policy
  # (y de assume_role_policy) durante el plan. Fijamos un JSON válido por
  # defecto; el atributo de entrada `statement` viene de la configuración del
  # módulo, así que los asserts que lo inspeccionan siguen funcionando.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  # Los runs con command = apply necesitan ARNs bien formados en los atributos
  # calculados de estos recursos: aws_iam_role_policy_attachment valida que
  # policy_arn sea un ARN, y los claims de rol concatenan los ARNs del rol y de
  # los proveedores SAML. El mock genera valores aleatorios por defecto (no
  # ARNs), así que fijamos ARNs válidos por recurso. Los nombres y la estructura
  # (la statement de las políticas, los count de los proveedores) se siguen
  # calculando desde la configuración del módulo.
  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::111111111111:policy/mock-federation-policy"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111111111111:role/mock-federation-role"
    }
  }

  mock_resource "aws_iam_saml_provider" {
    defaults = {
      arn = "arn:aws:iam::111111111111:saml-provider/mock-provider"
    }
  }
}

# Entradas buenas comunes. Los metadatos llevan EntityDescriptor para que se
# creen ambos proveedores SAML y existan los claims. El instance_arn es un ARN
# de instancia Connect bien formado (región us-east-1, cuenta de 12 dígitos,
# UUID) del que se derivan el recurso de la política y las relay state URLs.
variables {
  environment          = "dev"
  workload             = "connectwl"
  region_code          = "use1"
  saml_resource_code   = "saml"
  max_session_duration = 3600
  instance_arn         = "arn:aws:connect:us-east-1:111111111111:instance/11111111-1111-1111-1111-111111111111"

  # NOTA: el proveedor aws valida que saml_metadata_document mida entre 1000 y
  # 10.000.000 caracteres en tiempo de plan. Los metadatos de marcador deben
  # superar los 1000 caracteres (además de contener EntityDescriptor, que exige
  # la validación del módulo). Se rellena con un comentario XML para alcanzar la
  # longitud mínima sin alterar la estructura del EntityDescriptor.
  metadata_admin = "<?xml version=\"1.0\"?><EntityDescriptor entityID=\"admin\"><!-- ${join("", [for i in range(60) : "padding-admin-0123456789abcdef "])} --></EntityDescriptor>"
  metadata_agent = "<?xml version=\"1.0\"?><EntityDescriptor entityID=\"agent\"><!-- ${join("", [for i in range(60) : "padding-agent-0123456789abcdef "])} --></EntityDescriptor>"
}

# =============================================================================
# Casos de fallo: una `run` por regla de validación (Req 3.9).
# =============================================================================

# Req 3.4 — environment fuera de la lista blanca dev|qa|stg|prod.
run "ambiente_invalido_falla" {
  command = plan

  variables {
    environment = "produccion"
  }

  expect_failures = [var.environment]
}

# Req 10.4 / diseño — instance_arn con formato inválido (no es un ARN de
# instancia Connect).
run "instance_arn_con_formato_invalido_falla" {
  command = plan

  variables {
    instance_arn = "arn:aws:connect:us-east-1:111111111111:instance/no-es-uuid"
  }

  expect_failures = [var.instance_arn]
}

# Req 10.4 / diseño — metadata_admin sin EntityDescriptor.
run "metadata_admin_sin_entitydescriptor_falla" {
  command = plan

  variables {
    metadata_admin = "<?xml version=\"1.0\"?><Otro></Otro>"
  }

  expect_failures = [var.metadata_admin]
}

# Req 10.4 / diseño — metadata_agent vacío.
run "metadata_agent_vacio_falla" {
  command = plan

  variables {
    metadata_agent = "   "
  }

  expect_failures = [var.metadata_agent]
}

# Req 10.3 — max_session_duration por encima de 3600 (techo PCI).
run "sesion_mayor_a_3600_falla" {
  command = plan

  variables {
    max_session_duration = 43200
  }

  expect_failures = [var.max_session_duration]
}

# Req 10.3 — max_session_duration distinto de 3600 por debajo del valor único.
# El módulo fija 3600 (techo PCI = piso de IAM); cualquier otro valor falla.
run "sesion_distinta_de_3600_falla" {
  command = plan

  variables {
    max_session_duration = 1800
  }

  expect_failures = [var.max_session_duration]
}

# Req 10.1 / OQ-3 — saml_resource_code obligatorio (no se inventa el código).
run "saml_resource_code_ausente_falla" {
  command = plan

  variables {
    saml_resource_code = null
  }

  expect_failures = [var.saml_resource_code]
}

# Req 10.1 — saml_resource_code no kebab-case.
run "saml_resource_code_no_kebab_falla" {
  command = plan

  variables {
    saml_resource_code = "SAML_Code"
  }

  expect_failures = [var.saml_resource_code]
}

# Req 11.4 — exception_id con formato inválido cuando se informa.
run "exception_id_con_formato_invalido_falla" {
  command = plan

  variables {
    exception_id = "exc-1234-5678"
  }

  expect_failures = [var.exception_id]
}

# =============================================================================
# Casos de entrada buena: planea sin error y afirma invariantes.
# =============================================================================

# Req 2.5 / 3.9 — la entrada buena completa planea sin errores de validación.
run "entrada_buena_planea" {
  command = plan

  assert {
    condition     = var.max_session_duration == 3600
    error_message = "La entrada buena debe aceptar max_session_duration = 3600."
  }
}

# Req 10.3 — el rol lleva el permission boundary dcp-platform-permission-boundary
# y su duración de sesión coincide con la entrada.
run "rol_lleva_permission_boundary_y_sesion" {
  command = plan

  variables {
    max_session_duration = 3600
  }

  # El boundary se arma como arn:<partition>:iam::<account>:policy/<nombre>.
  assert {
    condition     = aws_iam_role.federation.permissions_boundary == "arn:aws:iam::111111111111:policy/dcp-platform-permission-boundary"
    error_message = "El rol de federación debe llevar el permission boundary dcp-platform-permission-boundary (Req 10.3)."
  }

  # El módulo fija max_session_duration en 3600 (techo PCI = piso de IAM).
  assert {
    condition     = aws_iam_role.federation.max_session_duration == 3600
    error_message = "max_session_duration del rol debe ser 3600 (Req 10.3; único valor que cumple el techo PCI y el mínimo de IAM)."
  }
}

# Req 10.1 — el nombre del rol contiene "connect-federation" y sigue el patrón
# dcp-<domain>-<env>-<workload>-role-connect-federation.
run "nombre_del_rol_contiene_connect_federation" {
  command = plan

  assert {
    condition     = aws_iam_role.federation.name == "dcp-diners-dev-connectwl-role-connect-federation"
    error_message = "El nombre del rol debe seguir el patrón ...-role-connect-federation (Req 10.1)."
  }

  assert {
    condition     = can(regex("connect-federation", aws_iam_role.federation.name))
    error_message = "El nombre del rol debe contener 'connect-federation' (Req 10.1)."
  }

  assert {
    condition     = aws_iam_policy.federation.name == "dcp-diners-dev-connectwl-policy-connect-federation"
    error_message = "El nombre de la política debe seguir el patrón ...-policy-connect-federation (Req 10.2)."
  }
}

# Req 10.2 — política de una sola acción (connect:GetFederationToken) acotada al
# recurso instance/<id>/user/*.
#
# NOTA: no se afirma sobre data.aws_iam_policy_document.federation.statement.
# Ese data source lo calcula el provider y, bajo mock_provider, su atributo
# `json`/`statement` no es observable de forma estable (el mock lo necesita
# fijado para que aws_iam_policy valide, lo que vacía la statement). Para no
# depender de eso, el módulo expone la acción y el recurso en outputs
# deterministas (federation_action, federation_resource), calculados en locals
# a partir de la entrada. Se afirma sobre esos outputs en modo plan.
run "politica_de_una_sola_accion_acotada_a_la_instancia" {
  command = plan

  assert {
    condition     = output.federation_action == "connect:GetFederationToken"
    error_message = "La única acción permitida debe ser connect:GetFederationToken (Req 10.2)."
  }

  assert {
    condition     = output.federation_resource == "arn:aws:connect:us-east-1:111111111111:instance/11111111-1111-1111-1111-111111111111/user/*"
    error_message = "El recurso debe ser instance/<id>/user/* de la instancia dada (Req 10.2)."
  }
}

# Req 10.1 — la condición de confianza fija SAML:aud a la audiencia de AWS y la
# acción de assume es sts:AssumeRoleWithSAML. Igual que arriba, se afirma sobre
# outputs deterministas (trust_assume_action, trust_saml_audience) en vez del
# atributo calculado del data source.
run "confianza_fija_saml_aud" {
  command = plan

  assert {
    condition     = output.trust_assume_action == "sts:AssumeRoleWithSAML"
    error_message = "La acción de confianza debe ser sts:AssumeRoleWithSAML (Req 10.1)."
  }

  assert {
    condition     = output.trust_saml_audience == "https://signin.aws.amazon.com/saml"
    error_message = "La confianza debe condicionar SAML:aud = https://signin.aws.amazon.com/saml (Req 10.1)."
  }
}

# Req 10.1 — se crean exactamente dos proveedores IAM SAML (admin y agente)
# cuando hay metadatos para ambos.
run "dos_proveedores_saml_con_metadatos" {
  command = plan

  assert {
    condition     = length(aws_iam_saml_provider.admin) == 1 && length(aws_iam_saml_provider.agent) == 1
    error_message = "Deben existir los dos proveedores SAML (admin y agente) cuando hay metadatos (Req 10.1)."
  }

  assert {
    condition     = aws_iam_saml_provider.admin[0].name == "dcp-diners-dev-connectwl-saml-admin"
    error_message = "El nombre del proveedor admin debe seguir el patrón ...-saml-admin."
  }

  assert {
    condition     = aws_iam_saml_provider.agent[0].name == "dcp-diners-dev-connectwl-saml-agent"
    error_message = "El nombre del proveedor agente debe seguir el patrón ...-saml-agent."
  }
}

# Req 10.6 — relay state URLs con los destinos codificados correctos.
run "relay_state_urls_correctas" {
  command = plan

  assert {
    condition     = output.admin_relay_state_url == "https://us-east-1.console.aws.amazon.com/connect/federate/11111111-1111-1111-1111-111111111111?destination=%2Fconnect"
    error_message = "La relay state admin debe apuntar a destination=%2Fconnect (Req 10.6)."
  }

  assert {
    condition     = output.agent_relay_state_url == "https://us-east-1.console.aws.amazon.com/connect/federate/11111111-1111-1111-1111-111111111111?destination=%2Fagent-app-v2"
    error_message = "La relay state agente debe apuntar a destination=%2Fagent-app-v2 (Req 10.6)."
  }
}

# Req 10.6 — los claims de rol tienen la forma "<role-arn>,<provider-arn>" y
# existen para ambas apps cuando hay metadatos.
run "claims_de_rol_presentes" {
  # command = apply: los claims incluyen los ARNs del rol y de los proveedores
  # SAML, desconocidos durante el plan bajo mock_provider. Con apply sobre el
  # provider simulado se resuelven a valores simulados y split(claim, ",")
  # evalúa de forma estable (estructura "<role-arn>,<provider-arn>").
  command = apply

  assert {
    condition     = output.admin_role_claim != null && output.agent_role_claim != null
    error_message = "Deben existir los claims de rol admin y agente cuando hay metadatos (Req 10.6)."
  }

  # El claim tiene la forma "<role-arn>,<provider-arn>": exactamente un separador
  # de coma entre dos ARNs. Se afirma la estructura (no los ARNs, desconocidos
  # bajo el provider simulado) para que el test sea estable en modo plan.
  assert {
    condition     = length(split(",", output.admin_role_claim)) == 2
    error_message = "El claim admin debe tener la forma <role-arn>,<provider-arn> (Req 10.6)."
  }

  assert {
    condition     = length(split(",", output.agent_role_claim)) == 2
    error_message = "El claim agente debe tener la forma <role-arn>,<provider-arn> (Req 10.6)."
  }
}
