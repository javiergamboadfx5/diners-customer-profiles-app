# connect/connect-customer-profiles

Módulo de Amazon Connect Customer Profiles del build dev de Diners Club Perú. Un
solo módulo sirve a dos stacks del Live_Repo mediante el switch `component`:

| `component` | Crea | Stack que lo usa | Contrato SSM que publica |
|---|---|---|---|
| `kms` | CMK dedicada de Customer Profiles (rotación 365 d, ventana de borrado 30 d), su alias | `kms-customer-profiles/` (Profiles_KMS_Stack) | `customer-profiles-kms-key-arn` |
| `domain` | Dominio de Customer Profiles, tipo de objeto `CTR` y una integración con la instancia | `customer-profiles/` (Profiles_Stack) | `customer-profiles-domain-name`, `customer-profiles-domain-arn` |

Los proyectos lo consumen por SHA de 40 caracteres desde `dcp-terraform-modules`
(`git::ssh://git@github.com/Diners/dcp-terraform-modules.git//modules/connect/connect-customer-profiles?ref=<SHA>`);
nunca se copia al repo live.

> **Categoría `connect/` pendiente de confirmación de Platform** (L03
> `<category>/<module>`).

## Propósito y límites

El módulo crea la CMK dedicada y el dominio de Customer Profiles de un contact
center de Connect bajo los controles del banco (PCI DSS v4.0.1, LPDP, L14).
Según el componente activo:

- `kms`: una CMK simétrica **dedicada** a Customer Profiles, separada de la CMK
  de almacenamiento de grabaciones/transcripciones para que Profiles_App nunca
  alcance esos datos (L14 DR-4). Administración separada del uso, condiciones
  `aws:SourceAccount` en todo principal de servicio y, cuando `bind_domain_arn`,
  `aws:SourceArn` del dominio computado (DD-5). Incluye un statement opcional
  para Profiles_App solo cuando su rol está publicado en SSM (OQ-11).
- `domain`: el dominio de Customer Profiles (`matching` desactivado, expiración
  del input, data store apagado por defecto), el tipo de objeto `CTR` desde la
  plantilla `CTR-AutoAssociateOnly` y una única integración con la instancia.

El dominio y el tipo de objeto **no definen campos para PAN, CVV, PIN, track
data ni ningún otro dato sensible de autenticación** (Req 8.10). El tipo de
objeto `CTR` se crea solo desde la plantilla (`template_id`), que aporta sus
propios Fields y Keys; el módulo no declara ningún campo propio, de modo que es
estructuralmente imposible introducir un nombre de campo prohibido.

**No crea** (fuera de alcance de este módulo): la instancia de Connect ni sus
contratos (los provee `connect/connect-instance`), el rol de Profiles_App ni su
política (los crea el repo que posee Profiles_App, Req 9), flujos, perfiles de
seguridad, usuarios, ni recursos de red.

## Recursos

Por componente (`<prefix>` = `dcp-diners-<env>-<workload>`):

**`component = "kms"`**

| Recurso | Nombre / nota |
|---|---|
| `aws_kms_key.profiles` | CMK simétrica, rotación 365 d, borrado 30 d, `prevent_destroy` |
| `aws_kms_alias.profiles` | `alias/dcp/diners/<env>/<workload>/customer-profiles` |
| `aws_iam_policy_document.profiles_key` | statements `KeyAdministration`, `ProfileService`, `ConnectService`, `DeployRole`, y `ProfilesApp` opcional |
| `aws_ssm_parameter.profiles_kms_key_arn` | `/dcp/diners/<env>/<workload>/config/customer-profiles-kms-key-arn` |

**`component = "domain"`** (requiere `awscc`, [Blocked: OQ-12])

| Recurso | Nota |
|---|---|
| `aws_customerprofiles_domain.this` | `amazon-connect-dcp-diners-<env>-<workload>`, matching off, SSE-KMS del contrato SSM, `prevent_destroy` |
| `awscc_customerprofiles_object_type.ctr` | `CTR` desde la plantilla `CTR-AutoAssociateOnly`, sin fields propios |
| `awscc_customerprofiles_integration.ctr` | única integración, `uri` = ARN de la instancia (SSM `connect-instance-arn`) |
| `aws_ssm_parameter.profiles_domain_name` | `/dcp/diners/<env>/<workload>/config/customer-profiles-domain-name` |
| `aws_ssm_parameter.profiles_domain_arn` | `/dcp/diners/<env>/<workload>/config/customer-profiles-domain-arn` |

Data sources comunes: `aws_partition`, `aws_caller_identity`, `aws_region`. El
componente `kms` lee el rol key-admin de
`/dcp/diners/<env>/<workload>/config/key-admin-role-arn` (OQ-13, sin default:
una `postcondition` falla el plan con el mensaje de OQ-13) y consulta el path de
config con `aws_ssm_parameters_by_path` para el statement opcional de
Profiles_App (OQ-11, lista vacía = statement omitido). El componente `domain`
lee `customer-profiles-kms-key-arn` y `connect-instance-arn` por
`data "aws_ssm_parameter"` sin default: un contrato ausente falla el plan de
forma nativa y el dominio no se planifica (Req 8.2).

El módulo añade únicamente el tag `Name` (Req 2.6); el resto de tags
obligatorios los inyecta el root `terragrunt.hcl` vía provider `default_tags`.

## Proveedores

| Proveedor | Versión | Uso |
|---|---|---|
| Terraform | `>= 1.15.8, < 1.16.0` | runtime `1.15.8` |
| `hashicorp/aws` | `>= 6.47.0, < 7.0.0` | CMK, alias, dominio, parámetros SSM, data sources |
| `hashicorp/awscc` | `>= 1.0.0, < 2.0.0` | tipo de objeto `CTR` e integración (componente `domain`) **[Blocked: OQ-12]** |

### Por qué `awscc`

El proveedor `hashicorp/aws` expone `aws_customerprofiles_domain`, pero **no**
expone recursos para el mapeo de tipo de objeto ni para la integración de la
instancia. Esos recursos solo existen en `hashicorp/awscc`
(`awscc_customerprofiles_object_type`, `awscc_customerprofiles_integration`),
por lo que el componente `domain` lo requiere. El límite mayor va acotado
(`< 2.0.0`) por el estándar de módulos (L03). La entrada de `awscc` debe
registrarse en `compatibility.yaml` con el espejo de Nexus antes de que el
componente `domain` pueda mezclarse (OQ-12). El código se deja completo y
funcional; el bloqueo es de registro, no de implementación.

El módulo no declara `configuration_aliases`: opera en una sola región/cuenta.
Los proveedores se instalan solo desde el mirror de Nexus.

## Entradas

Comunes a ambos componentes salvo indicación:

| Nombre | Tipo | Default | Obligatoria | Descripción |
|---|---|---|---|---|
| `component` | string | — | sí | `kms` o `domain`. |
| `domain` | string | `diners` | no | Único dominio cloud aprobado. |
| `workload` | string | — | sí | Capacidad del catálogo, `^[a-z][a-z0-9]{1,9}$` (OQ-1). |
| `region_code` | string | — | sí | `use1`, `use2`, `usw2` o `sae1`. |
| `environment` | string | — | sí | `dev`, `qa`, `stg` o `prod`. |
| `cde_scope` | bool | — | sí | Alcance CDE (OQ-6). Determina el chequeo del tag `Compliance`. |
| `matching_enabled` | bool | `false` | no | Matching de perfiles. Debe permanecer en `false` por el diseño de la app (Req 8.1). |
| `bind_domain_arn` | bool | `true` | no | Enlaza `aws:SourceArn` del dominio en la política de la clave desde el primer apply (DD-5). |
| `tags` | map(string) | `{}` | no | Solo tags complementarios del catálogo (`Criticality`, `BackupPolicy`, `ExpiryDate`, `ExceptionId`, `Service`). |

Dominio (componente `domain`):

| Nombre | Tipo | Default | Descripción |
|---|---|---|---|
| `domain_name` | string | `null` | Nombre del dominio. Prefijo obligatorio `amazon-connect-`, ≤ 64, `[A-Za-z0-9_-]`. Si es `null` se computa `amazon-connect-dcp-diners-<env>-<workload>`. **Cambiarlo reemplaza el dominio.** |
| `default_expiration_days` | number | `null` | Días de expiración por defecto (OQ-10). Entero entre 1 y 1098. Sin valor, el plan falla. |
| `enable_data_store` | bool | `false` | Habilita el data store. Apagado por defecto (retención de 10 años, LPDP). |
| `data_store_approval_ref` | string | `""` | Referencia de aprobación de Cumplimiento; obligatoria y no vacía cuando `enable_data_store = true` (Req 8.4). |

Excepción (ambos componentes, cuando aplica OQ-14):

| Nombre | Tipo | Default | Descripción |
|---|---|---|---|
| `require_exception` | bool | `false` | Fuerza la validación de `exception_id` (p. ej. OQ-14 para el prefijo `amazon-connect-`). |
| `exception_id` | string | `""` | `^exc-cloud-[0-9]{4}-[0-9]{4}$`. Obligatorio cuando `require_exception = true`. |

## Salidas

| Nombre | Descripción | Valor cuando el componente no aplica |
|---|---|---|
| `kms_key_arn` | ARN de la CMK dedicada de perfiles. | `null` (si `component != kms`) |
| `kms_key_id` | ID de la CMK dedicada de perfiles. | `null` (si `component != kms`) |
| `kms_alias` | Alias de la CMK dedicada de perfiles. | siempre (nombre, libre de proveedor) |
| `profiles_app_statement_present` | `true` si la política de la clave incluye el statement `ProfilesApp` (contrato `profiles-app-role-arn` publicado, Req 7.4). | `null` (si `component != kms`) |
| `profiles_domain_name` | Nombre del dominio (efectivo si `component = domain`; computado en otro caso). | nombre computado |
| `profiles_domain_arn` | ARN del dominio. | `null` (si `component != domain`) |
| `profiles_object_type_name` | Nombre del tipo de objeto (`CTR`). | `null` (si `component != domain`) |
| `profiles_integration_uri` | URI de la integración (ARN de la instancia). | `null` (si `component != domain`) |
| `ssm_base` | Base de los contratos SSM del workload. | siempre |

## Ejemplo básico

`examples/basic/` activa el componente `kms` en dev (`cde_scope = false`). Es el
primer stack del orden de apply (`kms-customer-profiles -> customer-profiles`),
porque publica el contrato `customer-profiles-kms-key-arn` que consume el
dominio. El rol key-admin (OQ-13) debe existir en el contrato SSM
`/dcp/diners/dev/<workload>/config/key-admin-role-arn` antes del apply real.

```hcl
module "profiles_kms" {
  source = "../.."

  component   = "kms"
  domain      = "diners"
  environment = "dev"
  workload    = "<OQ-1>"
  region_code = "use1"

  # Dev no está en alcance CDE.
  cde_scope = false
}
```

## Ejemplo producción

`examples/production/` activa el componente `domain`. Lee los contratos
`customer-profiles-kms-key-arn` (que publica el stack `kms-customer-profiles`) y
`connect-instance-arn` (que publica el stack `instance`); si falta cualquiera,
el plan falla antes de planear el dominio (Req 8.2). El data store queda apagado
por el valor por defecto (retención de 10 años, LPDP).

```hcl
module "profiles_domain" {
  source = "../.."

  component   = "domain"
  domain      = "diners"
  environment = "prod"
  workload    = "<OQ-1>"
  region_code = "use1"

  default_expiration_days = 1098 # <OQ-10>, entero 1..1098
  enable_data_store       = false

  cde_scope = true
}
```

## Supuestos de seguridad

- **CMK dedicada, separada del almacenamiento** (L14 DR-4). La clave de perfiles
  es distinta de la CMK de grabaciones/transcripciones, y su política no otorga
  a Profiles_App ningún permiso sobre esa otra clave (Req 7.5). Así, la app de
  perfiles no puede descifrar grabaciones ni transcripciones.
- **Administración separada del uso en KMS** (DR-3). El statement
  `KeyAdministration` no incluye acciones de datos; el uso va en statements
  aparte (`ProfileService`, `ConnectService`, `DeployRole`, `ProfilesApp`).
  Ningún Allow usa `Principal: "*"` sin `Condition`, y todo principal de servicio
  lleva `aws:SourceAccount` de la cuenta (Req 7.2, 7.5). Cuando `bind_domain_arn`,
  `ProfileService` también se condiciona por `aws:SourceArn` del dominio
  computado (DD-5), de modo que la condición rige desde el primer apply sin
  requerir que el dominio ya exista. El rol key-admin y el rol de Profiles_App
  entran por contrato SSM (OQ-13, OQ-11), nunca como ARN literal (Req 7.6).
- **Statement de Profiles_App opcional** (Req 7.3, 7.4). Solo se añade cuando el
  contrato `profiles-app-role-arn` existe; concede
  `Encrypt`/`Decrypt`/`GenerateDataKey`/`DescribeKey` condicionado por
  `aws:PrincipalArn` y `kms:ViaService = profile.us-east-1.amazonaws.com`. Si el
  contrato no está publicado, el statement se omite y el plan sigue adelante
  (OQ-11 queda pendiente en el PR).
- **Sin datos de tarjeta en los perfiles** (Req 8.10). Ni el dominio ni el tipo
  de objeto `CTR` definen campos para PAN, CVV, PIN, track data ni SAD. El tipo
  de objeto se crea solo desde la plantilla.
- **Clasificación de datos.** El dominio de Customer Profiles es
  `confidential`/`restricted`/`pci` con `Compliance` `lpdp` (o `pci-dss` en CDE);
  el tag lo pone el root según el catálogo y OQ-6 (Req 11.3).
- **Recurso protegido.** La CMK y el dominio llevan `prevent_destroy = true`
  literal; un plan que los destruya o reemplace falla.

## Costos

Órdenes de magnitud (us-east-1; confirmar con la calculadora de AWS):

- **KMS:** costo mensual fijo por clave más el costo por solicitudes de cifrado
  del dominio.
- **Amazon Connect Customer Profiles:** se factura por el número de perfiles
  almacenados y por las operaciones de la API. La expiración
  (`default_expiration_days`, OQ-10) acota el número de perfiles vivos. El
  **data store**, cuando se habilita, añade costo de almacenamiento y la
  retención de 10 años que impone (ver más abajo); por eso va apagado por
  defecto.
- **SSM Parameter Store:** los contratos son parámetros `String` estándar, sin
  costo relevante.

## Excepción de naming del dominio (OQ-14)

AWS exige que el nombre del dominio de Customer Profiles comience con el prefijo
`amazon-connect-`. Ese requisito lo impone la política gestionada
`AmazonConnectServiceLinkedRolePolicy`: el rol vinculado al servicio solo puede
operar sobre dominios cuyo nombre empieza por `amazon-connect-`. Un nombre sin
ese prefijo no funciona.

Esto **choca con el patrón de naming del banco** (`dcp-<domain>-<env>-...`,
iac-naming-tags L07). Bajo la **regla de precedencia 1** de `iac-core-rules`
(un constraint nativo de AWS gana sobre el patrón `dcp-...`), el constraint de
AWS prevalece. El módulo resuelve el conflicto componiendo ambos:

```
amazon-connect-dcp-diners-<environment>-<workload>
```

Así el nombre conserva el prefijo que AWS exige y, a continuación, el patrón
`dcp-...` del banco. La longitud queda muy por debajo del límite de 64
caracteres: 15 (`amazon-connect-`) + 11 (`dcp-diners-`) + `<env>` (≤ 4) + `-` +
`<workload>` (≤ 10).

La `validation` de `domain_name` comprueba las tres reglas por separado (prefijo,
longitud ≤ 64, caracteres `[A-Za-z0-9_-]`) y el mensaje nombra la regla violada
(Req 3.7).

**OQ-14 — ¿hace falta un registro `exc-cloud-*`?** El módulo no decide esa
condición de negocio: expone `require_exception` y `exception_id`. Si
Arquitectura Cloud determina que esta desviación del patrón de naming necesita
un registro de excepción formal (`exceptions/cloud/<id>.yaml`), el stack pone
`require_exception = true` y un `exception_id` válido, que además viaja como tag
`ExceptionId` del catálogo. Mientras OQ-14 no se resuelva, el stack opera sin
excepción (el constraint de AWS no es negociable y no se está debilitando ningún
control; es la precedencia 1 la que resuelve el conflicto).

## Retención del data store (10 años)

El **data store** de Customer Profiles (segmentos y predictive insights)
almacena el histórico de perfiles con una **retención fija de 10 años** que no
se puede acortar. Bajo LPDP (minimización y limitación del plazo de
conservación) y el principio de no guardar datos personales más de lo necesario,
mantener 10 años de histórico de perfiles de socios es un riesgo que requiere
justificación explícita.

Por eso el módulo **apaga el data store por defecto** (`enable_data_store =
false`), a diferencia del patrón DFX5 que lo deja encendido. Para habilitarlo:

1. Debe existir un caso de uso aprobado de segmentos o predictive insights.
2. El stack debe pasar `enable_data_store = true` **y** una
   `data_store_approval_ref` no vacía (la referencia de aprobación de
   Cumplimiento, OQ-10).
3. Si se pone `enable_data_store = true` sin esa referencia, la `validation`
   falla el plan (Req 8.3, 8.4).

El plazo de expiración de los perfiles en sí (`default_expiration_days`, 1..1098
días) es independiente del data store y lo fija Cumplimiento (OQ-10).

## Comportamiento de reemplazo

- **`domain_name` fuerza el reemplazo del dominio.** El nombre del dominio es un
  atributo `ForceNew` de `aws_customerprofiles_domain`: cambiarlo recrea el
  dominio. Como el dominio tiene `prevent_destroy = true`, el cambio convierte el
  plan en un error en vez de recrear el dominio (Req 8.8). Dado que el nombre se
  computa de `domain`, `environment` y `workload`, cambiar cualquiera de esos
  inputs también cambia el nombre y, por tanto, también falla el plan.
- **La clave KMS (`default_encryption_key`) fuerza el reemplazo del dominio.**
  La clave de cifrado del dominio no se puede cambiar in-place; cambiar el
  contrato `customer-profiles-kms-key-arn` que alimenta `default_encryption_key`
  reemplaza el dominio y, por `prevent_destroy`, falla el plan. La CMK, a su vez,
  también está protegida con `prevent_destroy`, de modo que recrearla falla
  antes de llegar al dominio.
- Para cambiar de verdad el nombre o la clave hay que retirar la protección de
  forma deliberada, evaluar el impacto y usar `moved`/`import` según corresponda;
  no se recrea un dominio de producción para reorganizar.
- El resto de recursos (tipo de objeto `CTR`, integración, contratos SSM) se
  actualizan in-place o se adoptan por `import` (DD-4) cuando ya existen (Req
  8.6); la integración existente se adopta vía `env.hcl adopt.customer-profiles`
  y el plan debe mostrar 0 integraciones a crear.

## Estrategia de upgrade / cambios incompatibles

- El módulo se publica con tags SemVer `connect/connect-customer-profiles/vX.Y.Z`
  firmados; los stacks lo fijan por SHA de 40 caracteres registrado en
  `compatibility.yaml`. Un upgrade es un PR que cambia ese SHA tras revisar el
  diff del plan.
- **Patch** (fix sin cambio de contrato): sin acción en el stack más allá del
  nuevo SHA. **Minor** (nueva variable opcional / nuevo output): compatible.
  **Major** (cambio de contrato: renombrar/eliminar una variable u output,
  cambiar un nombre físico, cambiar el switch `component`): requiere deprecación
  previa y, cuando toca direcciones de recursos, bloques `moved`; adoptar
  recursos existentes requiere `import`.
- Cambiar la plantilla del nombre del dominio o la alias de la CMK es un cambio
  mayor: `prevent_destroy` impide recrear el recurso. Planifíquelo con
  `moved`/`import` y evaluación de impacto.
- Rango del proveedor `aws` acotado al major 6 (`>= 6.47.0, < 7.0.0`) y del
  `awscc` al major 1 (`>= 1.0.0, < 2.0.0`): subir de major es un cambio mayor que
  exige nueva entrada en `compatibility.yaml` y revalidación del dominio, el tipo
  de objeto, la integración y las políticas KMS.

## Notas de diseño

- **DD-4 — adopción por `import`.** El módulo no declara bloques `import`. Cuando
  la instancia ya tiene una integración de Customer Profiles, el root
  `terragrunt.hcl` genera `import.tf` a partir de `env.hcl adopt.customer-profiles`;
  el plan debe mostrar 0 integraciones a crear (Req 8.6).
- **DD-5 — `aws:SourceArn` desde el primer apply.** El ARN del dominio se calcula
  de forma determinista en `naming.tf`
  (`arn:<partition>:profile:<region>:<account>:domains/<domain-name>`) para
  enlazar `aws:SourceArn` en la política de la clave sin requerir que el dominio
  ya exista. Es un riesgo a confirmar en el primer apply en dev.
- **OQ-11 — rol de Profiles_App.** El statement `ProfilesApp` de la política de
  la clave solo aparece cuando el contrato `profiles-app-role-arn` está
  publicado. Profiles_App, su rol y su política los crea el repo que posee la app
  (Req 9); este módulo solo provee el statement de la clave que la app consume.
- **OQ-12 — `awscc` por registrar.** El tipo de objeto y la integración
  requieren `hashicorp/awscc`; la entrada en `compatibility.yaml` con el espejo
  de Nexus debe aprobarse antes de que el componente `domain` pueda mezclarse.
- **OQ-13 — rol key-admin.** El componente `kms` lee el rol key-admin del
  contrato SSM; si no está publicado, la `postcondition` falla el plan con el
  mensaje "key-admin role not published (OQ-13)".
