# Diners Club Perú · Modernización del contact center — contexto rápido

Resumen para entrar en contexto sin leer toda la doc viva.
Fuente: `diners-flujos-tobe (13).html`, versión de trabajo 1.43 del 21 de octubre de 2026.

> Nota: la doc dice **Diners Club Perú** (IVR 615-1111, soles, SBS, Unibanca, feriados de Perú).
> Si en la reunión se habló de Ecuador, conviene confirmarlo antes de usarlo en material de preventa.

## 1. Qué es el entregable

Un **documento vivo** (HTML autocontenido, un solo archivo, sin dependencias) que publica todas las definiciones del proyecto para que Diners y DFX5 revisen lo mismo antes de construir. Tiene dos áreas:

- **Proyecto actual** (vigente, desde el 19 de octubre): sin integraciones.
- **Archivo**: la propuesta anterior con integraciones (hasta el 1 de octubre). No es alcance vigente.

Navegación por canal (**Voz** / **Chat WhatsApp**) y por vistas: Flujos, **Flujos agénticos**, Configuración, Técnico, Pendientes, Contactos. Cada paso tiene marca de origen del texto (Vigente / Adaptado / Propuesto por DFX5) y un control de revisión por paso.

## 2. Alcance del proyecto

Migración del IVR y del WhatsApp de **Covisian/Laraigo a Amazon Connect**, con un agente de IA generativa en lugar de menús.

- **Fase 1 (actual): sin integraciones transaccionales.** No hay saldos, movimientos, bloqueos, constancias ni validación de identidad en autoservicio. Lo que no se puede resolver se **deriva con contexto**, no con un enlace y adiós.
- **Fase 2 (marzo–abril 2027):** integraciones productivas con sistemas de Diners (CRM Dynamics, Unibanca, constancias, validación con teléfono / 4 últimos dígitos / PIN).
- Los datos del autoservicio vienen de **Customer Profiles** (archivo), **base de conocimiento en S3 + Amazon Q in Connect** y **dos tablas de datos de Connect** (campañas D03, enlaces D06).
- Las colas y los asesores actuales se mantienen. Bloqueos siguen yendo a **Unibanca** (transferencia externa).

## 3. Arquitectura, en una línea cada pieza

| Pieza | Servicio |
|---|---|
| Entrada chat | AWS End User Messaging (WhatsApp, sin proveedor intermedio) |
| Entrada voz | Desvío incondicional del 615-1111 a un número de Connect |
| Núcleo | Amazon Connect en **us-east-1**: agente de IA (Amazon Bedrock), 6 colas, tareas, horarios, grabación |
| Conocimiento | Bucket S3 de Diners indexado por **Amazon Q in Connect** (responde al agente y asiste al asesor) |
| Perfil del socio | **Amazon Connect Customer Profiles** (se carga por archivo) |
| Datos editables por negocio | Tablas de datos de Connect: D03 campañas, D06 enlaces |
| Puesto del asesor | Agent Workspace en navegador, SSO con **Entra ID (SAML)** |
| Supervisión | Contact Lens; registros de contacto exportados a S3 (Athena / QuickSight) |
| IaC | **Terraform**, repo DFX5 sincronizado al repo de Diners, pipeline DevOps de Diners. Funciones en Python |

## 4. Flujos agénticos (el foco)

Principios: sin menú pero con red de seguridad (si no entiende a la segunda, muestra opciones); **responder antes de derivar**; identificar como hoy con mejor trato; **capturar para el especialista**; dos tipos de paso a asesor; fuera de horario nada se pierde (queda como tarea); nada confidencial sin integración.

**Habilidades del agente (N0–N9):**

| ID | Habilidad |
|---|---|
| N0 | Bienvenida e identificación por documento |
| N1 | Preguntas frecuentes y campañas |
| N2 | Préstamo: captura y paso a asesor (sin simulación: BI no entrega TEA por socio) |
| N3 | Pagar, conocer la deuda y financiar consumos (deriva al app) |
| N4 | Robo, pérdida, bloqueo y constancia |
| N5 | Anulación de tarjeta con retención en el momento |
| N6 | Afiliación de servicios y reclamos |
| N7 | No socio |
| N8 | Paso al asesor: dos tipos de ascenso |
| N9 | Cierre y encuesta (3 preguntas definidas por Diners el 21 de octubre) |

**Dos tipos de ascenso a humano:**
1. *Solo chat, sin autenticación* → primera línea, para lo informativo o lo que no toca la cuenta.
2. *Chat y luego llamada* → el especialista (Ventas, UR, Reclamos) toma el chat con el contexto, valida con OTP y **llama al socio en el momento**.

**Colas (6, todas existentes en Diners):** Primera línea WhatsApp (17 asesores del proveedor, por segmento), Primera línea voz (35 proveedor + 28 in-house Elite/Premium), Segunda línea Ventas, UR Tarjetas, UR Seguros, Reclamos.
**Horarios:** autoservicio 24×7; colas de Diners lunes a sábado 9:00–18:00 (zona América/Lima, feriados de Perú como excepción); el pool de voz del proveedor también atiende domingos; Unibanca 24×7.

**Diferencias por canal:** en voz todo es por voz sin teclas (teclado solo como respaldo tras dos fallos) y los enlaces se envían al WhatsApp del número que llama con plantilla de Meta. En chat hay botones de sugerencia y tres atajos tras identificar: *Solicite su préstamo · Consulte su estado de cuenta · Financiamiento*.

**Plantillas de Meta:** hoy **no existe ninguna aprobada** en el Meta Business de Diners. DFX5 propone 11 y las somete con el acceso que dé Giovanna.

## 5. App de terceros (3P app) para cargar Customer Profiles

Definido el **21 de octubre**. Es el punto en el que hay que profundizar.

- **Qué es:** una aplicación construida por DFX5 que vive **dentro del sitio de Amazon Connect Customer**, no en el Agent Workspace (corregido el 23 de octubre: la doc viva dice Agent Workspace, pero Servicio al Socio entra al sitio de la instancia con sus credenciales). Se monta como página personalizada de un *workspace* de Connect. No es un proceso externo ni manual.
- **Para qué:** Servicio al Socio **sube el archivo** en el formato acordado, la app **valida columnas y formato de DNI y teléfono** y **actualiza Customer Profiles** sola. Deja **registro de cada carga**: fecha, usuario, filas cargadas y filas rechazadas.
- **Por qué importa:** Diners decide cuándo cargar, **sin depender de DFX5 ni de un proceso manual**. Reemplaza la carga mensual que hoy Servicio al Socio hace contra Laraigo.
- **Volumen de referencia:** **176.865 socios** al 20 de octubre (Base WhatsApp).
- **Dueño:** DFX5 construye (Juan Zapata); Servicio al Socio la usa.
- **Carga también D13**, la base de deudas cedidas a estudios de cobranza (documento, estudio, teléfono del estudio), como atributos del mismo perfil.

**Campos del perfil (D01):**

| Campo | Nota |
|---|---|
| `DNI` | Clave del perfil y de búsqueda. 8 dígitos; la base trae **391 registros con 4 o 9 dígitos** que hay que depurar |
| `NOMBRE_SOCIO` | Apellidos y nombres, para saludar por nombre |
| `SEGMENTO_VALOR` | 1 alto, 2 medio, 3 bajo. Decide el grupo de ejecutivos. **1,5% viene vacío** |
| `MARCA_RETENER` | 1 retener, 2 no retener. Decide la ruta de anulación |
| `TELEFONO_1` | Celular con prefijo 51, para la llamada de los equipos especializados. **5% viene vacío** |
| `tiene_oferta` | Por agregar, confirmado el 21. Dispara la oferta proactiva de préstamo |
| `tipo_producto` | Por agregar, confirmado el 21. Free, Hiraoka, Club, Miles, Special Edition, Carte Blanche |
| `correo` | Por agregar. Confirmaciones y constancias |
| `tea` | **No disponible.** BI no puede entregar la TEA por socio, así que el agente no simula |

**Abierto sobre la app de carga:**
- **Contradicción por resolver:** el TL indicó que la app es **solo para la carga inicial**, pero la doc dice que «Diners decide cuándo cargar, sin depender de DFX5 ni de un proceso manual», y campos como `tiene_oferta`, segmento, marca retener y D13 cambian de forma constante. Sin recarga la base se desactualiza y, según el mecanismo de ingesta, puede expirar a los 90 días. Ver el anexo.
- Formato del archivo: la doc dice **Excel**; en la reunión se habló de **CSV**. Está como tarea pendiente *«Acordar el formato del Excel de carga de perfiles (columnas y validaciones)»* — Juan Zapata con Diana Carolina Solano. Es el momento de fijar CSV vs XLSX, delimitador, encoding y columnas exactas.
- Frecuencia de carga y quién la autoriza.
- Depuración de los 391 DNI inválidos y de los campos vacíos: ¿rechazo de fila o carga parcial?
- Seguridad: Customer Profiles guarda solo lo que viene en el archivo (ID, documento, nombre, celular, correo, segmento, marcas). **Sin datos de tarjeta.** Falta el visto bueno de Kevin Licas (ciberseguridad).
- Perfiles de seguridad / grupos de Entra ID que habilitan la app a Servicio al Socio (pendiente general del SSO).

## 6. Pendientes que bloquean

1. **Respuestas de las consultas frecuentes** (catálogo de 36 preguntas recibido solo con las preguntas). Giovanna Montero con Formación, entregas parciales hasta el viernes 23 de octubre. Sin esto el agente solo responde membresía, salones VIP y financiamiento.
2. **Base de deudas cedidas a estudios de cobranza** (D13). Diana Carolina Solano.
3. **Formato del archivo de carga de perfiles** (ver arriba).
4. **¿El CRM tiene API para ingresar la constancia sin un humano?** Mary Carmen Vílchez. Si no, la tarea va directo a back office.
5. Documentación de templates y pipelines de Terraform, antes del primer módulo.
6. Grupos de Entra ID → perfiles de seguridad de Connect; requisitos de red del puesto (WebRTC).
7. Traspaso del número productivo de WhatsApp sin perder la verificación de la cuenta.
8. Enlaces faltantes en D06: URL de pago y tutorial del app (6 de 8 entregadas).

## 7. Quién es quién

**Diners:** Patricia Santa Cruz (PMO), Giovanna Montero (dueña funcional, Meta Business), Diana Carolina Solano (entregables funcionales), Mary Carmen Vílchez (líder técnica), Kevin Licas (ciberseguridad), Rommel Kerrigan / Gian Mark Nuñez / José Enrique La Torre / Stephanie Santisteban (infraestructura), Edgar (DevOps), Luis (desarrollo).
**DFX5:** Juan Zapata (líder técnico, arquitectura, diseño agéntico, esta doc), Alejandro Muzzi (gestión), Luis Guevara (Track 2, integraciones).
**AWS:** Yesith Cárdenas Herrera.

## 8. Datos de costo y cronograma

- Desarrollo: **USD 89,14/mes** durante la construcción (400 chats, 400 llamadas, 1 DID, telefonía de referencia de EE. UU., sin impuestos).
- Producción: estimado entregado a Diners, incluye telefonía, WhatsApp con costo de Meta e IA. Amazon Connect no cobra licencias.
- Umbral de alta demanda: 30 llamadas o 15 chats en espera (el triple del actual).
- Sin NDA nuevo: DFX5 trabaja bajo el acuerdo de confidencialidad Diners–AWS.
- Fase 2 prevista entre marzo y abril de 2027.

## 9. Profundización

- [3P-APP-CARGA-CUSTOMER-PROFILES.md](./3P-APP-CARGA-CUSTOMER-PROFILES.md) — Customer Profiles explicado desde cero y las preguntas abiertas de la app de carga (carga nativa vs app propia, backend, clave de búsqueda, identity resolution, costo, formato del archivo).
