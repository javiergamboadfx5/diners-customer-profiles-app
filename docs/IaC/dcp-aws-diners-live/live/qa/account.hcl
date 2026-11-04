# Cuenta destino del ambiente. Para mudar el stack a otra cuenta solo cambia account_key
# (la nueva cuenta debe existir en catalogs/accounts.yaml con sus roles de Terraform).
locals {
  account_key = "diners-qa"
  account     = yamldecode(file("${get_repo_root()}/catalogs/accounts.yaml")).accounts[local.account_key]
  account_id  = local.account.account_id
}
