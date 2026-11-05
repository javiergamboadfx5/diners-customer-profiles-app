# =============================================================================
# app.hcl — datos de la aplicacion del contact center (workload exclusivo).
#
# El root terragrunt.hcl lee owner, cost_center, data_classification, compliance,
# application y workload de este archivo SIN default por try(...): si falta un
# valor, el plan falla (Requisito 11.2, DD-3). Estos valores alimentan los tags
# obligatorios (default_tags) y el naming (workload).
#
# Todos los valores deben coincidir con una entrada en catalogs/catalogos-cloud.yaml
# (applications.<app> y workloads[]); Conftest lo valida en el PR.
#
# PENDIENTES (no se inventan valores de catalogo):
#  - OQ-1: codigo de workload del contact center. No esta en la lista L07
#    (channels? customers?). Requiere PR al catalogo. Mientras tanto, el nombre de
#    la carpeta de workload y el valor workload quedan como placeholder <OQ-1>.
#  - OQ-5: application, owner, cost_center, data_classification, compliance,
#    criticality. Los fija el Service Owner y se registran en el catalogo.
#  - OQ-6: define si el workload es CDE, lo que puede forzar data_classification
#    en {confidential, restricted, pci} y compliance en {lpdp, pci-dss}
#    (Requisito 11.3). data_classification y compliance aqui deben respetar esa
#    decision.
#
# La carpeta padre (workloads/OQ-1-workload) tambien es un placeholder: debe
# renombrarse al codigo de workload catalogado cuando se resuelva OQ-1.
# =============================================================================
locals {
  # TODO(OQ-1): workload catalogado del contact center (p.ej. "channels").
  workload = "<OQ-1>"

  # TODO(OQ-5): application registrada en catalogos-cloud.yaml applications.<app>,
  # con workload, owner y cost_center coincidentes.
  application = "<OQ-5>"

  # TODO(OQ-5): equipo responsable (nunca una persona). Valor de catalogo.
  owner = "<OQ-5>"

  # TODO(OQ-5): centro de costo ^[0-9]{6}$ del catalogo.
  cost_center = "<OQ-5>"

  # TODO(OQ-5 / OQ-6): clasificacion del dato. En {public, internal, confidential,
  # restricted, pci}. Para Customer Profiles debe ser confidential|restricted|pci
  # (Requisito 11.3). Depende de la decision PCI (OQ-6).
  data_classification = "<OQ-5>"

  # TODO(OQ-5 / OQ-6): compliance. En {general, pci-dss, lpdp}. lpdp por defecto;
  # pci-dss si la cuenta es CDE (Requisito 11.3, OQ-6).
  compliance = "<OQ-5>"

  # TODO(OQ-5): criticidad en {tier-0, tier-1, tier-2, tier-3}.
  criticality = "<OQ-5>"
}
