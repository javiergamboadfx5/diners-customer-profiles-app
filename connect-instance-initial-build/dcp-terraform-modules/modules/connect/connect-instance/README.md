# connect/connect-instance

Módulo de Amazon Connect del build dev de Diners Club Perú. Un solo módulo sirve
a tres stacks del Live_Repo mediante el switch `component`:

| `component` | Crea | Stack que lo usa | Contrato SSM que publica |
|---|---|---|---|
| `kms` | CMK de almacenamiento (rotación 365 d, ventana de borrado 30 d), su alias | `kms/` (Storage_KMS_Stack) | `connect-kms-key-arn` |
| `storage` | Bucket S3 endurecido + política + ciclo de vida | `storage/` (Storage_Stack) | `connect-storage-bucket-name` |
| `instance` | Instancia Connect, log group de flujos, 2 storage configs | `instance/` (Instance_Stack) | `connect-instance-id`, `connect-instance-arn`, `connect-instance-alias` |

Los proyectos lo consumen por SHA de 40 caracteres desde `dcp-terraform-modules`
(`git::ssh://git@github.com/Diners/dcp-terraform-modules.git//modules/connect/connect-instance?ref=<SHA>`);
nunca se copia al repo live.

> **Categoría `connect/` pendiente de confirmación de Platform** (L03
> `<category>/<module>`).

## Propósito y límites

El módulo crea la base de almacenamiento y la instancia de un contact center de
Connect bajo los controles del banco (PCI DSS v4.0.1, L14). Según el componente
activo:

- `kms`: una CMK simétrica dedicada a grabaciones y transcripciones, con
  administración separada del uso (DR-3), condiciones `aws:SourceAccount` en
  todo principal de servicio y un statement para que CloudWatch Logs cifre el
  log group de flujos con esta misma clave (DD-1).
- `storage`: el bucket de almacenamiento con los 4 ajustes de Block Public
  Access, `BucketOwnerEnforced`, versionado, SSE-KMS con bucket key, política de
  denegación de transporte inseguro y de clave/algoritmo equivocados, y reglas
  de ciclo de vida por prefijo.
- `instance`: la instancia Connect con Contact Lens, los dos storage configs
  (`CALL_RECORDINGS`, `CHAT_TRANSCRIPTS`) cifrados con KMS, y el log group
  `/aws/connect/<alias>` creado antes de la instancia (DD-6).

**No crea** (fuera de alcance de este módulo): flujos de contacto, colas,
perfiles de seguridad, usuarios, números de teléfono, horarios, ni recursos
adicionales para contact-type tasks (funcionan con los valores por defecto de la
instancia, Req 6.2). Tampoco crea la VPC, subredes ni ningún recurso de red
(las cuentas de workload consumen la Shared VPC vía RAM).

**Seguridad gestionada fuera del módulo:** CloudTrail S3 data events y Macie
para el bucket (cuando la cuenta está en alcance CDE) los habilita un PR en
`dcp-aws-security-live`, no este módulo (DD-2). El módulo solo exige una
referencia de cobertura (`security_coverage_ref`) cuando `cde_scope = true`.

## Recursos

Por componente (`<prefix>` = `dcp-diners-<env>-<workload>`):

**`component = "kms"`**

| Recurso | Nombre / nota |
|---|---|
| `aws_kms_key.storage` | CMK simétrica, rotación 365 d, borrado 30 d, `prevent_destroy` |
| `aws_kms_alias.storage` | `alias/dcp/diners/<env>/<workload>/connect-storage` |
| `aws_ssm_parameter.connect_kms_key_arn` | `/dcp/diners/<env>/<workload>/config/connect-kms-key-arn` |

**`component = "storage"`**

| Recurso | Nota |
|---|---|
| `aws_s3_bucket.storage` | `<prefix>-s3-connect-storage-use1-<unique>`, `prevent_destroy` |
| `aws_s3_bucket_public_access_block.storage` | 4 ajustes en `true` |
| `aws_s3_bucket_ownership_controls.storage` | `BucketOwnerEnforced` |
| `aws_s3_bucket_versioning.storage` | `Enabled` |
| `aws_s3_bucket_server_side_encryption_configuration.storage` | `aws:kms` + bucket key, CMK del contrato SSM |
| `aws_s3_bucket_policy.storage` | `DenyInsecureTransport`, `DenyWrongKmsKey`, `DenyNonKmsEncryption` |
| `aws_s3_bucket_lifecycle_configuration.storage` | expiración por prefijo y de versiones no actuales + abort multipart 7 d |
| `aws_ssm_parameter.connect_storage_bucket_name` | `/dcp/diners/<env>/<workload>/config/connect-storage-bucket-name` |

**`component = "instance"`**

| Recurso | Nota |
|---|---|
| `aws_cloudwatch_log_group.flow_logs` | `/aws/connect/<alias>`, cifrado con la CMK de almacenamiento (DD-1), creado antes de la instancia (DD-6) |
| `aws_connect_instance.this` | Contact Lens + flow logs + llamadas; `prevent_destroy` |
| `aws_connect_instance_storage_config.call_recordings` | `CALL_RECORDINGS`, S3 + KMS |
| `aws_connect_instance_storage_config.chat_transcripts` | `CHAT_TRANSCRIPTS`, S3 + KMS |
| `aws_ssm_parameter.connect_instance_id` / `_arn` / `_alias` | contratos del workload |

Data sources comunes: `aws_partition`, `aws_caller_identity`, `aws_region`.
El componente `storage` lee `connect-kms-key-arn` y el `instance` lee
`connect-kms-key-arn` y `connect-storage-bucket-name`, todos por
`data "aws_ssm_parameter"` sin default: un contrato ausente falla el plan de
forma nativa (Req 5.3, 6.4). El componente `kms` lee el rol key-admin de
`/dcp/diners/<env>/<workload>/config/key-admin-role-arn` (OQ-13).

## Proveedores

| Proveedor | Versión | Uso |
|---|---|---|
| Terraform | `>= 1.15.8, < 1.16.0` | runtime `1.15.8` |
| `hashicorp/aws` | `>= 6.47.0, < 7.0.0` | todos los recursos |

El módulo no declara `configuration_aliases`: opera en una sola región/cuenta
(la de la instancia). Los proveedores se instalan solo desde el mirror de Nexus.

## Entradas

Comunes a los tres componentes salvo indicación:

| Nombre | Tipo | Default | Obligatoria | Descripción |
|---|---|---|---|---|
| `component` | string | — | sí | `kms`, `storage` o `instance`. |
| `domain` | string | `diners` | no | Único dominio aprobado. |
| `environment` | string | — | sí | `dev`, `qa`, `stg` o `prod`. |
| `workload` | string | — | sí | Capacidad del catálogo, `^[a-z][a-z0-9]{1,9}$` (≤ 10 por el límite del bucket). |
| `region_code` | string | — | sí | `use1`, `use2`, `usw2` o `sae1`. |
| `org_id` | string | — | sí | `o-xxxxxxxxxx`. Determinista del root/catálogo; solo interviene en el nombre del bucket. |
| `account_id` | string | — | sí | 12 dígitos de la cuenta. Determinista del root/catálogo; solo interviene en el nombre del bucket. |
| `cde_scope` | bool | — | sí | Alcance CDE (OQ-6). Sin default a propósito: bloquea el plan hasta que Ciberseguridad lo resuelva. |
| `security_coverage_ref` | string | `""` | condicional | Referencia de cobertura de CloudTrail data events y Macie (DD-2). Obligatoria y no vacía cuando `cde_scope = true`. |

Identidad e instancia (componente `instance`):

| Nombre | Tipo | Default | Descripción |
|---|---|---|---|
| `instance_alias` | string | `null` | Alias Connect, `^[a-z0-9]([a-z0-9-]{0,60}[a-z0-9])?$` (1 a 62). **Cambiarlo reemplaza la instancia.** |
| `identity_management_type` | string | `SAML` | `SAML`, `CONNECT_MANAGED` o `EXISTING_DIRECTORY`. **Cambiarlo reemplaza la instancia.** |
| `directory_id` | string | `null` | Obligatorio con `EXISTING_DIRECTORY`. |
| `exception_id` | string | `""` | `^exc-cloud-[0-9]{4}-[0-9]{4}$`. Requerido en qa/stg/prod no-SAML (Req 3.5) y en dev `CONNECT_MANAGED` (Req 3.6). |
| `inbound_calls_enabled` | bool | `true` | Llamadas entrantes. |
| `outbound_calls_enabled` | bool | `true` | Llamadas salientes. |
| `contact_flow_logs_enabled` | bool | `true` | Logs de flujos. |
| `contact_lens_enabled` | bool | `true` | Contact Lens (el módulo lo fija en `true` en la instancia, Req 6.1). |
| `flow_log_retention_days` | number | `null` | Retención del log group; valor permitido por CloudWatch, nunca 0 (Req 6.5). |

Almacenamiento (componentes `storage` e `instance`):

| Nombre | Tipo | Default | Descripción |
|---|---|---|---|
| `bucket_prefix_recordings` | string | `connect/call-recordings` | Prefijo S3 de grabaciones, sin barra inicial. |
| `bucket_prefix_transcripts` | string | `connect/chat-transcripts` | Prefijo S3 de transcripciones, sin barra inicial. |
| `recordings_retention_days` | number | `null` | Días de retención de grabaciones; entero ≥ 1 (OQ-7). |
| `transcripts_retention_days` | number | `null` | Días de retención de transcripciones; entero ≥ 1 (OQ-7). |
| `noncurrent_retention_days` | number | `null` | Días de retención de versiones no actuales; entero ≥ 1 (OQ-7). |
| `tags` | map(string) | `{}` | Solo tags complementarios del catálogo (`Criticality`, `BackupPolicy`, `ExpiryDate`, `ExceptionId`, `Service`). |

El módulo añade únicamente el tag `Name` (Req 2.6); el resto de tags
obligatorios los inyecta el root `terragrunt.hcl` vía provider `default_tags`.

## Salidas

| Nombre | Descripción | Valor cuando el componente no aplica |
|---|---|---|
| `name_prefix` | `dcp-diners-<env>-<workload>`. | siempre |
| `kms_alias` | Alias de la CMK de almacenamiento. | siempre (nombre, libre de proveedor) |
| `ssm_base` | Base de contratos SSM del workload. | siempre |
| `kms_key_arn` | ARN de la CMK. | `null` |
| `kms_key_id` | ID de la CMK. | `null` |
| `bucket_name` | Nombre del bucket. | `null` |
| `bucket_arn` | ARN del bucket. | `null` |
| `instance_id` | ID de la instancia. | `null` |
| `instance_arn` | ARN de la instancia. | `null` |
| `instance_alias` | Alias de la instancia. | `null` |
| `log_group_name` | Nombre del log group de flujos. | `null` |
| `ssm_parameter_names` | Mapa de contratos SSM publicados por el componente activo. | `{}` |

## Ejemplo básico

`examples/basic/` activa el componente `kms` en dev (`cde_scope = false`). Es el
primer stack del orden de apply porque publica `connect-kms-key-arn`:

```hcl
module "connect_kms" {
  source = "../.."

  component   = "kms"
  domain      = "diners"
  environment = "dev"
  workload    = "<OQ-1>"
  region_code = "use1"

  org_id     = "o-example00"
  account_id = "000000000000"

  cde_scope = false
}
```

## Ejemplo producción

`examples/production/` activa el componente `instance` con SAML y Contact Lens.
Lee los contratos `connect-kms-key-arn` y `connect-storage-bucket-name` (que
publican los stacks `kms` y `storage`) y, en alcance CDE, exige
`security_coverage_ref`:

```hcl
module "connect_instance" {
  source = "../.."

  component   = "instance"
  domain      = "diners"
  environment = "prod"
  workload    = "<OQ-1>"
  region_code = "use1"

  org_id     = "o-example00"
  account_id = "000000000000"

  instance_alias           = "<OQ-8>"
  identity_management_type = "SAML"
  flow_log_retention_days  = 365

  cde_scope             = true
  security_coverage_ref = "<security-coverage-ref>"
}
```

## Supuestos de seguridad

- **Cifrado en reposo con CMK dedicada.** El bucket y el log group de flujos se
  cifran con la CMK de almacenamiento; no hay fallback a SSE-S3 ni a una clave
  gestionada por AWS. Si el contrato `connect-kms-key-arn` falta o llega vacío,
  el plan falla (Req 5.3, 6.4).
- **Administración separada del uso en KMS** (DR-3). El statement
  `KeyAdministration` no incluye `Encrypt`/`Decrypt`/`GenerateDataKey*`/`ReEncrypt*`;
  el uso va en statements aparte. Ningún Allow usa `Principal: "*"` sin
  `Condition`, y todo principal de servicio lleva `aws:SourceAccount` de la
  cuenta (Req 4.2, 4.3). El rol key-admin entra por contrato SSM (OQ-13), nunca
  como ARN literal.
- **Bucket nunca público ni en claro.** 4 ajustes de Block Public Access,
  `BucketOwnerEnforced`, versionado y SSE-KMS; la política niega
  `aws:SecureTransport = false`, las subidas con otra clave KMS y las subidas
  cuyo algoritmo no sea `aws:kms` (Req 5.2, 5.4). Los Deny con `Principal: "*"`
  son correctos aquí (la regla de wildcard del guardrail aplica solo a los Allow
  de las políticas KMS).
- **El módulo no abre ningún control CDE por sí mismo.** CloudTrail data events
  y Macie los habilita `dcp-aws-security-live` (DD-2). Clasificación de datos:
  grabaciones y transcripciones son `restricted` como mínimo; el tag
  `DataClassification`/`Compliance` lo pone el root según el catálogo y OQ-6.
- **Recursos protegidos.** La CMK, el bucket y la instancia llevan
  `prevent_destroy = true` literal; un plan que los destruya o reemplace falla.

## Costos

Órdenes de magnitud (us-east-1; confirmar con la calculadora de AWS):

- **KMS:** la CMK tiene un costo mensual fijo por clave más el costo por
  solicitudes de cifrado. Bucket key en S3 reduce drásticamente las solicitudes
  KMS por objeto.
- **S3:** almacenamiento por GB-mes de grabaciones y transcripciones (crece con
  el volumen de contactos y la retención OQ-7), más solicitudes. El versionado y
  las reglas de ciclo de vida acotan el crecimiento al expirar objetos y
  versiones no actuales.
- **Amazon Connect:** se factura por uso (minutos de voz, mensajes de chat,
  tareas) y Contact Lens por minuto/mensaje analizado. La instancia en sí no
  tiene costo fijo; el gasto lo marca el tráfico del contact center.
- **CloudWatch Logs:** ingesta y almacenamiento del log group de flujos, acotado
  por `flow_log_retention_days`.
- **SSM Parameter Store:** los contratos son parámetros `String` estándar, sin
  costo relevante.

El mayor riesgo de costo es la retención del almacenamiento; por eso las
lifecycle rules dependen de valores aprobados por Cumplimiento (OQ-7).

## Comportamiento de reemplazo

- **`instance_alias` e `identity_management_type` fuerzan el reemplazo de la
  instancia** (son atributos `ForceNew` de `aws_connect_instance`). Como la
  instancia tiene `prevent_destroy = true`, cambiar cualquiera de los dos
  convierte el plan en un error en vez de recrear la instancia (Req 6.6). Para
  cambiarlos de verdad hay que retirar la protección de forma deliberada,
  evaluar el impacto y usar `moved`/`import` según corresponda; no se recrea una
  instancia de producción para reorganizar.
- **La CMK, su alias y el bucket** también están protegidos con
  `prevent_destroy`. Cambiar el nombre del bucket (que depende de `workload`,
  `region_code`, `org_id` y `account_id`) o recrear la CMK falla el plan.
- El log group `/aws/connect/<alias>` se recrea si cambia el alias (su nombre
  deriva del alias); como el cambio de alias ya falla por la instancia
  protegida, no se llega a recrear el log group.
- El resto de recursos (configuración S3, storage configs, políticas, contratos
  SSM) se actualizan in-place o se reemplazan sin pérdida de datos.

## Estrategia de upgrade / cambios incompatibles

- El módulo se publica con tags SemVer `connect/connect-instance/vX.Y.Z`
  firmados; los stacks lo fijan por SHA de 40 caracteres registrado en
  `compatibility.yaml`. Un upgrade es un PR que cambia ese SHA tras revisar el
  diff del plan.
- **Patch** (fix sin cambio de contrato): sin acción en el stack más allá del
  nuevo SHA. **Minor** (nueva variable opcional / nuevo output): compatible.
  **Major** (cambio de contrato: renombrar/eliminar una variable u output,
  cambiar un nombre físico, cambiar el switch `component`): requiere
  deprecación previa y, cuando toca direcciones de recursos, bloques `moved`;
  adoptar recursos existentes requiere `import`.
- Cambiar la plantilla de un nombre físico (bucket, alias, log group) es un
  cambio mayor: `check "physical_name_limits"` falla el plan si el bucket supera
  63 caracteres o el alias el límite, y `prevent_destroy` impide recrear el
  recurso. Planifíquelo con `moved`/`import` y evaluación de impacto.
- Rango de proveedor AWS acotado al major 6 (`>= 6.47.0, < 7.0.0`): subir a AWS
  7 es un cambio mayor que exige nueva entrada en `compatibility.yaml` y
  revalidación de los storage configs y las políticas KMS/S3.

## Notas de diseño

- **DD-1 — log group cifrado con la CMK de almacenamiento.** No existe un tercer
  stack de clave: el log group `/aws/connect/<alias>` se cifra con la misma CMK
  de almacenamiento. Por eso la política de la clave (componente `kms`) incluye
  un statement `LogsService` para el principal `logs.us-east-1.amazonaws.com`,
  condicionado por `aws:SourceAccount` y por
  `kms:EncryptionContext:aws:logs:arn` sobre `/aws/connect/*`.
- **DD-2 — CloudTrail data events y Macie son de `dcp-aws-security-live`.** Este
  módulo no crea los data events de S3 ni la cobertura de Macie del bucket; los
  habilita un PR en `dcp-aws-security-live`. El módulo solo exige una referencia
  de cobertura no vacía (`security_coverage_ref`) cuando `cde_scope = true`
  (Req 5.6); si falta, el plan del componente que la requiere falla en
  validación.
- **DD-6 — orden del log group.** El log group `/aws/connect/<alias>` se crea
  antes que la instancia (`depends_on`), para que Terraform controle su KMS,
  retención y tags, y para que la `precondition` falle el plan si los contratos
  de almacenamiento llegan vacíos antes de planear la instancia.
