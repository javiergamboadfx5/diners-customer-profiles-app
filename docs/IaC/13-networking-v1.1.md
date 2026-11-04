# L13 — Estándar de direccionamiento IP, segmentación, conectividad híbrida y networking AWS

Propuesta consolidada para los repositorios Terraform/Terragrunt de Diners Club Perú · Versión 1.1 · Estado: decisiones de base aprobadas el 28/10/2026

> **Cambios en v1.1 (2026-10-28):**
>
> - Catálogo de entornos: `dev`, `qa`, `stg`, `prod`. Se descarta `cert`.
> - Una sola cuenta de networking con Shared VPC por tier (prod y nonprod) y subredes por cuenta vía RAM.
> - EKS por fases: F1 Auto Mode + clúster estándar con nodos híbridos (Cilium) para servicios legados con conexión al AS400; F2 migración a un solo clúster Auto Mode; F3 clúster estándar con Cilium e Istio. Las decisiones de Cilium, service mesh y Cilium Egress Gateway aplican a la fase 3 (sección 9.4).
> - Ingress HTTP(S) alineado a L16: borde intercambiable, API Gateway REST y ALB interno con mTLS. Ingress no HTTP de partners: VPC de ingress central.
> - Reglas de pipeline por niveles: bloquea, avisa con fecha o revisión manual.
> - Pendientes: egress con IP de origen fija y el inventario de la matriz de conectividad (sección 15).

## 1. Objetivo

Establecer las reglas obligatorias para diseñar, implementar, operar y auditar la red AWS de la organización, incluyendo:

- Asignación y reserva de rangos IP mediante IPAM.
- Diseño de VPC y segmentación por subnets y zonas de disponibilidad.
- Separación de redes públicas, workloads, datos, endpoints y conectividad.
- Conectividad entre cuentas, VPC, on-premises y plataformas externas autorizadas.
- Transit Gateway, VPN, Direct Connect, DNS, egress e inspección de tráfico.
- Networking de Amazon EKS, incluyendo asignación de IP de Pods y capacidad durante upgrades.
- Controles de seguridad de red y políticas automatizadas.
- Responsabilidades de los repositorios Terraform/Terragrunt y trazabilidad de cambios.

## 2. Alcance y principios obligatorios

El lineamiento aplica a todas las cuentas, regiones, entornos y cargas de trabajo AWS administradas por Terraform/Terragrunt.

| Principio | Regla |
| --- | --- |
| IPAM centralizado | Los CIDR deben proceder de un esquema de direccionamiento aprobado. |
| Sin solapamientos | No se permiten rangos superpuestos entre redes que requieran conectividad, salvo una excepción arquitectónica formal. |
| Ownership centralizado | La cuenta/repositorio de Networking administra los componentes de conectividad compartida que le hayan sido asignados. |
| Segmentación por riesgo | Las subnets se separan según confianza, exposición, routing, seguridad y capacidad, no simplemente por producto AWS. |
| Conectividad explícita | Todo flujo entre entornos, cuentas y redes externas debe estar autorizado y documentado. |
| Mínima exposición | Las cargas de trabajo privadas no deben exponerse directamente a Internet por defecto. |
| Infraestructura como código | Los recursos de red se administran mediante Terraform/Terragrunt y pipelines aprobados. |
| Sin dependencias implícitas | Las cargas de trabajo consumen interfaces y outputs aprobados, sin acceder arbitrariamente al state de otros stacks. |

## 3. Responsabilidad por repositorio

La siguiente distribución mantiene el modelo de repositorios definido para la arquitectura.

| Repositorio | Responsabilidad de networking |
| --- | --- |
| `dcp-aws-networking-live` | IPAM, VPC compartidas, subnets compartidas, Transit Gateway, attachments, tablas de rutas centrales, VPN/DX, DNS compartido, egress e inspección centralizada, según el diseño aprobado. |
| `dcp-terraform-modules` | Módulos reutilizables para VPC, subnets, routing, TGW, endpoints, IPAM y recursos de conectividad. |
| `dcp-aws-diners-live` | Consumo de redes y despliegue de workloads de Diners según el modelo aprobado; no debe crear conectividad central ni redes públicas por iniciativa propia. |
| `dcp-aws-shared-services-live` | Servicios compartidos y sus necesidades de conectividad, conforme a las responsabilidades acordadas. |
| `dcp-aws-security-live` | Controles de seguridad centralizados y componentes de inspección asignados a Seguridad. |
| `dcp-aws-governance-live` | Guardrails, validaciones y políticas de cumplimiento de red. |

La asignación exacta de ownership debe quedar registrada en el catálogo de arquitectura. Un módulo reutilizable no debe decidir por sí mismo la topología de red de una cuenta: esa decisión pertenece al stack y al diseño aprobados.

## 4. IPAM y planificación de direccionamiento

### 4.1 Reglas de asignación

- Todo CIDR de VPC y subnet debe estar contemplado en el plan de direccionamiento aprobado.
- Se debe validar el solapamiento con otras VPC, on-premises, VPN, Direct Connect, redes de partners y plataformas externas que necesiten comunicarse.
- Las asignaciones deben considerar región, cuenta, entorno, zona de disponibilidad y crecimiento previsto.
- Los rangos reservados deben registrarse con propietario, finalidad, entorno, región, estado y fecha o condición de revisión.
- No se deben asignar CIDR manualmente fuera del proceso aprobado.
- Los rangos utilizados por EKS deben considerar por separado las IP de nodos, Pods y otros recursos de red, según el CNI seleccionado.

### 4.2 Estados de asignación

| Estado | Significado | ¿Terraform puede crear la subnet? |
| --- | --- | --- |
| `ACTIVE` | Rango aprobado para su implementación. | Sí, dentro del alcance autorizado. |
| `RESERVED` | Espacio reservado para uso futuro; todavía no autorizado para implementación. | No. |
| `PROHIBITED` | Rango o uso expresamente no permitido. | No. |

**Regla:** reservar un CIDR no significa crear una subnet vacía. La reserva debe existir en el registro IPAM o en el mecanismo de planificación adoptado, y convertirse en un recurso desplegable únicamente después de su aprobación.

### 4.3 Distribución por cuenta, entorno y región

La planificación IP debe contemplar como mínimo:

- Región AWS y zonas de disponibilidad.
- Cuenta propietaria y entorno (`dev`, `qa`, `stg`, `prod`, según el catálogo aprobado).
- CIDR de VPC y subnets.
- Redes compartidas y redes dedicadas.
- Espacio para expansión y futuros clústeres EKS.
- Rangos de on-premises y otras redes que requieran conectividad.

No se deben fijar bloques CIDR universales para todos los entornos sin revisar primero el inventario real y los rangos existentes. El tamaño de cada bloque se determina a partir de la capacidad y las necesidades de conectividad.

## 5. Diseño y segmentación de subnets

### 5.1 Capas de red

La arquitectura puede utilizar las siguientes capas lógicas. No todas las VPC necesitan implementarlas todas.

| Capa | Uso |
| --- | --- |
| Public / Edge | Recursos que requieren exposición pública aprobada; por ejemplo, ciertos balanceadores o gateways de borde. |
| Workload | EKS, EC2, ECS y otros componentes de aplicación privados. |
| Data | Bases de datos y servicios de datos con requisitos de aislamiento específicos. |
| Endpoint | Interfaces de red de VPC endpoints cuando corresponda. |
| Storage | Servicios como EFS cuando sus mount targets requieran subnets dedicadas o controladas. |
| TGW / Inspection | Subnets dedicadas a attachments de Transit Gateway y a appliances de inspección, si aplican. |

La segmentación definitiva debe responder a diferencias reales de seguridad, routing, disponibilidad, capacidad o dominio de confianza.

### 5.2 Reglas de segmentación

- Las subnets de workloads y de bases de datos deben estar separadas por defecto.
- Las cargas EKS, EC2 y ECS pueden compartir subnets de workload si tienen requisitos de routing, confianza y capacidad compatibles.
- No se creará una subnet por cada servicio AWS automáticamente.
- S3 y SNS son servicios administrados regionales; no necesitan subnets propias. Para S3 se puede evaluar un gateway endpoint; para SNS, según el caso, un interface endpoint.
- Los interface endpoints utilizan interfaces de red en subnets seleccionadas. Su distribución debe contemplar disponibilidad, consumo IP y controles de acceso.
- Los mount targets de EFS requieren interfaces de red en subnets de la VPC; su ubicación debe definirse de acuerdo con la disponibilidad y el patrón de acceso.
- Las subnets para attachments de TGW deben dedicarse a esa función y desplegarse en las zonas de disponibilidad requeridas por la arquitectura.
- Las subnets de inspección se deben definir cuando el diseño incluya appliances o flujos centralizados de inspección.
- Las reglas de seguridad deben utilizar Security Groups y Network ACLs de forma coherente, evitando depender de la subnet como único control de seguridad.

### 5.3 Naming de subnets

Los nombres deben respetar el catálogo y la convención oficial de naming del lineamiento existente. Como ejemplos conceptuales:

```text
dcp-diners-prod-workload-use1-az1
dcp-diners-prod-data-use1-az1
dcp-diners-prod-endpoint-use1-az1
dcp-diners-prod-tgw-use1-az1
dcp-networking-prod-public-use1-az1
dcp-networking-prod-inspection-use1-az1
```

Los ejemplos no sustituyen la validación del catálogo oficial de regiones, entornos y zonas.

## 6. Política para subnets públicas

**Regla general:** las subnets públicas están prohibidas por defecto en cuentas de workloads.

- La cuenta de Networking administra las subnets públicas o de borde cuando el modelo aprobado centraliza el ingreso o la salida a Internet.
- Las cuentas consumidoras no deben crear Internet Gateways, subnets públicas o NAT Gateways propios sin una excepción aprobada.
- Las cuentas no propietarias de la red pueden reservar espacio IP para una posible necesidad futura, utilizando el estado `RESERVED`.
- La reserva no autoriza crear recursos ni habilitar rutas públicas.
- Toda excepción debe identificar la carga, exposición requerida, propietario, controles de seguridad, flujos permitidos y aprobación correspondiente.

Una subnet no es pública únicamente por su nombre o por tener un CIDR enrutable: su comportamiento depende de su tabla de rutas y de los recursos asociados. La clasificación y validación deben comprobar la configuración real.

Si el diseño adopta ingress y egress centralizados, los workloads deben consumir los mecanismos de entrada y salida aprobados, en lugar de implementar caminos paralelos por cuenta.

## 7. Conectividad centralizada: TGW, VPN, Direct Connect y routing

### 7.1 Transit Gateway

- La topología de TGW y sus attachments deben administrarse desde el dominio de Networking autorizado.
- Cada attachment debe tener propietario, finalidad, VPC de origen, región, entorno y tablas de rutas asociadas documentados.
- Las tablas de rutas deben separar dominios de confianza según la política aprobada.
- No se debe asumir que conectar una VPC al TGW implica que todos los destinos quedan autorizados.
- Se prohíben los peering y caminos de conectividad ad hoc fuera de la arquitectura aprobada.
- Las rutas deben evaluarse tanto en el TGW como en las tablas de rutas de las VPC involucradas; ambos lados deben ser coherentes.

### 7.2 VPN y Direct Connect

- Los enlaces con on-premises deben gestionarse conforme al ownership aprobado de Networking.
- Los CIDR anunciados y aceptados deben estar documentados y validados contra el plan IP.
- Deben definirse redundancia, rutas preferidas, failover, límites de propagación y procedimientos de recuperación.
- Los cambios en BGP, propagación, rutas y conectividad productiva requieren revisión de impacto.
- Las rutas por defecto (`0.0.0.0/0` y, cuando aplique, `::/0`) deben estar justificadas y aprobadas.

### 7.3 Matriz de conectividad

Toda conectividad relevante debe registrarse en una matriz con, como mínimo:

| Campo | Contenido requerido |
| --- | --- |
| Origen | Cuenta, entorno, VPC, subnet o servicio. |
| Destino | Cuenta, entorno, CIDR, servicio o red externa. |
| Protocolo/puerto | TCP, UDP, ICMP u otro protocolo aplicable y puertos concretos. |
| Propósito | Justificación de negocio o técnica. |
| Medio | TGW, VPN, Direct Connect, PrivateLink u otro mecanismo aprobado. |
| Control | Security Group, Network Policy, firewall o política aplicable. |
| Dirección | Iniciador, retorno y rutas necesarias. |
| Propietario | Equipo responsable de origen, destino y conectividad. |
| Entorno | `dev`, `qa`, `stg` o `prod`, según el catálogo aprobado. |
| Aprobación | Referencia al cambio o excepción autorizada. |

La matriz debe especificar explícitamente las comunicaciones permitidas y prohibidas entre entornos, on-premises, AWS y plataformas externas como Experience, cuando formen parte de la arquitectura. No se debe asumir que el acceso entre entornos está permitido por compartir TGW.

## 8. Networking de Amazon EKS

Esta sección es crítica porque el modelo elegido afecta al consumo de direcciones IP, al diseño de subnets, a la conectividad con on-premises y a la operación de los clústeres.

### 8.1 El modelo de CNI debe ser una decisión explícita

Cada clúster EKS debe documentar qué CNI utiliza, cómo se asignan las IP de los Pods, qué rangos se consumen y qué limitaciones de routing existen.

| Modelo | Consumo de IP de VPC | Consideración principal |
| --- | --- | --- |
| AWS VPC CNI tradicional | Los Pods reciben IP de la VPC. | Integración nativa con VPC y mayor consumo de direcciones. |
| AWS VPC CNI con Prefix Delegation | Los Pods siguen utilizando IP de la VPC; se asignan prefijos a las interfaces de red. | Mejora la eficiencia de asignación y la densidad de Pods, pero no elimina el consumo de IP de VPC. |
| AWS VPC CNI con Custom Networking | Las IP de los Pods se asignan desde subnets configuradas para ese propósito, que pueden proceder de un CIDR secundario. | Permite separar el espacio IP de Pods del espacio de IP de nodos. |
| CNI alternativo con overlay, por ejemplo Cilium | Las IP de los Pods pueden proceder de un CIDR overlay independiente del CIDR de la VPC. | Reduce la dependencia de IP de VPC para Pods, pero exige validar routing, encapsulación, MTU y conectividad externa. |

AWS documenta Prefix Delegation y Custom Networking como opciones para optimizar la asignación de IP en EKS (fuente: documentación de Amazon EKS).

**Regla del estándar:** no se impondrá un CNI único para todos los clústeres sin una decisión arquitectónica. El modelo seleccionado debe estar aprobado y documentado por clúster, junto con sus implicaciones operativas.

### 8.2 Dimensionamiento de subnets para EKS

El dimensionamiento debe considerar, como mínimo:

- Número actual y máximo previsto de nodos.
- Tipo de instancia y límites de interfaces de red.
- Densidad máxima de Pods por nodo.
- IP reservadas por el CNI para nodos y Pods.
- Pods del sistema y componentes de infraestructura.
- Escalamiento horizontal y autoscaling.
- Nodos temporales durante reemplazos, upgrades y operaciones de drain.
- Crecimiento previsto y margen de capacidad.
- Fragmentación de direcciones, especialmente si se utiliza Prefix Delegation.
- Interfaces de red de balanceadores y otros componentes que consuman IP en esas subnets.

No basta con dimensionar para los nodos actuales. Durante una actualización pueden coexistir nodos antiguos y nuevos; por ello debe comprobarse la capacidad de la subnet durante el escenario de máxima demanda.

### 8.3 Criterios de selección

- **VPC CNI con Prefix Delegation:** candidato preferente cuando se necesita mantener integración nativa con la red VPC y mejorar la asignación de IP.
- **Custom Networking:** considerar cuando se requiere separar las IP de Pods de las IP de nodos, especialmente ante presión de direccionamiento IPv4.
- **Overlay CNI:** considerar cuando la presión de IP de VPC justifique una arquitectura alternativa y se puedan validar los requisitos de conectividad, soporte y operación.

La elección no debe basarse únicamente en la cantidad de IP disponibles. Debe contemplar también seguridad, observabilidad, compatibilidad con los servicios AWS, conectividad híbrida y soporte operativo.

### 8.4 Requisitos de conectividad de EKS

Cada clúster debe documentar:

- Subnets y zonas de disponibilidad de nodos.
- CIDR de Pods y Services, según el modelo de red.
- Endpoint del control plane y su exposición pública o privada.
- Conectividad hacia servicios AWS mediante endpoints o rutas aprobadas.
- Salida a Internet, si se requiere, y mecanismo de egress.
- Flujos autorizados hacia on-premises, bases de datos, plataformas externas y servicios compartidos.
- Requisitos de MTU y compatibilidad con encapsulación si se usa overlay.
- Estrategia de observabilidad, resolución de problemas y registro de tráfico.
- Procedimiento de escalamiento, reemplazo de nodos y recuperación ante agotamiento de IP.

Un CIDR overlay no debe anunciarse ni tratarse automáticamente como una red VPC enrutable. Antes de permitir acceso desde on-premises o desde otra VPC, se debe definir cómo se resuelve el direccionamiento y cómo se devuelve el tráfico.

## 9. Seguridad de red y comunicación entre microservicios

El estándar debe distinguir tres capas independientes.

| Capa | Alcance |
| --- | --- |
| Capa 1 — CNI y conectividad | Asignación de IP, comunicación entre Pods, rutas y NetworkPolicy. |
| Capa 2 — Identidad y cifrado | mTLS, autenticación mutua y autorización de comunicaciones entre servicios. |
| Capa 3 — Resiliencia y tráfico | Circuit breaker, timeouts, retries, rate limiting y políticas de tráfico L7. |

### 9.1 NetworkPolicy

- Las cargas deben tener una política de comunicación explícita conforme a su clasificación de seguridad.
- Las reglas deben permitir únicamente los flujos necesarios.
- Se deben evaluar las políticas de Kubernetes y, si se usa Cilium, sus capacidades de NetworkPolicy.
- Los controles de red no sustituyen la autenticación ni la autorización a nivel de aplicación.

### 9.2 mTLS

Cuando la clasificación de seguridad lo requiera, la arquitectura de microservicios debe exigir autenticación mutua y cifrado entre los servicios correspondientes.

La solución (service mesh, proxies o implementación en la aplicación) debe definir cómo se emiten, rotan y revocan los certificados, cómo se identifican los servicios y cómo se aplica la autorización.

> **Importante:** no se debe asumir que instalar Cilium Overlay habilita mTLS automáticamente. La implementación de mTLS debe seleccionarse y validarse de forma independiente.

### 9.3 Circuit breaker y resiliencia

Los servicios críticos deben evaluar controles de resiliencia adecuados, como:

- Timeouts explícitos.
- Retries limitados y con backoff, cuando sean seguros.
- Circuit breaker para limitar el impacto de servicios degradados.
- Límites de conexiones y solicitudes concurrentes.
- Métricas, logs y alertas sobre fallos y latencia.

Estas capacidades pueden implementarse mediante una librería de aplicación o mediante una solución de proxy/service mesh. Si se considera Cilium Service Mesh, se debe validar la madurez y el alcance de las funcionalidades elegidas antes de adoptarlas como estándar corporativo. Por ejemplo, la documentación consultada de Cilium (1.20.2) marca su mecanismo de mutual authentication como beta, mientras que documenta por separado el circuit breaking basado en Envoy.

### 9.4 Decisión arquitectónica (v1.1): EKS por fases

**Fase 1 · coexistencia**

- Clúster EKS Auto Mode por ambiente para servicios nuevos y migrados: VPC CNI, NetworkPolicy por NodeClass (DefaultDeny) y Kyverno; sin service mesh; circuit breaker, timeouts y retries en librería de aplicación.
- Clúster EKS estándar con nodos híbridos en el data center para servicios legados con conexión directa al AS400. Los nodos híbridos solo admiten Cilium como CNI (la VPC CNI no es compatible), por eso es un clúster separado del Auto Mode. Política de red con CiliumNetworkPolicy y Kyverno. El segmento on-premise que aloja los nodos entra al alcance PCI.
- Las llamadas entre ambos clústeres van por API interna, nunca pod a pod.

**Fase 2 · migración**

- Cada servicio legado se mueve al Auto Mode cuando el AS400 queda expuesto por API o ESB y su egress con IP fija está resuelto en AWS.
- Se cierra cuando no quedan servicios en nodos híbridos; el segmento on-premise sale del alcance PCI.

**Fase 3 · destino**

- Clúster EKS estándar con Cilium (soporte comercial), Istio ambient para mTLS y circuit breaker, y Cilium Egress Gateway para IP de salida fija.
- Requiere antes: equipo de plataforma capaz de operar nodos y CNI propios, contrato de soporte de Cilium y PoC de Istio ambient sobre Cilium.

La matriz de conectividad registra el control de red como `np` (NetworkPolicy, Auto Mode) o `cnp` (CiliumNetworkPolicy, clúster híbrido o fase 3).

## 10. Egress, ingress y servicios AWS

### 10.1 Ingress

La exposición de aplicaciones debe utilizar el patrón de entrada aprobado:

- **HTTP(S):** borde intercambiable (etapa 1 CloudFront + AWS WAF + Shield; etapa 2 Cloudflare) que termina TLS, mTLS hacia el API Gateway REST de la cuenta de integración e integración privada con mTLS hacia el ALB interno de EKS (L16).
- **Partners no HTTP:** VPC de ingress central en la cuenta de networking, con Network Firewall; PrivateLink si el partner opera en AWS; VPN o Direct Connect si exige enlace privado.

Los workloads privados no deben exponer interfaces públicas directamente sin aprobación.

La ubicación de los balanceadores y sus subnets debe ser consistente con el diseño de alta disponibilidad y seguridad.

### 10.2 Egress

- El tráfico saliente debe seguir el modelo aprobado: egress centralizado o egress local justificado.
- Las rutas por defecto deben tener propietario, propósito y controles definidos.
- El acceso a servicios AWS debe utilizar endpoints privados cuando sean apropiados y estén disponibles para el servicio.
- La elección entre gateway endpoints, interface endpoints, NAT y egress centralizado debe considerar costos, disponibilidad, seguridad y requisitos de routing.

### 10.3 DNS

- Las zonas privadas, asociaciones entre VPC y resolución híbrida deben tener ownership definido.
- Las reglas de resolución y forwarding hacia on-premises deben estar documentadas.
- Las cuentas consumidoras deben utilizar los mecanismos aprobados para consumir DNS compartido, sin crear zonas duplicadas o asociaciones incompatibles.
- La integración con Route 53 Resolver debe contemplar rutas, reglas de forwarding y conectividad de ida y retorno.

## 11. Terraform y Terragrunt

### 11.1 Contrato de los módulos

Los módulos de networking deben ser reutilizables y parametrizables. Como mínimo, cuando aplique, deben exponer o recibir:

- CIDR de VPC y subnets.
- Zona de disponibilidad y clasificación de subnet.
- IDs de VPC, TGW, attachments y tablas de rutas.
- Configuración de propagación y asociaciones de rutas.
- Configuración de endpoints, DNS y logging.
- Tags obligatorios.
- Parámetros de segmentación y controles habilitados.

Los módulos no deben contener CIDR productivos, IDs de cuentas, decisiones de topología ni excepciones codificadas de manera implícita.

### 11.2 Contrato de los stacks live

Cada stack debe tener un alcance claro de ownership y cumplir el principio existente:

> 1 directorio live ejecutable = 1 root module = 1 backend = 1 Terraform state = 1 unidad de pipeline.

- Los stacks de Networking son responsables de los recursos centrales que les correspondan.
- Los stacks consumidores deben recibir referencias de recursos mediante mecanismos aprobados, como parámetros centralizados, recursos compartidos o interfaces de consumo definidas.
- No se debe utilizar `terraform_remote_state` como mecanismo general de intercambio cuando existan alternativas más adecuadas y autorizadas.
- Los cambios de CIDR, routing, TGW, conectividad híbrida y exposición pública deben pasar por revisión de impacto y aprobación conforme al entorno.
- Los módulos deben consumirse con la versión o el SHA inmutable exigido por el estándar vigente.

### 11.3 Validaciones automáticas

Los pipelines deben validar, según el recurso y la política aplicable:

- CIDR dentro de rangos aprobados y sin solapamientos conocidos.
- Naming y tags obligatorios.
- Ausencia de subnets públicas no autorizadas.
- Ausencia de rutas por defecto no aprobadas.
- Ausencia de peering no autorizado.
- Consistencia entre subnets, zonas de disponibilidad y attachments.
- Cumplimiento de las reglas de conectividad entre entornos.
- Capacidad IP prevista para EKS y para interfaces de red.
- Configuración de logging y controles de seguridad requeridos.

Las validaciones deben ejecutarse antes de aplicar los cambios. Una revisión manual no sustituye los guardrails automatizables.

## 12. Inventario y documentación obligatoria

El equipo de Networking debe mantener dos registros centrales.

### 12.1 CIDR Allocation Register

| Campo | Descripción |
| --- | --- |
| Cuenta / entorno | Propietario y entorno correspondiente. |
| Región | Región AWS. |
| VPC / subnet | Identificador o nombre del recurso. |
| CIDR | Rango asignado o reservado. |
| Capa | Public, workload, data, endpoint, TGW, etc. |
| AZ | Zona de disponibilidad. |
| Estado | `ACTIVE`, `RESERVED` o `PROHIBITED`. |
| Propietario | Equipo responsable. |
| Uso / capacidad | Finalidad, capacidad prevista y margen de crecimiento. |
| Referencia | Stack Terraform, registro IPAM o aprobación correspondiente. |

### 12.2 Connectivity Matrix

Debe documentar los flujos autorizados entre AWS, on-premises, entornos, servicios compartidos y plataformas externas. Debe revisarse cuando cambien los CIDR, las rutas, las políticas de seguridad o los requisitos de las aplicaciones.

Para EKS, se añadirá el modelo CNI, el CIDR de Pods, las subnets de nodos y Pods, los requisitos de acceso externo y la estrategia de capacidad.

## 13. Excepciones y gobierno

Toda excepción al lineamiento debe registrar:

- Requisito que justifica la excepción.
- Recursos y entornos afectados.
- Riesgo de seguridad, disponibilidad y direccionamiento.
- Controles compensatorios.
- Propietario técnico y responsable de aprobación.
- Evidencia de validación.
- Fecha de revisión o condición de expiración.

Los cambios en direccionamiento, conectividad híbrida, exposición pública, rutas del TGW o modelo de networking de EKS deben revisarse cuando puedan afectar otras cuentas, entornos o servicios.

## 14. Criterios de aceptación del L13

Antes de considerar conforme una implementación de networking, deben poder verificarse los siguientes puntos:

- [ ] Todos los CIDR están inventariados y aprobados.
- [ ] No existen solapamientos conocidos en redes que requieren conectividad.
- [ ] Las subnets tienen una finalidad, propietario, AZ y estado definidos.
- [ ] Las subnets públicas están prohibidas por defecto en cuentas de workloads.
- [ ] Los attachments y las tablas de rutas del TGW responden a una topología aprobada.
- [ ] La conectividad con on-premises y Experience está documentada y autorizada.
- [ ] DNS, egress, endpoints y logging cumplen el diseño aprobado.
- [ ] El CNI y el modelo de direccionamiento de cada clúster EKS están documentados.
- [ ] Las subnets EKS soportan el escenario previsto de escalamiento y reemplazo de nodos.
- [ ] Los requisitos de mTLS y circuit breaker están definidos por separado del CNI.
- [ ] Terraform/Terragrunt y los pipelines aplican las validaciones requeridas.
- [ ] Las excepciones tienen aprobación y evidencia trazable.

## 15. Decisiones adoptadas y pendientes (v1.1)

**Adoptadas el 28/10/2026:**

- Catálogo de entornos: `dev`, `qa`, `stg`, `prod`.
- Modelo de red compartida: Shared VPC por tier, propiedad de Networking; subredes por cuenta compartidas por RAM.
- EKS CNI y service mesh: por fases (sección 9.4).
- Ingress de partners no HTTP: VPC de ingress central.
- Guardrails: por niveles (bloquea, avisa con fecha de promoción, revisión manual), publicados en `policies/terraform`.

**Pendientes:**

- Egress con IP de origen fija en Auto Mode (Cilium Egress Gateway no existe en F1 y F2). Opciones en evaluación: subred dedicada por app con NodePool y NodeClass, NAT dedicado por app, proxy de salida, o mantener la app en nodos híbridos durante F1. Ver `decisiones-casos-landing-zone.drawio`, pestaña 03.
- Topología híbrida: completar el registro de flujos de la matriz de conectividad con el inventario real de DEV, QA, STG, PROD, on-premise y Experience. Ver pestaña 08.

**Recomendación final:** aprobar primero el modelo de ownership, direccionamiento, segmentación y conectividad; después validar el CNI de EKS y el service mesh mediante una prueba técnica. De esa manera, la elección de Cilium o de otro CNI no obliga a rehacer la planificación IP ni la arquitectura central de Transit Gateway.

La propuesta se alinea con las recomendaciones oficiales de AWS para networking y optimización de IP en EKS, pero la selección definitiva de tecnologías y políticas debe validarse contra la arquitectura real de Diners.
