# Carga de perfiles · Diners Club Perú

App para que Servicio al Socio cargue la base de socios en Amazon Connect Customer Profiles: sube un CSV o un Excel, revisa la validación fila por fila, confirma, y la app escribe los perfiles.

Esta carpeta es autocontenida: se copia tal cual al repositorio de infraestructura del proyecto. Incluye el código de la app, el módulo de Terraform, el stack que lo despliega, el script de publicación del frontend y la documentación.

## Contenido

```
carga-perfiles/
├── app/                          código de la app
│   ├── src/, index.html, package.json, vite.config.ts …   frontend (React + Cloudscape)
│   ├── backend/                  Lambdas en Python 3.12 + esquema-inicial.json
│   └── datos-ejemplo/            archivos de prueba (5 socios ficticios)
├── terraform/
│   ├── modules/carga_perfiles/   módulo de la app
│   └── stack/                    root module que se despliega por ambiente
│       └── envs/                 dev.tfvars.example, dev.s3.tfbackend.example
├── scripts/publicar-frontend.ps1 build del frontend + sync a S3 + invalidación de CloudFront
└── docs/
    ├── ARQUITECTURA.md           diseño de la app (frontend, backend, datos, seguridad, operación)
    ├── CONTRATO-STACK-CONNECT.md lo que este stack necesita del stack de Connect, y lo que le entrega
    ├── INTEGRACION-WORKSPACE.md  cómo se muestra la app dentro de Connect y qué se probó
    └── MIGRACION-SANDBOX.md      cómo pasar el despliegue existente del sandbox a esta versión
```

Todas las rutas son relativas a la carpeta. El stack encuentra el backend en `../../app/backend`, así que se puede mover `carga-perfiles/` a cualquier lugar del repo sin tocar código. Si el repo separa los módulos del código, cambia solo `directorio_backend` en `terraform/stack/main.tf`.

## Qué despliega este stack y qué no

| Lo despliega este stack | Lo despliega el stack de Connect |
|---|---|
| CloudFront, bucket del sitio, `config.json` | Instancia de Connect |
| API Gateway HTTP con autorizador JWT, 4 Lambdas, SQS + DLQ | **Dominio de Customer Profiles** y su KMS |
| DynamoDB (cargas, lock, esquema), bucket de cargas, KMS de la app | Object type `CTR` y vínculo dominio ↔ instancia |
| Object type `DinersSocio` (el esquema de socios dentro del dominio) | Perfiles de seguridad (incluido el acceso a esta app) |
| Registro de la app en Connect (AppIntegrations) y su asociación a la instancia | Workspaces, views y páginas, si se gestionan como código |
| Alarmas de la DLQ y de errores de las Lambdas | |
| Cognito de pruebas (opcional, solo dev) | |

El detalle de las variables y de los outputs que se intercambian está en [docs/CONTRATO-STACK-CONNECT.md](docs/CONTRATO-STACK-CONNECT.md).

## Requisitos

- Terraform 1.7 o superior, AWS CLI v2, Node.js 20 y PowerShell 7 (para el script de publicación).
- Stack de Connect ya aplicado: la instancia y el dominio de Customer Profiles tienen que existir.
- La instancia usa un Service-Linked Role. Las instancias nuevas ya lo usan.
- Ningún SCP de la cuenta bloquea `connect:*`, `profile:*` ni `app-integrations:*`.
- Para producción: app registration de Entra ID (SPA con PKCE y la API expuesta), con `accessTokenAcceptedVersion: 2`.

## Despliegue

Los comandos se ejecutan desde la carpeta `carga-perfiles/`, con las credenciales de la cuenta destino en el entorno (`AWS_PROFILE` o el rol del pipeline).

1. **Configurar el ambiente.** Copia los ejemplos y complétalos con los outputs del stack de Connect:
   ```powershell
   Copy-Item terraform/stack/envs/dev.tfvars.example terraform/stack/envs/dev.tfvars
   Copy-Item terraform/stack/envs/dev.s3.tfbackend.example terraform/stack/envs/dev.s3.tfbackend
   ```
   Los `.tfvars` y `.s3.tfbackend` reales están en `.gitignore`. Si el repo los versiona, quita esas líneas: no contienen secretos.

2. **Inicializar y revisar el plan.**
   ```powershell
   terraform -chdir=terraform/stack init -backend-config=envs/dev.s3.tfbackend
   terraform -chdir=terraform/stack plan -var-file=envs/dev.tfvars -out=dev.tfplan
   ```
   En un ambiente nuevo el plan crea unos 60 recursos y no modifica ni destruye ninguno. Si aparece un `destroy` sobre `awscc_customerprofiles_object_type.socio`, detente: reemplazarlo borra los perfiles. El `prevent_destroy` lo bloquea igual.

3. **Aplicar.**
   ```powershell
   terraform -chdir=terraform/stack apply dev.tfplan
   ```

4. **Entra ID.** Registra el output `app.redirect_uri` como Redirect URI (SPA) en el app registration.

5. **Publicar el frontend.**
   ```powershell
   ./scripts/publicar-frontend.ps1 -Ambiente dev
   ```
   El script comprueba que el stack inicializado corresponda al ambiente indicado antes de subir nada.

6. **Dar acceso a la app en Connect.** En el perfil de seguridad de los usuarios, sección **Agent Applications**, habilita la app (`app.nombre_app_connect`). Sin este permiso Connect no la muestra. Si los perfiles de seguridad son código del stack de Connect, usa el output `application_arn` (ver el contrato).

7. **Mostrarla en Connect.** Sigue [docs/INTEGRACION-WORKSPACE.md](docs/INTEGRACION-WORKSPACE.md). Resumen: dentro del Agent Workspace funciona. En una página de workspace del admin website, el componente de app de terceros no se renderiza, y hay alternativas descritas en ese documento.

Para otro ambiente, repite los pasos con `envs/qa.*` o `envs/prod.*`. Cada ambiente tiene su propio estado.

### Usuario de prueba con Cognito (solo dev)

Con `crear_cognito_pruebas = true`, el stack crea un user pool en lugar de usar Entra ID. Los usuarios se crean por CLI después del apply, así las contraseñas no quedan en el estado:

```powershell
$pool = (terraform -chdir=terraform/stack output -json app | ConvertFrom-Json).cognito_user_pool_id
aws cognito-idp admin-create-user --user-pool-id $pool --username usuario@dfx5.com --user-attributes Name=email,Value=usuario@dfx5.com Name=email_verified,Value=true
aws cognito-idp admin-add-user-to-group --user-pool-id $pool --username usuario@dfx5.com --group-name carga-perfiles
```

## Cambios respecto de `app-carga-perfiles/infra`

- El módulo ya **no crea el dominio** de Customer Profiles, el object type `CTR` ni el vínculo dominio ↔ instancia. Se eliminaron `crear_dominio_perfiles`, `plantilla_contactos` y `habilitar_customer_profiles`. `dominio_perfiles` ahora es obligatorio.
- El módulo recibe la ruta del backend (`directorio_backend`) en lugar de calcularla con `../../../..`.
- El stack reemplaza la variable `app` de tipo `any` por variables tipadas y usa un backend S3 parcial por ambiente.
- La access URL registrada en Connect termina en `/`. El componente de la view arma la URL como access URL más el path.
- Outputs nuevos: `nombre_app_connect`, `application_arn` y `lambda_role_arn`.
- `migracion.tf` permite aplicar esta versión sobre un estado anterior sin borrar el dominio. Ver [docs/MIGRACION-SANDBOX.md](docs/MIGRACION-SANDBOX.md).

El código de la app (`app/`) es una copia sin cambios de `app-carga-perfiles/`.
