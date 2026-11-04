# Estándar de módulos Terraform (v1.1)

> **Cambios en v1.1 (2026-10-28):** tags de release por módulo (`<categoría>/<módulo>/vX.Y.Z`).

## Propósito

Define cómo desarrollar, probar, versionar, publicar y evolucionar módulos reutilizables en `dcp-terraform-modules`.

## Repositorio `dcp-terraform-modules`

### Propósito

Centralizar módulos Terraform reutilizables, versionados y validados.

### Estructura del repositorio de módulos

```text
dcp-terraform-modules/
├── modules/
│   ├── foundation/
│   │   ├── iam-role/
│   │   ├── kms-key/
│   │   ├── mandatory-tags/
│   │   └── deployment-role/
│   │
│   ├── network/
│   │   ├── ipam/
│   │   ├── vpc/
│   │   ├── subnet/
│   │   ├── route-table/
│   │   ├── ram-share/
│   │   ├── transit-gateway/
│   │   ├── tgw-attachment/
│   │   ├── vpc-endpoints/
│   │   ├── route53-resolver/
│   │   └── network-firewall/
│   │
│   ├── platform/
│   │   ├── eks/
│   │   ├── eks-node-group/
│   │   ├── load-balancer/
│   │   └── waf/
│   │
│   ├── security/
│   │   ├── guardduty-organization/
│   │   ├── security-hub-organization/
│   │   ├── inspector-organization/
│   │   ├── config-conformance-pack/
│   │   ├── cloudtrail/
│   │   └── firewall-manager/
│   │
│   ├── data/
│   │   ├── aurora-postgresql/
│   │   ├── rds-postgresql/
│   │   ├── documentdb/
│   │   ├── dynamodb/
│   │   ├── elasticache-redis/
│   │   ├── sqs/
│   │   ├── sns/
│   │   ├── msk-kafka/
│   │   └── secrets-manager/
│   │
│   └── observability/
│       ├── cloudwatch-log-group/
│       ├── cloudwatch-alarms/
│       ├── flow-logs/
│       └── central-log-destination/
│
├── examples/
├── tests/
├── CHANGELOG.md
└── README.md
```

Solo se crean carpetas para módulos implementados. No se versionan directorios vacíos ni módulos anunciados sin contrato, pruebas y owner.

### Estructura mínima de un módulo

Todas las carpetas de módulo deberán tener su estructura organizada de la siguiente manera.

```text
modules/<categoria>/<modulo>/
├── main.tf
├── variables.tf
├── outputs.tf
├── versions.tf
├── locals.tf
├── README.md
├── examples/
│   ├── basic/
│   └── production/
└── tests/
```

## Reglas de diseño

Cada módulo deberá:

- Tener una responsabilidad clara.
- Evitar componentes no relacionados.
- Definir versiones mínimas de Terraform y providers.
- Documentar inputs y outputs.
- Incluir ejemplos funcionales.
- Incluir validaciones.
- Aplicar tags obligatorios.
- No contener valores de cuenta o ambiente.
- No contener secretos.
- No depender de rutas relativas hacia repositorios live.

## Versionamiento

Se utilizará Semantic Versioning:

```text
v1.0.0
v1.1.0
v2.0.0
```

Los módulos reutilizables se versionarán utilizando Semantic Versioning:

```text
v<major>.<minor>.<patch>
```

Tag de versiones:

```bash
git tag -s compute/ec2-instance/v1.4.0 -m "compute/ec2-instance v1.4.0"
git push origin compute/ec2-instance/v1.4.0
```

> **Decidido en v1.1:** como el repositorio contiene varios módulos, cada tag lleva la ruta del módulo (`<categoría>/<módulo>/vX.Y.Z`). `compatibility.yaml` registra el SHA que consumen los repos live.

Ejemplo de invocación:

```hcl
terraform {
  source = "git::ssh://git@github.com/Diners/dcp-terraform-modules.git//modules/platform/eks?ref=7f3c2a1986d4b50e2f01897ca640d5bb18e2a417"
}
```

## Reglas

### Restricciones de versiones

Los módulos reutilizables deben declarar:

- `required_version = ">= 1.15.8, < 1.16.0"` para Terraform.
- `hashicorp/aws` con `>= 6.47.0, < 7.0.0` y `hashicorp/helm` con `>= 3.1.2, < 4.0.0` cuando se utilicen. Otros providers requieren una entrada aprobada en `compatibility.yaml` con rango mayor acotado.
- El root module selecciona el patch exacto en `.terraform.lock.hcl` y lo actualiza mediante pull request automatizado y pruebas en todos los stacks consumidores.
- Un módulo declara `configuration_aliases` únicamente si su contrato crea recursos en más de una región o cuenta; cada alias se documenta, se prueba y debe ser suministrado explícitamente por el root module.

Los root modules y stacks live deben fijar rangos controlados y conservar `.terraform.lock.hcl` en control de versiones para obtener versiones y checksums reproducibles de providers.

Los módulos remotos deben consumirse siempre mediante una referencia inmutable:

```text
ref=<sha-completo-de-40-caracteres>
```

No se permite consumir módulos desde ramas, `main`, tags o commits no aprobados. Cada release SemVer crea un tag anotado y firmado; como una referencia Git es actualizable, el ruleset impide modificarla o eliminarla y `compatibility.yaml` registra el commit SHA que consume Terraform. La metadata de GitHub Release es informativa y no sustituye el SHA.

Queda prohibido consumir módulos desde Terraform Registry público, repositorios Git externos o URLs de descarga externas. Los módulos reutilizables deben provenir de repositorios Git corporativos y utilizar referencias inmutables. Los providers y binarios requeridos deben descargarse desde el repositorio hosted aprobado de Nexus configurado como network mirror por Platform.

### Compatibilidad

- Un cambio patch corrige comportamiento sin cambiar contratos.
- Un cambio minor agrega capacidades compatibles.
- Un cambio major puede modificar inputs, outputs o comportamiento.
- La eliminación de una variable u output requiere deprecación previa.
- Los cambios de dirección de recursos deben incluir bloques `moved` cuando sea posible.
- La adopción de recursos existentes debe utilizar bloques `import` o un proceso controlado de importación.

### Pruebas

Cada módulo debe incluir, según su criticidad:

- Validaciones de variables.
- `terraform fmt` y `terraform validate`.
- TFLint.
- Escaneo IaC.
- Pruebas con `terraform test`.
- Pruebas de contrato sobre outputs.

### Documentación mínima

El README del módulo debe contener:

- Propósito y límites.
- Recursos creados.
- Inputs y outputs.
- Providers y versiones.
- Ejemplo básico y productivo.
- Supuestos de seguridad.
- Costos relevantes.
- Comportamiento de reemplazo.
- Estrategia de actualización y breaking changes.
