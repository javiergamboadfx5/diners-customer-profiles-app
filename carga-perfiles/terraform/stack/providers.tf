# Credenciales: las del entorno (AWS_PROFILE, rol del pipeline). No se fijan aqui.
provider "aws" {
  region = var.region
}

provider "awscc" {
  region = var.region
}
