terraform {
  # Rango obligatorio del estándar de módulos (L03).
  required_version = ">= 1.15.8, < 1.16.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.47.0, < 7.0.0"
    }

    # awscc: necesario para el tipo de objeto y la integración de Customer
    # Profiles. El proveedor hashicorp/aws (>= 6.47.0) expone
    # aws_customerprofiles_domain, pero NO expone recursos para el mapeo de tipo
    # de objeto ni para la integración de la instancia; esos recursos
    # (awscc_customerprofiles_object_type, awscc_customerprofiles_integration)
    # solo existen en hashicorp/awscc. Por eso el módulo lo declara.
    #
    # Límite mayor acotado, en línea con el estándar de módulos (L03). La entrada
    # debe registrarse en compatibility.yaml con el espejo de Nexus antes de que
    # el componente domain pueda mezclarse. [Blocked: OQ-12]
    awscc = {
      source  = "hashicorp/awscc"
      version = ">= 1.0.0, < 2.0.0"
    }
  }
}
