# =============================================================================
# REFERENCIA — lo administra Platform Engineering, no los proyectos.
# Roles CI/CD de la cuenta dinersclub-devops que el pipeline asume por OIDC.
# Viven en dcp-aws-devops-live/live/devops/us-east-1/deployment-roles/ (L02 v1.1).
#
# Cadena de identidad:
#   job de GitHub ──OIDC──▶ dcp-platform-shared-cicd-role-terraform-<plan|apply-nonprod|apply-prod>  (cuenta DevOps)
#                 ──AssumeRole──▶ TerraformPlanRole | TerraformApplyRole  (cuenta destino)
# =============================================================================

locals {
  github_org       = "Diners"
  live_repos       = ["dcp-aws-diners-live", "dcp-aws-data-live"]
  template_wf      = "Diners/dcp-platform-pipeline-templates/.github/workflows/terraform-stack.yml"
  nonprod_accounts = ["111111111101", "111111111102", "111111111103"] # desde accounts.yaml
  prod_accounts    = ["111111111104"]
}

# Proveedor OIDC de GitHub (uno por cuenta).
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

# -----------------------------------------------------------------------------
# El claim "sub" se personaliza a nivel de organización GitHub para incluir el
# workflow reusable que corre el job (include_claim_keys = repo, context, job_workflow_ref):
#
#   repo:Diners/dcp-aws-diners-live:pull_request:job_workflow_ref:Diners/dcp-platform-pipeline-templates/.github/workflows/terraform-stack.yml@<sha>
#   repo:Diners/dcp-aws-diners-live:ref:refs/heads/main:job_workflow_ref:...
#   repo:Diners/dcp-aws-diners-live:environment:diners-prod:job_workflow_ref:...
#
# Así ningún workflow escrito por un proyecto puede asumir estos roles: solo el template.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "trust_plan" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = flatten([
        for r in local.live_repos : [
          "repo:${local.github_org}/${r}:pull_request:job_workflow_ref:${local.template_wf}@*",
          "repo:${local.github_org}/${r}:ref:refs/heads/main:job_workflow_ref:${local.template_wf}@*",
        ]
      ])
    }
  }
}

data "aws_iam_policy_document" "trust_apply" {
  for_each = {
    nonprod = ["dev", "qa", "stg"]
    prod    = ["prod", "prod-cde"]
  }

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Solo jobs que pasaron la aprobación del environment del tier correspondiente.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = flatten([
        for r in local.live_repos : [
          for e in each.value :
          "repo:${local.github_org}/${r}:environment:*-${e}:job_workflow_ref:${local.template_wf}@*"
        ]
      ])
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "dcp-platform-shared-cicd-role-terraform-plan"
  assume_role_policy   = data.aws_iam_policy_document.trust_plan.json
  max_session_duration = 3600
  permissions_boundary = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/dcp-platform-permission-boundary"
}

resource "aws_iam_role" "apply" {
  for_each = data.aws_iam_policy_document.trust_apply

  name                 = "dcp-platform-shared-cicd-role-terraform-apply-${each.key}"
  assume_role_policy   = each.value.json
  max_session_duration = 3600
  permissions_boundary = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/dcp-platform-permission-boundary"
}

data "aws_caller_identity" "current" {}

# El rol de plan puede asumir TerraformPlanRole en todas las cuentas; cada rol de apply,
# solo TerraformApplyRole de su tier. Más acceso al estado y al bucket de planes.
data "aws_iam_policy_document" "plan_permissions" {
  statement {
    actions   = ["sts:AssumeRole"]
    resources = [for a in concat(local.nonprod_accounts, local.prod_accounts) : "arn:aws:iam::${a}:role/TerraformPlanRole"]
  }

  statement {
    sid       = "PlanArtifacts"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::dcp-platform-shared-cicd-s3-tfplans-use1-<unique>/*"]
  }
  # El acceso de lectura y lock al bucket de estado lo concede la bucket policy del bootstrap,
  # acotado al prefijo de cada dominio (diners/*, data/*).
}

data "aws_iam_policy_document" "apply_permissions" {
  for_each = {
    nonprod = local.nonprod_accounts
    prod    = local.prod_accounts
  }

  statement {
    actions   = ["sts:AssumeRole"]
    resources = [for a in each.value : "arn:aws:iam::${a}:role/TerraformApplyRole"]
  }

  statement {
    sid       = "ReadApprovedPlans"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["arn:aws:s3:::dcp-platform-shared-cicd-s3-tfplans-use1-<unique>/*"]
  }
}

resource "aws_iam_role_policy" "plan" {
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_permissions.json
}

resource "aws_iam_role_policy" "apply" {
  for_each = aws_iam_role.apply

  role   = each.value.id
  policy = data.aws_iam_policy_document.apply_permissions[each.key].json
}
