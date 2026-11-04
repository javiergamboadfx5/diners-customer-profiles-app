# 3P app de carga a Customer Profiles · qué preguntar al TL

Diners Club Perú · Modernización del contact center. 22 de octubre de 2026.
Contexto del proyecto en [CONTEXTO-PROYECTO.md](./CONTEXTO-PROYECTO.md).

Dos partes: primero **Customer Profiles explicado desde cero** (si es tu primera vez), después **las preguntas para el TL**, ordenadas por cuánto cambian el estimado.

---

# Parte 1 · Customer Profiles en corto

## El modelo mental

Customer Profiles **no es una tabla de datos**. Es el almacén de clientes de Amazon Connect, pensado para dar al asesor y al agente de IA una vista unificada del cliente durante la interacción.

| Concepto | Qué es |
|---|---|
| **Dominio** | El contenedor de todo. Uno por instancia de Connect. Define cifrado (KMS) y retención (`DefaultExpirationDays`) |
| **Perfil** | Un cliente. Trae campos **estándar** (`FirstName`, `LastName`, `PhoneNumber`, `EmailAddress`, `AccountNumber`, direcciones, `BirthDate`) más un saco `Attributes` de pares clave-valor para lo que sea tuyo |
| **Object type** | El esquema de ingesta. Mapea los campos de tu fuente a campos del perfil (`_source.x` → `_profile.y`) y **declara qué campos son claves de búsqueda** |
| **Plantillas** | Object types prearmados para orígenes conocidos: Salesforce, Zendesk, ServiceNow, Marketo y `_S3Connector` para datos propios desde S3 |

Encima de eso hay funciones que en este proyecto no se usan, pero conviene reconocer por nombre: **identity resolution** (fusión de duplicados por ML o por reglas), **atributos calculados** (sumas, promedios, primera y última ocurrencia), **segmentos**, **event triggers** y **recommenders**.

## Cómo entran los datos

Tres caminos, y la diferencia entre ellos es el centro de la discusión con el TL:

1. **Import de segmentos** (`CreateUploadJob`, o la UI de *Customer segments*). Sube un CSV, mapea columnas, crea o actualiza perfiles y los agrupa en un segmento.
2. **Integración de S3 con object type mapping** (`PutIntegration`). Defines el esquema una vez y Customer Profiles ingesta lo que cae en el bucket.
3. **API fila por fila** (`PutProfileObject`, `UpdateProfile`). Tu código hace el upsert.

## Cómo se leen los datos

- Desde un flujo: el bloque **Customer profiles** busca por **teléfono, correo o account ID** y devuelve los atributos del perfil como atributos del contacto. **No busca por un atributo personalizado arbitrario.**
- Desde el Agent Workspace: el panel de perfil se arma automáticamente contra el contacto entrante y muestra historial, casos y atributos. El layout se configura (*domain layouts*).
- Desde código: `SearchProfiles`, `GetProfile`, con `@aws-sdk/client-customer-profiles`.

## Números y comportamiento que importan

- Límites: 100M de perfiles y 1000 object types por dominio.
- Latencia: la búsqueda del perfil es de milisegundos; la ingesta y la resolución de identidad son **asíncronas**.
- Cifrado en reposo con KMS, incluida clave administrada por el cliente.
- Es **regional**: no se replica solo entre regiones.
- Se cobra **por perfil almacenado por mes** y por los jobs de identity resolution.
- GDPR: `DeleteProfile` para borrado, `DefaultExpirationDays` para retención automática.

## La idea que conviene no perder de vista

En este proyecto Customer Profiles es la **base maestra de socios**, no un caché ni un enriquecimiento opcional. Sin integraciones, es lo único que permite reconocer al socio, saludarlo por nombre, elegir el grupo de ejecutivos por segmento y decidir la ruta de anulación por la marca retener. Eso es lo que convierte cualquier detalle de retención o expiración en un problema de arquitectura y no en un detalle de configuración.

---

# Parte 2 · Preguntas para el TL

Validado contra la documentación de AWS; fuentes al final.

## Lo primero · «Solo carga inicial» cambia todo

El TL indicó que la app es **solo para la carga inicial**. Esa frase tiene dos lecturas y hay que cerrar cuál es antes de seguir, porque llevan a diseños distintos.

| Lectura | Qué significa | Consecuencia |
|---|---|---|
| **A. Corre una sola vez** | Se cargan los 176.865 socios al salir a producción y no hay recarga definida hasta la fase 2 | La base se congela y, si la ingesta es por import de segmentos, **desaparece en 90 días como máximo** |
| **B. Carga completa, re-ejecutable** | La app solo hace carga total de la base, no sincronización incremental ni deltas, pero Diners la corre cuando quiera | Es coherente con el resto del diseño y es lo que probablemente se quiso decir |

### Si es la lectura A, hay tres problemas

**La base se vence.** Con una sola carga no hay recarga mensual que la rescate. Si la ingesta usa `CreateUploadJob` (import de segmentos), los perfiles expiran en 14 días por defecto y 90 como máximo, y se borran del dominio. El agente dejaría de reconocer a los socios unos tres meses después de salir a producción. Esto convierte la elección del mecanismo de ingesta en una decisión bloqueante, no en un detalle: **solo la integración de S3 con object type mapping deja la retención en manos del `DefaultExpirationDays` del dominio.**

**Los datos se desactualizan donde más duele.** Tres campos del perfil cambian de forma constante:
- `tiene_oferta`: las ofertas de préstamo son campañas, cambian todos los meses. De ese campo dependen la oferta proactiva de N0 y toda la habilidad N2.
- `SEGMENTO_VALOR` y `MARCA_RETENER`: deciden el grupo de ejecutivos y la ruta de anulación. Un socio mal segmentado se enruta mal.
- `TELEFONO_1`: es el número al que los equipos especializados devuelven la llamada.

Y **D13**, las deudas cedidas a estudios de cobranza, por naturaleza rota: se ceden deudas nuevas y cambian los estudios. Una carga única la deja obsoleta en semanas, y el agente le estaría dando al socio el teléfono de un estudio equivocado.

**Construir una 3P app para una operación de una sola vez no cierra.** Si corre una vez, lo razonable es un script que DFX5 ejecuta de forma controlada: S3 más un job de ingesta, sin app embebida, sin hosting HTTPS, sin registro de origen en la instancia, sin backend con IAM, sin revisión de ciberseguridad y sin módulo de Terraform. Todo ese andamiaje se justifica porque **Diners la usa de forma recurrente sin depender de DFX5**, que es textualmente el argumento de la doc. Si no es recurrente, el esfuerzo está sobredimensionado y se puede reducir el alcance.

### Preguntas concretas

1. ¿Carga inicial significa una sola vez, o carga completa re-ejecutable cuando Diners lo decida?
2. Si es una sola vez: **¿cuál es el mecanismo de actualización entre la salida a producción y la fase 2 de marzo o abril de 2027?** Son varios meses con la base quieta.
3. ¿Quién actualiza `tiene_oferta` cuando cambia la campaña del mes, y D13 cuando se ceden deudas nuevas?
4. Si la respuesta es «lo recarga DFX5 cuando lo pidan», eso es justamente la dependencia que la app venía a eliminar. ¿Está aceptado?
5. Si la respuesta es «Diners lo recarga desde el admin website», entonces el camino nativo vuelve a estar sobre la mesa (ver sección 1) y la app podría no ser necesaria.
6. Con una sola carga, ¿el estimado de la app baja? Y al revés: ¿el costo mensual de Customer Profiles por 176.865 perfiles sigue estando igual (ver sección 6), porque los perfiles se almacenan se recarguen o no?

## 1. ¿Por qué una app propia si Connect ya tiene carga por CSV?

Amazon Connect trae una importación nativa: *Customer segments → Create segment → From file upload*. Sube un CSV (menos de 1 GB, UTF-8 **sin BOM**), mapea las columnas a atributos de perfil (sugerencia automática o manual), **crea o actualiza perfiles** y muestra un panel de progreso con nombre de archivo, fecha, filas procesadas, exitosas y fallidas, con opción de cancelar. Es casi exactamente lo que describe la doc de la 3P app.

### El acceso no es el problema: no hace falta la consola de AWS

Esto hay que tenerlo claro porque suele ser el argumento con el que se justifica la app, y no se sostiene.

La importación nativa **no vive en la consola de AWS**. Vive en el **admin website de Amazon Connect** (`https://<instancia>.my.connect.aws`), que es la misma URL de la instancia a la que Servicio al Socio entraría con sus credenciales, por SSO con Entra ID. Sin usuario IAM y sin consola de AWS.

El acceso se otorga con un **permiso de perfil de seguridad**, no con IAM: en *Security Profiles* se habilitan los permisos de **customer segments** de forma granular (**View, Create, Delete, Export**, o All). El permiso que habilita la carga es **`CustomerProfiles.Segments.Create`**. Se puede crear un perfil de seguridad que tenga **solo eso** y asignárselo a Servicio al Socio: la navegación del admin website se filtra por permisos, así que no verían flujos, colas ni usuarios.

Lo que sí queda como objeción legítima, y vale plantearla como tal y no como impedimento técnico: a Diners puede no gustarle que personal de Servicio al Socio entre al admin website, aunque sea con un perfil mínimo, por gobernanza. Esa es una decisión de Diners, no un límite de la herramienta.

### Los topes que sí descartan el camino nativo

| Límite nativo | Impacto en Diners |
|---|---|
| **Expiración del perfil: 14 días por defecto, máximo 90** | Los perfiles importados se borran del segmento **y del dominio** al expirar. Con carga mensual sobrevive, pero queda frágil: si Servicio al Socio se salta un mes, el agente deja de reconocer a los socios. Este es el argumento fuerte |
| **Crea un segmento como subproducto** | Semánticamente raro para mantener una base maestra: cada carga genera un segmento nuevo que nadie va a usar |
| **Mapea, pero no valida reglas de negocio** | El import nativo valida cabeceras y formato del archivo; no valida que el DNI tenga 8 dígitos ni que el teléfono tenga prefijo 51. Los 391 DNI con 4 o 9 dígitos entrarían igual |
| **Máximo 25 atributos mapeados** | Hoy serían 9 campos; alcanza, pero limita el crecimiento |

**Preguntar:** ¿la 3P app existe para esquivar la expiración de 90 días y para validar DNI y teléfono antes de escribir, o se asumió que el camino nativo exigía consola de AWS? Importa por dos razones: la justificación del acceso no aplica, y el `CreateUploadJob` del SDK es el mismo mecanismo del import de segmentos, así que **si la app lo usa por debajo arrastra la expiración de 90 días y no resuelve el problema de fondo**.

## 2. ¿Dónde vive la app? No el Agent Workspace, sino una página del sitio de Connect

Corrección del 23 de octubre: la app **no va en el Agent Workspace**. Va en el sitio de Amazon Connect Customer, donde Servicio al Socio entra con sus credenciales. Eso es posible, pero no con el mecanismo que describe la doc original.

**Un 3P app, por sí solo, solo corre en el Agent Workspace.** AWS lo dice sin matices: las aplicaciones de terceros se admiten únicamente en el agent workspace de Connect Customer, no en escritorios de agente personalizados. Se registran como una **integración** en la consola de AWS de Connect (*Integrations → Add integration*, tipo *Standard application*), con URL de acceso HTTPS, orígenes aprobados, *contact scope*, *initialization timeout* y asociación a la instancia. El asesor las abre desde el **Apps launcher**.

**El camino para que viva en el sitio de Connect es Workspaces.** En el admin website, *UI Management → Workspaces*: se crea un workspace con **páginas personalizadas** (hasta 17 por instancia), cada una con su nombre de menú, su *slug* en la URL y una **view** con el contenido. Y el dato que lo habilita todo: una view **puede contener componentes, entre ellos aplicaciones de terceros**. El workspace se asigna a usuarios o perfiles de enrutamiento concretos, admite logo, tipografía y colores de Diners, y aparece en el encabezado del usuario; si tiene uno solo asignado, se abre automáticamente.

O sea: Servicio al Socio entra a la URL de la instancia con Entra ID, ve en el menú izquierdo una página «Carga de perfiles» y nada más. No toca la consola de AWS ni el CCP, y no necesita ser asesor.

**Decidido: sin SDK.** La app no usa `@amazon-connect/*`. Connect solo la renderiza en un iframe; no necesita eventos de agente ni de contacto, que un usuario de Servicio al Socio no tiene. Eso saca del medio el único punto realmente incierto y deja el resto como configuración: registrar la integración, armar la view, crear la página del workspace y asignar permisos.

**La consecuencia a resolver: la app no sabe quién es el usuario.** Sin el SDK, Connect no le pasa identidad. Dos cosas se siguen de ahí:

- El registro de auditoría que pide la doc (fecha, **usuario**, filas cargadas y rechazadas) necesita que la app autentique por su cuenta. Lo natural es registrarla en **Entra ID** (OIDC con PKCE) y tomar el usuario de ahí. Es el mismo IdP con el que la persona ya inició sesión, así que no ve una segunda pantalla de login, pero es **otro app registration** en Entra ID: se le pide a Stephanie Santisteban junto con el del SSO de Connect.
- **Estar dentro de Connect no es autorización.** El iframe es una URL alcanzable: quien la tenga, llega. La autorización la hace el backend validando el token de Entra ID y la pertenencia a un grupo; el `frame-ancestors` solo evita que la embeban en otro sitio. Sin esto, un endpoint que escribe 176.865 perfiles queda expuesto.

**Lo que hay que configurar y verificar:**
- Que el componente de aplicación de terceros dentro de una view se renderice para un usuario **sin perfil de enrutamiento y sin contactos**. Es la única incógnita que queda y se resuelve probándolo en la cuenta de desarrollo.
- La app debe ser embebible: su `Content-Security-Policy` necesita `frame-ancestors https://<instancia>.my.connect.aws`. Si responde `same origin` o `deny`, Connect no la puede poner en un iframe.
- Permisos: el recurso *workspace* se habilita desde *Users and Permissions* del perfil de seguridad, y además hace falta el permiso de acceso de la aplicación. Son dos cosas distintas.
- La instancia debe usar un **Service-Linked Role** para poder agregar integraciones.
- Registrar la integración sí es una tarea en la consola de AWS, pero la hace una vez el administrador (DFX5 con Mary Carmen), no Servicio al Socio.

**La alternativa, si Workspaces se complica:** una aplicación web independiente detrás de Entra ID, sin embeber nada en Connect. Más simple de construir y desplegar, pero Diners termina con dos lugares a los que entrar y se pierde el argumento de «todo dentro de Amazon Connect».

### El backend que falta, en cualquiera de los dos casos

**Lo que no tiene: credenciales de AWS.** El iframe no puede llamar a la API de Customer Profiles directamente. Hace falta un backend propio: API Gateway + Lambda con rol IAM, y un bucket S3 para el archivo.

Nada de eso aparece en las definiciones técnicas ni en el estimado.

- ¿Dónde se aloja el frontend? ¿S3 + CloudFront en la cuenta de Diners, o infra de DFX5? Si es de DFX5, datos de 176 mil socios pasan por un dominio de un tercero y eso lo tiene que aprobar Kevin Licas.
- ¿Qué recursos extra se despliegan con Terraform (API Gateway, Lambda, bucket, rol, origen permitido en la instancia)? La lista actual de «qué se despliega como código» no los incluye.
- ¿Quién autoriza al usuario? El iframe sabe **quién** es el asesor; la autorización real (¿este usuario puede cargar 176 mil perfiles?) la hace el backend. ¿Contra grupos de Entra ID o contra perfiles de seguridad de Connect?
- Las funciones van en Python según lo confirmado por Luis, pero las definiciones dicen que «en la fase 1 no se prevén funciones con lógica de negocio». Esta app es lógica de negocio. ¿Se actualiza esa definición?

## 3. ¿Cómo escribe en Customer Profiles? Hay tres caminos y cuestan distinto

| Camino | Cómo funciona | Cuándo conviene |
|---|---|---|
| **Segment import / `CreateUploadJob`** | El mismo mecanismo de la UI nativa | Rápido de construir, pero hereda la expiración de 90 días |
| **Integración de S3 + object type mapping** | Se define un object type (plantilla `_S3Connector` o propio) y Customer Profiles ingesta lo que cae en el bucket. La retención la manda `DefaultExpirationDays` del dominio | Es el camino correcto para una base maestra de socios |
| **`PutProfileObject` / `UpdateProfile` fila por fila** | El backend recorre el archivo y hace upsert | Control fino de validación y de error por fila, pero hay que resolver throughput, reintentos e idempotencia para 176.865 filas |

**Preguntar:** ¿cuál de los tres asumió el estimado? Cambia bastante el esfuerzo, y el segundo es el único que no le pone fecha de vencimiento a la base.

## 4. El DNI tiene que ser clave de búsqueda, no un atributo cualquiera

El bloque *Customer profiles* de los flujos busca por **teléfono, correo o account ID**. El agente identifica por DNI, así que:

- El DNI debería mapearse a **`AccountNumber`** (campo estándar, indexado) o declararse como *profile key* en el object type. **No** quedar suelto en `Attributes.DNI`.
- Confirmar cómo hace el lookup el **agente de IA** (Connect AI Agents con herramientas MCP) frente al bloque clásico de flujo. Si usa el bloque, la decisión es obligatoria ahora: cambiar la clave después implica recargar los 176 mil perfiles.
- El teléfono también es candidato a clave, pero **5% viene vacío** y puede repetirse entre socios. No sirve como clave única.

## 5. Identity resolution: apagarla a propósito

Customer Profiles puede fusionar duplicados automáticamente con reglas de *matching* (nombre + teléfono, correo, account number) y resolución de conflictos por recencia o por fuente. Con una sola fuente de datos y el DNI como clave única, el auto-merge solo introduce riesgo: dos socios que comparten celular podrían terminar fusionados.

**Preguntar:** ¿`Matching.Enabled` queda en false? Si Diners lo quiere activo pensando en la fase 2, ¿con qué `MinAllowedConfidenceScoreForMerging` y qué `MatchingAttributesList`?

## 6. El costo de Customer Profiles no está en el estimado

Se cobra **por perfil almacenado por mes**, del orden de **USD 0,0025 por perfil** (*a verificar en la página oficial de precios para us-east-1*). Con 176.865 socios serían unos **USD 440 al mes** solo de almacenamiento.

El estimado de desarrollo entregado el 21 de octubre es de **USD 89,14 al mes** (400 chats, 400 llamadas, 1 DID) y no menciona Customer Profiles.

**Preguntar:** ¿el estimado productivo que tiene Giovanna sí lo incluye? Si no, corregirlo antes de que Rommel lo lleve a costos. Y definir si en la cuenta de desarrollo se carga la base completa o una muestra, porque ahí el costo es evitable.

## 7. Formato del archivo y reglas de validación

La tarea abierta dice «acordar el formato del Excel». Conviene cerrarla con esto sobre la mesa:

- **CSV en UTF-8 sin BOM.** La importación nativa rechaza el BOM con un error de cabecera faltante, y es exactamente lo que produce Excel en Windows al guardar como CSV. O se les entrega el procedimiento exacto a Servicio al Socio, o la app acepta `.xlsx` y convierte en el backend. Decidir cuál.
- Delimitador: Excel en español suele escribir **punto y coma**, no coma. Y definir comillas y escapes.
- Teléfono: ¿el archivo trae el prefijo 51 o lo agrega la app?
- **Qué pasa con una fila inválida:** ¿se descarta la fila y se cargan las demás, o se aborta el archivo completo? Hay **391 DNI con 4 o 9 dígitos**, 1,5% sin segmento y 5% sin teléfono.
- **Semántica de la carga: ¿upsert o reemplazo total?** Si un socio desaparece del archivo porque se dio de baja, ¿su perfil se borra, se marca o se queda? Hoy no está definido y cambia el comportamiento del agente.
- ¿Se puede deshacer una carga mal hecha?
- Retención: ¿qué `DefaultExpirationDays` tiene el dominio, y qué pasa con un perfil que deja de aparecer en las cargas?

## 8. Operación

- ¿Quién recibe el reporte de filas rechazadas y por dónde? La doc dice que la app «deja registro» (fecha, usuario, filas cargadas y rechazadas): ¿es una pantalla, un correo, un CSV descargable?
- ¿Dos personas pueden cargar a la vez? ¿Se bloquea una carga mientras otra corre?
- ¿Hay ambiente de pruebas de la app con datos reales, y con qué enmascarado? Ciberseguridad va a preguntarlo.
- ¿La carga de **D13** (deudas cedidas a estudios de cobranza) va en el mismo archivo o en uno aparte? Son dueños distintos (Diana) y frecuencias distintas.
- ¿Quién es el dueño operativo de la app una vez en producción, y qué pasa si falla una carga un sábado?

---

## Fuentes

- [Create segments from imported files in Connect Customer](https://docs.aws.amazon.com/connect/latest/adminguide/customer-segments-imported-files.html) — límites del CSV, mapeo de atributos, expiración del perfil
- [Assign security profile permissions to manage customer segments](https://docs.aws.amazon.com/connect/latest/adminguide/security-profile-customer-profile-segmentation.html) — permisos View, Create, Delete, Export de customer segments
- [Manage customer segments in Connect Customer](https://docs.aws.amazon.com/connect/latest/adminguide/customer-segments-managing-segments.html) — permiso `CustomerProfiles.Segments.Create`
- [Create and ingest customer data into Customer Profiles](https://docs.aws.amazon.com/connect/latest/adminguide/customer-profiles-object-type-mappings.html) — object type mapping e ingesta desde S3
- [CreateUploadJob (AWS CLI)](https://docs.aws.amazon.com/cli/latest/reference/customer-profiles/create-upload-job.html)
- [CreateUploadJobCommand (AWS SDK v3 para JavaScript)](https://docs.aws.amazon.com/AWSJavaScriptSDK/v3/latest/client/customer-profiles/command/CreateUploadJobCommand/)
- [Integrate third-party applications in the agent workspace](https://docs.aws.amazon.com/connect/latest/adminguide/3p-apps.html) — soporte solo en el agent workspace, tipos de integración, orígenes aprobados y requisito de iframe
- [Set up workspaces for your business users](https://docs.aws.amazon.com/connect/latest/adminguide/amazon-connect-workspaces.html) — workspaces, páginas personalizadas, views y asignación por usuario
- [Amazon Connect Agent Workspace Developer Guide](https://docs.aws.amazon.com/agentworkspace/latest/devguide/) — 3P apps, registro de origen, SDK
- Precio por perfil: referencia comunitaria en [re:Post](https://repost.aws/questions/QU0VKGoit1RPCdrP76Wr-mxQ/high-cost-for-the-amazon-connect-customer-profile). **Confirmar en la página oficial de precios de Amazon Connect.**

Contenido parafraseado de las fuentes citadas por restricciones de licenciamiento.
