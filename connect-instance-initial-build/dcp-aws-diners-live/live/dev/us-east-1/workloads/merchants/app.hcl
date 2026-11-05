# Datos de la aplicación. Deben coincidir con applications.merchant-portal en
# catalogs/catalogos-cloud.yaml; Conftest lo valida en el PR.
locals {
  workload            = "merchants"
  application         = "merchant-portal"
  owner               = "equipo-comercios"
  cost_center         = "410230"
  data_classification = "confidential"
  compliance          = "lpdp"
  criticality         = "tier-2"
}
