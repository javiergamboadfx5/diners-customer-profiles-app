# Naming AWS: datos, mensajería y observabilidad

## Propósito

Define nombres físicos para almacenamiento, bases de datos, caché, mensajería, secretos, parámetros, observabilidad,
backup y analítica.

### Almacenamiento y bases de datos

#### S3 buckets

Los nombres de bucket deben ser globalmente únicos.
Se utilizará:

```text
dcp-<scope>-<environment>-<workload>-s3-<purpose>-<region>-<unique>
```

`unique` será un sufijo determinístico de doce caracteres calculado como
`substr(sha256("<organization-id>:<account-id>:<purpose>"), 0, 12)`; no se regenera en cada despliegue.

Ejemplos:

```text
dcp-diners-prod-payments-s3-documents-use1-a1b2c3d4e5f6
dcp-diners-prod-billing-s3-statements-use1-a1b2c3d4e5f6
dcp-security-prod-logs-s3-cloudtrail-use1-f6e5d4c3b2a1
```

No se utilizarán puntos en el nombre de buckets empresariales.

Buckets del backend de Terraform:

```text
dcp-platform-shared-terraform-s3-state-<tier>-<region>-<unique>
```

Valores de `tier`:

```text
foundation
nonprod
prod
```

Ejemplos:

```text
dcp-platform-shared-terraform-s3-state-foundation-use1-a1b2c3d4e5f6
dcp-platform-shared-terraform-s3-state-nonprod-use1-a1b2c3d4e5f6
dcp-platform-shared-terraform-s3-state-prod-use1-a1b2c3d4e5f6
```

Prefijos de objetos:

```text
<workload>/<data-type>/year=YYYY/month=MM/day=DD/
```

Ejemplo:

```text
payments/transactions/year=2026/month=07/day=15/
```

#### Aurora PostgreSQL

Cluster:

```text
dcp-<domain>-<environment>-<workload>-aurora-<purpose>-<region>
```

Ejemplo:

```text
dcp-diners-prod-payments-aurora-core-use1
```

Instancias del cluster:

```text
<cluster-name>-instance-01
<cluster-name>-instance-02
```

Ejemplos:

```text
dcp-diners-prod-payments-aurora-core-use1-instance-01
dcp-diners-prod-payments-aurora-core-use1-instance-02
```

El nombre de la instancia es estable y no codifica un rol mutable. Las aplicaciones usan los endpoints de
cluster `writer` y `reader`; el tag `DatabaseRole` refleja el rol observado y puede cambiar durante un failover.

DB subnet group:

```text
dcp-<domain>-<environment>-<workload>-dbsubnet-<region>
```

Parameter groups:

```text
dcp-<domain>-<environment>-<workload>-aurora-pg-<major-version>
```

#### RDS PostgreSQL

```text
dcp-<domain>-<environment>-<workload>-rds-<purpose>-<region>
```

Ejemplo:

```text
dcp-diners-prod-billing-rds-core-use1
```

#### DynamoDB

Tabla:

```text
dcp-<domain>-<environment>-<workload>-ddb-<entity>
```

Ejemplos:

```text
dcp-diners-prod-payments-ddb-idempotency
dcp-diners-prod-payments-ddb-payment-session
```

Índices:

```text
gsi-<partition-attribute>[-<sort-attribute>]
lsi-<sort-attribute>
```

Ejemplos:

```text
gsi-status-created-at
gsi-customer-id-created-at
lsi-updated-at
```

No existe un esquema universal. Cada tabla documenta primero sus access patterns y deriva `pk`, `sk`, índices,
tipos, proyección, consistencia y estrategia de hot-partition. Los atributos de auditoría se agregan solo cuando
el contrato los necesita; una clave puede ser UUID, ULID o una clave compuesta estable. El pipeline exige el
documento de access patterns y pruebas de distribución antes de crear la tabla.

#### ElastiCache para Redis/Valkey

```text
dcp-<domain>-<environment>-<workload>-redis-<region>
```

Ejemplo:

```text
dcp-diners-prod-payments-redis-use1
```

Debido al límite del identificador, si el
workload supera el máximo se utilizará el código
compacto aprobado.

Subnet group:

```text
dcp-<domain>-<environment>-<workload>-redis-subnet
```

Parameter group:

```text
dcp-<domain>-<environment>-<workload>-redis-pg-<major-version>
```

---

### Mensajería y eventos

#### SQS

Queue estándar:

```text
dcp-<domain>-<environment>-<workload>-sqs-<message>
```

Ejemplos:

```text
dcp-diners-prod-payments-sqs-payment-created
dcp-diners-prod-billing-sqs-statement-requested
```

Dead-letter queue:

```text
<queue-name>-dlq
```

Ejemplo:

```text
dcp-diners-prod-payments-sqs-payment-created-dlq
```

Para una cola FIFO, la DLQ también es FIFO y conserva el sufijo al final:

```text
dcp-diners-prod-payments-sqs-payment-command-dlq.fifo
```

FIFO:

```text
<queue-name>.fifo
```

Ejemplo:

```text
dcp-diners-prod-payments-sqs-payment-command.fifo
```

#### SNS

```text
dcp-<domain>-<environment>-<workload>-sns-<event>
```

Ejemplo:

```text
dcp-diners-prod-payments-sns-payment-created
```

FIFO:

```text
dcp-diners-prod-payments-sns-payment-created.fifo
```

#### Amazon MSK

Cluster:

```text
dcp-<domain>-<environment>-platform-msk-<region>
```

Ejemplos:

```text
dcp-diners-dev-platform-msk-use1
dcp-diners-prod-platform-msk-use1
```

### Secretos y configuración

#### Secrets Manager

Se utilizará una ruta jerárquica:

```text
/dcp/<domain>/<environment>/<workload>/<resource>/<purpose>
```

Ejemplos:

```text
/dcp/diners/prod/payments/database/core
/dcp/diners/prod/payments/integration/processor-a
/dcp/diners/prod/channels/oauth/client
```

No se agregará un sufijo aleatorio manual al nombre del secreto.

Keys internas del JSON:

```text
username
password
host
port
database
clientId
clientSecret
```

#### Systems Manager Parameter Store

```text
/dcp/<domain>/<environment>/<workload>/config/<parameter>
```

Ejemplos:

```text
/dcp/diners/prod/payments/config/request-timeout
/dcp/diners/prod/payments/config/max-retries
/dcp/diners/prod/channels/config/api-base-url
```

Los valores sensibles deberán usar Secrets Manager
o `SecureString`, según la clasificación aprobada
por Ciberseguridad.

---

### Observabilidad

#### CloudWatch log groups

Log groups corporativos:

```text
/dcp/<domain>/<environment>/<workload>/<service>
```

Ejemplos:

```text
/dcp/diners/prod/payments/payment-api
/dcp/diners/prod/payments/payment-worker
```

Para servicios que generan grupos estándar AWS, se conservará el prefijo nativo:

```text
/aws/lambda/<function-name>
/aws/eks/<cluster-name>/cluster
/aws/apigateway/<api-name>
```

Terraform deberá administrar retención, cifrado y tags aun cuando el nombre sea generado por el servicio.

### Backup y continuidad

#### Backup vault

```text
dcp-<scope>-<environment>-bkpv-<purpose>-<region>
```

Ejemplos:

```text
dcp-diners-prod-bkpv-databases-use1
dcp-security-shared-bkpv-central-use1
```

#### Backup plan

```text
dcp-<scope>-<environment>-bkpp-<policy>
```

Ejemplos:

```text
dcp-diners-prod-bkpp-critical
dcp-diners-prod-bkpp-standard
```

#### Recovery points

Los IDs son administrados por AWS. Se identificarán
mediante tags del recurso origen y del plan.

---

### Data y analytics

#### S3 Data Lake

```text
dcp-data-<environment>-<layer>-s3-<region>-<unique>
```

Layers:

```text
landing
raw
trusted
curated
consumption
```

Ejemplo:

```text
dcp-data-prod-curated-s3-use1-a1b2c3
```

#### Glue Database

Los identificadores de catálogo usarán `snake_case`:

```text
dcp_<environment>_<layer>
```

Ejemplos:

```text
dcp_prod_raw
dcp_prod_curated
```

#### Glue tables

```text
<source>_<entity>
```

Ejemplos:

```text
payments_payment_transaction
billing_statement
```

#### Athena Workgroup

```text
dcp-data-<environment>-athena-<purpose>
```

Ejemplo:

```text
dcp-data-prod-athena-analytics
```

#### Redshift

```text
dcp-data-<environment>-redshift-<purpose>-<region>
```

Ejemplo:

```text
dcp-data-prod-redshift-analytics-use1
```

#### Kinesis Data Streams

```text
dcp-data-<environment>-kds-<event>
```

Ejemplo:

```text
dcp-data-prod-kds-payment-events
```

#### Firehose

```text
dcp-data-<environment>-firehose-<source>-to-<target>
```

Ejemplo:

```text
dcp-data-prod-firehose-msk-to-s3
```

#### OpenSearch

```text
dcp-<scope>-<environment>-<workload>-os-<purpose>-<region>
```

Ejemplo:

```text
dcp-diners-prod-customers-os-search-use1
```

## RDS Proxy

Patrón:

```text
dcp-<domain>-<environment>-<workload>-rdsproxy-<purpose>
```

Ejemplo:

```text
dcp-diners-prod-cards-rdsproxy-authorization
```

## EFS

Patrón:

```text
dcp-<scope>-<environment>-<workload>-efs-<purpose>-<region>
```

Ejemplo:

```text
dcp-diners-prod-documents-efs-shared-use1
```

EFS solo debe utilizarse cuando exista un requerimiento real de filesystem compartido.
No debe reemplazar almacenamiento de objetos ni persistencia de dominio.

## CloudWatch alarms

Patrón:

```text
dcp-<scope>-<environment>-<workload>-alarm-<condition>
```

Ejemplos:

```text
dcp-diners-prod-cards-alarm-aurora-cpu-high
dcp-diners-prod-payments-alarm-dlq-messages
```

## CloudWatch dashboards

Patrón:

```text
dcp-<scope>-<environment>-<workload>-dash-<purpose>
```

Ejemplo:

```text
dcp-diners-prod-cards-dash-operations
```

## Nombres generados por AWS

Cuando AWS genere el identificador físico, Terraform debe administrar como mínimo:

- Tags.
- Retención.
- Cifrado.
- Policies.
- Alarmas.
- Asociación con owner y stack.
