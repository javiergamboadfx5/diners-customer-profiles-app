# Estándares de infraestructura cloud y Terraform

## Propósito

Este directorio contiene el estándar empresarial para diseñar, nombrar, implementar, desplegar y gobernar
la Landing Zone AWS de Diners Club Perú mediante Terraform y Terragrunt.

## Principio

Cada regla debe mantenerse en un solo documento:

| Documento | Fuente normativa para |
|---|---|
| [Arquitectura Terraform](01-arquitectura-terraform.md) | Modelo multi-repo, principios, unidades de despliegue y decisiones estructurales. |
| [Topología de repositorios](02-topologia-repositorios.md) | Propósito, contenido, ownership y estructura de los repositorios `live`. |
| [Módulos Terraform](03-modulos-terraform.md) | Diseño, estructura, versionamiento, pruebas y compatibilidad de módulos reutilizables. |
| [Terragrunt y configuración live](04-terragrunt-configuracion-live.md) | Jerarquía de configuración, archivos HCL y composición de stacks. |
| [Backend, estados y dependencias](05-backend-estados-dependencias.md) | Bootstrap, S3 backend, locking, claves de estado, recuperación y publicación de outputs. |
| [Pipelines, Policy as Code y seguridad](06-pipelines-policy-seguridad.md) | Plan/apply, identidades, controles, secretos, drift y políticas automatizadas; consume el modelo transversal de [Platform Engineering](../Platform/Pipelines/02-pipeline-terraform.md). |
| [Naming AWS: principios y catálogos](07-aws-naming-principios-catalogos.md) | Patrones generales, ambientes, regiones, workloads y códigos controlados. |
| [Naming AWS: organización, IAM y networking](08-aws-naming-organizacion-iam-networking.md) | Organizations, cuentas, IAM, KMS, VPC, subnets, TGW, DNS y conectividad. |
| [Naming AWS: plataforma e integración](09-aws-naming-plataforma-integracion.md) | EKS, balanceadores, WAF, CloudFront, API Gateway, Lambda y EventBridge. |
| [Naming AWS: datos, mensajería y observabilidad](10-aws-naming-datos-mensajeria-observabilidad.md) | S3, bases de datos, Redis, SQS, SNS, MSK, secretos, backup, data y observabilidad. |
| [Tags, validaciones y Terraform](11-tags-validaciones-terraform.md) | Esquema de tags, implementación HCL, validaciones y catálogos obligatorios. |
| [Catálogo cloud versionado](catalogos-cloud.yaml) | Valores permitidos de ambientes, dominios, scopes, regiones, workloads, códigos y tags. |
| [Compatibilidad con microservicios](../Servicios/00-estandares-microservicios.md) | Namespaces, recursos Kubernetes, rutas REST, PostgreSQL y eventos lógicos se gobiernan en Servicios. |
| [Gobierno, excepciones y mantenimiento](12-gobierno-excepciones-mantenimiento.md) | Aprobación, excepciones, antipatrones, revisión y evolución del estándar. |

## Decisiones de consistencia

## Dominio y workload

El único dominio cloud permitido es:

```text
diners
```

`payments`, `billing`, `collections`, `cards`, `acquiring` y capacidades similares son `workloads`; no son
dominios cloud. Ningún recurso, cuenta, repositorio `live` o tag `Domain` puede declarar otro valor. Un cambio
de esta regla exige una nueva versión mayor del catálogo y la aprobación conjunta de Arquitectura Cloud,
Seguridad y Gobierno de Arquitectura mediante el proceso de excepción de este estándar.

## Ambientes

El catálogo activo es:

```text
dev | qa | stg | prod
```

No se permiten alias (`prd`, `sandbox`, `production`), ambientes implícitos ni valores `shared`. `shared` y
`foundation` son scopes de plataforma, no ambientes. Los cuatro ambientes se separan por cuenta, rol, backend,
estado, configuración GitOps y controles de aprobación.

## Fuente de verdad y precedencia

`catalogos-cloud.yaml` es la fuente de verdad legible por máquinas. Los documentos explican las reglas, pero no
pueden ampliar sus valores. El pipeline valida que ejemplos, módulos y configuraciones `live` usen una versión
exacta del catálogo. Ante una discrepancia, falla la validación y se corrigen ambos en el mismo pull request.

## Región en los nombres

La región se incluye cuando diferencia físicamente recursos regionales o facilita su operación multi-región.
Se omite en recursos globales, lógicos, DNS o cuando la restricción nativa del servicio exige otro patrón.

## Relación con los estándares de microservicios

Este conjunto es la fuente normativa para recursos físicos AWS, Terraform, Terragrunt, repositorios cloud,
estados y tags AWS.

Los estándares de microservicios siguen siendo la fuente normativa para:

- Nombres de servicios UX, BS, CR, GW y SP.
- Namespaces y recursos Kubernetes.
- Rutas y contratos REST.
- Nombres internos de PostgreSQL.
- Eventos y tópicos lógicos de integración.
