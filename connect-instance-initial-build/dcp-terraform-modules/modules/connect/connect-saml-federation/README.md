# connect/connect-saml-federation

Federación SAML 2.0 de Amazon Connect con Microsoft Entra ID para Diners Club
Perú. Crea los dos proveedores IAM SAML (admin y agente), el rol de federación y
su política de una sola acción, y expone como salidas los claims y las relay
state URLs que Infraestructura necesita para registrar las dos enterprise apps
en Entra ID.

Se consume por SHA desde `dcp-terraform-modules` (L03). No se copia a los repos
`live` ni se referencia por rama, tag o SHA corto.

> **Pendientes de gobierno que afectan a este módulo:**
>
> - **Categoría de módulo `connect/` pendiente de confirmación de Platform.** La
>   ruta `modules/connect/connect-saml-federation` asume que `connect` es una
>   categoría válida del catálogo de módulos. Mientras Platform no la confirme,
>   el SHA de este módulo no debe registrarse en `compatibility.yaml` como
>   definitivo.
> - **[OQ-3] `saml_resource_code`** — el código de recurso del proveedor IAM
>   SAML (propuesto `saml`) no está en la lista de códigos de L07. El módulo lo
>   exige como entrada y **no inventa el valor**: falla en plan si no se informa.
>   El valor real se fija con el PR de catálogo a `catalogos-cloud.yaml`
>   (Arquitectura Cloud).
> - **[OQ-9] Metadatos de Entra ID y mapeo de grupos** — los metadatos SAML
>   reales de las apps admin y agente, y el mapeo grupo Entra ID → perfil de
>   seguridad de Connect, los entrega Infraestructura (Stephanie Santisteban,
>   Rommel Kerrigan). El stack `saml-federation` se puede planear con metadatos
>   de marcador en dev pero **no se fusiona** hasta tener los reales.

---

## Propósito y límites

### Qué hace

- Crea **dos** proveedores IAM SAML (`aws_iam_saml_provider`), uno para la app
  de consola de administración (admin/supervisores) y otro para la app del
  Agent Workspace (agentes). Cada proveedor se crea solo cuando se le pasan sus
  metadatos.
- Crea **un** rol de federación
  `dcp-<domain>-<env>-<workload>-role-connect-federation`, con:
  - trust `sts:AssumeRoleWithSAML` hacia ambos proveedores, condicionado a
    `SAML:aud = https://signin.aws.amazon.com/saml`;
  - el permission boundary obligatorio `dcp-platform-permission-boundary`;
  - `max_session_duration = 3600` s (valor único: techo PCI y piso de IAM).
- Crea **una** política `...-policy-connect-federation` con exactamente
  `connect:GetFederationToken` sobre `instance/<instance-id>/user/*`, y la
  adjunta al rol.
- Expone como salidas los claims `Role` de Entra ID y las relay state URLs de la
  consola de federación de Connect (ver [Guía de Entra ID](#guía-de-entra-id)).

### Qué NO hace (fuera de alcance de este módulo y de esta fase)

- No crea la instancia Connect ni los perfiles de seguridad, usuarios, perfiles
  de enrutamiento ni jerarquías.
- No registra las enterprise apps en Entra ID: eso lo hace Infraestructura con
  la [guía](#guía-de-entra-id) de abajo.
- No configura SCIM ni el aprovisionamiento automático de usuarios (diferido).
- No publica contratos SSM: el módulo **lee** `connect-instance-arn`,
  `saml-metadata-admin` y `saml-metadata-agent` (publicados por otros stacks);
  no escribe ninguno.
- No añade ningún tag salvo `Name` (Req 2.6); los tags obligatorios llegan por
  `default_tags` del provider que genera el root `terragrunt.hcl` (L11 v2).

---

## Recursos

| Recurso | Tipo | Cantidad | Notas |
|---|---|---|---|
| Proveedor IAM SAML admin | `aws_iam_saml_provider` | 0 o 1 | Solo si se informan `metadata_admin` |
| Proveedor IAM SAML agente | `aws_iam_saml_provider` | 0 o 1 | Solo si se informan `metadata_agent` |
| Rol de federación | `aws_iam_role` | 1 | Permission boundary obligatorio, sesión ≤ 3600 s |
| Política de federación | `aws_iam_policy` | 1 | Única acción `connect:GetFederationToken` |
| Adjunto rol↔política | `aws_iam_role_policy_attachment` | 1 | |

Data sources: `aws_partition`, `aws_caller_identity`, `aws_region` (para construir
el ARN del permission boundary sin hardcodearlo).

---

## Proveedores

| Proveedor | Restricción |
|---|---|
| `hashicorp/aws` | `>= 6.47.0, < 7.0.0` |

Terraform `required_version = ">= 1.15.8, < 1.16.0"`. Runtime fijado por la
plataforma: Terraform `1.15.8`, Terragrunt `1.0.4`. Los proveedores se instalan
solo desde el mirror Nexus aprobado; cualquier descarga del registry público
falla.

---

## Entradas (inputs)

| Nombre | Tipo | Req. | Default | Descripción |
|---|---|:--:|---|---|
| `domain` | string | no | `"diners"` | Dominio cloud canónico. Único valor aprobado: `diners`. |
| `workload` | string | **sí** | — | Capacidad funcional del catálogo. Regex `^[a-z][a-z0-9]{1,9}$`. **[OQ-1]** |
| `region_code` | string | **sí** | — | Código corto de región: `use1`, `use2`, `usw2`, `sae1`. |
| `environment` | string | **sí** | — | `dev` \| `qa` \| `stg` \| `prod`. |
| `saml_resource_code` | string | **sí** | `null` | Código de recurso del proveedor IAM SAML (propuesto `saml`). Obligatorio; no se inventa. **[OQ-3]** |
| `instance_arn` | string | no | `null` | ARN de la instancia Connect (del contrato SSM `connect-instance-arn`). Valida formato `arn:aws:connect:<region>:<account>:instance/<uuid>`. |
| `metadata_admin` | string | no | `null` | Metadatos SAML de la app admin de Entra ID (contrato SSM `saml-metadata-admin`). No vacío y debe contener `EntityDescriptor`. **[OQ-9]** |
| `metadata_agent` | string | no | `null` | Metadatos SAML de la app agente de Entra ID (contrato SSM `saml-metadata-agent`). No vacío y debe contener `EntityDescriptor`. **[OQ-9]** |
| `max_session_duration` | number | no | `3600` | Duración máxima de sesión del rol, en segundos. Valor único **`3600`**: es el techo PCI (Req 10.3) y a la vez el mínimo que AWS IAM admite para la duración de sesión de un rol (rango IAM 3600-43200 s). La sesión efectiva del agente (incl. la CDE de 12 h) se controla en el IdP (Entra ID `SessionDuration`), no aquí. |
| `exception_id` | string | no | `""` | `exc-cloud-NNNN-NNNN` cuando el rol usa una excepción (p. ej. la sesión CDE de 12 h). Formato validado cuando se informa (Req 11.4). |
| `tags` | map(string) | no | `{}` | Solo tags complementarios del catálogo (`Criticality`, `BackupPolicy`, `ExpiryDate`, `ExceptionId`, `Service`). |

Notas sobre `metadata_admin`/`metadata_agent`: un proveedor SAML se crea solo si
se informan sus metadatos. En dev se admiten metadatos de marcador para planear;
el stack no se fusiona hasta tener los metadatos reales de Entra ID (OQ-9).

---

## Salidas (outputs)

Contrato de salida (Req 10.6). Los claims y los ARNs de proveedor valen `null`
cuando el proveedor correspondiente no se crea (sin metadatos), para no fabricar
un claim incompleto.

| Nombre | Descripción |
|---|---|
| `admin_provider_arn` | ARN del proveedor IAM SAML admin (`null` si no hay metadatos). |
| `agent_provider_arn` | ARN del proveedor IAM SAML agente (`null` si no hay metadatos). |
| `role_arn` | ARN del rol de federación. |
| `admin_role_claim` | Claim `Role` de Entra ID para la app admin: `"<role-arn>,<provider-arn>"`. |
| `agent_role_claim` | Claim `Role` de Entra ID para la app agente: `"<role-arn>,<provider-arn>"`. |
| `admin_relay_state_url` | Relay state de Connect para la app admin (`destination=%2Fconnect`). |
| `agent_relay_state_url` | Relay state de Connect para la app agente (`destination=%2Fagent-app-v2`). |
| `role_federation_name` | Nombre del rol (auxiliar, diagnóstico/pruebas). |
| `policy_federation_name` | Nombre de la política (auxiliar). |
| `ssm_base` | Base de los contratos SSM del workload (auxiliar). |

---

## Ejemplos

### Básico (`examples/basic/`)

```hcl
module "connect_saml" {
  source = "../.."

  environment        = "dev"
  workload           = "<OQ-1>"
  region_code        = "use1"
  saml_resource_code = "saml" # [Blocked: OQ-3]
}
```

Planea el rol y la política de federación. Sin `instance_arn` ni metadatos,
los recursos de proveedor no se crean y las salidas de relay state / claims
valen `null`: sirve para validar nombres, longitudes y el permission boundary.

### Producción (`examples/production/`)

```hcl
module "connect_saml" {
  source = "../.."

  environment          = "prod"
  workload             = "<OQ-1>"
  region_code          = "use1"
  saml_resource_code   = "saml" # [Blocked: OQ-3]
  max_session_duration = 3600
}
```

En el uso real por el stack `saml-federation`, `instance_arn`, `metadata_admin`
y `metadata_agent` se leen de contratos SSM; nunca se escriben como literales en
el stack (Req 2.7). Los `default_tags` del ejemplo son ilustrativos: en los
repos `live` los genera el root `terragrunt.hcl` desde el catálogo.

---

## Guía de Entra ID

Esta es la guía paso a paso que Infraestructura usa para registrar las dos
enterprise apps de Entra ID (admin y agente). Complementa `docs/sso/` del
workspace. Los ARNs y la instance-id provienen de las **salidas del módulo**;
no se copian a mano.

### 0. Prerequisitos (lado AWS, ya resueltos por el stack)

1. La instancia Connect existe con `IdentityManagementType = SAML` (si no, el
   plan del stack falla por su `precondition`).
2. Los metadatos de ambas apps de Entra ID están publicados en los contratos
   SSM `saml-metadata-admin` y `saml-metadata-agent` (OQ-9). El módulo crea los
   proveedores IAM SAML a partir de ellos.
3. Tras `apply`, se obtienen del módulo:
   - `admin_role_claim`, `agent_role_claim` → valor del claim `Role`.
   - `admin_relay_state_url`, `agent_relay_state_url` → relay state de cada app.
   - `role_arn`, `admin_provider_arn`, `agent_provider_arn` → referencia.

### 1. Crear las dos enterprise apps

En Entra ID → *Enterprise applications* → *New application* → *Create your own*
(non-gallery), una por tipo de acceso:

| App | Acceso | Destino |
|---|---|---|
| `Amazon Connect - Diners <ENV> (Consola)` | Admin / supervisores | Consola de administración |
| `Amazon Connect - Diners <ENV> (Agente)` | Agentes | Agent Workspace (CCP) |

Cada app necesita un **Entity ID** único dentro del tenant (sufijo `#1`, `#2`,
…) porque ambas apuntan al mismo ACS de AWS.

### 2. Basic SAML Configuration (por app)

En *Single sign-on* → *SAML* → *Basic SAML Configuration*:

| Ajuste | Valor |
|---|---|
| Identifier (Entity ID) | `https://signin.aws.amazon.com/saml#<sufijo-único>` |
| Reply URL (ACS) | `https://signin.aws.amazon.com/saml` |
| Sign-on URL | (vacío) |
| Relay State | Salida del módulo (ver tabla abajo) |

Relay State por app (viene de las salidas del módulo):

| App | Relay State (output) | Forma |
|---|---|---|
| Consola (admin) | `admin_relay_state_url` | `https://<region>.console.aws.amazon.com/connect/federate/<instance-id>?destination=%2Fconnect` |
| Agente | `agent_relay_state_url` | `https://<region>.console.aws.amazon.com/connect/federate/<instance-id>?destination=%2Fagent-app-v2` |

El módulo construye la `<instance-id>` y la `<region>` a partir de
`instance_arn`, así que ambas URLs quedan listas tras el `apply`.

### 3. Atributos y claims (Attributes & Claims, por app)

| Claim | Fuente / valor | Nota |
|---|---|---|
| Name ID (Unique User Identifier) | `user.userprincipalname` | Identifica al usuario (UPN `@diners`). |
| `.../SAML/Attributes/RoleSessionName` | `user.userprincipalname` | **Debe coincidir exactamente con el username de Connect** (sensible a mayúsculas). |
| `.../SAML/Attributes/SessionDuration` | `900` (constante) | Duración de las credenciales STS. Ver nota de sesión abajo. |
| `.../SAML/Attributes/Role` | `admin_role_claim` o `agent_role_claim` | `"<role-arn>,<provider-arn>"` tomado de las salidas del módulo. |

El claim `Role`:

- App Consola → valor de **`admin_role_claim`**
  (`<role_arn>,<admin_provider_arn>`).
- App Agente → valor de **`agent_role_claim`**
  (`<role_arn>,<agent_provider_arn>`).

### 4. Asignar grupos

Crear un grupo de Entra ID por tipo de acceso y asignarlo a su enterprise app
(*Users and groups*). El **username de Connect = UPN** de Entra ID.

**Mapeo grupo Entra ID → perfil de seguridad de Connect (placeholder, OQ-9):**

| Grupo Entra ID | App asignada | Perfil de seguridad Connect | Estado |
|---|---|---|---|
| `<grupo-admin>` | Consola | `<perfil-admin>` | Pendiente OQ-9 |
| `<grupo-supervisor>` | Consola | `<perfil-supervisor>` | Pendiente OQ-9 |
| `<grupo-agente>` | Agente | `<perfil-agente>` | Pendiente OQ-9 |

Este mapeo se completa cuando Infraestructura resuelva OQ-9.

### 5. Cómo fluyen los metadatos a AWS (contratos SSM)

```
Entra ID (Federation Metadata XML por app)
        │  descarga manual del XML
        ▼
Publicación en SSM (OQ-9):
  /dcp/diners/<env>/<workload>/config/saml-metadata-admin
  /dcp/diners/<env>/<workload>/config/saml-metadata-agent   (tier Advanced, DD-7)
        │  data "aws_ssm_parameter" en el stack
        ▼
module.connect_saml  → metadata_admin / metadata_agent
        │
        ▼
aws_iam_saml_provider.admin / .agent   (se crean al existir metadatos)
```

Los metadatos SAML **no son secretos**; se guardan como `String` en SSM tier
`Advanced` (límite 8 KB, DD-7). El módulo valida que cada metadato contenga
`EntityDescriptor` antes de crear el proveedor.

### 6. Nota de duración de sesión

`SessionDuration = 900` (segundos) controla solo la duración de las credenciales
temporales de STS. **Amazon Connect ignora este valor y aplica una sesión de 12
horas** tras el login. Ver la nota de CDE en [Supuestos de
seguridad](#supuestos-de-seguridad).

### 7. Inventario de certificados (plantilla)

Al cargar los metadatos reales, registrar el certificado de firma de cada app en
el inventario de certificados (Req 10.9):

| Campo | Valor |
|---|---|
| App / entidad | `Amazon Connect - Diners <ENV> (Consola \| Agente)` |
| Emisor | Microsoft Entra ID |
| Fecha de expiración | `<YYYY-MM-DD>` (del XML de metadatos) |
| Propietario (owner) | `<equipo responsable>` |
| Alerta | 30 días antes de la expiración |

Los certificados SAML de Entra ID expiran: al renovarlos hay que generar el
nuevo certificado, descargar el nuevo Federation Metadata XML y actualizar el
parámetro SSM correspondiente (lo que reemplaza el metadato del proveedor IAM).

### 8. Checklist de prueba (IdP-initiated)

- [ ] Metadatos cargados en los dos contratos SSM.
- [ ] Rol de federación con trust a ambos proveedores y condición `SAML:aud`.
- [ ] Entity ID y ACS correctos en cada enterprise app.
- [ ] Relay state de cada app = salida del módulo (`%2Fconnect` / `%2Fagent-app-v2`).
- [ ] Claim `Role` = `admin_role_claim` / `agent_role_claim`.
- [ ] `RoleSessionName` = `user.userprincipalname`.
- [ ] Usuario de prueba existe en Connect con username = UPN (sensible a mayúsculas).
- [ ] Usuario de prueba en el grupo correcto de Entra ID.
- [ ] Un usuario sin asignación recibe acceso denegado.

---

## Supuestos de seguridad

- **Privilegio mínimo:** el rol de federación otorga exactamente una acción
  (`connect:GetFederationToken`) sobre un único recurso
  (`instance/<id>/user/*`). No concede nada más (Req 10.2).
- **Permission boundary obligatorio:** todo rol creado por Terraform lleva
  `dcp-platform-permission-boundary` (iac-security-pci, iac-core-rules §6). El
  ARN se construye con el account del caller, nunca hardcodeado.
- **Sin usuarios IAM ni claves de acceso:** el acceso humano es federado vía
  Entra ID con MFA; el acceso de pipeline es GitHub OIDC (L06).
- **Audiencia acotada:** el trust exige
  `SAML:aud = https://signin.aws.amazon.com/saml`.
- **Sesión ≤ 3600 s** en el rol IAM (validado). El claim `SessionDuration` de
  Entra ID vale `900` s.
- **CDE — sesión de 12 h de Connect (L14 IA-3):** Amazon Connect impone una
  sesión de 12 h tras el login, que choca con el límite de inactividad de 15 min
  del CDE. **Si la cuenta es CDE (OQ-6), este conflicto debe elevarse a
  Ciberseguridad** y resolverse con una decisión documentada o una excepción
  `exc-cloud-NNNN-NNNN` (en cuyo caso el rol lleva el tag/entrada `ExceptionId`,
  Req 10.10 / 11.4).
- Los metadatos SAML no son secretos, pero el certificado de firma debe estar en
  el inventario con alerta a 30 días (Req 10.9).

---

## Costos

Los recursos son de IAM (proveedores SAML, rol, política): **sin costo directo**
en la factura de AWS. El costo asociado es operativo (gestión de identidades en
Entra ID) y el de la propia instancia Connect, ajeno a este módulo.

---

## Comportamiento de reemplazo

| Cambio | Efecto |
|---|---|
| `saml_resource_code`, `workload`, `environment`, `domain`, `region_code` | Cambia el **nombre** del rol/política/proveedores → reemplazo de esos recursos IAM. |
| `metadata_admin` / `metadata_agent` de `null` a un valor (o viceversa) | **Crea o destruye** el proveedor SAML correspondiente (recurso condicional por `count`). |
| Cambiar el contenido de los metadatos | Actualiza `saml_metadata_document` **in-place** (no reemplaza el proveedor). |
| `max_session_duration` | Actualiza el rol **in-place**. |

El rol y la política no llevan `prevent_destroy` porque son reconstruibles sin
pérdida de datos; aun así, el guardrail de recursos protegidos del repo `live`
vigila cambios de SAML (boundary presente, sesión ≤ 3600). Cambiar el username
de un usuario de Connect o el UPN rompe el login (coincidencia exacta,
sensible a mayúsculas) — es un cambio de operación, no de este módulo.

---

## Estrategia de versionado y cambios incompatibles

- Versionado SemVer por módulo con tag firmado
  `connect/connect-saml-federation/vX.Y.Z`:
  - **patch**: corrección sin cambio de contrato.
  - **minor**: entrada/salida nueva compatible (default seguro).
  - **major**: cambio de contrato (p. ej. renombrar/eliminar una salida como
    `admin_role_claim`, cambiar el formato del claim, o quitar una entrada).
- Quitar una variable o una salida exige **deprecación previa** (un ciclo con
  aviso) antes del major.
- El SHA consumido por los stacks `live` debe estar registrado en
  `compatibility.yaml`; nunca se consume por rama, tag móvil o SHA corto.
- Cambios de dirección de recurso (address) requieren bloques `moved`; adoptar
  recursos existentes requiere `import`. No se destruye/recrea en prod para
  reorganizar sin evaluación de impacto.

---

## Trazabilidad

Implementa los Requisitos 10.1–10.10 (federación SAML) y el estándar de README
de L03. Lectura de contratos SSM: `connect-instance-arn`, `saml-metadata-admin`,
`saml-metadata-agent`. Bloqueos activos: **OQ-3** (`saml_resource_code`),
**OQ-9** (metadatos y mapeo de grupos), y la confirmación de la categoría
`connect/` por Platform.
