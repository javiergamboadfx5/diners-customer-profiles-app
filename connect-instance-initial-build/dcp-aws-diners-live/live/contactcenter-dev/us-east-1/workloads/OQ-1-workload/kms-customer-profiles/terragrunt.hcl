# =============================================================================
# Stack: kms-customer-profiles — clave CMK dedicada del dominio Customer
#        Profiles del contact center (Profiles_Module).
# Estado:  diners/contactcenter-dev/us-east-1/workloads/<OQ-1>/kms-customer-profiles/terraform.tfstate
#          (la clave de estado la calcula el root terragrunt.hcl a partir de la
#          ruta relativa; este archivo no la escribe — L05).
# Módulo:  connect/connect-customer-profiles, component = "kms" (Profiles_Module,
#          NO connect-instance). Es una clave distinta de la del stack `kms`
#          (Connect_Module): alias `customer-profiles`, con statements propios de
#          Customer Profiles (ProfileService, ConnectService Decrypt, ProfilesApp
#          opcional) — Requisitos 7.1, 7.2, 7.3, 7.4.
#
# Tercero en el orden de aplicación (Requisito 12.7): kms -> storage ->
# kms-customer-profiles -> instance -> customer-profiles -> saml-federation.
# Por eso declara `dependencies { paths = ["../storage"] }` SOLO para ordenar el
# apply (los `dependencies` de Terragrunt transportan orden, no datos — DD-3,
# principio "least coupling"). No lleva `mock_outputs`: un mock nunca debe
# habilitar un apply. Esta clave no consume el contrato de storage; el `depends`
# únicamente reproduce el orden de aplicación especificado. La ordenación
# uno-a-uno del pipeline es lo que lo permite.
#
# Publica el contrato SSM `customer-profiles-kms-key-arn` (String) que leen los
# stacks `customer-profiles` (dominio) — Requisitos 7.1, 7.4, 7.8, 1.1. Por
# publicar un contrato, este stack mergea en un PR anterior y separado de los que
# lo consumen (iac-core-rules §3).
#
# Reglas que cumple este archivo (iac-core-rules, Requisitos 2.1, 2.7, 13.1,
# 13.2): sin IDs de cuenta, ARNs, CIDRs ni literales de entorno. El `source`
# apunta al repo de módulos por SHA de 40 hex. `environment`, `workload`,
# `region_code`, `cde_scope` y `bind_domain_arn` llegan por los inputs del root
# desde los Hierarchy_Files (DD-3). Las rutas SSM se construyen dentro del módulo
# a partir de `domain`, `environment` y `workload`.
#
# El rol key-admin se lee desde SSM dentro del módulo con un `precondition` que
# falla con el mensaje de OQ-13 si el contrato aún no está publicado. El statement
# opcional `ProfilesApp` solo se añade cuando `aws_ssm_parameters_by_path`
# devuelve `profiles-app-role-arn` (OQ-11); el módulo maneja su ausencia (no falla
# el plan). Aquí no se referencia ningún ARN de rol.
#
# El mecanismo `generate "import"` (DD-4) lo aporta el root terragrunt.hcl: emite
# import.tf solo si env.hcl define adopt."kms-customer-profiles". Aquí no hay nada
# que declarar.
#
# Lock file: `.terraform.lock.hcl` debe commitearse (Requisito 1.6, iac-core-
# rules §4), pero se genera desde el mirror Nexus aprobado en el pipeline. No se
# puede producir offline aquí; lo genera el runner con `terraform init` contra el
# mirror y el PR lo incluye.
# =============================================================================

# -----------------------------------------------------------------------------
# [Blocked: OQ-13]
# BLOQUEANTE — rol key-admin. El módulo lee `key-admin-role-arn` desde SSM sin
# fallback; su `precondition` falla con "key-admin role not published (OQ-13)"
# hasta que el publicador registre el contrato. El plan real no pasa hasta
# entonces.
#
# PENDIENTE — OQ-11 (profiles-app-role-arn). Si el rol de la app de perfiles aún
# no está publicado en SSM, se deja constancia como pendiente en el PR. El módulo
# maneja el statement `ProfilesApp` como OPCIONAL: solo lo añade si el parámetro
# existe, por lo que su ausencia no bloquea este plan. No se inventa el ARN.
#
# BLOQUEANTE — SHA del módulo. El módulo connect/connect-customer-profiles NO
# está aún registrado en dcp-terraform-modules/compatibility.yaml (solo hay
# módulos de ejemplo). El `ref` debe ser un SHA de 40 hex de un tag de release
# firmado y registrado en compatibility.yaml (iac-core-rules §4, Requisito 2.1).
# El valor de abajo es un PLACEHOLDER (40 ceros); hay que reemplazarlo por el SHA
# real registrado ANTES del merge. Hasta entonces scan_stack_files.py falla por
# diseño (regla module-sha: "SHA no está registrado en compatibility.yaml"). NO
# se debe inventar un SHA realista ni autorregistrarlo en compatibility.yaml.
# -----------------------------------------------------------------------------

include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

terraform {
  # TODO(OQ): reemplazar el SHA placeholder por el SHA de 40 hex del release
  # firmado de connect/connect-customer-profiles registrado en compatibility.yaml.
  source = "git::ssh://git@github.com/Diners/dcp-terraform-modules.git//modules/connect/connect-customer-profiles?ref=0000000000000000000000000000000000000000"
}

dependencies {
  # Orden de apply únicamente (sin mock_outputs): reproduce el orden especificado
  # kms -> storage -> kms-customer-profiles -> instance -> ... Este stack no
  # consume el contrato de storage; el `depends` solo transporta orden.
  paths = ["../storage"]
}

inputs = {
  component = "kms"
}
