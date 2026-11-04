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
  default_tags = merge(
    {
      Environment        = local.environment
      Scope              = local.scope
      ManagedBy          = "terraform"
      Repository         = local.repository
      TerraformStack     = local.terraform_stack
      Owner              = try(local.app.owner, "infraestructura-cloud")
      CostCenter         = try(local.app.cost_center, local.domain_cfg.locals.platform_cost_center)
      DataClassification = try(local.app.data_classification, "internal")
      Compliance         = try(local.app.compliance, "general")
      Application        = try(local.app.application, "platform")
    },
    # Domain y Workload solo para recursos de workload.
    { for k, v in { Domain = local.domain, Workload = try(local.app.workload, "") } : k => v if local.is_workload }
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
      region              = "${local.aws_region}"
      allowed_account_ids = ["${local.account_id}"]

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

# Inputs comunes; cada stack agrega solo los suyos.
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
  }
)
