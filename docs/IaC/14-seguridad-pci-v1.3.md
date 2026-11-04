# Lineamiento 14 — Seguridad y cumplimiento PCI DSS (v1.3)

| Campo | Valor |
|---|---|
| Versión | 1.3 (borrador para revisión con Ciberseguridad) |
| Fecha | 2026-10-28 |
| Cambios en 1.3 | Dos cuentas de seguridad (`dinersclub-log-archive` y `dinersclub-security`). EKS por fases (L13 v1.1): en F1 el clúster con nodos híbridos entra al alcance. Protección DDoS por etapas y autenticación de socios alineadas a L16. Versión de PCI DSS: la vigente del PCI SSC. |
| Cambios en 1.2 | Índice. Una sola cuenta de seguridad (`dinersclub-security`) para log archive, auditoría y herramientas, según L15. Runners y roles de despliegue en `dinersclub-devops` (`dcp-aws-devops-live`), según L02 v1.1. Alineado con L16: el borde (CloudFront + AWS WAF en etapa 1, Cloudflare en etapa 2) termina TLS y llega a API Gateway por mTLS con certificado público; hacia adentro se permiten certificados de una CA interna autofirmada. |
| Cambios en 1.1 | Un solo clúster EKS Auto Mode con namespaces ux y bs; aislamiento con NetworkPolicy y Kyverno en lugar de mTLS entre clústeres; APIs tipo REST; nueva sección 5.5 de autorización con Keycloak y Lambda authorizer según FAPI 2.0. |
| Owner | Ciberseguridad |
| Co-owners | Arquitectura Cloud, Infraestructura Cloud, Platform Engineering |
| Norma de referencia | La versión vigente de PCI DSS publicada por el PCI SSC: hoy v4.0.1 (única activa desde el 31/12/2024). PCI DSS v5.0 se espera en consulta pública a fines de 2026; el lineamiento se actualiza cuando se publique |
| Normas relacionadas | PCI PIN Security, PCI P2PE (adquirencia con terminales), PCI 3DS (emisión con ACS), reglas de la marca |
| Repos que lo implementan | `dcp-aws-governance-live`, `dcp-aws-security-live`, `dcp-aws-networking-live`, `dcp-aws-shared-services-live`, `dcp-aws-devops-live`, repos de workload |

> Numeración: la propuesta FinOps se incorporó al lineamiento 11 v2, por eso este documento toma el número 14. Si FinOps vuelve a ser un documento propio, este pasa a 15.

## Índice

1. [Propósito y punto de partida](#1-propósito-y-punto-de-partida)
2. [Principios](#2-principios)
3. [Alcance PCI y segmentación](#3-alcance-pci-y-segmentación)
4. [Identidad y acceso](#4-identidad-y-acceso-req-7-y-8)
5. [Perímetro y entrada](#5-perímetro-y-entrada-route-53--api-gateway--balanceadores-req-1-4-64)
6. [Red y segmentación interna](#6-red-y-segmentación-interna-req-1-y-115)
7. [Cifrado en tránsito y aislamiento entre microservicios](#7-cifrado-en-tránsito-y-aislamiento-entre-microservicios-req-1-y-4)
8. [Datos en reposo y gestión de llaves](#8-datos-en-reposo-y-gestión-de-llaves-req-3)
9. [Workloads y gestión de vulnerabilidades](#9-workloads-y-gestión-de-vulnerabilidades-req-5-6-y-113)
10. [Logging, detección y respuesta](#10-logging-detección-y-respuesta-req-10-115-y-1210)
11. [Emisión y adquirencia: controles específicos](#11-emisión-y-adquirencia-controles-específicos)
12. [Alternativas para decidir con Ciberseguridad](#12-alternativas-para-decidir-con-ciberseguridad)
13. [Dueño de cada control (repos)](#13-dueño-de-cada-control-repos)
14. [Validaciones en CI/CD](#14-validaciones-en-cicd)
15. [Excepciones](#15-excepciones)
16. [Fuentes](#16-fuentes)

---

## 1. Propósito y punto de partida

Este lineamiento define los controles de seguridad obligatorios de la Landing Zone AWS de Diners Club Perú y cómo cada uno cubre PCI DSS para una entidad **emisora** (tarjetas de crédito) y **adquirente** (recaudación de comercios).

### 1.1 Qué cubren hoy los 13 lineamientos

Los lineamientos actuales tratan la seguridad de forma dispersa y sin un estándar propio:

| Lineamiento | Qué cubre de seguridad | Qué falta |
|---|---|---|
| 02 Topología de repos | Repo `dcp-aws-security-live` con GuardDuty, Security Hub, Inspector, Macie, Access Analyzer, Firewall Manager, Config Aggregator, CloudTrail y Log Archive. Regla "aplicar controles PCI solo a cuentas CDE". | Cómo se configura cada servicio, qué planes de protección se activan, qué estándares, qué retención, qué cuentas son CDE. |
| 06 Pipelines y Policy as Code | OIDC, plan y apply separados, Nexus, Checkov, Conftest, secretos en Secrets Manager. | Seguridad de la aplicación (SAST, DAST, SCA), firma de imágenes, gestión de vulnerabilidades en runtime. |
| 11 Tags | `DataClassification = pci` y `Compliance = pci-dss`. | Qué controles disparan esos tags. |
| 13 Networking | Segmentación, egress e inspección central, Cilium overlay. EKS Auto Mode no admite Cilium: el L13 necesita una excepción o una actualización para este clúster. | Pruebas de segmentación PCI, WAF, Shield, DNS Firewall, TLS por salto. |
| 05 Backend | Cifrado del estado con KMS. | Política general de llaves y criptografía. |

**Conclusión:** no hay un lineamiento de seguridad. Faltan identidad y acceso, protección de datos de tarjeta, gestión de llaves, perímetro, detección y respuesta, gestión de vulnerabilidades, logging con retención PCI y el modelo de alcance (scope) PCI. Este documento cubre ese hueco y referencia a los otros lineamientos en lugar de repetirlos.

### 1.2 Alcance

Aplica a todas las cuentas de la organización. Los controles marcados **[CDE]** son obligatorios en cuentas del entorno de datos de tarjeta y en las cuentas conectadas a él. Los marcados **[ALL]** aplican a toda la organización.

---

## 2. Principios

1. **El alcance PCI se reduce por diseño.** Donde se pueda, el PAN se reemplaza por un token antes de entrar a un sistema. Cada sistema que no ve PAN sale del CDE.
2. **Cada salto cifrado y autenticado.** TLS 1.2 como mínimo en todo el camino de entrada y hacia sistemas fuera del clúster. Dentro del clúster, aislamiento por NetworkPolicy y TLS en los flujos que transportan PAN.
3. **Identidades temporales.** Ninguna persona ni pipeline usa access keys permanentes. Todo acceso humano pasa por Identity Center con MFA.
4. **Prevenir con guardrails, detectar con servicios gestionados, corregir con código.** SCP y RCP impiden lo prohibido; GuardDuty, Security Hub e Inspector detectan; la corrección se hace por PR en el repo dueño.
5. **Evidencia continua.** Cada control produce evidencia automática (Security Hub, Config, Audit Manager) para el QSA, en lugar de capturas manuales.
6. **Una sola fuente de verdad por control.** Cada control tiene un repo dueño (sección 13).

---

## 3. Alcance PCI y segmentación

### 3.1 Clasificación de cuentas

| Categoría | Definición | Cuentas (propuesta) |
|---|---|---|
| CDE | Almacena, procesa o transmite PAN o datos sensibles de autenticación (SAD) | `dinersclub-diners-prod` (EKS UX, EKS BS, Aurora), cuenta de gateway de integración si el API recibe PAN |
| Conectada al CDE | Puede impactar la seguridad del CDE | `dinersclub-networking`, `dinersclub-log-archive`, `dinersclub-security`, `dinersclub-devops` (despliega al CDE), `dinersclub-shared-services` |
| Fuera de alcance | Sin conectividad ni impacto sobre el CDE | Cuentas no productivas, sandbox, datalake **solo si no recibe PAN** |

**Regla [ALL]:** las cuentas CDE viven en una OU propia (`ou=pci`) con SCP adicionales. El tag `Compliance = pci-dss` en la cuenta y en sus recursos activa los controles de esta guía.

**Alerta del datalake:** el datalake actual guarda números de tarjeta cifrados con AES-SIV determinístico (`doc_fields`). Un PAN cifrado sigue siendo dato de tarjeta. Con eso, la cuenta del datalake y la cuenta de seguridad que guarda la llave entran al alcance PCI. Opciones: reemplazar el PAN por un token antes de la ingesta (recomendado), o tratar la cuenta del datalake como CDE.

### 3.2 Datos de tarjeta

| Dato | Almacenamiento permitido | Control |
|---|---|---|
| PAN | Sí, ilegible (3.5.1) | Token, cifrado fuerte con llave gestionada o hash con llave (3.5.1.1). Mostrar solo BIN + últimos 4 (3.4.1). |
| Nombre, fecha de vencimiento | Sí | Protegidos si se guardan junto al PAN. |
| SAD: banda, CVV2, PIN block | No después de la autorización (3.3.1) | Excepción de emisor (3.3.3): solo con justificación de negocio, cifrado y acceso restringido. |
| PIN | Nunca en claro | AWS Payment Cryptography o HSM; cumple PCI PIN. |

### 3.3 Segmentación

- **[CDE]** El CDE no tiene IGW, NAT ni subredes públicas. La salida a internet pasa por el egress central con lista de dominios permitidos (L13).
- **[CDE]** Rutas del TGW: la tabla de ruteo del CDE solo propaga las VPC conectadas aprobadas. Terceros (Pibank y otros) llegan únicamente a la cuenta de gateway de integración, nunca directo al CDE.
- **[CDE]** Prueba de segmentación cada **6 meses** (requisito 11.4.6 para proveedores de servicio; como adquirente que procesa para comercios se recomienda asumir esta frecuencia) y después de cada cambio de segmentación.
- **[CDE]** Revisión del alcance PCI cada 6 meses (12.5.2.1) usando Macie y el inventario de flujos (sección 10.4).

---

## 4. Identidad y acceso (Req. 7 y 8)

| # | Control | Ejemplo concreto |
|---|---|---|
| IA-1 [ALL] | Sin usuarios IAM ni access keys para personas o pipelines | SCP `DenyIAMUserCreation` (excepto break-glass). Pipelines por OIDC (L06). |
| IA-2 [ALL] | Acceso humano solo por IAM Identity Center con MFA resistente a phishing | Permission sets por función: `DCP-Diners-ReadOnly`, `DCP-Diners-ProdOperator`. MFA con FIDO2 para CDE. |
| IA-3 [CDE] | Sesión inactiva máx. 15 minutos (8.2.8) | Duración de sesión del permission set y timeout de consola. |
| IA-4 [CDE] | Revisión de accesos cada 6 meses (7.2.4) | Reporte de Identity Center + IAM Access Analyzer de accesos no usados. |
| IA-5 [ALL] | Cuentas break-glass con alerta en cada uso | Usuario root con MFA de hardware en caja fuerte; EventBridge alerta en `ConsoleLogin` de root. |
| IA-6 [CDE] | Pods con identidad propia | EKS Pod Identity; sin credenciales en variables de entorno. |
| IA-7 [CDE] | Acceso a base de datos sin contraseñas compartidas | Autenticación IAM en Aurora o secretos con rotación automática de Secrets Manager (≤ 90 días). |
| IA-8 [ALL] | Accesos externos detectados | IAM Access Analyzer de organización con analizador de acceso externo y no usado. |

Ejemplo de SCP para la OU PCI:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {"Sid": "DenyDisableSecurity", "Effect": "Deny",
     "Action": ["guardduty:Delete*", "guardduty:Disassociate*", "securityhub:Disable*",
                "cloudtrail:StopLogging", "cloudtrail:DeleteTrail", "config:Stop*", "config:Delete*"],
     "Resource": "*"},
    {"Sid": "DenyUnapprovedRegions", "Effect": "Deny", "NotAction": ["iam:*", "organizations:*", "sts:*", "support:*"],
     "Resource": "*", "Condition": {"StringNotEquals": {"aws:RequestedRegion": ["us-east-1", "us-east-2"]}}},
    {"Sid": "DenyIAMUsers", "Effect": "Deny", "Action": ["iam:CreateUser", "iam:CreateAccessKey"], "Resource": "*"}
  ]
}
```

---

## 5. Perímetro y entrada: Route 53 → API Gateway → balanceadores (Req. 1, 4, 6.4)

### 5.1 DNS — Route 53

- **[ALL]** DNSSEC firmado en zonas públicas que expongan APIs de comercios o tarjetahabientes.
- **[ALL]** Query logging de zonas públicas y del Resolver hacia Log Archive.
- **[CDE]** Route 53 Resolver DNS Firewall en las VPC CDE: bloquear dominios de listas gestionadas de AWS (malware, botnets) y permitir solo dominios aprobados para egress.
- **[ALL]** Revisión de registros huérfanos (subdomain takeover) en cada assessment.

### 5.2 Protección de borde — Shield y WAF

- **[CDE]** El borde termina el TLS del cliente: CloudFront con AWS WAF y Shield en la etapa 1 (AWS WAF no termina TLS por sí solo), Cloudflare en la etapa 2. Del borde a API Gateway hay mTLS: el custom domain presenta un certificado público y valida el certificado de cliente del borde (detalle en L16).
- **[CDE]** AWS WAF delante de todo endpoint público (API Gateway público y cualquier ALB o CloudFront). Cumple 6.4.2.
  - Reglas gestionadas: Core rule set, Known bad inputs, SQL database, Amazon IP reputation, Anonymous IP.
  - Regla de tasa por IP y por API key.
  - Bot Control y, para APIs de login de tarjetahabientes, Account Takeover Prevention.
  - Logs de WAF a Log Archive.
- **[CDE]** AWS Shield: Standard en todo; Shield Advanced en las IP y recursos públicos de adquirencia y canales de tarjetahabiente (alternativa en sección 12).
- **[ALL]** Firewall Manager despliega y audita las políticas de WAF y Shield en toda la organización.

### 5.3 API Gateway (tipo REST)

Todas las APIs se publican como **API Gateway REST**. Es el tipo que admite WAF, Lambda authorizer de tipo REQUEST, mTLS en custom domain regional, APIs privadas con resource policy y usage plans.

| Caso | Configuración |
|---|---|
| API pública (comercios, apps) | Custom domain regional, política TLS 1.2 mínima, WAF asociado, Lambda authorizer FAPI 2.0 (5.4), validación de request, throttling y usage plans. |
| Socio por internet con certificado | El mTLS del custom domain regional queda reservado para el borde. El socio hace mTLS contra el borde (mTLS de viewer en CloudFront, API Shield en Cloudflare) o usa el camino privado por VPN. API Gateway no soporta mTLS en APIs privadas. |
| Socio por VPN o PrivateLink (Pibank) | API privada con VPC endpoint `execute-api` y resource policy que solo acepta ese endpoint (`aws:SourceVpce`). La autenticación del socio se hace con firma de requests (SigV4) o con mTLS en un ALB. |
| Todas | Access logs en formato JSON a CloudWatch, con `requestId`, IP, identidad y estado. Nunca registrar el body si puede contener PAN. |

Ejemplo de resource policy de la API privada:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Deny", "Principal": "*", "Action": "execute-api:Invoke", "Resource": "execute-api:/*",
    "Condition": {"StringNotEquals": {"aws:SourceVpce": "vpce-0abc123integracion"}}
  }, {
    "Effect": "Allow", "Principal": "*", "Action": "execute-api:Invoke", "Resource": "execute-api:/*"
  }]
}
```

### 5.4 Autorización de APIs con Keycloak y Lambda authorizer (FAPI 2.0)

El API público solo acepta access tokens emitidos por Keycloak según el **FAPI 2.0 Security Profile** (Final, febrero 2025). Keycloak 26.4 o superior trae los perfiles de política de cliente `fapi-2-security-profile` y `fapi-2-dpop-security-profile`.

**Reglas del perfil que aplican:**

| Tema | Regla |
|---|---|
| Flujo | Solo authorization code. PAR obligatorio y autenticado. PKCE con S256. |
| Cliente | Solo clientes confidenciales: `private_key_jwt` o mTLS. FAPI 2.0 no admite clientes públicos. |
| Tokens | Sender-constrained con DPoP (recomendado para la app) o mTLS (socios B2B). |
| Tiempos | Código de autorización ≤ 60 s y de un solo uso; `request_uri` con `expires_in` < 600 s. |
| Respuesta | Parámetro `iss` (RFC 9207); la app lo valida junto con `state`. |
| Criptografía | PS256, ES256 o EdDSA; nunca `none`; RSA ≥ 2048. TLS 1.2+. |
| API | Token solo en el header `Authorization`; validar firma, expiración, revocación, alcance y la prueba DPoP. |

**Cliente móvil.** Como FAPI 2.0 exige cliente confidencial, la APK no puede ser un cliente público. Opción recomendada: cada instalación se registra como cliente propio (RFC 7591) después de validar Play Integrity, con una llave no exportable en Android Keystore que sirve para `private_key_jwt` y para DPoP. Alternativa: un BFF confidencial en EKS; la app mantiene sesión con el BFF. Un cliente público con PKCE y DPoP es más simple pero no cumple FAPI 2.0.

**Flujo (detalle en las pestañas 07 y 08 del draw.io):**

1. La app envía `POST /par` con `private_key_jwt`, `code_challenge` S256, `redirect_uri` (App Link https), `dpop_jkt` y scope. Recibe `request_uri`.
2. La app abre el navegador del sistema en `/auth?client_id&request_uri`. El tarjetahabiente se autentica con MFA o passkey y da su consentimiento.
3. Keycloak responde 303 al App Link con `code`, `state` e `iss`. La app valida `iss` y `state`.
4. La app envía `POST /token` con `code`, `code_verifier`, `private_key_jwt` y prueba DPoP. Recibe access token JWT de 5 minutos con `cnf.jkt`, refresh token ligado a DPoP e id_token.
5. La app llama al API con `Authorization: DPoP <token>` y el header `DPoP` (htm, htu, iat, jti, ath).
6. API Gateway invoca el Lambda authorizer de tipo REQUEST con caché desactivada.
7. El authorizer valida localmente: firma con JWKS en caché, `iss`, `aud`, `exp`, scope; prueba DPoP con thumbprint igual a `cnf.jkt`, método y URL, `iat` dentro de ±60 s y `ath`. Consulta en DynamoDB que el `jti` no se haya usado y que la sesión no esté revocada.
8. Si todo es válido, devuelve Allow con contexto (`sub`, `client_id`, scope). API Gateway enruta por VPC link al namespace ux.
9. Renovación con refresh token, `private_key_jwt` y prueba DPoP. Logout con `/revoke` (RFC 7009) y `end_session`. Un event listener de Keycloak publica el logout en EventBridge y la sesión queda revocada en DynamoDB hasta que expire el último access token.

**Correcciones respecto del diagrama inicial:**

- Keycloak no se publica con un API Gateway: se expone con **ALB + WAF**, solo con las rutas OIDC del realm (`/.well-known`, `par`, `auth`, `token`, `revoke`, `logout`, `certs`). La consola de administración nunca es pública.
- El Lambda authorizer **no llama a Keycloak en cada request**. Refresca el JWKS al iniciar o si llega un `kid` desconocido, por un camino privado.
- El Lambda authorizer vive en la misma cuenta que el API Gateway. Keycloak queda en la cuenta Shared Services.
- El backend recibe solo el contexto mínimo y aplica autorización fina por recurso (por ejemplo, que la tarjeta pertenezca al `sub`).

### 5.5 Balanceadores y PrivateLink

- **[CDE]** NLB con listener TLS (certificado de ACM o Private CA) o en modo passthrough hacia un destino que termina TLS. Nunca TCP en claro con datos de tarjeta.
- **[CDE]** ALB cuando se requiera mTLS de socio (modo *verify* con truststore) o reglas L7.
- **[CDE]** Endpoint services de PrivateLink con aceptación manual y lista de principals permitidos.
- **[ALL]** Política TLS de balanceadores: `ELBSecurityPolicy-TLS13-1-2-2021-06` o superior.

---

## 6. Red y segmentación interna (Req. 1 y 11.5)

- **[CDE]** AWS Network Firewall en la cuenta de networking inspecciona tráfico este-oeste entre VPC y la salida a internet. Reglas Suricata en modo *strict order*, acción por defecto *drop*, IPS activo (cumple 11.5.1).
- **[CDE]** VPN Site-to-Site: IKEv2, AES-256-GCM, SHA-384, grupos DH 19 o superiores, PFS. PSK de 32 caracteres rotada cada 12 meses o autenticación por certificado (Private CA). Logs de túnel activados.
- **[CDE]** Security Groups referenciando otros SG, sin `0.0.0.0/0` de entrada. NACL como segunda capa en subredes de base de datos.
- **[CDE]** VPC Flow Logs en todas las VPC (campos extendidos), a Log Archive.
- **[CDE]** Fase 1 de EKS (L13 v1.1): los servicios legados con conexión al AS400 corren en un clúster EKS estándar con nodos híbridos en el data center y Cilium como CNI. El segmento on-premise que aloja esos nodos entra al alcance PCI hasta que la fase 2 los retire. Su política de red es CiliumNetworkPolicy + Kyverno.

---

## 7. Cifrado en tránsito y aislamiento entre microservicios (Req. 1 y 4)

### 7.1 Por salto

| Salto | Protocolo mínimo | Autenticación | Ejemplo |
|---|---|---|---|
| Cliente → borde | TLS 1.2 (1.3 preferido) | Token | El borde termina TLS con el certificado público del dominio |
| Borde → API Gateway | mTLS | Certificado público del custom domain + certificado de cliente del borde | Truststore en S3 con la CA del borde |
| API Gateway → ALB interno (VPC link) | mTLS | Certificado de cliente de API Gateway + certificado del ALB | Certificados de la CA interna autofirmada (L16) |
| Tercero → integración (VPN) | IPsec + TLS dentro | Certificado | TLS de aplicación sobre el túnel, no solo IPsec |
| PrivateLink → NLB interno → pod | TLS | Certificado | NLB o ALB de Auto Mode en modo IP; TLS hasta el pod en flujos con PAN |
| Microservicio ↔ microservicio (ux → bs) | NetworkPolicy + cifrado Nitro; TLS si transporta PAN | Service account y namespace | 7.2 |
| Microservicio → Aurora | TLS 1.2 | IAM o secreto rotado | `rds.force_ssl = 1`, `sslmode=verify-full` |
| Microservicio → ESB / AS400 | TLS 1.2 sobre VPN o DX | Certificado | Certificado de cliente emitido por la CA interna |
| Cualquiera → servicios AWS | TLS por VPC endpoint | SigV4 | Endpoints de interfaz para KMS, Secrets Manager, STS, ECR |

PCI exige cifrado fuerte en redes públicas (4.2.1). Dentro del clúster no es obligatorio, pero se exige TLS en todo flujo que transporte PAN y en cualquier salto que salga del clúster o pase por on-premise. Hacia adentro de AWS se permiten certificados de una CA interna autofirmada (cert-manager), con la llave de la CA raíz en Secrets Manager cifrada con KMS. El inventario de certificados es obligatorio (4.2.1.1) e incluye los autofirmados.

### 7.2 Aislamiento en un solo clúster EKS Auto Mode

UX y BS comparten **un clúster EKS Auto Mode**, separados por namespace (fases 1 y 2 de L13 v1.1; en la fase 3 el clúster pasa a EKS estándar con Cilium e Istio). No hay mTLS entre clústeres. El aislamiento tiene tres capas:

1. **NetworkPolicy estándar** aplicada por Auto Mode. La `NodeClass` fija `networkPolicy: DefaultDeny` y el registro de eventos de red. Auto Mode no admite Cilium ni otros motores de políticas, solo NetworkPolicy L3/L4.
2. **Kyverno** genera la política por defecto en cada namespace nuevo y rechaza lo que rompa el modelo.
3. **Subredes y Security Groups separados** para los pods de bs con `podSubnetSelectorTerms` y `podSecurityGroupSelectorTerms` en una `NodeClass` propia.

Ejemplo de NetworkPolicy en bs:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: bs-desde-ux, namespace: bs}
spec:
  podSelector: {matchLabels: {app: autorizador}}
  policyTypes: [Ingress, Egress]
  ingress:
  - from: [{namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: ux}}, podSelector: {matchLabels: {app: canal-movil}}}]
    ports: [{port: 8443, protocol: TCP}]
  egress:
  - to: [{ipBlock: {cidr: 10.20.40.0/24}}]   # subred de Aurora
    ports: [{port: 5432, protocol: TCP}]
```

Ejemplo de Kyverno que crea la denegación por defecto en cada namespace:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: {name: default-deny-por-namespace}
spec:
  rules:
  - name: generar-default-deny
    match: {any: [{resources: {kinds: [Namespace]}}]}
    generate:
      apiVersion: networking.k8s.io/v1
      kind: NetworkPolicy
      name: default-deny
      namespace: "{{request.object.metadata.name}}"
      synchronize: true
      data:
        spec: {podSelector: {}, policyTypes: [Ingress, Egress]}
```

Otras políticas de Kyverno obligatorias: namespaces con etiqueta `pci-scope`, Pod Security `restricted`, `verifyImages` para imágenes firmadas de Nexus, y solo el equipo de plataforma puede cambiar NetworkPolicy en bs.

**Impacto PCI:** al compartir clúster, todo el clúster (plano de control, nodos, Kyverno y operadores) queda dentro del CDE aunque ux no vea PAN. La segmentación por namespace se prueba cada 6 meses como cualquier otra segmentación.

**Cifrado dentro del clúster** (decisión en la sección 12): recomendado limitar el NodePool a familias de instancia que cifran el tráfico entre instancias en la VPC y usar TLS de aplicación con cert-manager y Private CA en los servicios que reciben PAN.

---

## 8. Datos en reposo y gestión de llaves (Req. 3)

| # | Control | Ejemplo concreto |
|---|---|---|
| DR-1 [CDE] | Tokenizar el PAN en el primer punto de entrada | Servicio de tokenización en el CDE; el resto de servicios solo ve tokens. |
| DR-2 [CDE] | Cifrado a nivel de campo para PAN almacenado | El cifrado de disco de Aurora no basta (3.5.1.2). El PAN se guarda cifrado por la aplicación o como token. |
| DR-3 [ALL] | Todo almacenamiento cifrado con KMS CMK | Aurora, EBS, S3, EFS, Secrets Manager, secretos de Kubernetes (cifrado envolvente de EKS). |
| DR-4 [CDE] | Llaves por dominio de datos y ambiente | `alias/dcp/diners/prod/pagos/pan`, `alias/dcp/diners/prod/pagos/db`. Rotación anual automática. |
| DR-5 [CDE] | Separación de funciones en las llaves | Quien administra la llave no la usa. Key policy con roles de administrador y de uso separados. |
| DR-6 [CDE] | PIN, CVV, ARQC y traducción de PIN en HSM | AWS Payment Cryptography (PCI PIN, P2PE) o CloudHSM. |
| DR-7 [CDE] | Inventario de algoritmos y llaves (12.3.3) | Export de KMS y Payment Cryptography en la evidencia trimestral. |
| DR-8 [ALL] | Backups cifrados e inmutables | AWS Backup con vault lock en modo compliance, copia a cuenta de backup. |
| DR-9 [ALL] | Bloqueo de acceso público y cifrado obligatorio en S3 | Bloqueo a nivel de organización y política `aws:SecureTransport`. |
| DR-10 [CDE] | Descubrimiento de PAN fuera del CDE | Macie con detector de tarjetas sobre todos los buckets, mensual; resultado alimenta el scope (12.5.2). |

Ejemplo de key policy con separación de funciones:

```json
{
  "Statement": [
    {"Sid": "Admins", "Effect": "Allow",
     "Principal": {"AWS": "arn:aws:iam::<cuenta>:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_DCP-Security-KeyAdmin_*"},
     "Action": ["kms:Create*", "kms:Describe*", "kms:Enable*", "kms:Put*", "kms:Update*", "kms:Revoke*",
                "kms:Disable*", "kms:Get*", "kms:TagResource", "kms:ScheduleKeyDeletion"],
     "Resource": "*"},
    {"Sid": "Use", "Effect": "Allow",
     "Principal": {"AWS": "arn:aws:iam::<cuenta>:role/dcp-diners-prod-pagos-role-tokenizer"},
     "Action": ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"], "Resource": "*"}
  ]
}
```

---

## 9. Workloads y gestión de vulnerabilidades (Req. 5, 6 y 11.3)

| # | Control | Ejemplo concreto |
|---|---|---|
| VW-1 [CDE] | EKS Auto Mode con endpoint privado y versión soportada | Nodos gestionados por AWS, inmutables y con parches automáticos; `expireAfter` del NodePool para forzar renovación. |
| VW-2 [CDE] | Admisión de pods restringida | Pod Security Standards `restricted`; Kyverno u OPA Gatekeeper niegan privilegiados, hostPath y root. |
| VW-3 [CDE] | Solo imágenes firmadas desde Nexus | Firma con Notation y AWS Signer o cosign; política de admisión verifica la firma. |
| VW-4 [ALL] | Escaneo de vulnerabilidades continuo | Amazon Inspector en EC2, Lambda y en el pipeline (escaneo de SBOM de imágenes de Nexus, porque Inspector escanea ECR de forma nativa y aquí no se usa ECR). |
| VW-5 [CDE] | Parches críticos en 30 días o menos (6.3.3) | SLA medido desde la fecha del hallazgo en Inspector. |
| VW-6 [CDE] | Anti-malware y detección en runtime (5.2, 5.3) | GuardDuty Runtime Monitoring en EKS y EC2; Malware Protection para S3 en buckets de carga de archivos de comercios. |
| VW-7 [CDE] | Detección de cambios en archivos críticos (11.5.2) | Contenedores inmutables con raíz de solo lectura y nodos inmutables de Auto Mode; agente FIM en AS400 y servidores (sección 12). |
| VW-8 [CDE] | Seguridad del desarrollo (6.2) | SAST, SCA y escaneo de secretos en cada PR; DAST trimestral sobre APIs públicas. |
| VW-9 [CDE] | Escaneos y pruebas | Interno trimestral autenticado (11.3.1, 11.3.1.2); ASV externo trimestral (11.3.2); pentest anual y tras cambios significativos (11.4). |
| VW-10 [CDE] | Páginas de pago | Si se aloja una página de pago para comercios: inventario y autorización de scripts (6.4.3) y detección de cambios (11.6.1). |

---

## 10. Logging, detección y respuesta (Req. 10, 11.5 y 12.10)

### 10.1 Logging

- **[ALL]** CloudTrail de organización, multi-región, con validación de integridad, a Log Archive con S3 Object Lock.
- **[CDE]** Eventos de datos de CloudTrail en buckets S3 con datos de tarjeta y en KMS.
- **[CDE]** Logs obligatorios: VPC Flow Logs, WAF, API Gateway, Network Firewall (alertas y flujos), auditoría del plano de control de EKS, pgaudit de Aurora, Route 53 Resolver, VPN.
- **[CDE]** Retención: 12 meses, 3 meses disponibles de inmediato (10.5.1). Propuesta: 90 días en caliente, 12 meses en S3 con Object Lock, archivo a Glacier hasta 7 años si lo exige el regulador local.
- **[ALL]** Sincronización de hora con Amazon Time Sync (10.6).
- **[CDE]** Revisión diaria automatizada (10.4.1.1) y alerta ante falla de un control crítico de seguridad (10.7.2), por ejemplo GuardDuty o CloudTrail desactivado.

### 10.2 Detección

| Servicio | Configuración obligatoria |
|---|---|
| GuardDuty | Administrador delegado en `dinersclub-security`, auto-enable en toda la organización. Planes: S3, EKS (auditoría y runtime), RDS, Lambda, Malware Protection (EBS y S3). Extended Threat Detection activo. |
| Security Hub | Administrador delegado, agregación multi-región. Correlaciona CSPM, GuardDuty, Inspector y Macie en hallazgos de exposición. |
| Security Hub CSPM | Estándares: AWS Foundational Security Best Practices, CIS AWS Foundations y **PCI DSS v4.0.1** en cuentas CDE. |
| Inspector | EC2, Lambda y escaneo en CI/CD; hallazgos a Security Hub. |
| Macie | Descubrimiento automatizado de datos sensibles en toda la organización; detector de números de tarjeta. |
| AWS Config | Grabación continua en todas las cuentas; conformance pack *Operational Best Practices for PCI DSS 4.0* en cuentas CDE; agregador en `dinersclub-security`. |
| Detective | En `dinersclub-security` para investigación de hallazgos de GuardDuty. |
| Audit Manager | Framework PCI DSS v4.0 para recolectar evidencia del QSA. |

### 10.3 Respuesta

- **[ALL]** Plan de respuesta a incidentes (12.10) con runbooks por tipo de hallazgo: credencial expuesta, pod comprometido, PAN encontrado fuera del CDE (12.10.7), DDoS.
- **[CDE]** Contención automática con EventBridge y Step Functions para hallazgos de severidad alta: aislar instancia o pod con un SG o una política de red de cuarentena, revocar sesiones del rol.
- **[ALL]** Evaluar AWS Security Incident Response como apoyo 24x7 (sección 12).
- **[ALL]** Simulacro anual del plan.

### 10.4 Assessment paso a paso de la arquitectura actual

Se hace antes de aprobar este lineamiento y luego cada 6 meses. Cada paso produce evidencia y una lista de brechas.

| Paso | Qué revisar | Cómo (comandos y herramientas) | Evidencia y brecha típica |
|---|---|---|---|
| 0. Preparar | Alcance, inventario de cuentas, diagramas de flujo de datos de tarjeta, AOC de AWS | AWS Artifact (AOC PCI de AWS y matriz de responsabilidad); `aws organizations list-accounts`; diagrama de flujo de PAN por canal (emisión, adquirencia) | Cuentas sin clasificar CDE / conectada / fuera |
| 1. Identidad y acceso | Root, usuarios IAM, access keys, MFA, permission sets, roles con `AdministratorAccess`, SCP | `aws iam generate-credential-report` y `get-credential-report`; `aws accessanalyzer list-findings`; revisar permission sets en Identity Center; `aws organizations list-policies --filter SERVICE_CONTROL_POLICY` | Access keys en pipelines (encontradas en los repos del datalake), usuarios sin MFA, roles sobredimensionados |
| 2. Perímetro y DNS | Endpoints públicos, WAF, Shield, TLS, DNS | `aws apigateway get-rest-apis` y `get-domain-names`; `aws elbv2 describe-load-balancers` (scheme); `aws wafv2 list-web-acls` y `list-resources-for-web-acl`; `aws route53 list-hosted-zones`, `get-dnssec`; búsqueda de registros huérfanos | API Gateway público sin WAF, política TLS 1.0, zonas sin DNSSEC |
| 3. Conectividad de terceros | VPN, TGW, Network Firewall, PrivateLink | `aws ec2 describe-vpn-connections` (IKE, cifrados); `describe-transit-gateway-route-tables` y rutas propagadas; `aws network-firewall describe-firewall-policy`; `describe-vpc-endpoint-service-permissions` | Tercero que alcanza el CDE por propagación de rutas; firewall en modo *pass* por defecto |
| 4. Segmentación del CDE | SG, NACL, flujos reales | `aws ec2 describe-security-groups --filters Name=ip-permission.cidr,Values=0.0.0.0/0`; consultas a Flow Logs en Athena por origen fuera del CDE; VPC Reachability Analyzer y Network Access Analyzer con un *scope* "CDE ↔ no CDE" | Flujos del datalake hacia el CDE, SG con rangos amplios |
| 5. Workloads EKS | Endpoint, versión, NodeClass, políticas de red, Kyverno, identidad, imágenes | `aws eks describe-cluster` (endpointPublicAccess, logging, encryptionConfig); `kubectl get networkpolicies -A`; `kubectl get policyreport -A` (Kyverno); revisar la `NodeClass` (networkPolicy, subredes de pods); revisar nodos híbridos si existen | Namespaces sin política de red, políticas de Kyverno en modo audit, secretos sin cifrado envolvente |
| 6. Datos y llaves | Dónde está el PAN, cifrado, llaves, backups | Trabajo de descubrimiento de Macie; `aws rds describe-db-clusters` (StorageEncrypted, parámetro `rds.force_ssl`); `aws kms list-keys` y `get-key-rotation-status`, `get-key-policy`; búsqueda de PAN en esquemas de Aurora | PAN cifrado en el datalake, llaves sin rotación, backups sin vault lock |
| 7. Logging | CloudTrail, data events, Flow Logs, retención, inmutabilidad | `aws cloudtrail describe-trails` y `get-event-selectors`; Object Lock del bucket de Log Archive; retención de log groups | Retención < 12 meses, sin data events, logs de EKS desactivados |
| 8. Detección | GuardDuty, Security Hub, Inspector, Config, Macie en todas las cuentas y regiones | `aws guardduty list-detectors` y `get-detector` (features); `aws securityhub get-enabled-standards`; `aws inspector2 batch-get-account-status`; `aws configservice describe-configuration-recorder-status` | Regiones sin GuardDuty, PCI DSS v4.0.1 no habilitado en CSPM |
| 9. Vulnerabilidades y SDLC | Escaneos, pentest, pipeline | Prowler con el framework PCI 4.0 de AWS (confirmar el nombre con `prowler aws --list-compliance`); reporte de Inspector; últimos ASV y pentest | Sin ASV trimestral, imágenes sin firma, sin SAST |
| 10. Respuesta y resiliencia | Plan IR, runbooks, backups, DR | Revisión documental y de AWS Backup (`aws backup list-backup-vaults`, vault lock) | Plan sin simulacro, backups sin copia en otra cuenta |
| 11. Consolidar | Matriz de brechas por requisito PCI | Hoja de brechas: requisito, control, estado, severidad, dueño, fecha; exportar de Security Hub CSPM y Config | Plan de remediación priorizado |

---

## 11. Emisión y adquirencia: controles específicos

| Proceso | Control |
|---|---|
| Autorización de transacciones (emisor) | Verificación de CVV, iCVV, ARQC y PIN en Payment Cryptography o HSM; nunca en código de aplicación. |
| Personalización y emisión de tarjetas | Datos de personalización cifrados extremo a extremo hacia el bureau; llaves bajo ceremonia con custodios. |
| 3-D Secure (ACS) | Si Diners opera el ACS, aplica PCI 3DS además de PCI DSS. |
| Adquirencia con terminales (POS) | Terminales con P2PE; descifrado y traducción de PIN en Payment Cryptography (componente de descifrado P2PE registrado). |
| Comercios por API | Onboarding con mTLS o firma de requests; tokens de red de las marcas cuando aplique; WAF y rate limiting por comercio. |
| Liquidación y conciliación | Archivos con PAN truncado o tokenizado; transferencia por SFTP gestionado o PrivateLink, cifrado con PGP o KMS. |
| Terceros (12.8) | Inventario de proveedores con su AOC: Isovalent, Nexus, bureau de tarjetas, procesadores, marcas. |

---

## 12. Alternativas para decidir con Ciberseguridad

Cada fila es una decisión. La opción marcada con ★ es la recomendada para la v1. Decididas el 28/10/2026: protección DDoS y autenticación de socios. Pendiente de alinear con L16: exposición de Keycloak (detrás del borde intercambiable). Las demás se aprueban con Ciberseguridad.

| Decisión | Opción A | Opción B | Opción C | Criterio |
|---|---|---|---|---|
| Protección DDoS | ✔ Decidido: etapa 1 CloudFront + AWS WAF + Shield Advanced + Firewall Manager. | ✔ Decidido: etapa 2 Cloudflare; Shield Advanced se retira cuando Cloudflare absorba el DDoS. | Shield Standard + WAF. Menor costo, sin soporte en incidente. | L16 y contrato de Cloudflare |
| Autenticación de socios | ✔ Decidido: por internet, mTLS contra el borde (mTLS de viewer en CloudFront, API Shield en Cloudflare); el mTLS del custom domain queda reservado al borde. | ✔ Decidido: por VPN, API privada con resource policy por tercero y token de Keycloak. | Amazon Verified Access delante de las APIs internas. | L16 |
| Cliente móvil FAPI 2.0 | ★ App como cliente confidencial: registro por instalación tras Play Integrity, `private_key_jwt` y DPoP con llave en Keystore. | BFF confidencial en EKS; la app mantiene sesión con el BFF. | Cliente público con PKCE y DPoP. Más simple; no cumple FAPI 2.0. | Exigencia de FAPI 2.0 y esfuerzo en la app |
| Exposición de Keycloak (pendiente: alinear con el borde de L16) | ★ ALB + WAF con solo rutas OIDC. | CloudFront + WAF. | API Gateway REST como proxy. Agrega complejidad sin valor para un flujo de navegador. | Patrón de borde estándar |
| Cifrado dentro del clúster | ★ Cifrado Nitro entre instancias + TLS de aplicación en flujos con PAN. | TLS de aplicación en todos los servicios. | Malla de servicio (fase 3 de L13 v1.1: Istio ambient sobre Cilium); requiere CNI encadenado, validar soporte en Auto Mode. | Exigencia del QSA y esfuerzo en apps |
| Tokenización del PAN | ★ Servicio propio en el CDE con llaves en Payment Cryptography o CloudHSM. | Tokenización como servicio de un tercero certificado. Saca casi todo el PAN de Diners. | Tokens de red de la marca para comercios y wallets. Complemento, no reemplazo. | Costo, latencia, dependencia |
| HSM de pagos | ★ AWS Payment Cryptography (gestionado, PCI PIN y P2PE). | CloudHSM (FIPS 140-3 nivel 3, control total, más operación). | HSM on-premise (payShield) vía red híbrida. Ya existente; mantiene CDE en sitio. | Funciones de pago requeridas y estrategia on-premise |
| SIEM y correlación | ★ Security Lake + SIEM corporativo existente. | Security Hub + OpenSearch Security Analytics. | Security Hub como única consola. Insuficiente para revisión diaria y retención. | SIEM que use hoy el SOC |
| Detección de cambios en archivos (11.5.2) | ★ Contenedores y nodos inmutables + GuardDuty Runtime Monitoring + agente FIM en AS400 y servidores. | Falco o Tetragon como DaemonSet; validar que Auto Mode lo admita. | Agente comercial (EDR con FIM) donde la plataforma lo permita. | EDR corporativo vigente |
| Escaneo de imágenes | ★ Inspector en CI/CD (SBOM) + escaneo de Nexus. | Solo escáner de Nexus (Nexus IQ / Firewall). | Escáner comercial único para código, imágenes y runtime. | Licencias existentes |
| Acceso privilegiado a bases de datos | ★ Autenticación IAM + Identity Center + Session Manager. | PAM corporativo (CyberArk u otro) con grabación de sesión. | Secretos rotados de Secrets Manager con acceso por rol. | Requisitos de auditoría del QSA |
| Respuesta a incidentes | ★ Runbooks propios + AWS Security Incident Response. | Solo runbooks propios y SOC actual. | MSSP externo con acceso de solo lectura. | Cobertura 24x7 del SOC |

---

## 13. Dueño de cada control (repos)

| Control | Repo dueño | Ruta en el repo |
|---|---|---|
| SCP, RCP, Tag Policies, OU PCI | `dcp-aws-governance-live` | `organization/policies/` |
| GuardDuty, Security Hub, Inspector, Macie, Detective, Access Analyzer, Config, Audit Manager | `dcp-aws-security-live` | `live/security/us-east-1/<servicio>/` |
| CloudTrail, Log Archive, retención | `dcp-aws-security-live` | `live/log-archive/us-east-1/cloudtrail/`, `log-buckets/` y `retention/` |
| Firewall Manager, WAF, Shield | `dcp-aws-security-live` (políticas) + cuenta de integración (asociaciones) | `live/security/us-east-1/firewall-manager/` |
| Network Firewall, TGW, VPN, DNS Firewall, Route 53 | `dcp-aws-networking-live` | `live/networking/us-east-1/` |
| KMS, Payment Cryptography, Private CA | `dcp-aws-security-live` (llaves compartidas) y repo de workload (llaves de dominio) | según L02 |
| EKS Auto Mode, NodeClass, Kyverno, NetworkPolicy | `dcp-aws-shared-services-live` y plataforma EKS | según L13 |
| Keycloak (realm, políticas FAPI 2.0), ALB + WAF del IdP | `dcp-aws-shared-services-live` | `live/shared-services/us-east-1/ciam/` |
| Runners de CI/CD, proveedor OIDC y roles de despliegue (plan, apply-nonprod, apply-prod) | `dcp-aws-devops-live` | `live/devops/us-east-1/runners/` y `deployment-roles/` |
| Lambda authorizer, tabla DynamoDB de jti y sesiones revocadas | repo de la cuenta del API (integración) | `live/<cuenta>/us-east-1/api-auth/` |
| Módulos reutilizables (WAF, KMS, SG) | `dcp-terraform-modules` | `modules/security/` |

---

## 14. Validaciones en CI/CD

Se agregan a las de L06 y L11. El pipeline rechaza:

- Buckets S3 sin cifrado KMS, sin bloqueo de acceso público o sin política `aws:SecureTransport`.
- API Gateway público sin WAF asociado o con política TLS inferior a 1.2.
- Listeners de balanceador sin TLS en cuentas con `Compliance = pci-dss`.
- Aurora sin `StorageEncrypted`, sin `rds.force_ssl = 1` o con acceso público.
- Security Groups con `0.0.0.0/0` de entrada en cuentas CDE.
- Clústeres EKS con endpoint público, sin cifrado de secretos o sin logs de auditoría.
- Llaves KMS sin rotación o con `Principal: "*"` sin condición.
- Recursos en cuentas CDE sin tags `DataClassification` y `Compliance`.

Herramientas: Checkov con políticas propias, Conftest/OPA, y como verificación posterior al despliegue Security Hub CSPM y el conformance pack de Config.

---

## 15. Excepciones

Toda excepción sigue el L12 y además registra: requisito PCI afectado, control compensatorio (con el formato de la hoja de controles compensatorios de PCI DSS), análisis de riesgo dirigido (12.3.1) si aplica, dueño y fecha de expiración. Ninguna excepción se aprueba sin Ciberseguridad.

---

## 16. Fuentes

- [PCI SSC: PCI DSS v4.0.1 publicado](https://blog.pcisecuritystandards.org/just-published-pci-dss-v4-0-1)
- [AWS Security Hub FAQ: Security Hub, Security Hub CSPM y soporte PCI DSS v4.0.1](https://aws.amazon.com/security-hub/faqs)
- [Exposure findings en Security Hub](https://docs.aws.amazon.com/en_us/securityhub/latest/userguide/exposure-findings.html)
- [API Gateway: mTLS para REST APIs (no soportado en APIs privadas)](https://docs.aws.amazon.com/en_uk/apigateway/latest/developerguide/rest-api-mutual-tls.html)
- [API Gateway: custom domain para APIs privadas](https://aws.amazon.com/about-aws/whats-new/2024/11/amazon-api-gateway-custom-domain-name-private-rest-apis/)
- [AWS Payment Cryptography: casos de uso de adquirencia](https://docs.aws.amazon.com/payment-cryptography/latest/userguide/use-cases-acquirers.html)
- [AWS Payment Cryptography: casos de uso de emisión](https://aws.amazon.com/it/about-aws/whats-new/2024/10/aws-payment-cryptography-card-issuing-use-cases/)
- [GuardDuty Extended Threat Detection para EKS](https://aws.amazon.com/ko/blogs/korea/amazon-guardduty-expands-extended-threat-detection-coverage-to-amazon-eks-clusters)
- [FAPI 2.0 Security Profile (Final)](https://openid.net/specs/fapi-security-profile-2_0.html)
- [Keycloak 26.4: perfiles FAPI 2.0 y DPoP](https://www.keycloak.org/2025/09/keycloak-2640-released)
- [EKS Auto Mode: redes y NetworkPolicy](https://docs.aws.amazon.com/eks/latest/userguide/auto-networking.html)
- [Kyverno: política para agregar NetworkPolicy](https://kyverno.io/policies/best-practices/add-network-policy/add-network-policy)
