# =============================================================================
# Stack: kms — clave CMK de almacenamiento del contact center (Connect_Module).
# Estado:  diners/contactcenter-dev/us-east-1/workloads/<OQ-1>/kms/terraform.tfstate
#          (la clave de estado la calcula el root terragrunt.hcl a partir de la
#          ruta relativa; este archivo no la escribe — L05).
# Módulo:  connect/connect-instance, component = "kms".
#
# Primero en el orden de aplicación (Requisito 12.7): kms -> storage ->
# kms-customer-profiles -> instance -> customer-profiles -> saml-federation.
# Por ser el primero, no tiene bloque `dependencies` (no consume ningún contrato).
#
# Publica el contrato SSM `connect-kms-key-arn` (String) que leen los stacks
# `storage` e `instance` (Requisitos 4.1, 4.4, 1.1).
#
# Reglas que cumple este archivo (iac-core-rules, Requisitos 2.1, 2.7, 13.1,
# 13.2): sin IDs de cuenta, ARNs, CIDRs ni literales de entorno. El `source`
# apunta al repo de módulos por SHA de 40 hex. `environment`, `workload`,
# `region_code`, retención, `cde_scope`, `instance_alias` e
# `identity_management_type` llegan por los inputs del root desde los
# Hierarchy_Files (DD-3). Las rutas SSM se construyen dentro del módulo a partir
# de `domain`, `environment` y `workload`.
#
# El mecanismo `generate "import"` (DD-4) lo aporta el root terragrunt.hcl: emite
# import.tf solo si env.hcl define adopt."kms". Aquí no hay nada que declarar.
#
# Lock file: `.terraform.lock.hcl` debe commitearse (Requisito 1.6, iac-core-
# rules §4), pero se genera desde el mirror Nexus aprobado en el pipeline. No se
# puede producir offline aquí; lo genera el runner con `terraform init` contra el
# mirror y el PR lo incluye.
# =============================================================================

# -----------------------------------------------------------------------------
# [Blocked: OQ-1, OQ-4, OQ-5, OQ-13]
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

inputs = {
  component = "kms"
}
