# =============================================================================
# terragrunt.hcl (raíz) — configuración común de dcp-aws-diners-live (L02)
#
# Cada stack lo incluye con:
#   include "root" { path = find_in_parent_folders("terragrunt.hcl") }
#
# Resuelve, sin que el stack escriba nada:
#   1. backend S3 por tier (nonprod / prod) con lock nativo y KMS
#   2. provider AWS con AssumeRole al rol de plan o apply de la cuenta destino
#   3. tags obligatorios por default_tags
#   4. inputs comunes de naming (environment, workload, region_code)
#
# Regla operativa: los comandos de Terragrunt se ejecutan dentro de live/ o de la
# carpeta de un stack, nunca en la raíz del repo; si no, Terragrunt trataría este
# archivo como un stack más.
# =============================================================================

terraform_version_constraint  = ">= 1.15.8, < 1.16.0"
terragrunt_version_constraint = ">= 0.90.0"

locals {
  domain_cfg  = read_terragrunt_config(find_in_parent_folders("domain.hcl"))
  env_cfg     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  account_cfg = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_cfg  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  state_cfg   = read_terragrunt_config(find_in_parent_folders("state.hcl"))

  # app.hcl solo existe bajo workloads/<workload>/; los stacks de platform/ no lo tienen.
  app_file    = find_in_parent_folders("app.hcl", "")
  app         = try(read_terragrunt_config(local.app_file).locals, {})
  is_workload = local.app_file != ""

  # stack_inputs (DD-3): valores que varían por Environment (retención, cde_scope,
  # alias, identity_management_type, expiración de perfiles, etc.) viven en env.hcl.
  # El root los fusiona en inputs para que los archivos de stack no lleven ningún
  # valor específico del Environment (Requisito 13.2). Opcional: default {}.
  stack_inputs = try(local.env_cfg.locals.stack_inputs, {})

  domain      = local.domain_cfg.locals.domain
  scope       = local.domain_cfg.locals.scope
  repository  = local.domain_cfg.locals.repository
  environment = local.env_cfg.locals.environment
  account_id  = local.account_cfg.locals.account_id
  aws_region  = local.region_cfg.locals.aws_region
  region_code = local.region_cfg.locals.region_code

  # live/dev/us-east-1/workloads/merchants/compute -> dev/us-east-1/workloads/merchants/compute
  relative_stack_path = trimprefix(path_relative_to_include(), "live/")
  terraform_stack     = "${local.domain}/${local.relative_stack_path}"

  # ---------------------------------------------------------------------------
  # Adopción por import (DD-4): nombre del stack actual = último segmento de la
  # ruta relativa (p. ej. "instance", "customer-profiles"). Se usa como clave en
  # el mapa adopt de env.hcl.
  # ---------------------------------------------------------------------------
  stack_name = basename(local.relative_stack_path)

  # adopt (DD-4): mapa opcional por stack en env.hcl. Si falta, {} (no-op). Cada
  # entrada adopt.<stack> es una lista de pares { to, id } que se convierten en
  # bloques import {} en un import.tf generado. Los recursos existentes se
  # adoptan con import en lugar de destruir/recrear (iac-core-rules: adoptar
  # recursos existentes requiere import; nunca destruir/recrear en prod para
  # reorganizar). Requisitos 6.8, 8.6.
  adopt         = try(local.env_cfg.locals.adopt, {})
  adopt_entries = try(local.adopt[local.stack_name], [])

  # Bloques import {} renderizados: `to` es una dirección de recurso y se emite
  # sin comillas; `id` es un string y se emite con comillas (jsonencode).
  import_blocks = join("\n", [
    for e in local.adopt_entries :
    "import {\n  to = ${e.to}\n  id = ${jsonencode(e.id)}\n}"
  ])

  # Contenido del import.tf. Vacío (solo comentarios) = no-op compatible con los
  # stacks existentes. El archivo está git-ignorado (tarea 7.4).
  import_contents = length(local.adopt_entries) == 0 ? join("\n", [
    "# import.tf generado por el root terragrunt.hcl (DD-4).",
    "# Sin adopción para el stack \"${local.stack_name}\": env.hcl no define",
    "# adopt.\"${local.stack_name}\". No-op; no se adopta ningún recurso.",
    ]) : join("\n", [
    "# import.tf generado por el root terragrunt.hcl (DD-4).",
    "# Adopción de recursos existentes para el stack \"${local.stack_name}\"",
    "# declarada en env.hcl (adopt.\"${local.stack_name}\"). Cada bloque import",
    "# trae un recurso ya existente bajo gestión sin destruir/recrear.",
    local.import_blocks,
  ])

  # ---------------------------------------------------------------------------
  # Estado: un bucket por tier, una clave por stack (L05)
  # ---------------------------------------------------------------------------
  state_tier = {
    dev  = "nonprod"
    qa   = "nonprod"
    stg  = "nonprod"
    prod = "prod"
  }[local.environment]

  # ---------------------------------------------------------------------------
  # Identidad: el pipeline exporta DCP_TERRAFORM_ROLE con TerraformPlanRole o
  # TerraformApplyRole. Fuera del pipeline solo se puede planificar.
  # ---------------------------------------------------------------------------
  deploy_role  = get_env("DCP_TERRAFORM_ROLE", "TerraformPlanRole")
  session_name = "tf-${local.environment}-${get_env("GITHUB_RUN_ID", "local")}"

  # ---------------------------------------------------------------------------
  # Tags obligatorios (L11). Name lo pone cada módulo en cada recurso.
  # ---------------------------------------------------------------------------
  # Tags comunes a cualquier stack.
  common_tags = {
    Environment    = local.environment
    Scope          = local.scope
    ManagedBy      = "terraform"
    Repository     = local.repository
    TerraformStack = local.terraform_stack
  }

  # Para stacks de workload (hay app.hcl) estos tags se leen de app.hcl SIN
  # default por try(...): si falta un valor, el plan falla (Requisito 11.2) en vez
  # de sustituir un valor local. Domain y Workload también se agregan aquí (L11 v2).
  workload_tags = {
    Owner              = local.app.owner
    CostCenter         = local.app.cost_center
    DataClassification = local.app.data_classification
    Compliance         = local.app.compliance
    Application        = local.app.application
    Domain             = local.domain
    Workload           = local.app.workload
  }

  # Para stacks de platform/ (sin app.hcl) se conservan los defaults de plataforma;
  # no llevan Domain ni Workload (11 tags obligatorios en recursos foundational).
  platform_tags = {
    Owner              = "infraestructura-cloud"
    CostCenter         = local.domain_cfg.locals.platform_cost_center
    DataClassification = "internal"
    Compliance         = "general"
    Application        = "platform"
  }

  default_tags = merge(
    local.common_tags,
    local.is_workload ? local.workload_tags : local.platform_tags
  )
}

remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket       = local.state_cfg.locals.bucket_by_tier[local.state_tier]
    key          = "${local.terraform_stack}/terraform.tfstate"
    region       = local.state_cfg.locals.aws_region
    encrypt      = true
    kms_key_id   = local.state_cfg.locals.kms_key_arn
    use_lockfile = true

    # El bucket lo crea y protege dcp-terraform-bootstrap; Terragrunt no lo toca.
    disable_bucket_update = true
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region                = "${local.aws_region}"
      allowed_account_ids   = ["${local.account_id}"]
      tag_policy_compliance = "error"

      assume_role {
        role_arn     = "arn:aws:iam::${local.account_id}:role/${local.deploy_role}"
        session_name = "${local.session_name}"
      }

      default_tags {
        tags = ${jsonencode(local.default_tags)}
      }
    }
  EOF
}

# -----------------------------------------------------------------------------
# generate "import" (DD-4): mecanismo de adopción.
#
# Cuando env.hcl define adopt.<stack> con una lista de pares { to, id }, este
# bloque escribe un import.tf con un bloque import {} por cada par, de modo que
# los recursos ya existentes en la cuenta se adoptan bajo gestión de Terraform en
# lugar de destruirse y recrearse (iac-core-rules: adoptar recursos existentes
# requiere import; nunca destruir/recrear producción para reorganizar; usar
# moved/import). Requisitos 6.8 (adopción de la instancia por alias) y 8.6
# (adopción de la integración de Customer Profiles).
#
# No-op cuando el mapa adopt está vacío o no define el stack actual: se genera un
# import.tf solo con comentarios (sin bloques import), de forma que los stacks
# existentes siguen igual (compatibilidad hacia atrás). El import.tf está
# git-ignorado (tarea 7.4): es un artefacto generado, no se versiona.
generate "import" {
  path      = "import.tf"
  if_exists = "overwrite_terragrunt"
  contents  = local.import_contents
}

# Inputs comunes; cada stack agrega solo los suyos.
# stack_inputs (DD-3) aporta los valores que varían por Environment desde env.hcl;
# van al final para que el Environment gobierne retención, cde_scope, alias, etc.,
# sin que el archivo de stack los escriba (Requisito 13.2).
inputs = merge(
  {
    domain      = local.domain
    environment = local.environment
    region_code = local.region_code
  },
  {
    for k, v in {
      workload = try(local.app.workload, "")
      tags     = { Criticality = try(local.app.criticality, "") }
    } : k => v if local.is_workload
  },
  local.stack_inputs
)
