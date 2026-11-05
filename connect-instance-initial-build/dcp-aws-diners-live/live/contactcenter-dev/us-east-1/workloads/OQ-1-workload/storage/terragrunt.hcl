# =============================================================================
# Stack: storage — bucket S3 de almacenamiento del contact center (Connect_Module).
# Estado:  diners/contactcenter-dev/us-east-1/workloads/<OQ-1>/storage/terraform.tfstate
#          (la clave de estado la calcula el root terragrunt.hcl a partir de la
#          ruta relativa; este archivo no la escribe — L05).
# Módulo:  connect/connect-instance, component = "storage" (mismo Connect_Module
#          y mismo SHA que el stack kms; un módulo sirve a kms, storage e
#          instance a través del switch `component`).
#
# Segundo en el orden de aplicación (Requisito 12.7): kms -> storage ->
# kms-customer-profiles -> instance -> customer-profiles -> saml-federation.
# Por eso declara `dependencies { paths = ["../kms"] }` SOLO para ordenar el
# apply (los `dependencies` de Terragrunt transportan orden, no datos — DD-3,
# principio "least coupling"). No lleva `mock_outputs`: el primer apply necesita
# los valores SSM reales que publica kms (`connect-kms-key-arn`), y un mock
# nunca debe habilitar un apply. La ordenación uno-a-uno del pipeline es lo que
# permite un solo PR; si el pipeline no la garantiza, el PR de kms mergea antes
# (Requisitos 12.7, 12.8, 5.3).
#
# Lee el contrato SSM `connect-kms-key-arn` (publicado por kms) para la cifrado
# SSE-KMS del bucket, sin fallback: si el parámetro no existe el plan falla
# (Requisitos 5.2, 5.3). La lectura la hace el módulo con un data source; aquí no
# se referencia ningún ARN.
#
# Publica el contrato SSM `connect-storage-bucket-name` (String) que lee el stack
# `instance` (Requisitos 5.7, 1.1). Por publicar un contrato, este stack mergea
# después de que el PR de kms haya aplicado (stacks que publican van en un PR
# anterior y separado de los que consumen — iac-core-rules §3).
#
# Reglas que cumple este archivo (iac-core-rules, Requisitos 2.7, 13.1, 13.2):
# sin IDs de cuenta, ARNs, CIDRs ni literales de entorno. El `source` apunta al
# repo de módulos por SHA de 40 hex. `environment`, `workload`, `region_code`,
# retención (OQ-7) y `cde_scope`/`security_coverage_ref` (OQ-6) llegan por los
# inputs del root desde los Hierarchy_Files (DD-3): viven en env.hcl
# `stack_inputs` como placeholders <OQ-n> y NO se escriben aquí. Las rutas SSM se
# construyen dentro del módulo a partir de `domain`, `environment` y `workload`.
#
# El mecanismo `generate "import"` (DD-4) lo aporta el root terragrunt.hcl: emite
# import.tf solo si env.hcl define adopt."storage". Aquí no hay nada que declarar.
#
# Lock file: `.terraform.lock.hcl` debe commitearse (Requisito 1.6, iac-core-
# rules §4), pero se genera desde el mirror Nexus aprobado en el pipeline. No se
# puede producir offline aquí; lo genera el runner con `terraform init` contra el
# mirror y el PR lo incluye.
# =============================================================================

# -----------------------------------------------------------------------------
# [Blocked: OQ-1, OQ-4, OQ-5, OQ-6, OQ-7, OQ-13]
# BLOQUEANTE — SHA del módulo. El módulo connect/connect-instance NO está aún
# registrado en dcp-terraform-modules/compatibility.yaml (solo hay módulos de
# ejemplo). El `ref` debe ser un SHA de 40 hex de un tag de release firmado y
# registrado en compatibility.yaml (iac-core-rules §4, Requisito 2.1). El valor
# de abajo es un PLACEHOLDER (40 ceros); hay que reemplazarlo por el SHA real
# registrado ANTES del merge. Hasta entonces scan_stack_files.py falla por diseño
# (regla module-sha: "SHA no está registrado en compatibility.yaml"). NO se debe
# inventar un SHA realista ni autorregistrarlo en compatibility.yaml.
#
# BLOQUEANTE — OQ-6/OQ-7: retención (recordings/transcripts/noncurrent) y
# cde_scope/security_coverage_ref llegan por env.hcl stack_inputs como <OQ-n>.
# El módulo los valida (enteros >= 1; cde_scope requerido) y el plan falla hasta
# que Cumplimiento (OQ-7) y Ciberseguridad (OQ-6) fijen los valores. No se
# inventan aquí.
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
  # Orden de apply únicamente (sin mock_outputs): kms debe aplicar antes para
  # publicar el contrato SSM connect-kms-key-arn que consume este stack.
  paths = ["../kms"]
}

inputs = {
  component = "storage"
}
