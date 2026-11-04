# Lineamiento 11 v2: tags, asignación de costos y datos de facturación

Oct 14, 2026 · @arturomc

## Propósito, alcance y decisiones aplicadas

Este lineamiento define qué tags lleva cada recurso AWS, de dónde salen sus valores, cómo se validan y cómo se convierten en datos de costo. Reemplaza al documento 11 anterior. También fija la infraestructura que deja los costos de toda la organización listos para la solución FinOps in-house.

**Alcance de esta versión (Fase 1):**

- modelo de tags y catálogo;
- activación de tags de costo y Cost Categories;
- exportaciones CUR 2.0 y FOCUS 1.2 a un bucket;
- consulta con Athena;
- rol de lectura para la solución in-house.

**Fuera de alcance (Fase 2, solución in-house):** dashboards, alertas por correo de desborde de presupuesto, proyección con un modelo predictivo en Python, vistas de administrador y de lectura, exportaciones por rol, y el modelo de cobro interno (showback o chargeback).

### Decisiones aplicadas

| Tema | Decisión | Efecto en este lineamiento |
| --- | --- | --- |
| Dónde se gestiona el costo | Centralizado en la cuenta de gestión | Los stacks de billing viven en `dcp-aws-governance-live/live/billing`. No se crea `dinersclub-finops`. |
| Centros de costo | Se define formato y lista inicial | Nueva lista `cost_centers` en `catalogos-cloud.yaml`; Finanzas asigna los códigos definitivos |
| Cobro interno | Lo decide la solución in-house | La IaC entrega los datos sin aplicar showback ni chargeback |
| Reparto de la plataforma compartida | Porcentaje fijo | Porcentajes en el catálogo, aplicados en una Cost Category con método `FIXED` |
| Dashboards | Solo Athena al inicio | Base Glue + workgroup Athena; CUR 2.0 y FOCUS en un bucket que lee la solución in-house |

El destino de los datos de costo es una variable (`cost_data_account`). Hoy apunta a la cuenta de gestión. Si en la Fase 2 la solución in-house tiene su propia cuenta, el cambio es de un valor, no de estructura: Data Exports puede entregar en otra cuenta autorizada desde abril de 2026.

## Principios del etiquetado

| Principio | Regla | Justificación técnica |
| --- | --- | --- |
| Fuente única | Las claves, los valores permitidos y los tags de costo salen de `catalogos-cloud.yaml`. Ningún stack, módulo ni política escribe valores a mano. | Las Tag Policies, la validación del provider, Conftest y el CUR leen la misma lista, sin divergencias. |
| Generado, no escrito | El `terragrunt.hcl` raíz genera los `default_tags` a partir del catálogo, `accounts.yaml` y la ruta del stack. | El equipo no puede omitir un tag ni escribirlo distinto. Repository y TerraformStack salen solos. |
| Listo para costos | Todo tag con valor económico se activa como *cost allocation tag* desde el día uno. | Un tag no activado no aparece en el CUR. La activación tardía pierde historia: el backfill solo cubre hasta 12 meses. |
| Validado antes de desplegar | El plan falla si falta un tag exigido o si un valor no está en el catálogo. | Corregir en el PR cuesta menos que corregir el drift o reclasificar costos después. |
| Baja cardinalidad en costos | Solo se activan para costos los tags con pocos valores estables. | Los identificadores únicos (Name, TerraformStack) inflan el CUR y no sirven para agrupar costos. |
| Cada costo tiene dueño | Lo que no admite tags se asigna por cuenta. Lo compartido, por regla fija. | La meta es que el 100% del costo llegue a un centro de costo, aunque el recurso no tenga tags. |
| Sin datos sensibles | Los tags no llevan secretos, PAN, PII, nombres de personas ni datos de alta cardinalidad. | Los tags se replican a CUR, Cost Explorer, CloudTrail y Config, con controles de acceso más amplios. |
|  |  |  |

## Modelo de tags

Una sola tabla reemplaza las tres listas del documento anterior. Los tags se agrupan por la pregunta que responden. “Costo” indica si el tag se activa como *cost allocation tag*.

### Identidad: ¿qué es?

| Tag | Obligatorio en | Valor | Fuente | Costo | Justificación |
| --- | --- | --- | --- | --- | --- |
| `Name` | Todo recurso que lo admita | Nombre físico del recurso | Módulo (naming 07 a 10) | No | Identifica recursos con ID generado por AWS; tiene un valor por recurso. |
| `Application` | Todo recurso | Catálogo `applications` | Stack o módulo | Sí | Agrupa el costo por sistema. En fundacionales: `networking`, `security`, `governance`, `devops`, `bootstrap-backend` o `shared-services`. |
| `Service` | Recurso exclusivo de un microservicio | Nombre del servicio (estándar de microservicios) | Stack | Sí | Permite el costo unitario por servicio. Es opcional fuera de ese caso. |

### Pertenencia y costo: ¿de quién es y quién paga?

| Tag | Obligatorio en | Valor | Fuente | Costo | Justificación |
| --- | --- | --- | --- | --- | --- |
| `CostCenter` | Todo recurso | Catálogo `cost_centers` (código de Finanzas) | `accounts.yaml` por defecto; el stack puede usar otro código válido | Sí | Es la clave principal de asignación. El valor por cuenta asegura que ningún recurso quede sin centro de costo. |
| `Owner` | Todo recurso | Catálogo `owners` (equipo, nunca persona) | `accounts.yaml` o stack | Sí | Define a quién escalar un desvío de costo o un hallazgo. Un equipo sobrevive a la rotación de personas. |
| `Domain` | Recursos de workload | `diners` | `domain.hcl` | No | Valor único: no aporta como dimensión de costo, pero se conserva para naming y políticas. |
| `Workload` | Recursos de workload | Catálogo `workloads` | Ruta del stack (`workloads/<workload>`) | Sí | Separa el costo de payments, cards, acquiring y demás dentro de la misma cuenta. |

### Contexto: ¿dónde y para qué?

| Tag | Obligatorio en | Valor | Fuente | Costo | Justificación |
| --- | --- | --- | --- | --- | --- |
| `Environment` | Todo recurso | `dev`, `qa`, `stg`, `prod` | `accounts.yaml` | Sí | Separa el gasto productivo del no productivo. La infraestructura fundacional usa `prod`, porque sostiene producción. |
| `Scope` | Todo recurso | `diners`, `data`, `platform`, `security`, `networking` | `accounts.yaml` | Sí | Distingue plataforma, seguridad y red de los dominios. Es la entrada del reparto de la plataforma compartida. |

### Seguridad y cumplimiento

| Tag | Obligatorio en | Valor | Fuente | Costo | Justificación |
| --- | --- | --- | --- | --- | --- |
| `DataClassification` | Todo recurso | `public`, `internal`, `confidential`, `restricted`, `pci` | Stack (por defecto, el de la cuenta) | No | Lo consumen controles y auditoría, no el análisis de costos. |
| `Compliance` | Todo recurso | `general`, `pci-dss`, `lpdp` | `accounts.yaml` o stack | Sí | Mide cuánto cuesta el alcance PCI (CDE). |

### Trazabilidad y automatización

| Tag | Obligatorio en | Valor | Fuente | Costo | Justificación |
| --- | --- | --- | --- | --- | --- |
| `ManagedBy` | Todo recurso | `terraform`, `control-tower`, `aws-managed` | `terragrunt.hcl` raíz | No | Distingue lo creado por IaC de lo creado por servicios de AWS al analizar drift. |
| `Repository` | Todo recurso | Nombre del repositorio live | `terragrunt.hcl` raíz | No | Lleva del recurso al código que lo define. |
| `TerraformStack` | Todo recurso | Ruta del stack, por ejemplo `diners/prod/us-east-1/platform/eks` | `terragrunt.hcl` raíz | No | Localiza el estado exacto. Tiene alta cardinalidad. |

### Condicionales (solo cuando aplica)

| Tag | Cuándo | Valor | Costo | Justificación |
| --- | --- | --- | --- | --- |
| `Criticality` | Recursos de workload productivos | `tier-0` a `tier-3` | No | Prioriza respaldo y respuesta ante incidentes. |
| `BackupPolicy` | Recursos con respaldo | Nombre del plan (`critical`, `standard`) | No | Lo consumen las Backup Policies de Organizations. |
| `ExpiryDate` | Recursos temporales | Fecha `AAAA-MM-DD` | No | Permite detectar y limpiar recursos vencidos. |
| `ExceptionId` | Recurso cubierto por una excepción | `exc-cloud-AAAA-NNNN` | No | Vincula el recurso con su excepción vigente (documento 12). |

También se activa para costos `aws:createdBy`, el tag que genera AWS. Sirve para rastrear quién creó lo que quedó sin tags.

**Total:** 13 tags obligatorios en recursos de workload y 11 en fundacionales, donde Domain y Workload no aplican; Service es condicional y 9 tags activados para costos: Application, Service, CostCenter, Owner, Workload, Environment, Scope, Compliance y `aws:createdBy`.

## Reglas de formato y valores

| Regla | Detalle | Justificación técnica |
| --- | --- | --- |
| Claves en PascalCase | `CostCenter`, no `costcenter` ni `cost-center` | Las claves distinguen mayúsculas. Dos variantes generan dos columnas distintas en el CUR y parten el costo. |
| Valores en minúsculas kebab-case | `payment-api`, `infraestructura-cloud` | Agrupar no depende de cómo se escribió el valor. Excepciones: códigos de Finanzas (numéricos), fechas y `ExceptionId`. |
| Caracteres permitidos | Letras, números, espacios y `+ - = . _ : / @`; máximo 128 caracteres en la clave y 256 en el valor | Límites de AWS. Un valor inválido hace fallar el apply en algunos servicios. |
| Prefijo `aws:` reservado | Nunca se usa en tags propios | AWS lo reserva para tags que genera el sistema. |
| Sin valores vacíos ni comodines | Prohibidos `""`, `unknown`, `n/a`, `tbd`, `temp`, `shared`, `default` | Un comodín equivale a no tener tag y oculta el costo sin asignar. |
| Solo valores del catálogo | Environment, Scope, CostCenter, Owner, Application, Workload, DataClassification, Compliance y ManagedBy | Las Tag Policies y Conftest rechazan cualquier otro valor. |
| `shared` no es ambiente | Puede usarse como código de naming (`dcp-network-shared-tgw-use1`), nunca como `Environment` | El documento 07 lo prohíbe como ambiente y el 08 lo usa en esa posición del nombre; queda como código de naming y el 07 debe registrarlo así. |
| Scope de red | El valor del tag es `networking`; `network` queda como código corto de naming | Documenta la diferencia en lugar de dejarla implícita. |

Un cambio de valor en un recurso existente es un cambio controlado: se hace por PR al catálogo y al stack. Los costos ya facturados conservan el valor anterior; la solución in-house resuelve la equivalencia con el historial del catálogo.

## Catálogo de valores

`catalogos-cloud.yaml` incorpora cuatro listas. El pipeline valida sus relaciones: toda aplicación pertenece a un workload, a un owner y a un centro de costo existentes.

### Centros de costo: formato

| Campo | Formato | Ejemplo | Uso |
| --- | --- | --- | --- |
| `code` | `^[0-9]{6}$`, código contable de Finanzas | `123456` | Valor del tag `CostCenter`. Numérico y estable, igual al sistema contable, para que la solución in-house concilie sin traducir. |
| `id` | kebab-case | `plataforma-cloud` | Referencia legible dentro del catálogo |
| `name` | Texto libre | Plataforma Cloud | Descripción para reportes |
| `owner` | Catálogo `owners` | `infraestructura-cloud` | Responsable del presupuesto |
| `kind` | `platform` o `business` | `platform` | Indica si el centro recibe o aporta el reparto de la plataforma compartida |
| `shared_platform_pct` | Número de 0 a 100, solo en `business` | `30` | Porcentaje fijo del costo de plataforma que absorbe. La suma debe ser 100. |
| `monthly_budget_usd` | Número | `15000` | Dato para la solución in-house (alertas de desborde en la Fase 2) |
| `status` | `active` o `retired` | `active` | Un centro retirado no puede usarse en recursos nuevos |

El formato de 6 dígitos sigue el ejemplo del documento 04 (`cost_center = "123456"`). Si el código contable real es distinto, se ajusta solo el patrón.

### Centros de costo: lista inicial propuesta

Los códigos los asigna Finanzas. La agrupación sigue los scopes y workloads del catálogo, para que el mapeo sea automático.

| id | Nombre | kind | Cubre | Código |
| --- | --- | --- | --- | --- |
| `plataforma-cloud` | Plataforma Cloud | platform | governance, networking, devops, bootstrap-backend, shared-services | Por asignar |
| `ciberseguridad` | Ciberseguridad | platform | audit, log-archive, security-tooling | Por asignar |
| `datos-analitica` | Datos y Analítica | business | data-qa, data-lake-prod, analytics-prod | Por asignar |
| `diners-``a``d``q``u``i``r``e``n``c``i``a` | Adquirencia | business | payments, acquiring, merchants | Por asignar |
| `diners-``e``m``i``s``i``o``nes` | Emisiones | business | cards, customers, fraud | Por asignar |
| `diners-facturacion` | Facturación y Cobranzas | business | billing, collections | Por asignar |
| `diners-canales` | Canales e Integración | business | channels, integration, platform del dominio diners | Por asignar |

Los dos centros `platform` forman el costo compartido que se reparte por porcentaje fijo entre los cinco centros `business`.

### Owners, aplicaciones y cuentas

```yaml
owners:                        # equipos o listas de distribución, nunca personas
  - id: infraestructura-cloud
    contact: infra-cloud@dinersclub.com.pe
  - id: equipo-payments
    contact: payments@dinersclub.com.pe

applications:
  - id: payment-api
    workload: payments
    owner: equipo-payments
    cost_center: diners-pagos     # se resuelve al code

cost_centers:
  - id: plataforma-cloud
    code: "000000"                # Finanzas asigna el definitivo
    name: Plataforma Cloud
    owner: infraestructura-cloud
    kind: platform
    status: active
  - id: diners-pagos
    code: "000000"
    name: Pagos y Adquirencia
    owner: equipo-payments
    kind: business
    shared_platform_pct: 0        # Finanzas define; suma de business = 100
    monthly_budget_usd: 0
    status: active
```

`accounts.yaml` agrega a cada cuenta `cost_center`, `owner`, `environment`, `scope` y `compliance`. Esos valores son el default de los tags y la base de las Cost Categories por cuenta.

```yaml
- name: dinersclub-diners-prod
  account_id: "222222222222"
  environment: prod
  scope: diners
  cost_center: diners-canales    # default; cada workload lo sobrescribe
  owner: equipo-plataforma-diners
  compliance: pci-dss
```

## Asignación de costos

Un costo llega a su centro por una de cuatro rutas, en este orden de prioridad:

1. tag `CostCenter` del recurso;
2. split cost allocation de EKS por pod;
3. reparto fijo de la plataforma compartida;
4. centro de costo por defecto de la cuenta.

Todo se configura en la cuenta de gestión, la única que ve el costo consolidado.

### Activación de tags de costo

- Los 9 tags marcados en el modelo se activan con `aws_ce_cost_allocation_tag`, generados desde el catálogo.
- **Backfill de 12 meses** al activar por primera vez.
- **Justificación:** AWS solo incluye en el CUR y en Cost Explorer los tags activados por el payer. Un tag tarda unas 24 horas desde que se usa hasta que puede activarse, y la activación no es retroactiva sin backfill. Por eso se activa en la Fase 1b, antes de desplegar workloads.

### Cost Category `dcp-cost-center`

Una Cost Category traduce las cuatro rutas a un único valor: el `id` del centro de costo.

| Orden | Regla | Resultado |
| --- | --- | --- |
| 1 | Tag `CostCenter` con valor del catálogo | El centro del tag |
| 2 | Cuentas `kind: platform` en `accounts.yaml` | `plataforma-compartida` |
| 3 | Resto de cuentas | `cost_center` de la cuenta en `accounts.yaml` |
| — | Sin coincidencia | `sin-asignar`, que es el indicador de calidad |

Las reglas se generan desde los catálogos. Una cuenta o centro nuevo se agrega por PR al catálogo.

### Reparto fijo de la plataforma compartida

- Una *split charge rule* con método `FIXED` toma el valor `plataforma-compartida` como origen y lo reparte entre los centros `business` según `shared_platform_pct`.
- CI valida que los porcentajes sumen 100. La API acepta hasta 500 destinos por regla.
- **Lo que debe saber la solución in-house:** el reparto de una *split charge rule* se ve en Cost Explorer y Budgets, pero no reescribe las líneas del CUR ni de FOCUS. En los archivos exportados, el costo de plataforma aparece con el valor `plataforma-compartida`. La solución in-house aplica los mismos porcentajes, que lee del catálogo publicado. Este comportamiento debe confirmarse con la primera exportación.

### Clústeres EKS compartidos

- Se habilita *split cost allocation data* para EKS en las preferencias de Cost Management y se exporta con `INCLUDE_SPLIT_COST_ALLOCATION_DATA`.
- El costo de cada nodo se reparte entre los pods por CPU y memoria, y los labels del pod se importan como tags de costo (hasta 50 por pod).
- Labels obligatorios en los pods, definidos en el estándar de microservicios: `dinersclub.com.pe/cost-center`, `dinersclub.com.pe/workload` y `dinersclub.com.pe/application`, con valores del mismo catálogo. Kyverno los exige al admitir pods.
- **Justificación:** sin este reparto, un clúster compartido aparece entero en el centro de la cuenta y no se sabe cuánto consume cada workload.

### Recursos que no admiten tags

Se registran en el catálogo de recursos no etiquetables, como ya exige este lineamiento, y heredan el centro de su cuenta (regla 3). AWS Config compara diariamente ese inventario.

### Indicador de calidad

Costo mensual en `sin-asignar` sobre el costo total. Meta: 0% en workloads y menos de 2% en la organización. Se calcula con Athena desde la Fase 1.

## Datos de facturación para la solución in-house

La IaC deja en un bucket dos exportaciones estándar y una copia del catálogo. La solución in-house lee los tres con un rol de solo lectura. Athena permite consultar esos mismos datos desde el primer día, sin esperar la Fase 2.

&#91;embedded content: datos de facturación · cuenta de gestión → bucket → solución in-house\]

### Exportaciones

| Export | Tabla | Configuración | Para qué | Justificación |
| --- | --- | --- | --- | --- |
| `dcp-cur2-hourly` | `COST_AND_USAGE_REPORT` (CUR 2.0) | `TIME_GRANULARITY = HOURLY`, `INCLUDE_RESOURCES = TRUE`, `INCLUDE_SPLIT_COST_ALLOCATION_DATA = TRUE`; Parquet, `OVERWRITE_REPORT` | Detalle por recurso, tags, Cost Category y reparto por pod | Es la única fuente con ID de recurso y split de EKS. Lo horario permite detectar picos y entrenar el modelo de proyección. |
| `dcp-focus12-daily` | `FOCUS_1_2_AWS` (FOCUS 1.2 con columnas AWS) | `TIME_GRANULARITY = DAILY`; Parquet, `OVERWRITE_REPORT` | Esquema estándar y portable para la solución in-house | FOCUS es una especificación abierta multicloud, así que la misma lógica servirá para los exports FOCUS de Azure. Lo diario basta para presupuestos y reduce volumen. |

Ambas se crean en la cuenta de gestión, que es la única que exporta el costo de toda la organización, y Data Exports las refresca hasta una vez al día. Las exportaciones de recomendaciones de optimización y de carbono quedan como flags apagados (`enabled: false`) para activarlas después sin cambios de estructura.

### Bucket

| Control | Valor |
| --- | --- |
| Nombre | `dcp-platform-prod-finops-s3-cost-exports-use1-<unique>` (patrón S3 del documento 10; workload nuevo `finops` en el catálogo) |
| Cifrado | SSE-KMS con llave dedicada `alias/dcp/platform/prod/finops/cost-data`. La key policy permite cifrar al servicio de Data Exports y descifrar al rol de lectura. |
| Acceso de escritura | Bucket policy solo para los principales de servicio de Data Exports, con condiciones `aws:SourceAccount` y `aws:SourceArn`. La IaC la declara completa, porque la consola reemplaza la policy existente al configurar un export. |
| Acceso público | Block Public Access en las cuatro opciones; Object Ownership `BucketOwnerEnforced` |
| Versionado y retención | Versionado activo. Lifecycle a Glacier Instant Retrieval a los 13 meses y expiración según `cost_data_retention_months` del catálogo, propuesta 84 meses, a validar con Cumplimiento. |
| Auditoría | Eventos de datos de CloudTrail en el bucket hacia Log Archive |
| Clasificación | `DataClassification = confidential`: el costo revela contratos, descuentos y volumen de negocio |

### Contrato de datos (lo que la solución in-house puede asumir)

| Prefijo | Contenido | Partición |
| --- | --- | --- |
| `cur2/dcp-cur2-hourly/data/` | CUR 2.0 en Parquet | `BILLING_PERIOD=AAAA-MM` |
| `focus/dcp-focus12-daily/data/` | FOCUS 1.2 en Parquet | `BILLING_PERIOD=AAAA-MM` |
| `catalog/v<versión>/` | `cost_centers.json`, `applications.json`, `owners.json`, `accounts.json`, con códigos, porcentajes fijos y presupuestos | Versión del catálogo |
| `catalog/latest.json` | Puntero a la versión vigente | — |

Reglas del contrato:

- El mes en curso se reescribe en cada refresco; un mes cerrado puede corregirse hasta el cierre de la factura. La solución in-house reprocesa la partición completa, no agrega filas.
- En CUR 2.0, los tags llegan en la columna `resource_tags` y la Cost Category en `cost_category`. En FOCUS llegan en `Tags`. La solución normaliza las claves contra el catálogo.
- El catálogo se publica en cada merge a `main` que lo modifique, así que los porcentajes fijos y presupuestos que usa la Fase 2 son exactamente los aprobados por PR.
- Un cambio incompatible de prefijos o columnas exige una nueva versión del contrato, que se publica junto a la anterior.

### Athena desde el día uno

- Base Glue `dcp_prod_finops` con tablas `cur2` y `focus12` y proyección de particiones, sin crawlers que mantener.
- Workgroup `dcp-platform-prod-athena-finops` con resultados cifrados en un prefijo propio, configuración forzada y límite de bytes escaneados por consulta.
- Vistas iniciales: costo por centro y mes, `sin-asignar` y cobertura de tags, top 20 recursos por costo, y costo de plataforma compartida con el reparto fijo aplicado desde `catalog/`.

### Accesos

| Identidad | Permisos | Uso |
| --- | --- | --- |
| `dcp-platform-prod-finops-role-cost-data-reader` | `s3:GetObject` y `s3:ListBucket` en el bucket, `kms:Decrypt` de la llave, Athena y Glue de solo lectura sobre su base y workgroup | Solución in-house. El trust se toma de la variable `cost_data_consumers` (cuenta y rol). |
| Permission set `DCP-FinOps-Analyst` | Athena en el workgroup y lectura del bucket | Analistas FinOps y Finanzas durante la Fase 1 |
| Pipeline de IaC (`TerraformApplyRole` de gestión) | Escritura en `catalog/` | Publicar el catálogo |

Nadie más recibe acceso a la cuenta de gestión por temas de costo.

## Enforcement y propagación

Cinco capas, ordenadas de la más temprana a la más tardía. Cada una cubre lo que la anterior no ve.

| Capa | Mecanismo | Qué detiene | Por qué no basta sola |
| --- | --- | --- | --- |
| 1 · Generación | El `terragrunt.hcl` raíz genera `default_tags` desde el catálogo y `accounts.yaml` | Omisiones y errores de escritura en los stacks | No cubre recursos sin soporte de `default_tags` ni los creados por controladores |
| 2 · Provider | `tag_policy_compliance = "error"` en el provider de AWS (6.22 o superior; el estándar usa 6.47) | Un plan con recursos sin los tags exigidos por la Tag Policy efectiva | Valida la presencia del tag, no la coherencia con el catálogo |
| 3 · CI | Conftest sobre el plan: valores del catálogo y coherencia Application, Workload y CostCenter | Valores inválidos o combinaciones incoherentes | Solo ve lo que pasa por el pipeline |
| 4 · Organización | Tag Policies generadas desde el catálogo, con valores permitidos y `report_required_tag_for` por tipo de recurso, adjuntas a las OUs | Valores fuera de catálogo en servicios que lo soportan, incluso fuera de Terraform | No obliga a etiquetar en todos los servicios |
| 5 · Detección | Regla `required-tags` de AWS Config e indicador `sin-asignar` en Athena | Lo que llegó sin tags por cualquier vía | Detecta después del hecho |

No se usan SCP que nieguen la creación de recursos sin tags. AWS crea recursos por su cuenta (ENIs, snapshots, recursos de servicios administrados), y una SCP así bloquearía operaciones legítimas. La exigencia preventiva queda en las capas 2 y 4.

Los roles `TerraformPlanRole` y `TerraformApplyRole` necesitan el permiso `tag:ListRequiredTags` para que la capa 2 funcione. El account vending lo incluye.

### Propagación de tags

| Caso | Regla | Motivo |
| --- | --- | --- |
| Auto Scaling Groups | `propagate_at_launch = true` en cada tag | Las instancias que lanza el ASG no heredan `default_tags` |
| Launch templates (incluidos los de node groups de EKS) | `tag_specifications` para `instance`, `volume` y `network-interface` | El cómputo y sus volúmenes son la mayor parte del costo de EKS |
| EKS managed node groups | Tags en el launch template, no solo en el recurso node group | Los tags del node group no llegan a las instancias |
| Recursos creados desde Kubernetes | Tags por defecto en AWS Load Balancer Controller (`defaultTags`) y en el driver EBS CSI (`extraVolumeTags`) | ALB, NLB y volúmenes nacen fuera de Terraform |
| Snapshots y respaldos | `copy_tags_to_snapshot` en RDS y Aurora; tags en las reglas de AWS Backup | Los respaldos generan costo continuo |
| Recursos compartidos por RAM | Cada cuenta etiqueta lo que crea sobre la subnet compartida | Los tags de un recurso compartido no son visibles en la cuenta participante |

El módulo de cada uno de estos recursos aplica la regla por defecto. CI la verifica (sección de validaciones).

## Implementación IaC

Se despliega en la Fase 1b, junto con el gobierno base y antes de cualquier workload. Así los tags de costo están activos cuando aparece el primer recurso etiquetado. Cada stack es una unidad de estado y pipeline, y todo se alimenta del catálogo, según el pilar de parametrización.

### Estructura

```
dcp-aws-governance-live/live/billing/
├── cost-allocation-tags/      # activa los 9 tags y el backfill
├── cost-categories/           # dcp-cost-center + split FIXED
├── cost-data-bucket/          # bucket, KMS, bucket policy, lifecycle
├── data-exports/              # CUR 2.0 y FOCUS 1.2 (depende del bucket)
├── cost-data-catalog/         # Glue, workgroup Athena, vistas
├── cost-data-access/          # rol de lectura in-house
└── catalog-publication/       # publica catalog/v<versión>/*.json

dcp-terraform-modules/modules/finops/
├── cost-allocation-tags/
├── cost-category/
├── cost-data-bucket/
├── data-export/
├── athena-cost-catalog/
└── cost-data-reader-role/
```

```yaml
# capabilities.yaml
billing:
  cost_allocation_tags: { enabled: true }
  cost_categories:      { enabled: true }
  exports:
    cur2:                 { enabled: true }
    focus12:              { enabled: true }
    cost_recommendations: { enabled: false }
    carbon:               { enabled: false }
  athena:               { enabled: true }
  eks_split_allocation: { enabled: false }   # true al desplegar el primer EKS (Fase 3)
cost_data_account: management                 # destino de los datos; ver Propósito
cost_data_consumers: []                       # cuenta y rol de la solución in-house (Fase 2)
```

### Provider con tags y validación (todas las cuentas)

```hcl
generate "provider" {
  path      = "provider.generated.tf"
  if_exists = "overwrite"
  contents  = <<EOF
provider "aws" {
  region                = "${local.aws_region}"
  tag_policy_compliance = "error"
  assume_role { role_arn = "${local.terraform_role_arn}" }
  default_tags { tags = ${jsonencode(local.mandatory_tags)} }
}
EOF
}
```

`local.mandatory_tags` combina el catálogo, `accounts.yaml` y la ruta del stack. No pone `Domain` ni `Workload` en fundacionales.

### Activación de tags y Cost Category

```hcl
resource "aws_ce_cost_allocation_tag" "this" {
  for_each = toset(var.cost_allocation_tag_keys)   # desde el catálogo
  tag_key  = each.value
  status   = "Active"
}

resource "aws_ce_cost_category" "cost_center" {
  name          = "dcp-cost-center"
  rule_version  = "CostCategoryExpression.v1"
  default_value = "sin-asignar"

  dynamic "rule" {                       # 1. tag CostCenter
    for_each = var.cost_centers
    content {
      value = rule.value.id
      rule {
        tags {
          key           = "CostCenter"
          values        = [rule.value.code]
          match_options = ["EQUALS"]
        }
      }
    }
  }

  dynamic "rule" {                       # 2 y 3. por cuenta
    for_each = var.account_cost_center_map # id -> [account_ids]
    content {
      value = rule.key
      rule {
        dimension {
          key           = "LINKED_ACCOUNT"
          values        = rule.value
          match_options = ["EQUALS"]
        }
      }
    }
  }

  split_charge_rule {                    # reparto fijo de plataforma
    source  = "plataforma-compartida"
    targets = [for c in var.business_cost_centers : c.id]
    method  = "FIXED"
    parameter {
      type   = "ALLOCATION_PERCENTAGES"
      values = [for c in var.business_cost_centers : tostring(c.shared_platform_pct)]
    }
  }
}
```

Las reglas se evalúan en orden: el tag del recurso gana sobre la cuenta. Los centros `kind: platform` y las cuentas de plataforma se resuelven siempre al valor `plataforma-compartida`, para que todo su costo entre al reparto fijo, esté etiquetado o no. El módulo hace esa traducción desde el catálogo.

### Exportación CUR 2.0

```hcl
resource "aws_bcmdataexports_export" "cur2" {
  export {
    name = "dcp-cur2-hourly"
    data_query {
      query_statement = local.cur2_query   # columnas explícitas, versionadas en el módulo
      table_configurations = {
        COST_AND_USAGE_REPORT = {
          TIME_GRANULARITY                      = "HOURLY"
          INCLUDE_RESOURCES                     = "TRUE"
          INCLUDE_SPLIT_COST_ALLOCATION_DATA    = "TRUE"
          INCLUDE_MANUAL_DISCOUNT_COMPATIBILITY = "FALSE"
        }
      }
    }
    destination_configurations {
      s3_destination {
        s3_bucket = var.cost_data_bucket_name
        s3_prefix = "cur2"
        s3_region = var.aws_region
        s3_output_configurations {
          format      = "PARQUET"
          compression = "PARQUET"
          output_type = "CUSTOM"
          overwrite   = "OVERWRITE_REPORT"
        }
      }
    }
    refresh_cadence { frequency = "SYNCHRONOUS" }
  }
}
```

FOCUS usa el mismo módulo con `FOCUS_1_2_AWS`, `TIME_GRANULARITY = DAILY` y el prefijo `focus`.

### Bucket policy de entrega

```hcl
data "aws_iam_policy_document" "exports" {
  statement {
    sid       = "AllowDataExportsDelivery"
    actions   = ["s3:PutObject", "s3:GetBucketPolicy"]
    resources = [module.bucket.arn, "${module.bucket.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["billingreports.amazonaws.com", "bcm-data-exports.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:SourceArn"
      values = [
        "arn:aws:cur:us-east-1:${var.management_account_id}:definition/*",
        "arn:aws:bcm-data-exports:us-east-1:${var.management_account_id}:export/*",
      ]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.management_account_id]
    }
  }
}
```

La policy se valida contra la guía vigente de Data Exports en la primera entrega. La key policy de la llave KMS otorga `kms:GenerateDataKey*` a los mismos principales, con las mismas condiciones.

### Publicación del catálogo

```hcl
resource "aws_s3_object" "catalog" {
  for_each     = local.catalog_files   # cost_centers, applications, owners, accounts
  bucket       = var.cost_data_bucket_name
  key          = "catalog/v${var.catalog_version}/${each.key}.json"
  content      = jsonencode(each.value)
  content_type = "application/json"
}
```

### Split cost allocation de EKS

Es una preferencia de Cost Management de la cuenta de gestión. Si la versión aprobada del provider no tiene un recurso para ella, el stack la aplica con la API de AWS desde el pipeline (paso idempotente de solo activación). Queda registrada como excepción temporal hasta que exista soporte declarativo.

## Validaciones, criterios de aceptación y cambios

### Validaciones en CI

| Regla | Nivel | Herramienta |
| --- | --- | --- |
| Recurso sin alguno de los tags obligatorios | Bloquea | Provider (`tag_policy_compliance`) y Conftest |
| Valor de Environment, Scope, CostCenter, Owner, Application, Workload, DataClassification, Compliance o ManagedBy fuera del catálogo | Bloquea | Conftest |
| Application cuyo workload, owner o centro de costo no coincide con el catálogo | Bloquea | Conftest |
| Clave fuera de PascalCase o valor con comodín (`unknown`, `n/a`, `tbd`, `shared`, vacío) | Bloquea | Conftest y TFLint |
| `Domain` o `Workload` en un recurso fundacional | Bloquea | Conftest |
| Provider de AWS sin `tag_policy_compliance = "error"` o con versión menor a 6.22 | Bloquea | Conftest |
| Cuenta en `accounts.yaml` sin `cost_center`, `owner`, `environment`, `scope` o `compliance` | Bloquea | Validación del catálogo |
| Porcentajes `shared_platform_pct` de los centros `business` que no suman 100 | Bloquea | Validación del catálogo |
| Centro de costo con código fuera de `^[0-9]{6}$` o `status: retired` en un recurso nuevo | Bloquea | Conftest |
| ASG o launch template sin propagación de tags | Avisa y bloquea en fecha | Conftest |
| Recursos de billing declarados fuera de `dcp-aws-governance-live/live/billing` | Bloquea | Conftest |
| Tag de costo del catálogo sin activar en la cuenta de gestión | Avisa | Drift del stack `cost-allocation-tags` |

### Criterios de aceptación de la Fase 1

- [ ] Los 9 tags de costo están activos con backfill y aparecen en Cost Explorer.
- [ ] La Cost Category `dcp-cost-center` clasifica todas las cuentas; el reparto fijo suma 100%.
- [ ] CUR 2.0 y FOCUS 1.2 entregan Parquet en el bucket, con particiones `BILLING_PERIOD`.
- [ ] Athena consulta ambas tablas y las vistas de costo por centro y de `sin-asignar`.
- [ ] El catálogo publicado en `catalog/` coincide con el de `main`.
- [ ] El rol de lectura funciona con un consumidor de prueba sin otros permisos.
- [ ] Un plan con un recurso sin tags falla en el provider y en Conftest.
- [ ] Finanzas aprobó los códigos y porcentajes de la lista inicial de centros de costo.

### Cambios respecto a la versión anterior

Es un cambio *major* según el documento 12: agrega tags obligatorios a recursos existentes y obliga a migrar `default_tags`. La migración agrega tags sin reemplazar recursos, porque cambiar tags no fuerza recreación.

| Cambio | Antes | Ahora | Justificación |
| --- | --- | --- | --- |
| Listado de tags | Tres enumeraciones distintas: lista de 11 tags, tabla de 13 (Domain y Workload solo en workload) y tabla de clasificación que pone ambos como principales sin condición; además, los valores controlados aparecen dos veces y solo una copia incluye `ManagedBy` | Una tabla por categoría con columna de costo | Una sola fuente para CI, Tag Policies y CUR |
| Domain y Workload | Condición ambigua: la tabla de 13 tags los limita a workload, pero la lista de 11 los omite y la tabla de clasificación los exige sin condición | Solo en workload; prohibidos en fundacionales | Evita valores inventados que distorsionan el costo |
| CostCenter, Owner, Application | Texto libre | Catálogo con relaciones validadas | Sin catálogo no hay agrupación confiable |
| Tags de costo | No se activaban | 9 activos con backfill desde la Fase 1b | Sin activación, los tags no llegan al CUR |
| Generación de tags | No se definía cómo llegan los tags al stack: el local `mandatory_common_tags` usa `var.owner`, `var.cost_center`, `var.application`, `var.repository` y `var.terraform_stack`, pero ningún documento dice de dónde salen; `domain.hcl`, `env.hcl`, `account.hcl` y `region.hcl` solo aportan dominio, ambiente, cuenta y región, y no hay `generate` con `default_tags` | `terragrunt.hcl` raíz genera `default_tags` desde el catálogo y `accounts.yaml` | Ningún stack depende de pasar tags a mano |
| Validación en el provider | No existía | `tag_policy_compliance = "error"` | Falla en el plan, no después |
| Asignación de costos | No definida | Tag, split EKS, reparto fijo y cuenta | 100% del costo con dueño |
| Datos de facturación | No existían | CUR 2.0 y FOCUS 1.2 en bucket, Athena y contrato para la solución in-house | Base de la Fase 2 sin depender de la consola |
| `shared` y `network` | Definidos de forma contradictoria: el 07 prohíbe `shared` como ambiente y su catálogo de scope dice `networking`; el 08 usa `shared` en la posición de ambiente (`dcp-network-shared`, `dcp-platform-shared-cicd-role-terraform-apply`) y `network` como scope; el 11 rechaza `shared` como valor de tag | Válidos solo como códigos cortos en nombres físicos, nunca como valor de tag: `Environment` es dev, qa, stg o prod y el `Scope` de red es `networking` | Alinea el 07 (Naming: principios y catálogos) con el 08 (Naming: organización, IAM y networking) sin renombrar recursos existentes; el 07 debe registrar `shared` como código de naming para recursos sin ambiente |

Ownership: Arquitectura Cloud es owner del lineamiento. FinOps y Finanzas son co-owners del catálogo de centros de costo y aprueban los porcentajes de reparto. Infraestructura Cloud es owner de los stacks de billing.

Fuentes: [FOCUS 1.2 con columnas AWS](https://docs.aws.amazon.com/cur/latest/userguide/table-dictionary-focus-1-2-aws.md) · [Crear una exportación estándar](https://docs.aws.amazon.com/cur/latest/userguide/dataexports-create-standard.html) · [Data Exports con entrega entre cuentas](https://aws.amazon.com/de/about-aws/whats-new/2026/03/aws-data-exports-cross-account-delivery-cost/) · [Split charge rules de Cost Categories](https://docs.aws.amazon.com/aws-cost-management/latest/APIReference/API_CostCategorySplitChargeRule.html) · [Split cost allocation de EKS con labels](https://aws.amazon.com/about-aws/whats-new/2025/10/split-cost-allocation-data-amazon-eks-kubernetes-labels) · [Tags exigidos en IaC con Tag Policies](https://docs.aws.amazon.com/organizations/latest/userguide/enforce-required-tag-keys-iac.html) · [Terraform: tag policy compliance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/guides/tag-policy-compliance)
