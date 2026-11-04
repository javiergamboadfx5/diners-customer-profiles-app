# Topología de repositorios cloud (v1.2)

> **Cambios en v1.2 (2026-10-28):**
>
> - Dos cuentas de seguridad (opción B): `dinersclub-log-archive` y `dinersclub-security`. Reemplaza la cuenta única de v1.1.
> - Nuevo repositorio `dcp-aws-integration-live` para la cuenta `dinersclub-integration-gateway` (L16).
> - `dcp-aws-diners-live` suma el stack `platform/eks-hybrid/` (fase 1 de EKS) y las cuentas de producto, empezando por Amazon Connect en cuenta propia.
> - Una sola cuenta de networking con Shared VPC por tier (sin `networking-nonprod`).

> **Cambios en v1.1 (2026-10-27):**
>
> - Nuevo repositorio `dcp-aws-devops-live` para la cuenta `dinersclub-devops`: runners de CI/CD y roles de despliegue (OIDC, plan y apply). Salen de `dcp-aws-shared-services-live`.
> - Una sola cuenta de seguridad, `dinersclub-security`, en lugar de `dinersclub-audit`, `dinersclub-log-archive` y `dinersclub-security-tooling` (L15).
> - Se ratifica `terragrunt.hcl` como nombre del archivo raíz de cada repo live. Los comandos de Terragrunt se ejecutan dentro de `live/` o de la carpeta de un stack, nunca en la raíz.

## Propósito

Define los repositorios operativos de la Landing Zone, sus cuentas, responsabilidades, ownership, aprobadores y estructura live.

## Vista general

`dcp-terraform-bootstrap` y `dcp-terraform-modules` se detallan respectivamente en los documentos de backend y módulos.

### Matriz de responsabilidades

| Repositorio | Responsabilidad principal |
| --- | --- |
| `dcp-aws-governance-live` | Organizations, OUs, SCP, RCP, Tag Policies, Backup Policies, Control Tower e Identity Center. |
| `dcp-aws-networking-live` | IPAM, TGW, DNS, conectividad híbrida, VPC compartidas, inspección y egress. |
| `dcp-aws-security-live` | Auditoría, logs, postura de seguridad, hallazgos y remediaciones. |
| `dcp-aws-shared-services-live` | Servicios compartidos de ingeniería y plataforma (Nexus, Argo CD, CIAM, Backstage). |
| `dcp-aws-devops-live` | Runners de CI/CD y roles de despliegue (OIDC, plan y apply) en la cuenta `dinersclub-devops`. |
| `dcp-aws-integration-live` | Borde (AWS WAF / Cloudflare), API Gateway público y privado, authorizer e integraciones privadas en la cuenta `dinersclub-integration-gateway`. |
| `dcp-aws-diners-live` | Plataforma y recursos exclusivos del dominio diners. |
| `dcp-aws-data-live` | Plataforma de datos, analítica, catálogo, lake y capacidades de ML. |

## Repositorio `dcp-aws-governance-live`

### Propósito

Administrar el gobierno de la organización AWS.

### Contenido

- AWS Organizations.
- OUs.
- SCPs.
- Tag Policies.
- Backup Policies.
- Delegated Administrators.
- AWS Control Tower controls.
- IAM Identity Center.
- Permission Sets.
- Account assignments.
- Permission Boundaries.

### Estructura

```text
dcp-aws-governance-live/
├── terragrunt.hcl
│
├── live/
│   ├── organization/
│   │   ├── organizational-units/
│   │   │   └── terragrunt.hcl
│   │   ├── service-control-policies/
│   │   │   └── terragrunt.hcl
│   │   ├── tag-policies/
│   │   │   └── terragrunt.hcl
│   │   ├── backup-policies/
│   │   │   └── terragrunt.hcl
│   │   └── delegated-administrators/
│   │       └── terragrunt.hcl
│   │
│   ├── control-tower/
│   │   ├── mandatory-controls/
│   │   ├── strongly-recommended-controls/
│   │   └── elective-controls/
│   │
│   └── identity-center/
│       ├── permission-sets/
│       └── assignments/
│
├── policies/
│   ├── scp/
│   ├── tag-policies/
│   ├── backup-policies/
│   └── permission-boundaries/
│
├── tests/
└── README.md
```

### Ownership y aprobadores

- **Owner:** Infraestructura cloud.
- **Co-owner:** Ciberseguridad.
- **Aprobador obligatorio:** Ciberseguridad.

## Repositorio `dcp-aws-networking-live`

### Propósito

Administrar toda la red central de la Landing Zone.

### Cuenta principal

- `dinersclub-networking`

### Contenido

- IPAM.
- Transit Gateway.
- Route tables del TGW.
- VPN y Direct Connect, si aplica.
- Inspection VPC.
- Egress VPC.
- Endpoint VPC.
- Network Firewall.
- Route 53 Resolver.
- Private Hosted Zones.
- Shared VPC.
- Subnets compartidas.
- AWS RAM shares.
- Flow Logs.
- Conectividad on-premise.

### Estructura

```text
dcp-aws-networking-live/
├── terragrunt.hcl
├── account.hcl
│
├── live/
│   ├── global/
│   │   └── ipam/
│   │       └── terragrunt.hcl
│   │
│   └── us-east-1/
│       ├── region.hcl
│       ├── core/
│       │   ├── transit-gateway/
│       │   ├── hybrid-connectivity/
│       │   ├── dns/
│       │   ├── inspection-vpc/
│       │   ├── egress-vpc/
│       │   └── endpoint-vpc/
│       │
│       ├── shared-vpc-prod/
│       │   ├── base/
│       │   ├── subnets-diners/
│       │   ├── subnets-data/
│       │   ├── ram-diners-prod/
│       │   └── ram-data-prod/
│       │
│       └── shared-vpc-nonprod/
│           ├── base/
│           ├── subnets-diners-dev/
│           ├── subnets-diners-qa/
│           ├── subnets-data-qa/
│           ├── ram-diners-dev/
│           ├── ram-diners-qa/
│           └── ram-data-qa/
│
├── compositions/
│   ├── shared-vpc/
│   └── central-egress/
│
├── tests/
└── README.md
```

### Estados

```text
networking/global/ipam/terraform.tfstate
networking/us-east-1/core/transit-gateway/terraform.tfstate
networking/us-east-1/core/dns/terraform.tfstate
networking/us-east-1/core/inspection-vpc/terraform.tfstate
networking/us-east-1/shared-vpc-prod/base/terraform.tfstate
networking/us-east-1/shared-vpc-nonprod/base/terraform.tfstate
```

### Reglas

- Las cuentas workload no crearán VPC propia cuando usen Shared VPC.
- Las subnets se compartirán mediante AWS RAM.
- El routing central será administrado únicamente por Networking.
- Los CIDR se asignarán mediante IPAM.
- No se permitirá VPC peering ad hoc.
- Flow Logs se enviarán al destino central.
- Los cambios de TGW, egress, inspection y DNS requerirán aprobación especial.

### Ownership y aprobadores

- **Owner:** Infraestructura cloud.
- **Aprobador:** Ciberseguridad.

## Repositorio `dcp-aws-security-live`

### Propósito

Administrar seguridad, auditoría y logging organizacional.

### Cuentas

- `dinersclub-log-archive`: logs centrales inmutables (CloudTrail, Config, Flow Logs, WAF, DNS); administrador delegado de Security Lake; nadie la opera.
- `dinersclub-security`: administrador delegado de GuardDuty, Security Hub, Inspector, Macie, Config, Detective, Firewall Manager, Access Analyzer y Audit Manager; es la cuenta Audit de Control Tower.

El acceso de auditoría y QSA es un permission set de solo lectura (`DCP-Security-Auditor`), no una cuenta.

### Contenido

- GuardDuty.
- Security Hub.
- Inspector.
- Macie.
- Access Analyzer.
- Firewall Manager.
- AWS Config Aggregator.
- Organization Config Rules.
- Conformance Packs.
- CloudTrail.
- Buckets de logs.
- Integración con SIEM.
- Automatizaciones de remediación.

### Estructura

```text
dcp-aws-security-live/
├── terragrunt.hcl
│
├── live/
│   ├── log-archive/
│   │   ├── account.hcl
│   │   └── us-east-1/
│   │       ├── region.hcl
│   │       ├── cloudtrail/
│   │       ├── log-buckets/
│   │       ├── retention/
│   │       └── security-lake/
│   │
│   └── security/
│       ├── account.hcl
│       └── us-east-1/
│           ├── region.hcl
│           ├── guardduty/
│           ├── security-hub/
│           ├── inspector/
│           ├── macie/
│           ├── access-analyzer/
│           ├── firewall-manager/
│           ├── config-aggregator/
│           ├── config-rules/
│           ├── conformance-packs/
│           └── audit-manager/
│
├── policies/
├── tests/
└── README.md
```

### Reglas

- Utilizar delegated administrator.
- Incorporar automáticamente cuentas nuevas.
- Centralizar hallazgos en Security Hub.
- Proteger el bucket de logs centrales contra borrado (S3 Object Lock en modo compliance, KMS propia, RCP y SCP). El administrador de seguridad no tiene acceso a Log Archive; el acceso humano a esa cuenta es solo por break-glass.
- Aplicar controles PCI únicamente a cuentas CDE.
- Las remediaciones automáticas deben ser idempotentes y auditables.

### Ownership y aprobadores

- **Owner:** Ciberseguridad.
- **Co-owner:** Infraestructura cloud.
- **Aprobador:** Ciberseguridad.

## Repositorio `dcp-aws-shared-services-live`

### Propósito

Administrar servicios compartidos de ingeniería, automatización y plataforma.

### Cuenta

- `dinersclub-shared-services`

### Contenido

- CIAM.
- Gestor de artefactos.
- Argo CD.
- Backstage.
- Gateways centralizados.

Los runners de CI/CD y los roles de despliegue no viven aquí: están en `dcp-aws-devops-live`.

### Estructura

```text
dcp-aws-shared-services-live/
├── terragrunt.hcl
├── account.hcl
│
├── live/
│   └── us-east-1/
│       ├── region.hcl
│       ├── ciam/
│       ├── argocd/
│       ├── backstage/
│       └── gateways/
│
├── compositions/
├── tests/
└── README.md
```

### Ownership y aprobadores

- **Owner:** Platform Engineering.
- **Co-owner:** Infraestructura cloud.
- **Aprobador:** Ciberseguridad o Platform Engineering.

## Repositorio `dcp-aws-devops-live`

### Propósito

Administrar la cuenta desde la que se despliega toda la Landing Zone: runners de CI/CD y roles de despliegue.

### Cuenta

- `dinersclub-devops` (OU Deployments)

### Contenido

- Runners de GitHub Actions en AWS CodeBuild (efímeros, en VPC privada, sin egress general).
- Imagen del runner publicada en Nexus y fijada por digest.
- Proveedor OIDC de GitHub.
- Roles de despliegue: `dcp-platform-shared-cicd-role-terraform-plan`, `dcp-platform-shared-cicd-role-terraform-apply-nonprod` y `dcp-platform-shared-cicd-role-terraform-apply-prod`.
- Bucket de planes Terraform (SSE-KMS, expiración corta) y evidencias de despliegue.
- Bucket seed del génesis.
- Conexión de GitHub (CodeConnections).

### Estructura

```text
dcp-aws-devops-live/
├── terragrunt.hcl
│
├── live/
│   └── devops/
│       ├── account.hcl
│       └── us-east-1/
│           ├── region.hcl
│           ├── github-connection/
│           ├── oidc-provider/
│           ├── deployment-roles/
│           ├── runners/
│           ├── plan-artifacts/
│           └── seed-state/
│
├── tests/
└── README.md
```

### Reglas

- El rol de servicio de CodeBuild no despliega: solo escribe logs, crea interfaces de red y lee la credencial de Nexus. Las credenciales de despliegue se obtienen por OIDC.
- El webhook del runner acepta solo jobs de los repositorios `dcp-aws-*-live` con el workflow de Terraform aprobado.
- Los roles de despliegue solo los puede asumir el template de pipeline de Platform (claim `job_workflow_ref`). El rol de apply exige un environment aprobado de GitHub y hay uno por tier (nonprod y prod).
- En cada cuenta destino, `TerraformPlanRole` y `TerraformApplyRole` confían únicamente en los roles de despliegue de esta cuenta.
- Los equipos de proyecto no tienen acceso a la consola de esta cuenta; ven sus ejecuciones en GitHub Actions.

### Ownership y aprobadores

- **Owner:** Platform Engineering (GH).
- **Co-owner:** Infraestructura cloud.
- **Aprobador obligatorio:** Ciberseguridad.

## Repositorio `dcp-aws-integration-live`

### Propósito

Administrar la exposición de APIs hacia clientes, comercios y terceros (L16).

### Cuenta

- `dinersclub-integration-gateway` (OU Infrastructure/Prod)

### Contenido

- Borde intercambiable: CloudFront + AWS WAF (etapa 1) o Cloudflare (etapa 2).
- API Gateway REST público (custom domain regional con mTLS hacia el borde) y privado (VPC endpoint por tercero).
- Lambda authorizer y su DynamoDB de `jti` y sesiones revocadas.
- VPC links e integraciones privadas con mTLS hacia el ALB interno de EKS.
- Interface endpoints de PrivateLink hacia servicios de shared-services (por ejemplo, Keycloak para terceros por VPN, si se aprueba).

### Estructura

```text
dcp-aws-integration-live/
├── terragrunt.hcl
│
├── live/
│   └── <env>/
│       ├── account.hcl
│       ├── env.hcl
│       └── us-east-1/
│           ├── region.hcl
│           ├── edge/          ← provider = aws-waf | cloudflare
│           ├── domains/       ← custom domains, certificados, truststores
│           ├── authorizer/
│           ├── vpc-links/
│           └── apis/<api>/    ← un estado por API
│
├── tests/
└── README.md
```

### Ownership y aprobadores

- **Owner:** Platform Engineering.
- **Co-owner:** Infraestructura cloud.
- **Aprobador obligatorio:** Ciberseguridad.

## Repositorio `dcp-aws-diners-live`

### Propósito

Administrar la plataforma y los recursos compartidos del dominio diners de Diners Club Perú.

`dcp-aws-diners-live` es el único repositorio de dominio. `payments`, `cards`, `acquiring` y las demás capacidades son workloads dentro de este repositorio.

### Cuentas

- `dinersclub-diners-dev`
- `dinersclub-diners-qa`
- `dinersclub-diners-stg`
- `dinersclub-diners-prod`
- `dinersclub-contactcenter-<env>` (Amazon Connect en cuenta propia desde el día 1; carpetas `live/contactcenter-<env>/`)

### Estructura

```text
dcp-aws-diners-live/
├── terragrunt.hcl
├── domain.hcl
│
├── live/
│   ├── dev/
│   │   ├── account.hcl
│   │   ├── env.hcl
│   │   └── us-east-1/
│   │       ├── region.hcl
│   │       ├── platform/
│   │       │   ├── eks/            ← EKS Auto Mode
│   │       │   ├── eks-hybrid/     ← fase 1: clúster con nodos híbridos y Cilium
│   │       │   ├── kms/
│   │       │   ├── observability/
│   │       │   └── shared-iam/
│   │       └── workloads/
│   │           ├── payments/
│   │           │   ├── database/
│   │           │   ├── messaging/
│   │           │   ├── cache/
│   │           │   └── secrets/
│   │           ├── billing/
│   │           └── collections/
│   │
│   ├── qa/
│   │   ├── account.hcl
│   │   ├── env.hcl
│   │   └── us-east-1/
│   │       ├── region.hcl
│   │       ├── platform/
│   │       └── workloads/
│   │
│   ├── stg/
│   │   ├── account.hcl
│   │   ├── env.hcl
│   │   └── us-east-1/
│   │       ├── region.hcl
│   │       ├── platform/
│   │       └── workloads/
│   │
│   └── prod/
│       ├── account.hcl
│       ├── env.hcl
│       └── us-east-1/
│           ├── region.hcl
│           ├── platform/
│           └── workloads/
│
├── compositions/
│   ├── domain-platform/
│   └── workload-baseline/
│
├── tests/
└── README.md
```

### Estados

Cada directorio live ejecutable tendrá un estado Terraform independiente.

La separación se realizará por:

```text
ambiente + región + stack lógico
```

Ejemplo de estados:

```text
diners/dev/us-east-1/workloads/payments/database/terraform.tfstate
diners/dev/us-east-1/workloads/payments/messaging/terraform.tfstate
diners/dev/us-east-1/workloads/payments/cache/terraform.tfstate
diners/dev/us-east-1/workloads/payments/secrets/terraform.tfstate

diners/qa/us-east-1/workloads/payments/database/terraform.tfstate
diners/stg/us-east-1/workloads/payments/database/terraform.tfstate
diners/prod/us-east-1/workloads/payments/database/terraform.tfstate
diners/prod/us-east-1/workloads/payments/messaging/terraform.tfstate
```

No se permite un estado agregado por workload. Cada directorio ejecutable del ejemplo es una unidad de estado, pipeline, aprobación y recuperación; los directorios organizativos no crean estado.

### Criterio `platform` y `workloads`

`platform` contiene recursos compartidos:

- EKS.
- Node Groups.
- KMS base.
- Roles comunes.
- Observabilidad.
- Service mesh.
- Load balancers compartidos.

`workloads` contiene recursos exclusivos:

- Base de datos.
- Colas y tópicos.
- Cache.
- Secrets.
- Buckets dedicados.
- Roles específicos.

### Reglas

- No compartirá recursos de aplicación con otros repositorios; consumirá únicamente los servicios centrales autorizados.
- Las cuentas productivas podrán tener controles PCI adicionales.

## Repositorio `dcp-aws-data-live`

### Propósito

Administrar la plataforma de datos y analítica.

### Cuentas

- `dinersclub-data-qa`
- `dinersclub-data-lake-prod`
- `dinersclub-analytics-prod`

### Estructura

```text
dcp-aws-data-live/
├── terragrunt.hcl
├── domain.hcl
│
├── live/
│   ├── data-qa/
│   │   ├── account.hcl
│   │   ├── env.hcl
│   │   └── us-east-1/
│   │       ├── region.hcl
│   │       ├── data-lake/
│   │       ├── ingestion/
│   │       ├── catalog/
│   │       └── analytics/
│   │
│   ├── data-lake-prod/
│   │   ├── account.hcl
│   │   ├── env.hcl
│   │   └── us-east-1/
│   │       ├── region.hcl
│   │       ├── storage/
│   │       ├── lake-formation/
│   │       ├── glue/
│   │       └── ingestion/
│   │
│   └── analytics-prod/
│       ├── account.hcl
│       ├── env.hcl
│       └── us-east-1/
│           ├── region.hcl
│           ├── athena/
│           ├── redshift/
│           ├── bi-integration/
│           └── machine-learning/
│
├── compositions/
└── README.md
```

### Reglas

- `data-qa` utilizará `environment = "qa"`.
- `data-lake-prod` y `analytics-prod` utilizarán `environment = "prod"`.
- Data Lake y Analytics Prod tendrán estados independientes.
- El acceso cross-account será explícito.
- Los datos sensibles se tokenizarán o enmascararán.
- Lake Formation y KMS usarán políticas restrictivas.
- No se compartirán credenciales entre cuentas.

## Reglas añadidas

### Fronteras de ownership

Un repositorio live no debe administrar recursos cuya aprobación, cuenta o equipo propietario corresponda a otro repositorio. Las integraciones entre repositorios deben realizarse mediante contratos publicados, como Parameter Store, AWS RAM, Route 53, Organizations, tags o data sources autorizados.

### Ciclo de vida de cuentas

La incorporación, actualización o retiro de una cuenta debe coordinar:

- Ubicación en la OU correcta.
- Controles de AWS Control Tower.
- SCP, RCP y políticas declarativas aplicables.
- Roles de Terraform Plan y Apply.
- Backend y permisos de estado.
- Presupuesto, tags y contactos.
- Integración con auditoría, Security Hub, GuardDuty y logs.
