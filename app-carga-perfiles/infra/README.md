# Infraestructura de la app de carga de perfiles

Terraform, un módulo (`terraform/modules/carga_perfiles`) con un root por ambiente (`terraform/envs/<ambiente>`).

## Arquitectura

```
Connect (workspace, iframe) ──> CloudFront ──┬─> S3 sitio (SPA + config.json)
                                             └─> /api/* ─> API Gateway HTTP (JWT Entra ID) ─> Lambda api
Navegador ──POST prefirmado──> S3 cargas/<id>/original.csv ──evento──> Lambda validador
                                   reporte.csv, hallazgos.json, validas.jsonl <──┘
Confirmar ─> Lambda encolador ─> SQS (25 filas/mensaje) ─> Lambda escritor ─> PutProfileObject
DynamoDB: cargas, historial, lock de una carga a la vez y versiones del esquema.
```

## Desplegar

1. Copia `terraform/envs/dev/terraform.tfvars.example` a `terraform.tfvars` y complétalo.
2. `terraform -chdir=infra/terraform/envs/dev init` y luego `plan` / `apply`.
3. Registra el output `redirect_uri` como Redirect URI (SPA) en el app registration de Entra ID.
4. `./infra/publicar-frontend.ps1 -Ambiente dev`.
5. En el admin website de Connect: UI Management > Workspaces, página «Carga de perfiles» con la app registrada.

Requisitos de la cuenta: Customer Profiles habilitado en la instancia y sin SCP que bloquee `profile:*` y `connect:*`.

## Pendiente

- Estado remoto: completar el `backend "s3"` según el pipeline de Diners.
- `.xlsx`: el backend acepta solo CSV; convertir en Lambda requiere empaquetar `openpyxl`.
- Las claves del object type (DNI → `AccountNumber`, UNIQUE) las define Terraform; cambiar el identificador en la pantalla de esquema no cambia la clave en AWS.
