# Naming AWS: plataforma e integración

## Propósito

Define nombres físicos para EKS, balanceadores, WAF, CloudFront, API Gateway, Lambda, Step Functions y
EventBridge.

> Los nombres en este documento son solo ejemplos, no quiere decir que se tenga que crear un cluster o servicio
> para ese dominio/workload

## EKS y Kubernetes

### Cluster EKS

```text
dcp-<domain>-<environment>-platform-eks-<region>
```

Ejemplos:

```text
dcp-diners-dev-platform-eks-use1
dcp-diners-qa-platform-eks-use1
dcp-diners-stg-platform-eks-use1
dcp-diners-prod-platform-eks-use1
```

### Managed node groups

```text
dcp-<domain>-<environment>-ng-<purpose>
```

Ejemplos:

```text
dcp-diners-prod-ng-general
dcp-diners-prod-ng-memory
dcp-diners-prod-ng-arm
dcp-diners-prod-ng-system
```

## Balanceadores, WAF y CloudFront

### ALB y NLB

Debido al límite reducido del servicio se utilizará
el patrón compacto:

```text
dcp-<domain-code>-<env-code>-<workload-code>-<type>-<region>
```

Códigos compactos:

```text
domain: din
environment: dev | qa | stg | prod
```

Ejemplos:

```text
dcp-din-prod-pay-alb-use1
dcp-din-prod-pay-nlb-use1
```

El catálogo de códigos compactos de workload
deberá mantenerse en Terraform:

```text
payments = pay
billing = bill
collections = coll
customers = cust
acquiring = acq
merchants = merch
```

### Target groups

```text
dcp-<domain-code>-<env-code>-<workload-code>-tg-<purpose>
```

Ejemplos:

```text
dcp-din-prod-pay-tg-api
dcp-din-prod-pay-tg-worker
```

### WAF Web ACL

```text
dcp-<scope>-<environment>-<workload>-waf-<exposure>
```

Ejemplo:

```text
dcp-diners-prod-payments-waf-public
```

### CloudFront

CloudFront asigna un ID técnico. El `Name`
tag o comentario deberá seguir:

```text
dcp-<scope>-<environment>-<workload>-cf-<purpose>
```

Ejemplo:

```text
dcp-diners-prod-channels-cf-web
```

Alias DNS:

```text
www.dinersclub.com.pe
assets.dinersclub.com.pe
```

---

## API Gateway y APIs

### API Gateway

```text
dcp-<domain>-<environment>-<workload>-apigw-<exposure>
```

Ejemplos:

```text
dcp-diners-prod-payments-apigw-private
dcp-diners-prod-channels-apigw-public
```

Valores de exposición:

```text
public
private
partner
internal
```

### Stage

El stage representa el ambiente:

```text
dev
qa
stg
prod
```

La versión del API se representará en el base path:

```text
/v1
/v2
```

Ejemplo:

```text
https://api.dev.dinersclub.com.pe/payments/v1/authorizations
https://api.qa.dinersclub.com.pe/payments/v1/authorizations
https://api.stg.dinersclub.com.pe/payments/v1/authorizations
https://api.dinersclub.com.pe/payments/v1/authorizations
```

### Custom domains

Ejemplo de estructura:

```text
api.dev.dinersclub.com.pe
api.qa.dinersclub.com.pe
api.stg.dinersclub.com.pe
api.dinersclub.com.pe
partner-api.aws.dinersclub.com.pe
```

## Lambda y serverless

### Lambda functions

```text
dcp-<domain>-<environment>-<workload>-fn-<action>
```

Ejemplos:

```text
dcp-diners-prod-payments-fn-authorize
dcp-diners-prod-payments-fn-reconcile
dcp-diners-prod-billing-fn-generate-statement
```

El propósito de toda función se expresará mediante verbo y objeto:

```text
authorize-payment
process-settlement
generate-statement
```
Las versiones numéricas son administradas por
Lambda.

### Lambda layers

```text
dcp-<scope>-<environment>-layer-<purpose>
```

Ejemplos:

```text
dcp-platform-shared-layer-observability
dcp-platform-shared-layer-security
```

### Step Functions

```text
dcp-<domain>-<environment>-<workload>-sfn-<process>
```

Ejemplos:

```text
dcp-diners-prod-payments-sfn-process-payment
dcp-diners-prod-billing-sfn-close-cycle
```

### EventBridge buses

```text
dcp-<domain>-<environment>-<workload>-ebus
```

Ejemplo:

```text
dcp-diners-prod-payments-ebus
```

Bus compartido:

```text
dcp-diners-prod-integration-ebus
```

### EventBridge rules

```text
dcp-<domain>-<environment>-<workload>-erule-<event>
```

Ejemplo:

```text
dcp-diners-prod-payments-erule-payment-created
```

### EventBridge Pipes

```text
dcp-<domain>-<environment>-<workload>-pipe-<source>-to-<target>
```

Ejemplo:

```text
dcp-diners-prod-payments-pipe-ddb-to-sqs
```

## Registro de imágenes

Nexus Repository Pro es el único registro autorizado para imágenes de aplicaciones, imágenes base, charts y
evidencias. No se crean repositorios ECR para esos artefactos. ECR se limita a imágenes administradas por AWS que
un servicio AWS requiera internamente y que no sean publicadas ni promovidas por equipos de producto; cualquier
otro uso se bloquea por Policy as Code y requiere una excepción temporal.

## EKS Pod Identity

EKS Pod Identity es el mecanismo predeterminado para workloads. Antes de crear una asociación, el módulo valida:

- el add-on `eks-pod-identity-agent` instalado, disponible y con una versión aprobada;
- nodos Linux EC2 compatibles o la capacidad equivalente soportada por EKS;
- SDK AWS del runtime compatible y cadena de credenciales predeterminada, sin credenciales estáticas;
- trust policy para `pods.eks.amazonaws.com`, permiso `sts:TagSession` y rol de mínimo privilegio;
- namespace y ServiceAccount existentes en el mismo cluster de la asociación.

Nombre lógico del recurso o tag `Name`:

```text
dcp-<domain>-<environment>-<workload>-podid-<service>
```

Ejemplo:

```text
dcp-diners-prod-cards-podid-bs-cards-authorization
```

La asociación debe identificar de forma explícita:

- Cluster.
- Namespace.
- ServiceAccount.
- Rol IAM.
- Owner.
- Permisos.

IRSA se conserva solo para workloads existentes o incompatibilidades demostradas, con excepción, owner y fecha
de migración. Nunca se configuran EKS Pod Identity e IRSA simultáneamente en un ServiceAccount.

## EventBridge Scheduler

Patrón:

```text
dcp-<domain>-<environment>-<workload>-sched-<purpose>
```

Ejemplo:

```text
dcp-diners-prod-billing-sched-close-cycle
```

## Certificados ACM

El certificado se identifica principalmente por sus dominios. Cuando el servicio admita un nombre o tag:

```text
dcp-<scope>-<environment>-acm-<purpose>
```

Ejemplo:

```text
dcp-diners-prod-acm-public-api
```

Los dominios, SAN, validación y renovación deben administrarse como parte del contrato del certificado.
