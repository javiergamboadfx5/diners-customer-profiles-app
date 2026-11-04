# Naming AWS: organización, IAM y networking

## Propósito

Define nombres para AWS Organizations, cuentas, Identity Center, IAM, KMS, networking, conectividad y DNS.

### AWS Organizations y cuentas

#### Organización

Nombre descriptivo:

```text
Diners Club Peru
```
#### Organizational Units

Las OUs utilizarán `PascalCase`, sin prefijo `dcp`,
porque su contexto ya es la organización AWS.

```text
Security
Infrastructure
Identity
Workloads
Diners
Prod
NonProd
PolicyStaging
Exceptions
Transitional
MPA
Data
```

Jerarquía inicial:

```text
Workloads
└── Diners
    ├── Prod
    └── NonProd
```

No se incluirán nombres de región en OUs.

#### Cuentas AWS

Patrón de workload:

```text
dinersclub-<domain>-<environment>
```

Ejemplos:

```text
dinersclub-diners-dev
dinersclub-diners-qa
dinersclub-diners-prod
```

Patrón de cuentas fundacionales:

```text
dinersclub-<function>
```

Ejemplos:

```text
dinersclub-networking
dinersclub-shared-services
dinersclub-security-tooling
dinersclub-log-archive
dinersclub-audit
```

Cuentas de datos:

```text
dinersclub-data-qa
dinersclub-data-lake-prod
dinersclub-analytics-prod
```

La cuenta `dinersclub-data-qa` utilizará el código de ambiente
`qa`; no se utilizará un ambiente adicional denominado `test`.

#### Alias de cuenta

Cuando se configure un account alias:

```text
dcp-<scope>-<environment>
```

Ejemplos:

```text
dcp-diners-prod
dcp-network-shared
dcp-security-shared
```

### IAM, Identity Center y cifrado

#### Permission Sets

```text
DCP-<Scope>-<AccessLevel>
```

Ejemplos:

```text
DCP-Diners-Developer
DCP-Diners-ReadOnly
DCP-Diners-ProdOperator
DCP-Networking-Administrator
DCP-Security-Auditor
DCP-Platform-Administrator
```

Niveles aprobados:

```text
ReadOnly
Developer
Operator
ProdOperator
Administrator
Auditor
```

#### Roles IAM

```text
dcp-<scope>-<environment>-<workload>-role-<purpose>
```

Ejemplos:

```text
dcp-diners-prod-payments-role-lambda-exec
dcp-diners-prod-payments-role-apigw-logs
dcp-diners-prod-platform-role-eks-control-plane
dcp-platform-shared-cicd-role-terraform-apply
```

Roles Terraform obligatorios:

```text
TerraformPlanRole
TerraformApplyRole
```

Estos dos nombres se mantienen sin prefijo para que sean iguales en todas las cuentas y
puedan ser resueltos de forma uniforme por los pipelines.

#### Policies IAM

```text
dcp-<scope>-<environment>-<workload>-policy-<permission>
```

Ejemplos:

```text
dcp-diners-prod-payments-policy-dynamodb-rw
dcp-diners-prod-payments-policy-sqs-consume
dcp-platform-shared-cicd-policy-assume-workload
```

#### IAM Roles for Service Accounts

```text
dcp-<domain>-<environment>-<workload>-irsa-<service>
```

Ejemplo:

```text
dcp-diners-prod-payments-irsa-payment-api
```

#### KMS aliases

Patrón jerárquico:

```text
alias/dcp/<scope>/<environment>/<workload>/<purpose>
```

Ejemplos:

```text
alias/dcp/diners/prod/payments/data
alias/dcp/diners/prod/payments/secrets
alias/dcp/security/shared/log-archive
alias/dcp/network/shared/flow-logs
```

El nombre físico de la key será generado por AWS;
el alias es la referencia estable que deberán utilizar los módulos y aplicaciones.

---

### Networking

#### VPC

```text
dcp-<scope>-<environment>-vpc-<region>
```

Ejemplos:

```text
dcp-diners-prod-vpc-use1
dcp-diners-qa-vpc-use1
dcp-network-shared-inspection-vpc-use1
dcp-network-shared-egress-vpc-use1
```

Cuando se implemente Shared VPC, el nombre se
asignará según la frontera de confianza y no según
la cuenta participante.

#### Subnets

```text
dcp-<scope>-<environment>-snet-<tier>-<exposure>-<az-id>
```

Ejemplos:

```text
dcp-diners-prod-snet-app-private-use1-az1
dcp-diners-prod-snet-data-private-use1-az2
dcp-diners-prod-snet-ingress-public-use1-az1
dcp-network-shared-snet-endpoints-private-use1-az1
```

Se utilizará el AZ ID lógico, como `use1-az1`,
en lugar de depender únicamente de la letra
visible `us-east-1a`.

Tiers aprobados:

```text
ingress
app
data
endpoints
inspection
egress
```

Exposición:

```text
public
private
isolated
```

#### Route tables

```text
dcp-<scope>-<environment>-rt-<tier>-<region>
```

Ejemplos:

```text
dcp-diners-prod-rt-app-use1
dcp-diners-prod-rt-data-use1
dcp-network-shared-rt-inspection-use1
```

#### Network ACL

```text
dcp-<scope>-<environment>-nacl-<tier>-<region>
```

Ejemplo:

```text
dcp-diners-prod-nacl-data-use1
```

#### Security groups

```text
dcp-<scope>-<environment>-<workload>-sg-<purpose>
```

Ejemplos:

```text
dcp-diners-prod-payments-sg-api
dcp-diners-prod-payments-sg-aurora
dcp-diners-prod-platform-sg-eks-nodes
dcp-network-shared-endpoints-sg-vpce
```

El nombre describe al recurso protegido, no al
origen de cada regla.

No usar:

```text
allow-port-5432
allow-from-anywhere
sg-temporal
```

#### Transit Gateway

```text
dcp-network-shared-tgw-<region>
```

Ejemplo:

```text
dcp-network-shared-tgw-use1
```

Attachment:

```text
dcp-<scope>-<environment>-tgwatt-<region>
```

Ejemplo:

```text
dcp-diners-prod-tgwatt-use1
```

Route table de TGW:

```text
dcp-network-<segment>-tgwrt-<region>
```

Ejemplos:

```text
dcp-network-prod-tgwrt-use1
dcp-network-nonprod-tgwrt-use1
dcp-network-inspection-tgwrt-use1
```

#### VPC endpoints

```text
dcp-<scope>-<environment>-vpce-<aws-service>-<region>
```

Ejemplos:

```text
dcp-diners-prod-vpce-s3-use1
dcp-diners-prod-vpce-secretsmanager-use1
dcp-diners-prod-vpce-ecr-api-use1
```

El endpoint ECR solo permite que EKS obtenga imágenes de componentes administrados por AWS incluidos en la
allowlist de plataforma. No autoriza repositorios ECR de aplicaciones ni sustituye Nexus; las NetworkPolicies,
policies del endpoint y SCP limitan cuentas y repositorios permitidos.

#### IPAM

```text
dcp-network-<environment>-ipam-pool-<region>
```

Ejemplos:

```text
dcp-network-prod-ipam-pool-use1
dcp-network-nonprod-ipam-pool-use1
```

#### Route 53

Las zonas y registros utilizan nombres DNS, no el patrón físico de recursos AWS.

Zona privada sugerida:

```text
<environment>.aws.dinersclub.com.pe
```

Ejemplos:

```text
prod.aws.dinersclub.com.pe
qa.aws.dinersclub.com.pe
dev.aws.dinersclub.com.pe
```

Nombres de servicios:

```text
<service>.<workload>.<environment>.aws.dinersclub.com.pe
```

Ejemplo:

```text
payment-api.payments.prod.aws.dinersclub.com.pe
```

## Reglas

### Políticas de Organizations

Las políticas deben utilizar nombres descriptivos y estables según su resultado, no según el ticket o proyecto que las originó.

Patrones sugeridos:

```text
DCP-SCP-<Outcome>
DCP-RCP-<Outcome>
DCP-TagPolicy-<Scope>
DCP-BackupPolicy-<Scope>
DCP-DeclarativePolicy-<Service>-<Outcome>
```

Ejemplos:

```text
DCP-SCP-DenyUnapprovedRegions
DCP-RCP-ProtectCentralLogs
DCP-TagPolicy-Workloads
DCP-BackupPolicy-Production
```

### Recursos administrados por Control Tower

Los recursos creados y administrados por AWS Control Tower no deben renombrarse ni modificarse
directamente. Las personalizaciones deben realizarse mediante mecanismos soportados y quedar
registradas en el repositorio de gobierno.

### CIDR e IPAM

Los nombres no sustituyen la asignación formal de CIDR. Todo VPC, subnet y pool debe vincularse a:

- Pool IPAM.
- Cuenta.
- Ambiente.
- Región.
- Frontera de confianza.
- Owner.
- Estado de asignación.

### DNS

Los nombres DNS representan contratos de resolución y no deben copiar mecánicamente el nombre
físico AWS. Los cambios de zonas privadas, resolvers y delegaciones deben preservar compatibilidad y documentar consumidores.
