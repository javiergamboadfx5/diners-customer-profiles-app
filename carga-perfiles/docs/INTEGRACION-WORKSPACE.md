# Integración con Amazon Connect

Cómo se muestra la app dentro de Connect, y qué se probó en la cuenta sandbox (433193941444, instancia `de-monitoring-test`) el 29 de octubre de 2026.

## Cómo encuentra Connect la app

La view no guarda la URL de CloudFront. Guarda solo el nombre de la app, y Connect resuelve el resto:

```
View → componente External Application (App Name = diners-carga-perfiles-dev)
  → registro en AppIntegrations con ese nombre (lo crea connect.tf)
      AccessUrl = https://<cloudfront>/   ← de aquí sale la URL del iframe
  → comprueba: app asociada a la instancia + perfil de seguridad del usuario con ACCESS
  → <iframe src = AccessUrl + Path>
  → el navegador lo acepta porque la CSP de la app incluye frame-ancestors https://<alias>.my.connect.aws
```

Hay dos listas de orígenes y solo una aplica:

| Lista | Dónde | Aplica aquí |
|---|---|---|
| Approved origins de la app | Registro de la app (`approved_origins` en `connect.tf`) | Sí. Connect embebe la app |
| Approved domains de la instancia | Configuración de la instancia | No. Es para sitios que embeben el CCP o el chat |

## Resultado de las pruebas

| Dónde | Resultado |
|---|---|
| **Agent Workspace** (`https://<alias>.my.connect.aws/agent-app-v2/`), Apps launcher | ✅ La app abre |
| **Página de workspace** del admin website (UI Management → Workspaces), view de tipo *Workspace Page* con el componente External Application | ❌ «Invalid Link Path Configured. The link diners-carga-perfiles-dev is not reachable» |

Se descartó en la prueba:
- Nombre de la app: coincide exactamente, sin espacios.
- Asociación con la instancia: existe.
- Permiso: el perfil Admin tiene `ACCESS`.
- CloudFront: responde 200 con el `frame-ancestors` correcto y sin `X-Frame-Options`.
- Access URL sin `/` final: se corrigió y el error siguió.

La causa más probable es que el componente solo se renderiza dentro del Agent Workspace. Su texto de ayuda dice «only available to agents using the workspace», y AWS documenta que las apps de terceros solo se admiten en el agent workspace ([3p-apps](https://docs.aws.amazon.com/connect/latest/adminguide/3p-apps.html)). AWS no documenta este error. Es una inferencia, no una causa confirmada.

## Opciones

| Opción | Experiencia | Estado |
|---|---|---|
| **A. Agent Workspace + Apps launcher** | App embebida. Los usuarios de Servicio al Socio necesitan acceso al agent desktop (perfil de enrutamiento mínimo y permiso de CCP) | Funciona |
| **B. Página de workspace con un componente Link** | «Carga de perfiles» en el menú de Connect, y un botón que abre la app (`app.url_app`) en otra pestaña | Funciona por diseño. Sin probar |
| **C. Página de workspace con HTML Box y un `<iframe>`** | App embebida en la página | Sin probar. Lo más probable es que el componente sanitice el `<iframe>` o que la CSP del admin website lo bloquee. Aunque funcione, no está soportado y puede dejar de funcionar sin aviso |
| **D. Página de workspace que embebe un guide (componente Connect Application) cuya view contiene la app** | App embebida tras pulsar *Begin*. Cada apertura inicia un contacto de chat en segundo plano | Sin probar. Puede fallar por el mismo motivo que el componente directo |
| **E. Web independiente** | Fuera de Connect, detrás de Entra ID | Funciona. Se pierde el «todo dentro de Connect» |

En B y E la seguridad no cambia: la autorización la hace el backend con el token de Entra ID, no el hecho de estar dentro de Connect.

## Pasos para la opción A (la que funciona hoy)

1. Aplica el stack. Crea el registro de la app y su asociación a la instancia.
2. En el perfil de seguridad de los usuarios, sección **Agent Applications**, habilita `diners-carga-perfiles-<ambiente>`.
3. El usuario abre `https://<alias>.my.connect.aws/agent-app-v2/`, despliega el **Apps launcher** y elige la app.

## Pasos para una página de workspace (opciones B, C y D)

1. **UI Management → Create View** → propósito **Workspace Page** → **Create new**. Hace falta el permiso *Channels and flows → Views*.
2. Agrega un **Container** y, dentro, el componente de la opción elegida:
   - B: Link con la URL `app.url_app`.
   - C: HTML Box con `<iframe src="<app.url_app>/" style="width:100%;height:80vh;border:0" title="Carga de perfiles"></iframe>`.
   - D: Connect Application, namespace *Guide*, con el `ContactFlowId` de un flujo de tipo guide cuya *Show view* contenga el componente External Application.
3. **Publica** la view.
4. **UI Management → Workspaces → Add new workspace** → *Set page with custom page slug*: nombre `Carga de perfiles`, slug `carga-perfiles`, la view publicada.
5. Asigna el workspace primero solo a tu usuario (*Visible to assigned users*) y **refresca el navegador**.
6. Prueba también con un usuario **sin perfil de enrutamiento ni acceso al CCP**, que es el caso real de Servicio al Socio.

## SDK de Connect

El frontend usa `@amazon-connect/app` y `@amazon-connect/contact` para leer el usuario y su perfil de enrutamiento (permisos `User.Details.View` y `User.Configuration.View` en `connect.tf`). Fuera del Agent Workspace el SDK no recibe contexto, y la app sigue sin él en hasta 4 segundos. El filtro por perfil de enrutamiento es solo de interfaz. La autorización real es el token y el grupo.
