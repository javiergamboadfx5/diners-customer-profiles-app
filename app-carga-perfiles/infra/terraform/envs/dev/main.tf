terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
    awscc = {
      source  = "hashicorp/awscc"
      version = "~> 1.20"
    }
  }
  # Estado remoto: completar con el bucket que defina el pipeline de Diners (lineamientos de DevOps).
  # backend "s3" {
  #   bucket       = "<bucket-de-estado>"
  #   key          = "diners/carga-perfiles/dev.tfstate"
  #   region       = "us-east-1"
  #   use_lockfile = true
  #   encrypt      = true
  # }
}

provider "aws" {
  region = var.region
}

provider "awscc" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "app" {
  description = "Variables del modulo para este ambiente (ver terraform.tfvars.example)."
  type        = any
}

module "carga_perfiles" {
  source = "../../modules/carga_perfiles"

  ambiente               = "dev"
  oidc_issuer            = var.app.oidc_issuer
  oidc_client_id         = var.app.oidc_client_id
  oidc_audiences         = var.app.oidc_audiences
  oidc_scope             = var.app.oidc_scope
  grupos_carga           = try(var.app.grupos_carga, [])
  grupos_admin           = try(var.app.grupos_admin, [])
  connect_instance_alias = var.app.connect_instance_alias
  connect_instance_arn   = try(var.app.connect_instance_arn, "")
  crear_dominio_perfiles = try(var.app.crear_dominio_perfiles, false)
  dominio_perfiles       = var.app.dominio_perfiles
  concurrencia_escritura = try(var.app.concurrencia_escritura, 5)
}

output "app" {
  value = {
    url_app          = module.carga_perfiles.url_app
    redirect_uri     = module.carga_perfiles.redirect_uri
    bucket_sitio     = module.carga_perfiles.bucket_sitio
    distribucion_id  = module.carga_perfiles.distribucion_id
    dominio_perfiles = module.carga_perfiles.dominio_perfiles
    object_type      = module.carga_perfiles.object_type
  }
}
