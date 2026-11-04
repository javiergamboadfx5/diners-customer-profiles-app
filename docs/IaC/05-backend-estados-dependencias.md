# Backend, estados y dependencias Terraform

## Propósito

Define el bootstrap, los buckets de estado, el locking, la separación de estados, las claves, la recuperación y el intercambio controlado de outputs.

### Repositorio `dcp-terraform-bootstrap`

#### Propósito — Repositorio dcp-terraform-bootstrap

Crear los recursos mínimos necesarios para que los demás repositorios
puedan utilizar un backend remoto seguro.

#### Contenido

- Buckets S3 de estado.
- Versionado.
- KMS para cifrado.
- Políticas de bucket.
- Block Public Access.
- Logging y auditoría.
- Roles de acceso al backend.
- Lock del estado.
- Alarmas sobre modificaciones no autorizadas.

#### Estructura

```text
dcp-terraform-bootstrap/
├── live/
│   └── tooling/
│       └── us-east-1/
│           └── terraform-backend/
│               ├── main.tf
│               ├── variables.tf
│               ├── outputs.tf
│               ├── providers.tf
│               ├── versions.tf
│               └── terraform.tfvars
│
├── policies/
├── tests/
└── README.md
```

> Se incluye la región en la estructura para soportar una arquitectura
> regional del stack y facilitar una futura expansión
> multi-región sin reorganizar el repositorio.

#### Buckets de estados

Los buckets seguirán la convención de S3 definida en las convenciones

```text
dcp-platform-shared-terraform-s3-state-foundation-use1-<unique>
dcp-platform-shared-terraform-s3-state-nonprod-use1-<unique>
dcp-platform-shared-terraform-s3-state-prod-use1-<unique>
```

`<unique>` es `substr(sha256("<organization-id>:<account-id>:terraform-state"), 0, 12)`. El bootstrap publica
el nombre final, la región y el ARN KMS en `state.hcl`; los repositorios `live` no contienen sufijos de ejemplo.

#### Requisitos

Cada bucket deberá tener:

- Versioning.
- SSE-KMS.
- Block Public Access.
- Bucket policy restrictiva.
- Acceso únicamente desde roles autorizados.
- CloudTrail.
- Recuperación de versiones.
- Lock nativo de S3.

### Backend generado

El ejemplo siguiente corresponde a los repositorios de workload.
Los repositorios fundacionales utilizarán directamente el tier
`foundation`.

```hcl
locals {
  domain_config = read_terragrunt_config(
    find_in_parent_folders("domain.hcl")
  )

  env_config = read_terragrunt_config(
    find_in_parent_folders("env.hcl")
  )

  account_config = read_terragrunt_config(
    find_in_parent_folders("account.hcl")
  )

  region_config = read_terragrunt_config(
    find_in_parent_folders("region.hcl")
  )

  state_config = read_terragrunt_config(
    find_in_parent_folders("state.hcl")
  )

  domain      = local.domain_config.locals.domain
  environment = local.env_config.locals.environment
  account_id  = local.account_config.locals.account_id
  aws_region  = local.region_config.locals.aws_region

  state_tier = {
    dev  = "nonprod"
    qa   = "nonprod"
    stg  = "nonprod"
    prod = "prod"
  }[local.environment]

  state_bucket_name = local.state_config.locals.bucket_by_tier[local.state_tier]
  state_region     = local.state_config.locals.aws_region
  state_kms_key_id = local.state_config.locals.kms_key_arn

  relative_stack_path = trimprefix(
    path_relative_to_include(),
    "live/"
  )
}

remote_state {
  backend = "s3"

  config = {
    bucket       = local.state_bucket_name
    key          = "${local.domain}/${local.relative_stack_path}/terraform.tfstate"
    region       = local.state_region
    kms_key_id   = local.state_kms_key_id
    encrypt      = true
    use_lockfile = true
  }
}
```

Ejemplos de claves:

```text
diners/dev/us-east-1/platform/eks/terraform.tfstate
diners/qa/us-east-1/platform/eks/terraform.tfstate
diners/stg/us-east-1/platform/eks/terraform.tfstate
diners/prod/us-east-1/platform/eks/terraform.tfstate
diners/prod/us-east-1/workloads/payments/database/terraform.tfstate
diners/prod/us-east-1/workloads/payments/messaging/terraform.tfstate
```

### Dependencias entre estados

Se evitará una cadenas extensa de `terraform_remote_state`.

Los valores compartidos se publicarán preferentemente mediante:

- Systems Manager Parameter Store.
- AWS RAM.
- Route 53.
- Tags y data sources.
- AWS Organizations.
- Secrets Manager para información sensible.

Ejemplo:

```text
/dcp/networking/tgw/id
/dcp/networking/ipam/prod-pool-id
/dcp/networking/private-zone/id
```

Los parámetros compartidos incluyen `owner`, clasificación, versión del contrato y fecha de expiración cuando
corresponda. El consumidor no puede leer estado remoto directamente salvo una excepción temporal registrada.

## Reglas

### Clasificación del estado

El estado Terraform debe tratarse como información `restricted` porque puede contener identificadores,
topología, atributos sensibles y valores derivados de recursos.

Queda prohibido:

- Almacenar estados en Git.
- Descargar estados a equipos personales salvo procedimiento de contingencia.
- Editar manualmente el JSON.
- Compartir el estado entre cuentas o dominios sin una necesidad explícita.
- Exponer outputs sensibles como texto plano.

### Locking

El backend S3 debe utilizar:

```hcl
use_lockfile = true
```

### Recuperación

Cada bucket debe tener versioning y una política de retención que permita recuperar estados eliminados o
sobrescritos accidentalmente.

La recuperación debe incluir:

- Identificación de la versión correcta.
- Aprobación de Infraestructura Cloud.
- Validación del serial y lineage.
- Restauración controlada.
- Ejecución de `plan` antes de cualquier `apply`.
- Evidencia y registro del incidente.

### Force unlock

`terraform force-unlock` solo puede utilizarse cuando se haya demostrado que no existe una ejecución activa. Requiere registrar:

- Lock ID.
- Stack.
- Pipeline o usuario que generó el lock.
- Evidencia de la ejecución fallida.
- Aprobador.
- Resultado posterior del plan.

### Credenciales del backend

Las credenciales y datos sensibles no deben incluirse en el bloque backend ni en archivos `-backend-config`
almacenados en Git. El acceso debe resolverse con OIDC, perfiles temporales o `AssumeRole`.

### Registro de claves

Debe mantenerse un inventario de claves de estado para detectar:

- Duplicidades.
- Stacks huérfanos.
- Cambios de ruta.
- Estados sin pipeline.
- Estados sin owner.
