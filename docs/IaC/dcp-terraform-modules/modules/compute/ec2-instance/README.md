# compute/ec2-instance

> **Módulo nuevo (v1.0.0).** Es el ejemplo de cómo un equipo agrega un módulo que no existe en `dcp-terraform-modules`. Ver `PR-NUEVO-MODULO.md` en la raíz del repo.

## Propósito y límites

Crea **una** instancia EC2 de aplicación en subredes privadas compartidas por Networking, con su Security Group, su rol IAM y su log group.

No crea: VPC, subredes, NAT, balanceadores, AMIs, llaves SSH ni Auto Scaling Groups. Para más de una instancia del mismo propósito se instancia el módulo varias veces con `ordinal` distinto, o se usa un módulo de ASG cuando exista.

## Recursos creados

| Recurso | Nombre | Ejemplo (dev) |
|---|---|---|
| `aws_instance` | `dcp-<domain>-<env>-<workload>-ec2-<purpose>-<region>-<ordinal>` | `dcp-diners-dev-merchants-ec2-portal-use1-01` |
| `aws_security_group` | `dcp-<domain>-<env>-<workload>-sg-<purpose>` | `dcp-diners-dev-merchants-sg-portal` |
| Reglas de SG | una por puerto y CIDR | — |
| `aws_iam_role` + instance profile | `dcp-<domain>-<env>-<workload>-role-ec2-<purpose>` | `dcp-diners-dev-merchants-role-ec2-portal` |
| `aws_iam_policy` (opcional) | `dcp-<domain>-<env>-<workload>-policy-<purpose>-runtime` | `dcp-diners-dev-merchants-policy-portal-runtime` |
| `aws_cloudwatch_log_group` | `/dcp/<domain>/<env>/<workload>/<purpose>` | `/dcp/diners/dev/merchants/portal` |
| `aws_ssm_parameter` (contrato) | `/dcp/<domain>/<env>/<workload>/config/<purpose>-sg-id` | `/dcp/diners/dev/merchants/config/portal-sg-id` |

## Inputs principales

| Input | Obligatorio | Descripción |
|---|---|---|
| `environment`, `workload`, `purpose`, `region_code` | sí | Piezas del nombre; se validan contra el catálogo. |
| `instance_type` | sí | Tipo de instancia. |
| `ami_id_parameter` | sí | Parámetro SSM de la AMI endurecida de Platform (`/dcp/platform/ami/...`). |
| `vpc_id_parameter`, `subnet_ids_parameter` | no | Contratos de Networking; tienen valor por defecto. |
| `ingress_rules`, `egress_rules` | no | Orígenes y destinos por parámetro SSM o por SG. Nunca `0.0.0.0/0`. |
| `rds_iam_db_users`, `secrets_read_paths` | no | Permisos de la app en tiempo de ejecución. |
| `ebs_kms_key_arn`, `log_kms_key_arn` | no | CMK; obligatoria para datos `restricted` o `pci`. |
| `tags` | no | Solo tags complementarios. Los obligatorios llegan por `default_tags`. |

## Outputs

`instance_id`, `instance_name`, `private_ip`, `security_group_id`, `security_group_parameter_name`, `role_arn`, `log_group_name`.

## Providers y versiones

Terraform `>= 1.15.8, < 1.16.0`; `hashicorp/aws >= 6.47.0, < 7.0.0` (desde el mirror de Nexus).

## Supuestos de seguridad

- IMDSv2 obligatorio y volumen raíz cifrado.
- Sin llaves SSH: acceso por Session Manager (`AmazonSSMManagedInstanceCore`).
- Rol con permission boundary `dcp-platform-permission-boundary`.
- La app se conecta a Aurora por autenticación IAM; no hay contraseñas en `user_data` (una validación las rechaza).
- `disable_api_termination` activo en prod.

## Costos relevantes

Instancia, volumen gp3, métricas detalladas (`detailed_monitoring`) y retención de logs.

## Comportamiento de reemplazo

| Cambio | Efecto |
|---|---|
| `instance_type` | Detiene y reinicia la instancia (sin reemplazo). |
| `subnet_index`, `user_data`, `purpose`, `ordinal` | **Reemplaza** la instancia. |
| AMI nueva publicada por Platform | Ignorada hasta un `-replace` planificado. |
| Nombre del SG | Crea el SG nuevo antes de borrar el anterior. |

## Estrategia de actualización

SemVer. Un cambio de inputs u outputs es **major** y requiere deprecación previa. Los cambios de dirección de recursos llevan bloques `moved`.

## Ejemplos

- `examples/basic`: dev, sin entrada.
- `examples/production`: prod con CMK, acceso IAM a Aurora y lectura de secretos.
