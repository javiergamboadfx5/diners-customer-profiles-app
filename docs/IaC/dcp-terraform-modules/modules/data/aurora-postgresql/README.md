# data/aurora-postgresql

> **Módulo existente (v1.3.0).** Los proyectos lo consumen tal cual, por SHA. Si necesitan algo que no tiene, abren un issue o PR en este repo; no lo copian al repo live.

## Propósito y límites

Crea un cluster Aurora PostgreSQL privado, cifrado con CMK propia, con TLS obligatorio, autenticación IAM y contraseña maestra administrada por RDS en Secrets Manager.

No crea: subredes, proxies, réplicas globales ni usuarios de aplicación (se crean con la migración de esquema de la app).

## Recursos creados

| Recurso | Nombre | Ejemplo (prod) |
|---|---|---|
| Cluster | `dcp-<domain>-<env>-<workload>-aurora-<purpose>-<region>` | `dcp-diners-prod-merchants-aurora-core-use1` |
| Instancias | `<cluster>-instance-NN` | `dcp-diners-prod-merchants-aurora-core-use1-instance-01` |
| DB subnet group | `dcp-<domain>-<env>-<workload>-dbsubnet-<region>` | `dcp-diners-prod-merchants-dbsubnet-use1` |
| Cluster parameter group | `dcp-<domain>-<env>-<workload>-aurora-pg-<major>` | `dcp-diners-prod-merchants-aurora-pg-16` |
| Security group | `dcp-<domain>-<env>-<workload>-sg-aurora` | `dcp-diners-prod-merchants-sg-aurora` |
| KMS alias | `alias/dcp/<domain>/<env>/<workload>/data` | `alias/dcp/diners/prod/merchants/data` |
| Log group | `/aws/rds/cluster/<cluster>/postgresql` (prefijo nativo de AWS) | — |
| Secreto maestro | Nombre generado por RDS (`rds!cluster-...`); excepción de naming documentada | — |

## Entradas clave

`environment`, `workload`, `region_code`, `instance_class`, `instance_count`, `database_name`, `allowed_security_group_id_parameters` (contratos SSM de los SG que pueden conectarse).

## Reglas que el módulo impone

- En prod: 2 instancias o más, `deletion_protection` y 7 días o más de backup (precondición).
- `rds.force_ssl = 1`, `publicly_accessible = false`, `storage_encrypted = true`.
- Sin reglas de salida en el SG; la entrada solo desde SG publicados como contrato.

## Comportamiento de reemplazo

Cambiar `purpose`, `workload`, `region_code`, `database_name` o `master_username` **reemplaza el cluster** (pérdida de datos si no hay snapshot). `instance_class` y `engine_version` (minor) se aplican en la ventana de mantenimiento en prod.
