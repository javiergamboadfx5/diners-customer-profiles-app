# =============================================================================
# Stack: instance — instancia Amazon Connect del contact center (Connect_Module).
# Estado:  diners/contactcenter-dev/us-east-1/workloads/<OQ-1>/instance/terraform.tfstate
#          (la clave de estado la calcula el root terragrunt.hcl a partir de la
#          ruta relativa; este archivo no la escribe — L05).
# Módulo:  connect/connect-instance, component = "instance" (mismo Connect_Module
#          y mismo SHA que los stacks kms y storage; un módulo sirve a kms,
#          storage e instance a través del switch `component`).
#
# Cuarto en el orden de aplicación (Requisito 12.7): kms -> storage ->
# kms-customer-profiles -> instance -> customer-profiles -> saml-federation.
# Por eso declara `dependencies { paths = ["../kms-customer-profiles"] }` SOLO
# para ordenar el apply (los `dependencies` de Terragrunt transportan orden, no
# datos — DD-3, principio "least coupling"). No lleva `mock_outputs`: un mock
# nunca debe habilitar un apply, y este primer apply necesita los valores SSM
# reales que lee el módulo. Esta instancia NO consume el contrato de
# kms-customer-profiles; el `depends` únicamente reproduce el orden de aplicación
# especificado. La ordenación uno-a-uno del pipeline es lo que lo permite
# (Requisitos 12.7, 12.9).
#
# Lee los contratos SSM de storage que publican los stacks anteriores, a través
# de los data sources del módulo y sin fallback (si falta un parámetro el plan
# falla — Requisito 6.4):
#   - `connect-kms-key-arn`      (publicado por el stack kms)
#   - `connect-storage-bucket-name` (publicado por el stack storage)
# Aquí no se referencia ningún ARN ni nombre de bucket; la lectura la hace el
# módulo con sus data sources a partir de `domain`, `environment` y `workload`.
#
# Publica los 3 contratos SSM de la instancia (String) que leen los stacks
# `customer-profiles` (dominio, vía `connect-instance-arn`) y `saml-federation`
# (Requisitos 6.7, 1.1):
#   - `connect-instance-id`
#   - `connect-instance-arn`
#   - `connect-instance-alias`
# Por publicar contratos, este stack mergea en un PR posterior a los que aplica
# (kms, storage, kms-customer-profiles) y anterior y separado de los que los
# consumen (customer-profiles, saml-federation) — iac-core-rules §3.
#
# Reglas que cumple este archivo (iac-core-rules, Requisitos 2.1, 2.7, 13.1,
# 13.2): sin IDs de cuenta, ARNs, CIDRs ni literales de entorno. El `source`
# apunta al repo de módulos por SHA de 40 hex. `environment`, `workload`,
# `region_code`, `instance_alias`, `identity_management_type`, retención y
# `flow_log_retention_days` llegan por los inputs del root desde los
# Hierarchy_Files (DD-3): viven en env.hcl `stack_inputs` (el alias como <OQ-8>)
# y NO se escriben aquí. Las rutas SSM se construyen dentro del módulo.
#
# Adopción (Requisito 6.8, DD-4): el mecanismo `generate "import"` lo aporta el
# root terragrunt.hcl, que emite import.tf solo si env.hcl define
# adopt."instance". Un pre-check (aws connect list-instances) que encuentre una
# instancia con el alias objetivo ya existente poblará `adopt.instance` con los
# pares `to`/`id` para adoptarla en lugar de crearla; de lo contrario env.hcl
# deja `adopt` vacío y no se genera import.tf. Este archivo de stack NO declara
# bloques `import` — la adopción es declarativa vía adopt.instance en env.hcl.
#
# Lock file: `.terraform.lock.hcl` debe commitearse (Requisito 1.6, iac-core-
# rules §4), pero se genera desde el mirror Nexus aprobado en el pipeline. No se
# puede producir offline aquí; lo genera el runner con `terraform init` contra el
# mirror y el PR lo incluye.
# =============================================================================

# -----------------------------------------------------------------------------
# [Blocked: OQ-2, OQ-8]
# BLOQUEANTE — OQ-8 (instance_alias). El alias de la instancia llega por env.hcl
# `stack_inputs` como placeholder <OQ-8>. El módulo lo valida contra la regla del
# alias (Requisito 6.5/3.1) y el plan real no pasa hasta que se fije el valor
# definitivo. No se inventa aquí.
#
# BLOQUEANTE — OQ-2 (cuenta/prerequisitos de red y acceso). Este stack se
# mantiene SIN MERGEAR hasta confirmar los prerequisitos de usuarios de red y
# acceso de cuenta de `diners-flujos-tobe` v1.68. Mientras no se confirmen, el PR
# no mergea aunque el plan especulativo se genere.
#
# BLOQUEANTE — SHA del módulo. El módulo connect/connect-instance NO está aún
# registrado en dcp-terraform-modules/compatibility.yaml (solo hay módulos de
# ejemplo). El `ref` debe ser un SHA de 40 hex de un tag de release firmado y
# registrado en compatibility.yaml (iac-core-rules §4, Requisito 2.1). El valor
# de abajo es un PLACEHOLDER (40 ceros); hay que reemplazarlo por el SHA real
# registrado ANTES del merge. Hasta entonces scan_stack_files.py falla por diseño
# (regla module-sha: "SHA no está registrado en compatibility.yaml"). NO se debe
# inventar un SHA realista ni autorregistrarlo en compatibility.yaml.
# -----------------------------------------------------------------------------

include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

terraform {
  # TODO(OQ): reemplazar el SHA placeholder por el SHA de 40 hex del release
  # firmado de connect/connect-instance registrado en compatibility.yaml.
  source = "git::ssh://git@github.com/Diners/dcp-terraform-modules.git//modules/connect/connect-instance?ref=0000000000000000000000000000000000000000"
}

dependencies {
  # Orden de apply únicamente (sin mock_outputs): reproduce el orden especificado
  # kms -> storage -> kms-customer-profiles -> instance -> ... Esta instancia no
  # consume el contrato de kms-customer-profiles; el `depends` solo transporta
  # orden. Los contratos de storage que sí consume (connect-kms-key-arn,
  # connect-storage-bucket-name) los lee el módulo desde SSM, no por dependency.
  paths = ["../kms-customer-profiles"]
}

inputs = {
  component = "instance"
}
