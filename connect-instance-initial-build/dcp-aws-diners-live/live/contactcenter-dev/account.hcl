# =============================================================================
# account.hcl — cuenta destino del ambiente contactcenter-dev (L02, L08).
#
# Para este iniciativa el ambiente dev vive en una cuenta AWS NUEVA y aislada
# (decision de arquitectura, requirements.md "Documented Conflicts"). Esa cuenta
# todavia no esta registrada en catalogs/accounts.yaml (OQ-4): falta su account_key
# catalogado, su account_id real, los roles TerraformPlanRole/TerraformApplyRole,
# el OU, el centro de costo, el owner y el compliance.
#
# Mientras OQ-4 no se resuelva, account_key queda como un placeholder <OQ-4> que
# NO existe en accounts.yaml, de modo que el catalog sync del pipeline falla y el
# PR no puede mergear (Requisito 1.7). No se inventa un account_id literal aqui
# (Requisito 2.7 y iac-core-rules: nada de IDs de cuenta en archivos).
#
# Para mudar el stack a otra cuenta solo cambia account_key; la nueva cuenta debe
# existir en catalogs/accounts.yaml con sus roles de Terraform.
# =============================================================================
locals {
  # TODO(OQ-4): reemplazar por el account_key catalogado de la nueva cuenta dev
  # aislada, registrado en catalogs/accounts.yaml (dcp-aws-governance-live).
  # Ejemplo de la forma esperada: "diners-contactcenter-dev". El valor actual es
  # un placeholder que falla el catalog sync a proposito.
  account_key = "<OQ-4>"

  account    = yamldecode(file("${get_repo_root()}/catalogs/accounts.yaml")).accounts[local.account_key]
  account_id = local.account.account_id
}
