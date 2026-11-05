# =============================================================================
# Stack: customer-profiles — dominio Amazon Connect Customer Profiles del
#        contact center (Profiles_Module, component = "domain").
# Estado:  diners/contactcenter-dev/us-east-1/workloads/<OQ-1>/customer-profiles/terraform.tfstate
#          (la clave de estado la calcula el root terragrunt.hcl a partir de la
#          ruta relativa; este archivo no la escribe — L05).
# Módulo:  connect/connect-customer-profiles, component = "domain" (Profiles_Module,
#          el mismo módulo y mismo SHA que el stack kms-customer-profiles; un
#          módulo sirve a los componentes `kms` y `domain` a través del switch
#          `component`). Este stack crea el dominio, el object type `CTR` y la
#          integración con la instancia (Requisitos 8.1, 8.2, 8.5, 8.7).
#
# Quinto en el orden de aplicación (Requisito 12.7): kms -> storage ->
# kms-customer-profiles -> instance -> customer-profiles -> saml-federation.
# Por eso declara `dependencies { paths = ["../instance", "../kms-customer-profiles"] }`
# SOLO para ordenar el apply (los `dependencies` de Terragrunt transportan orden,
# no datos — DD-3, principio "least coupling"). No lleva `mock_outputs`: un mock
# nunca debe habilitar un apply, y este apply necesita los valores SSM reales que
# lee el módulo. Los contratos que este stack SÍ consume los lee el módulo desde
# SSM con sus data sources, no por `dependency`. La ordenación uno-a-uno del
# pipeline es lo que garantiza que instance y kms-customer-profiles ya han
# aplicado antes (Requisitos 12.7, 1.1).
#
# Lee los contratos SSM que publican los stacks anteriores, a través de los data
# sources del módulo y sin fallback (si falta un parámetro el plan falla):
#   - `customer-profiles-kms-key-arn` (publicado por kms-customer-profiles) — la
#     CMK dedicada del dominio (Requisitos 8.1, 7.4).
#   - `connect-instance-arn`          (publicado por instance) — `uri` de la
#     integración del dominio (Requisito 8.5).
# Aquí no se referencia ningún ARN; la lectura la hace el módulo con sus data
# sources a partir de `domain`, `environment` y `workload`.
#
# Publica los 2 contratos SSM del dominio (String) — Requisitos 8.2, 1.1:
#   - `customer-profiles-domain-name`
#   - `customer-profiles-domain-arn`
# Por publicar contratos, este stack mergea en un PR posterior a los que aplica
# (instance, kms-customer-profiles) y separado de cualquier consumidor futuro de
# estos contratos — iac-core-rules §3.
#
# Reglas que cumple este archivo (iac-core-rules, Requisitos 2.1, 2.7, 13.1,
# 13.2): sin IDs de cuenta, ARNs, CIDRs ni literales de entorno. El `source`
# apunta al repo de módulos por SHA de 40 hex. `environment`, `workload`,
# `region_code`, `default_expiration_days`, el estado del data store, `cde_scope`
# y `bind_domain_arn` llegan por los inputs del root desde los Hierarchy_Files
# (DD-3): viven en env.hcl `stack_inputs` y NO se escriben aquí. Las rutas SSM se
# construyen dentro del módulo.
#
# Adopción (Requisitos 8.6, 6.8, DD-4): el mecanismo `generate "import"` lo aporta
# el root terragrunt.hcl, que emite import.tf solo si env.hcl define
# adopt."customer-profiles". Si existe ya una integración/dominio de Customer
# Profiles para la instancia, `adopt.customer-profiles` se poblará con los pares
# `to`/`id` para adoptarlo en lugar de crearlo; de lo contrario env.hcl deja
# `adopt` vacío y no se genera import.tf. Este archivo de stack NO declara bloques
# `import` — la adopción es declarativa vía adopt.customer-profiles en env.hcl.
#
# Lock file: `.terraform.lock.hcl` debe commitearse (Requisito 1.6, iac-core-
# rules §4), pero se genera desde el mirror Nexus aprobado en el pipeline. No se
# puede producir offline aquí; lo genera el runner con `terraform init` contra el
# mirror y el PR lo incluye.
# =============================================================================

# -----------------------------------------------------------------------------
# [Blocked: OQ-10, OQ-12, OQ-14]
# BLOQUEANTE — OQ-10 (default_expiration_days y data store). La expiración del
# perfil y el estado del data store llegan por env.hcl `stack_inputs`. El módulo
# valida `default_expiration_days` (1..1098) y exige `data_store_approval_ref`
# cuando el data store se habilita (Requisitos 8.3, 8.4, 3.8). Los valores reales
# (expiración y la decisión de habilitar el data store de 10 años) dependen de
# Cumplimiento; mientras sean placeholders <OQ-10> el catalog sync / plan real no
# pasa. No se inventan aquí. Por defecto el data store queda deshabilitado.
#
# BLOQUEANTE — OQ-12 (provider awscc). Si el object type `CTR` y/o la integración
# del dominio requieren el provider `hashicorp/awscc` (porque `hashicorp/aws`
# >= 6.47.0 no los cubre), ese provider debe registrarse en compatibility.yaml
# con un major acotado y servirse desde el mirror Nexus aprobado. Hasta que OQ-12
# se resuelva y, si aplica, el awscc esté registrado, el plan real no pasa. No se
# registra aquí ni se añade un provider no aprobado.
#
# BLOQUEANTE — OQ-14 (excepción de nombre). El dominio exige el prefijo
# `amazon-connect-` (restricción nativa de Customer Profiles), que no cumple el
# patrón de nombres estándar `dcp-...` (L07). Esto requiere una excepción
# registrada `exc-cloud-*` en dcp-platform-policies con aprobación de Arquitectura
# Cloud (y Ciberseguridad si toca datos `confidential`/`restricted`/`pci`), y el
# recurso tagueado con `ExceptionId` (iac-core-rules §9). Hasta que la excepción
# exista y se referencie, el guardrail de nombres marca la desviación. No se
# inventa aquí.
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
  # ... -> instance -> customer-profiles -> ... Las dos dependencias transportan
  # SOLO orden. Los contratos que este stack consume (customer-profiles-kms-key-arn,
  # connect-instance-arn) los lee el módulo desde SSM, no por dependency.
  paths = ["../instance", "../kms-customer-profiles"]
}

inputs = {
  component = "domain"
}
