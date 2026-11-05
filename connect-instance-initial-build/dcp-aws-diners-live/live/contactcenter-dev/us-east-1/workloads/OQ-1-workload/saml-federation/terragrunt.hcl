# =============================================================================
# Stack: saml-federation — federacion SAML de la instancia Amazon Connect con
#        Entra ID (SAML_Module: connect/connect-saml-federation).
# Estado:  diners/contactcenter-dev/us-east-1/workloads/<OQ-1>/saml-federation/terraform.tfstate
#          (la clave de estado la calcula el root terragrunt.hcl a partir de la
#          ruta relativa; este archivo no la escribe — L05).
# Modulo:  connect/connect-saml-federation (SAML_Module). A diferencia de
#          Connect_Module (kms/storage/instance) y Profiles_Module
#          (kms-customer-profiles/customer-profiles), el SAML_Module NO tiene un
#          switch `component`: crea siempre los dos proveedores IAM SAML (admin y
#          agente), el rol de federacion con permission boundary y la politica de
#          una sola accion (connect:GetFederationToken). Por eso este stack no
#          declara `component` (Requisitos 10.1, 10.2, 10.3).
#
# Sexto y ultimo en el orden de aplicacion (Requisito 12.7): kms -> storage ->
# kms-customer-profiles -> instance -> customer-profiles -> saml-federation.
# Declara `dependencies { paths = ["../instance"] }` SOLO para ordenar el apply
# (los `dependencies` de Terragrunt transportan orden, no datos — DD-3, principio
# "least coupling"). No lleva `mock_outputs`: un mock nunca debe habilitar un
# apply, y este modulo necesita los valores SSM reales (el ARN de la instancia y
# los metadatos) que leen sus data sources. La ordenacion uno-a-uno del pipeline
# es lo que garantiza que la instancia y los contratos existan antes de este
# apply (Requisitos 12.7, 1.1).
#
# Lee tres contratos SSM que publican stacks anteriores, a traves de los locals /
# data sources del modulo y sin referenciarlos aqui (Requisito 10.4). El modulo
# construye las rutas dentro de naming.tf a partir de `domain`, `environment` y
# `workload` (base /dcp/<domain>/<env>/<workload>/config):
#   - `connect-instance-arn`   (publicado por el stack instance; Requisito 6.7)
#   - `saml-metadata-admin`    (metadatos SAML de la app admin de Entra ID; OQ-9)
#   - `saml-metadata-agent`    (metadatos SAML de la app agente de Entra ID; OQ-9)
# Aqui no se referencia ningun ARN de instancia ni documento de metadatos; la
# lectura la hace el modulo.
#
# Este stack NO publica contratos SSM (no hay consumidores aguas abajo), por lo
# que no comparte las restricciones de orden de PR de los stacks publicadores.
#
# Reglas que cumple este archivo (iac-core-rules, Requisitos 2.1, 2.7, 13.1,
# 13.2): sin IDs de cuenta, ARNs, CIDRs ni literales de entorno. El `source`
# apunta al repo de modulos por SHA de 40 hex. `domain`, `environment`,
# `workload`, `region_code` y `saml_resource_code` llegan por los inputs del root
# desde los Hierarchy_Files (DD-3): viven en env.hcl `stack_inputs`
# (`saml_resource_code` como <OQ-3>) y NO se escriben aqui. El permission
# boundary, la audiencia SAML y el recurso de la politica los construye el modulo.
# Por eso `inputs` queda vacio: el SAML_Module no tiene switch `component` y el
# unico input propio del stack (`saml_resource_code`) se fusiona desde el root.
#
# Adopcion (DD-4): el mecanismo `generate "import"` lo aporta el root
# terragrunt.hcl, que emite import.tf solo si env.hcl define
# adopt."saml-federation". Hoy `adopt` esta vacio, asi que no se genera import.tf.
# Este archivo de stack NO declara bloques `import`.
#
# Lock file: `.terraform.lock.hcl` debe commitearse (Requisito 1.6, iac-core-
# rules §4), pero se genera desde el mirror Nexus aprobado en el pipeline. No se
# puede producir offline aqui; lo genera el runner con `terraform init` contra el
# mirror y el PR lo incluye.
# =============================================================================

# -----------------------------------------------------------------------------
# [Blocked: OQ-3, OQ-9]
# BLOQUEANTE — OQ-3 (saml_resource_code). El codigo de recurso del proveedor IAM
# SAML (propuesto "saml") no esta registrado en catalogos-cloud.yaml. Llega por
# env.hcl `stack_inputs` como placeholder <OQ-3>; el SAML_Module lo exige
# (validation obligatoria) y el plan real no pasa hasta que se fije el codigo
# aprobado. No se inventa aqui.
#
# BLOQUEANTE — OQ-9 (metadatos de Entra ID). El modulo lee los contratos SSM
# `saml-metadata-admin` y `saml-metadata-agent` (metadatos SAML de las dos apps
# empresariales de Entra ID). Hasta que el publicador registre los metadatos
# reales (y, en dev, se validen), el PR no mergea. El modulo valida que los
# metadatos contengan EntityDescriptor; no se inventan documentos SAML.
#
# BLOQUEANTE — SHA del modulo. El modulo connect/connect-saml-federation NO esta
# aun registrado en dcp-terraform-modules/compatibility.yaml (solo hay modulos de
# ejemplo). El `ref` debe ser un SHA de 40 hex de un tag de release firmado y
# registrado en compatibility.yaml (iac-core-rules §4, Requisito 2.1). El valor de
# abajo es un PLACEHOLDER (40 ceros); hay que reemplazarlo por el SHA real
# registrado ANTES del merge. Hasta entonces scan_stack_files.py falla por diseno
# (regla module-sha: "SHA no esta registrado en compatibility.yaml"). NO se debe
# inventar un SHA realista ni autorregistrarlo en compatibility.yaml.
# -----------------------------------------------------------------------------

include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

terraform {
  # TODO(OQ): reemplazar el SHA placeholder por el SHA de 40 hex del release
  # firmado de connect/connect-saml-federation registrado en compatibility.yaml.
  source = "git::ssh://git@github.com/Diners/dcp-terraform-modules.git//modules/connect/connect-saml-federation?ref=0000000000000000000000000000000000000000"
}

dependencies {
  # Orden de apply unicamente (sin mock_outputs): reproduce el orden especificado
  # kms -> storage -> kms-customer-profiles -> instance -> customer-profiles ->
  # saml-federation. Los contratos que consume (connect-instance-arn,
  # saml-metadata-admin, saml-metadata-agent) los lee el modulo desde SSM, no por
  # dependency.
  paths = ["../instance"]
}

inputs = {
  # Vacio: el SAML_Module no tiene switch `component`. Su unico input propio del
  # stack, `saml_resource_code`, llega por env.hcl `stack_inputs` (<OQ-3>) y lo
  # fusiona el root. El resto (domain, environment, workload, region_code) lo
  # aportan los Hierarchy_Files via el root (DD-3).
}
