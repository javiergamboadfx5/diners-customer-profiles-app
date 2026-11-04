terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
    awscc = {
      source  = "hashicorp/awscc"
      version = "~> 1.20"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.6"
    }
  }

  # Configuracion parcial: bucket, key y region se pasan por ambiente en el init.
  #   terraform init -backend-config=envs/<ambiente>.s3.tfbackend
  # Si el repo destino usa otro backend o Terragrunt, reemplazar este bloque por su convencion.
  backend "s3" {}
}
