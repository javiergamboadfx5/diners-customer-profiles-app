# Plantillas IaC para proyectos — Terraform y Terragrunt alineados a los lineamientos

## 1. Convención de nombres

Patrón general (L07): `dcp-<domain>-<environment>-<workload>-<resource>[-<purpose>][-<region>][-<ordinal>]`

Los módulos arman los nombres a partir de `environment`, `workload`, `purpose` y `region_code`; el stack nunca escribe un nombre completo.

| Recurso | Patrón | dev | prod |
|---|---|---|---|
| Instancia EC2 | `…-ec2-<purpose>-<region>-<nn>` | `dcp-diners-dev-merchants-ec2-portal-use1-01` | `dcp-diners-prod-merchants-ec2-portal-use1-01` |
| SG de la EC2 | `…-sg-<purpose>` | `dcp-diners-dev-merchants-sg-portal` | `dcp-diners-prod-merchants-sg-portal` |
| Rol / instance profile | `…-role-ec2-<purpose>` | `dcp-diners-dev-merchants-role-ec2-portal` | `dcp-diners-prod-merchants-role-ec2-portal` |
| Política IAM | `…-policy-<purpose>-runtime` | `dcp-diners-dev-merchants-policy-portal-runtime` | idem prod |
| Log group app | `/dcp/<domain>/<env>/<workload>/<service>` | `/dcp/diners/dev/merchants/portal` | `/dcp/diners/prod/merchants/portal` |
| Cluster Aurora | `…-aurora-<purpose>-<region>` | `dcp-diners-dev-merchants-aurora-core-use1` | `dcp-diners-prod-merchants-aurora-core-use1` |
| Instancias Aurora | `<cluster>-instance-<nn>` | `…-aurora-core-use1-instance-01` | `-instance-01`, `-instance-02` |
| DB subnet group | `…-dbsubnet-<region>` | `dcp-diners-dev-merchants-dbsubnet-use1` | idem prod |
| Parameter group | `…-aurora-pg-<major>` | `dcp-diners-dev-merchants-aurora-pg-16` | idem prod |
| SG de Aurora | `…-sg-aurora` | `dcp-diners-dev-merchants-sg-aurora` | idem prod |
| Alias KMS | `alias/dcp/<domain>/<env>/<workload>/data` | `alias/dcp/diners/dev/merchants/data` | idem prod |
| Contrato SSM | `/dcp/<domain>/<env>/<workload>/config/<param>` | `/dcp/diners/dev/merchants/config/portal-sg-id` | idem prod |

> Un **Código nuevo `ec2`.** El catálogo de códigos de recurso no tiene EC2. El PR del módulo agrega `ec2` a `catalogos-cloud.yaml` y a la regla de TFLint. Lo aprueba Arquitectura.

Recursos Terraform internos en `snake_case` sin repetir el nombre físico: `aws_instance.this`, `aws_security_group.this`.

---

## 2. Tags

Los tags obligatorios **no se escriben en cada recurso**. El `terragrunt.hcl` raíz los arma desde los archivos de la jerarquía y los inyecta con `default_tags` del provider. Cada módulo solo agrega `Name`.

| Tag | De dónde sale | Valor en dev |
|---|---|---|
| `Name` | El módulo, por recurso | `dcp-diners-dev-merchants-ec2-portal-use1-01` |
| `Environment` | `env.hcl` | `dev` |
| `Scope` | `domain.hcl` | `diners` |
| `Domain` | `domain.hcl` (solo workloads) | `diners` |
| `Workload` | `app.hcl` | `merchants` |
| `Application` | `app.hcl` | `merchant-portal` |
| `Owner` | `app.hcl` | `equipo-comercios` |
| `CostCenter` | `app.hcl` | `410230` |
| `DataClassification` | `app.hcl` | `confidential` |
| `Compliance` | `app.hcl` | `lpdp` |
| `ManagedBy` | `terragrunt.hcl` raíz | `terraform` |
| `Repository` | `domain.hcl` | `dcp-aws-diners-live` |
| `TerraformStack` | `terragrunt.hcl` raíz (ruta del stack) | `diners/dev/us-east-1/workloads/merchants/compute` |
| `Criticality` (complementario) | `app.hcl` → input `tags` | `tier-2` |

Controles:

- Los módulos rechazan tags fuera del catálogo de complementarios y valores como `shared`, `unknown` o vacío.
- `policies/terraform/conftest/tags.rego` revisa el plan: faltan tags obligatorios, valores fuera de `catalogos-cloud.yaml`, o `Name` sin prefijo `dcp-`.
- Los volúmenes EBS no heredan `default_tags`; el módulo de EC2 los copia con `data "aws_default_tags"`.

---

## 3. Dónde se guarda el estado

| Pregunta | Respuesta |
|---|---|
| ¿Dónde? | S3 en la cuenta de bootstrap. Un bucket por tier: `dcp-platform-shared-terraform-s3-state-nonprod-use1-<unique>` (dev, qa, stg) y `…-state-prod-use1-<unique>` (prod). |
| ¿Clave? | `<domain>/<env>/<region>/<ruta del stack>/terraform.tfstate`, calculada por el `terragrunt.hcl` raíz desde la carpeta. |
| ¿Un estado por qué? | Por stack: `compute` y `database` tienen estados separados en cada ambiente (8 estados en total). |
| ¿Lock? | Nativo de S3 (`use_lockfile = true`), sin DynamoDB. |
| ¿Cifrado? | SSE-KMS con la llave que publica el bootstrap en `state.hcl`. |
| ¿Quién lo lee? | Solo los roles CI/CD de plan y apply, acotados por la bucket policy al prefijo `diners/*`. Nadie lo descarga a su laptop. |
| ¿Quién crea el bucket? | `dcp-terraform-bootstrap`. Terragrunt tiene `disable_bucket_update = true` y no lo toca. |

Ejemplos de claves:

```
diners/dev/us-east-1/workloads/merchants/compute/terraform.tfstate
diners/dev/us-east-1/workloads/merchants/database/terraform.tfstate
diners/prod/us-east-1/workloads/merchants/compute/terraform.tfstate
diners/prod/us-east-1/workloads/merchants/database/terraform.tfstate
```

`.terraform.lock.hcl` de cada stack **se versiona** en Git; `backend.tf` y `provider.tf` los genera Terragrunt y no se versionan.

---

## 4. Cómo se conectan los dos stacks sin leer estado ajeno

```
compute  ── publica ──▶  /dcp/diners/<env>/merchants/config/portal-sg-id  ── lee ──▶  database
   │                                                                                  │
   └── lee /dcp/networking/vpc/id, subnets/app-private/ids, vpc/cidr                  └── lee /dcp/networking/subnets/data-private/ids
```

- Networking publica la VPC, las subredes y los CIDR en Parameter Store de cada cuenta. Los módulos los leen; ningún stack escribe un ID de VPC o subred.
- `database/terragrunt.hcl` tiene `dependencies { paths = ["../compute"] }` solo para el **orden**; no lee outputs ni estado de compute (L05).
- La app se conecta a Aurora con **autenticación IAM** (`rds-db:connect` sobre `merchant_portal_app`). La contraseña maestra la genera y rota RDS en Secrets Manager; nunca aparece en el código.

> **Primer despliegue:** compute y database van en **dos PR**. El plan de database necesita el parámetro que compute publica; si ambos van en el mismo PR, el plan de database falla porque el parámetro aún no existe.

**Portabilidad:** para mudar la app a una cuenta propia, se agrega la cuenta a `accounts.yaml` y se cambia `account_key` en `account.hcl`. Los stacks no cambian porque los contratos SSM tienen las mismas rutas en todas las cuentas.

---

## 5. El pipeline

### Tipo

GitHub Actions con **workflow reusable** de Platform (`terraform-stack.yml`, llamado por SHA) corriendo en **runners efímeros de CodeBuild o EC2** en la cuenta DevOps (`dinersclub-devops`). Plan y apply usan **identidades distintas**. Se aplica **exactamente el plan aprobado**.

### Etapas

```
PULL REQUEST
  detect ─▶ validate ─────────────────────▶ plan especulativo ─▶ comentario en el PR
           · terragrunt hcl fmt --check      · rol de PLAN          (no se puede aplicar)
           · gitleaks (secretos)             · Conftest + Checkov
           · catálogos sincronizados           sobre el plan JSON
           · módulos por SHA de 40
           · app.hcl vs catálogo
                                   │
                         revisión CODEOWNERS + checks verdes
                                   ▼
MERGE A main
  detect ─▶ validate ─▶ plan guardado ─▶ ⏸ aprobación del environment ─▶ apply del mismo plan ─▶ evidencia
                        · sha256 + commit    · diners-dev: automática      · verifica sha256,
                        · S3 cifrado         · diners-qa/stg/prod:           commit y vigencia ≤ 24 h
                                               revisores (tabla abajo)     · rol de APPLY del tier
```

- Los stacks se procesan en orden de dependencias (compute antes que database) y el apply va de uno en uno.
- Si el plan tiene más de 24 h, cambió el commit o el checksum no coincide, el apply falla y hay que volver a correr el pipeline.
- `terraform apply` en prod desde una laptop está prohibido; fuera del pipeline solo se puede planificar.

### Aprobaciones

| Dónde | Quién aprueba | Regla |
|---|---|---|
| PR a `main` | CODEOWNERS: `Grp_GH_App_[App]_Leads` + `Grp_GH_Infrastructure`; en `live/prod/` también `Grp_GH_Release_Managers` | Checks verdes y conversación resuelta |
| Environment `diners-dev` | Nadie (automático) | Solo desde `main` |
| Environment `diners-qa` | `Grp_GH_QA_Leads` (1) | |
| Environment `diners-stg` | `Grp_GH_App_[App]_Leads` (1) | |
| Environment `diners-prod` | `Grp_GH_Release_Managers` + `Grp_GH_App_[App]_Leads` (2) | Quien hizo el cambio no puede aprobar; dentro de ventana de cambio |
| Stacks CDE (`DataClassification = pci`) | Además `Grp_GH_Security` | Environment `diners-prod-cde` |

---

## 6. Cómo se autentica contra AWS

No hay access keys en ningún lado: ni en GitHub, ni en el runner, ni en el código.

```
Job de GitHub (template de Platform)
   │  1. GitHub emite un token OIDC con:
   │     sub = repo:Diners/dcp-aws-diners-live:environment:diners-prod:job_workflow_ref:Diners/dcp-platform-pipeline-templates/...@<sha>
   ▼
Cuenta DevOps
   │  2. sts:AssumeRoleWithWebIdentity
   │     PR / main   → dcp-platform-shared-cicd-role-terraform-plan
   │     apply dev-stg → dcp-platform-shared-cicd-role-terraform-apply-nonprod   (sub con environment:*-dev|qa|stg)
   │     apply prod  → dcp-platform-shared-cicd-role-terraform-apply-prod      (sub con environment:*-prod)
   ▼
Cuenta destino (dinersclub-diners-<env>)
      3. El provider del terragrunt.hcl raíz hace sts:AssumeRole a TerraformPlanRole o TerraformApplyRole
         con allowed_account_ids = [la cuenta de account.hcl]
```

Qué garantiza cada pieza:

- **El claim `sub` incluye `job_workflow_ref`.** Solo el template de Platform puede asumir los roles; un workflow escrito por un proyecto no puede.
- **El rol de apply exige `environment:`.** Solo un job que pasó la aprobación del environment recibe credenciales de apply.
- **Hay un rol de apply por tier.** El de nonprod no puede asumir `TerraformApplyRole` en prod.
- **`TerraformApplyRole` de prod solo confía en el rol apply-prod**, dentro de la organización.
- **`TerraformPlanRole` es de solo lectura.** Sirve para el plan y la detección de drift.
- **Todo rol que crea Terraform lleva el permission boundary** `dcp-platform-permission-boundary`.

Detalle en `referencia-plataforma/cicd-roles.tf` y `target-account-roles.json`.

---


## 7. Paso a paso para un proyecto nuevo

1. **Registrar la app** en `catalogos-cloud.yaml` (repo de gobierno): workload, Application, Owner, CostCenter, DataClassification, Compliance y Criticality.
2. **Revisar módulos** en `compatibility.yaml`. Si falta uno, crearlo en `dcp-terraform-modules` siguiendo `PR-NUEVO-MODULO.md` y publicar el release.
3. **Crear la carpeta** `live/<env>/us-east-1/workloads/<workload>/` con `app.hcl` y un subdirectorio por stack (`compute/`, `database/`, ...).
4. **Escribir cada `terragrunt.hcl`** con `include "root"`, la fuente del módulo **por SHA** y solo los inputs propios. Nada de IDs de cuenta, VPC o subred; nada de secretos.
5. **PR a `main` con dev.** Revisar el plan especulativo en el comentario. Si hay stacks dependientes nuevos, primero el que publica el contrato.
6. **Merge.** El pipeline aplica dev sin aprobación manual.
7. **Promover:** un PR por ambiente (qa, stg, prod) copiando la carpeta y ajustando tamaños. Cada apply espera la aprobación de su environment.
8. **Operar:** el drift de prod se revisa con `plan -detailed-exitcode` programado; el destroy productivo usa el pipeline separado de L06.

---

