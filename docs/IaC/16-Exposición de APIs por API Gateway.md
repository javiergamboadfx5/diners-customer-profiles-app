# Lineamiento 16: Exposición de APIs por API Gateway

Oct 27, 2026 · @arturomc

**Índice**

1. Propósito y decisiones
2. Arquitectura de referencia
3. API pública
4. API privada para terceros con VPN
5. TLS y mTLS por salto
6. Certificados: públicos afuera, CA interna adentro
7. Independencia del WAF: AWS WAF hoy, Cloudflare mañana
8. Nomenclatura, IaC y validaciones
9. Decisiones tomadas, pendientes y fuentes

## Propósito y decisiones

Toda API que Diners expone a clientes, comercios o terceros entra por la **cuenta Gateway de integración** y por uno de dos caminos: **API Gateway REST público** para internet y **API Gateway REST privado** para terceros conectados por VPN. Ningún workload publica APIs directamente.

**Decisiones:**

1. **Dos caminos, un mismo backend.** Público y privado terminan en el mismo clúster EKS Auto Mode por la misma integración privada con mTLS. Lo que cambia es la entrada, no el backend.
2. **La autorización vive en el API, no en el borde.** El Lambda authorizer valida el token de Keycloak (FAPI 2.0) sin llamar a Keycloak en cada request. El WAF solo filtra tráfico.
3. **El borde termina TLS y es reemplazable.** Etapa 1: CloudFront con AWS WAF y Shield (AWS WAF no termina TLS por sí solo; lo hace la distribución CloudFront a la que se asocia). Etapa 2: Cloudflare. Ninguna aplicación, authorizer ni regla de negocio depende de algo que solo exista en el borde.
4. **mTLS entre el borde y API Gateway, con certificado público.** El custom domain de API Gateway presenta un certificado público y solo acepta conexiones que traigan el certificado de cliente del borde.
5. **Hacia adentro se permiten certificados autofirmados.** El mTLS entre API Gateway y EKS, la conexión de EKS a la BD y el resto del tráfico interno usan una CA interna autofirmada administrada con cert-manager. El origen de cada certificado es un parámetro, no una decisión de código.

**Relación con otros lineamientos:** L13 (red y egress), L14 §5.4 (autorización FAPI 2.0) y §7 (cifrado), L15 (cuentas y OUs), L09 (naming de API Gateway, WAF y ACM).

## Arquitectura de referencia

&#91;embedded content: arquitectura de referencia · camino público y camino privado\]

Los dos caminos comparten el Lambda authorizer, la integración privada con mTLS y el backend. Solo el borde (recuadro punteado) cambia entre la etapa 1 y la 2; en ambas termina el TLS del cliente y llega a API Gateway por mTLS con certificado público. La app y el tercero obtienen su token directamente en Keycloak; el authorizer solo descarga el JWKS cuando Keycloak rota sus llaves.

## API pública

La API pública atiende apps de tarjetahabientes y comercios por internet. La app obtiene el token en Keycloak y el API lo valida con un Lambda authorizer, sin llamar a Keycloak en cada request.

**Flujo de una llamada:**

1. La app ya tiene un access token DPoP emitido por Keycloak con PAR, PKCE y `private_key_jwt` (L14 §5.4).
2. DNS público resuelve `api.dinersclub.com.pe` hacia el borde: CloudFront con AWS WAF y Shield en la etapa 1, Cloudflare en la etapa 2.
3. El borde termina el TLS del cliente con el certificado público del dominio y aplica sus reglas.
4. El borde abre una conexión mTLS al **custom domain regional** de API Gateway: API Gateway presenta su certificado público y valida el certificado de cliente del borde contra el truststore.
5. API Gateway valida el request (esquema, tamaño, método) y aplica throttling por usage plan.
6. El **Lambda authorizer** (tipo REQUEST, caché desactivada) valida firma del token con el JWKS en caché, `iss`, `aud`, `exp`, scope y la prueba DPoP. Consulta en DynamoDB si el `jti` ya se usó o si la sesión fue revocada.
7. Si autoriza, API Gateway pasa al backend el contexto mínimo (`sub`, `client_id`, scope) por la integración privada con mTLS hacia EKS.

**Reglas:**

| Tema | Regla |
| --- | --- |
| Tipo de API | Solo REST, endpoint regional con custom domain. No se usan endpoints edge-optimized: su CloudFront lo administra AWS y no se puede intercambiar por Cloudflare. |
| Autorización | Lambda authorizer con Keycloak. Prohibido autorizar por IP, por cabeceras del WAF o con API keys solas (las API keys sirven solo para usage plans). |
| Cuota y protección | Throttling y usage plans en API Gateway siempre activos, aunque el borde también limite tasa. |
| URL para DPoP | El authorizer compara `htu` con la URL pública configurada como parámetro, no con cabeceras del borde. |
| IP del cliente | El backend usa la IP que entrega API Gateway (`X-Forwarded-For`). Nunca confía en cabeceras propias de un proveedor de borde. |
| Logs | Access logs JSON en CloudWatch con requestId, identidad del authorizer, latencia y estado. Nunca el body ni el token. |
| Errores | 401 y 403 con cuerpo estándar sin detalle interno; errores del authorizer se registran con el `jti`. |

## API privada para terceros con VPN

Los terceros con VPN (por ejemplo Pibank) consumen **APIs privadas** que no existen en internet. Llegan por su VPN a la cuenta de networking, pasan por inspección y entran a la cuenta de integración por un VPC endpoint de API Gateway.

**Flujo de una llamada:**

1. El tercero obtiene un token de Keycloak con **client credentials** y `private_key_jwt`, llamando al endpoint de token por la misma VPN (Keycloak expuesto en privado, nunca por internet para este caso).
2. Su tráfico entra por la VPN Site-to-Site, la tabla de ruteo del TGW propia del tercero y el Network Firewall (IPS). Solo puede alcanzar la VPC de la cuenta de integración.
3. Llama al **custom domain privado** (`<api>.partners.int.dinersclub.com.pe`) que resuelve al VPC endpoint `execute-api`.
4. La **resource policy** del API solo acepta ese VPC endpoint (`aws:SourceVpce`) y los CIDR del tercero (`aws:VpcSourceIp`).
5. El mismo Lambda authorizer valida el token: emisor, audiencia, scope del tercero y la prueba DPoP si el tercero la soporta.
6. API Gateway llega al backend por la misma integración privada con mTLS que la API pública.

**Reglas:**

| Tema | Regla |
| --- | --- |
| Aislamiento | Cada tercero tiene su tabla de ruteo en el TGW y su propio CIDR permitido; un tercero nunca ve a otro. |
| Identidad | Un cliente de Keycloak por tercero, con scopes por API. La VPN no es autenticación: sin token válido no hay acceso. |
| mTLS del tercero | API Gateway no admite mTLS en APIs privadas. Si un tercero exige mTLS, se pone un ALB interno con mTLS en modo *verify* delante, o se usa token ligado a DPoP. |
| Inspección | Network Firewall en el camino de la VPN. El WAF no es requisito en el camino privado. |
| Contratos | Cada API privada se publica con su OpenAPI, versión y límite de tasa por tercero (usage plan). |
| Alta de un tercero | VPN y ruta (Networking), cliente de Keycloak (Security), resource policy y usage plan (repo de integración): tres PR, ninguna acción por consola. |

## TLS y mTLS por salto

&#91;embedded content: cadena de confianza mTLS · opción A y opción B\]

La regla es simple: **certificado público donde valida alguien que no controlamos** (apps, navegadores, el borde, terceros), y **CA interna autofirmada en todo lo que ocurre dentro de AWS**.

- **Cliente → borde:** TLS 1.2 o superior. El borde termina el TLS con el certificado público del dominio.
- **Borde → API Gateway:** mTLS. El custom domain regional presenta un certificado público (ACM); el borde presenta su certificado de cliente y API Gateway lo valida contra el truststore en S3. Con el endpoint `execute-api` desactivado, solo el borde puede llamar al API.
- **API Gateway → EKS:** mTLS con certificados autofirmados. API Gateway presenta su certificado de cliente; el ALB interno de EKS Auto Mode (opción A, decidida) lo verifica en su truststore y presenta un certificado de la CA interna. Como esa CA no está en la lista de API Gateway, la integración usa `insecureSkipVerification`: el tráfico sigue cifrado y API Gateway revisa vencimiento, nombre y cadena, pero no exige emisor público. La opción B (NLB en paso directo al ingress del cluster) usa los mismos certificados.
- **Pods entre sí:** TLS con la CA interna cuando el servicio lo requiere; el aislamiento lo da NetworkPolicy.
- **EKS → BD:** TLS. RDS y Aurora usan la CA de RDS de AWS y el cliente la verifica (`verify-full`). RDS no autentica por certificado de cliente: el acceso es por IAM o con credenciales de Secrets Manager. ESB y AS400 usan la CA interna.

**Autofirmado no es un certificado suelto por servicio.** Se crea una CA raíz interna autofirmada (issuer `SelfSigned` y luego `CA` en cert-manager), con su llave en Secrets Manager cifrada con KMS, y de ella salen todos los certificados internos. Así hay un solo truststore, renovación automática y cero costo de AWS Private CA.

**Certificado de cliente del borde.** Desde el 15 de junio de 2026 las CAs públicas ya no emiten certificados TLS con uso de autenticación de cliente. Por eso «certificado público» aplica al servidor (el custom domain de API Gateway). El certificado de cliente del borde sale de la CA interna, importado en ACM para CloudFront (etapa 1), o de la CA de Authenticated Origin Pulls de Cloudflare (etapa 2).

En todos los casos, las llaves privadas nunca van a Git ni a tfvars, y el origen de cada certificado se fija con `cert_source`.

## Certificados: públicos afuera, CA interna adentro

El certificado de cada punto se elige por **quién lo valida**. Si lo valida alguien fuera de nuestro control, es público: ACM cuando el servicio lo integra gratis y lo renueva solo, o un tercero como ZeroSSL cuando el certificado debe salir de AWS (por ejemplo, para cargarlo en Cloudflare). Si lo valida un componente nuestro dentro de AWS, sale de la CA interna autofirmada.

| Punto | Quién lo valida | Certificado | Renovación |
| --- | --- | --- | --- |
| Dominio público en el borde (`api.dinersclub.com.pe`) | Apps y navegadores | Público: ACM en CloudFront (etapa 1); el de Cloudflare o uno cargado de ZeroSSL (etapa 2) | ACM y Cloudflare automáticas; cargado: el pipeline lo reemplaza 30 días antes |
| Custom domain regional de API Gateway | El borde | Público: ACM, o importado a ACM | ACM automática; importado: reimporte 30 días antes |
| Certificado de cliente del borde | API Gateway (truststore) | Etapa 1: CA interna, importado en ACM para CloudFront. Etapa 2: CA de Cloudflare (Authenticated Origin Pulls) | El pipeline actualiza el truststore antes de cada cambio |
| Custom domain privado de API Gateway | Terceros por VPN | Público: ACM | Automática |
| Certificado de cliente de API Gateway hacia EKS | ALB o ingress de EKS | Autofirmado: CA interna, o generado por API Gateway | CA interna: pipeline; generado por API Gateway: cada 365 días |
| Certificado servidor del ALB interno o del ingress | API Gateway | CA interna (importado en ACM para el ALB) | cert-manager y pipeline |
| Pod a pod, ESB, AS400 | Servicios internos | CA interna (cert-manager) | cert-manager |
| BD RDS o Aurora | Pods | CA de RDS (AWS) | AWS; se rota cuando AWS anuncia nueva CA |

**Reglas:**

- El origen de cada certificado es un **parámetro** del stack (`cert_source = acm | acm_import | acme | internal_ca`) o un `ClusterIssuer` de cert-manager. Cambiar de ACM a ZeroSSL no toca código de la aplicación.
- Una CA pública (ZeroSSL, Let’s Encrypt) solo emite para nombres de dominio públicos, validados por DNS. Para nombres internos (`.svc`, `.int`) se usa la CA interna.
- Ningún certificado de cliente se compra a una CA pública: desde junio de 2026 ya no traen uso de autenticación de cliente.
- `insecureSkipVerification` solo se permite en integraciones privadas hacia EKS con la CA interna. Hacia cualquier endpoint público está prohibido.
- La llave de la CA raíz interna vive en Secrets Manager cifrada con KMS, con vigencia y rotación definidas; nunca en Git.
- Todo certificado entra al inventario de certificados (PCI 4.2.1.1) con dueño, emisor y vencimiento, y con alerta 30 días antes de vencer. Los autofirmados también.

## Independencia del WAF: AWS WAF hoy, Cloudflare mañana

El borde es una capa intercambiable delante del custom domain de API Gateway. En la etapa 1 es AWS WAF con Shield; en la etapa 2, Cloudflare. El cambio debe ser de DNS, de certificados del borde y de reglas del borde, sin tocar authorizer, APIs ni aplicaciones.

**Qué va en cada capa:**

| Capa | Responsabilidad | No debe hacer |
| --- | --- | --- |
| Borde (WAF o Cloudflare) | DDoS, reputación de IP, reglas OWASP, bots, límite de tasa grueso | Autorizar, decidir por cliente o inyectar datos que la app use |
| API Gateway | TLS del dominio, validación de request, throttling por usage plan, Lambda authorizer | Depender de cabeceras o etiquetas del borde |
| Backend en EKS | Autorización fina por recurso con el contexto del authorizer | Leer IP o identidad de cabeceras del proveedor de borde |

**Prohibido (crea dependencia del WAF):**

- Usar etiquetas, cabeceras o tokens propios de AWS WAF (por ejemplo, tokens de CAPTCHA o challenge) dentro del authorizer o de la aplicación.
- Usar reglas del WAF como único límite de tasa por cliente o por API.
- Usar endpoints edge-optimized de API Gateway: su CloudFront lo administra AWS y no se puede intercambiar.
- Dejar el endpoint por defecto `execute-api` abierto: se desactiva y solo se llega por el custom domain.

**Etapa 2, migración a Cloudflare:**

1. Reglas de Cloudflare en Terraform (provider desde Nexus), equivalentes a las de AWS WAF y probadas en modo registro.
2. Se agrega al truststore del custom domain la CA de Authenticated Origin Pulls de Cloudflare, junto a la CA interna del certificado de CloudFront, para que ambos bordes convivan durante el cambio.
3. El certificado público del dominio se activa en Cloudflare (el emitido por Cloudflare o uno cargado).
4. Cambio de DNS del dominio público a Cloudflare en modo proxy, por API y con vuelta atrás inmediata.
5. Se retiran CloudFront y AWS WAF, se quita la CA de CloudFront del truststore y se retira Shield Advanced cuando Cloudflare absorba el DDoS.

**Cuidado:** en las dos etapas el borde termina el TLS del cliente. Un socio que exija mTLS en la API pública lo hace contra el borde (mTLS de viewer en CloudFront, API Shield en Cloudflare) o pasa al camino privado por VPN. Los logs del borde se normalizan en el SIEM para que los tableros no dependan del proveedor.

## Nomenclatura, IaC y validaciones

**Nombres (L09):**

| Recurso | Patrón | Ejemplo |
| --- | --- | --- |
| API REST | `dcp-<dominio>-<ambiente>-<workload>-apigw-<public\|private>` | `dcp-diners-prod-channels-apigw-public` |
| WAF | `dcp-<scope>-<ambiente>-<workload>-waf-<exposición>` | `dcp-diners-prod-channels-waf-public` |
| Certificado ACM | `dcp-<scope>-<ambiente>-acm-<propósito>` | `dcp-diners-prod-acm-public-api` |
| Lambda authorizer | `dcp-<dominio>-<ambiente>-<workload>-fn-<acción>` | `dcp-diners-prod-apiauth-fn-authorize` |
| Dominio público | `<api>.dinersclub.com.pe` | `api.dinersclub.com.pe` |
| Dominio privado | `<api>.partners.int.dinersclub.com.pe` | `cobranzas.partners.int.dinersclub.com.pe` |

**Estructura en el repo de la cuenta de integración** (L02 v1.2: `dcp-aws-integration-live`):

```text
live/prod/us-east-1/
  edge/           ← módulo de borde: provider = aws-waf | cloudflare
  domains/        ← custom domains, certificados, truststores
  authorizer/     ← Lambda authorizer + DynamoDB de jti y sesiones revocadas
  vpc-links/      ← integraciones privadas hacia EKS
  apis/<api>/     ← un estado por API: definición OpenAPI, stage, usage plans, resource policy
```

El módulo `edge` expone la misma interfaz para AWS WAF y Cloudflare. El cambio de etapa es cambiar `provider` y aplicar, no reescribir stacks.

**El pipeline rechaza:**

- APIs sin Lambda authorizer en métodos de negocio (solo `/health` puede ir sin él).
- Endpoint `execute-api` por defecto habilitado, endpoint edge-optimized o política TLS menor a 1.2.
- Custom domain público sin mTLS o con un truststore que no sea el del borde.
- Integraciones al backend sin certificado de cliente, o con `insecureSkipVerification` fuera de una integración privada hacia EKS.
- APIs privadas sin resource policy con `aws:SourceVpce`.
- Stages sin access logs, sin throttling o con logs de body.
- Código de authorizer o aplicaciones que lean cabeceras del borde (`x-amzn-waf-*`, `cf-*`).
- ARN de certificados escritos en el código: llegan por parámetro desde el catálogo o Parameter Store.

## Decisiones tomadas, pendientes y fuentes

**Decididas el 28/10/2026:**

- **Integración con EKS:** ALB interno con mTLS (opción A).
- **Shield Advanced:** se mantiene en la etapa 1 y se retira cuando Cloudflare absorba el DDoS.
- **Repo de la cuenta de integración:** `dcp-aws-integration-live` (L02 v1.2).

**Pendientes:**

1. **Prueba de concepto de la integración.** Validar que el ALB en modo *verify* acepta el certificado de cliente de API Gateway, que `insecureSkipVerification` aplica a la integración privada y que CloudFront hace mTLS hacia el custom domain. Si `insecureSkipVerification` no aplica, el ALB usa un certificado público de ACM (gratis) y el resto sigue con la CA interna.
2. **Certificados públicos fuera de AWS.** Análisis de precios y renovación en `decisiones-casos-landing-zone.drawio`, pestañas 05 y 06. Recomendación: ACM administrado en AWS (USD 0), Let’s Encrypt por ACME con cert-manager fuera de AWS (USD 0) y CA raíz interna autofirmada para lo interno (USD 0).
3. **Keycloak para terceros por VPN.** Opciones en la pestaña 07. Recomendación: Keycloak publicado por PrivateLink en la VPC de integración, para que la VPN siga alcanzando solo esa cuenta.
4. **Fecha de la etapa 2,** según el contrato de Cloudflare.
5. **Keycloak público detrás del borde intercambiable** (hoy L14 dice ALB + WAF).

**Fuentes:**

- [API Gateway: autenticación hacia el backend con certificado de cliente](https://docs.amazonaws.cn/en_us/apigateway/latest/developerguide/rest-api-backend-auth-overview.md)
- [API Gateway: tlsConfig e insecureSkipVerification](https://docs.aws.eu/apigateway/latest/developerguide/api-gateway-extensions-integration-tls-config.html)
- [API Gateway REST: integración privada con ALB (noviembre 2025)](https://aws.amazon.com/about-aws/whats-new/2025/11/api-gateway-rest-apis-integration-load-balancer)
- [API Gateway: mTLS en REST APIs (no disponible en APIs privadas)](https://docs.aws.amazon.com/en_uk/apigateway/latest/developerguide/rest-api-mutual-tls.html)
- [API Gateway: custom domain para APIs privadas](https://aws.amazon.com/about-aws/whats-new/2024/11/amazon-api-gateway-custom-domain-name-private-rest-apis/)
- [CloudFront: mTLS hacia el origen (enero 2026)](https://aws.amazon.com/about-aws/whats-new/2026/01/amazon-cloudfront-mutual-tls-for-origins)
- [CloudFront: guía de mTLS de origen](https://docs.aws.amazon.com/dk_dk/AmazonCloudFront/latest/DeveloperGuide/origin-mtls-authentication.html)
- [Fin del uso de autenticación de cliente en certificados TLS públicos (15 de junio de 2026)](https://www.thesslstore.com/blog/chrome-ssl-certificate-client-authentication-ends-june-2026/)
- [ACM: certificados públicos exportables en Kubernetes](https://docs.aws.eu/acm/latest/userguide/exportable-certificates-kubernetes.html)
- [ZeroSSL](https://zerossl.com)
