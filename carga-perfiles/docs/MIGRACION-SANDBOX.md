# Migración del despliegue del sandbox

En la cuenta sandbox (433193941444) la app está desplegada con la versión anterior, `app-carga-perfiles/infra/terraform/envs/dev`, que usa **estado local**. Esa versión creó el dominio `amazon-connect-de-monitoring-test`, el object type `CTR` y el vínculo con la instancia. Esta guía pasa ese despliegue a la nueva versión sin borrar el dominio ni los perfiles.

Para un ambiente nuevo (qa, prod o el repo del proyecto desde cero) no se necesita nada de esto: se despliega primero el stack de Connect y después este stack.

**Nada de esto se ha ejecutado.** Revisa cada plan antes de aplicar.

## Qué cambia en el estado

| Recurso (dentro de `module.carga_perfiles`) | Qué hace el plan | Por qué |
|---|---|---|
| `aws_customerprofiles_domain.socios[0]` | Lo **olvida**: sale del estado y sigue en AWS | `removed` con `destroy = false` en `migracion.tf` |
| `awscc_customerprofiles_object_type.ctr[0]` | Lo olvida | Igual |
| `awscc_customerprofiles_integration.connect[0]` | Lo olvida | Igual |
| `awscc_customerprofiles_object_type.socio[0]` | Lo **mueve** a `socio`, sin reemplazo | `moved` en `migracion.tf` |
| Lambdas | Posible actualización en el mismo lugar | El zip se genera en otra ruta. Si el contenido es igual, el hash no cambia |
| Todo lo demás | Sin cambios | Mismas direcciones y mismos valores |

El plan esperado tiene **0 recursos a destruir**. Si muestra alguno, detente.

## Pasos

1. **Respalda el estado actual.**
   ```powershell
   Copy-Item app-carga-perfiles/infra/terraform/envs/dev/terraform.tfstate "terraform.tfstate.respaldo-$(Get-Date -Format yyyyMMdd-HHmm)"
   ```

2. **Usa estado local en el stack nuevo.** El stack trae `backend "s3" {}`. Para el sandbox, crea `carga-perfiles/terraform/stack/local_override.tf` (está en `.gitignore`):
   ```hcl
   terraform {
     backend "local" {}
   }
   ```
   Copia el estado:
   ```powershell
   Copy-Item app-carga-perfiles/infra/terraform/envs/dev/terraform.tfstate carga-perfiles/terraform/stack/terraform.tfstate
   ```

3. **Crea `envs/dev.tfvars`** con los valores del sandbox:
   ```hcl
   ambiente               = "dev"
   connect_instance_alias = "de-monitoring-test"
   connect_instance_arn   = "arn:aws:connect:us-east-1:433193941444:instance/04a65692-6cd7-4056-bba9-2a3939b71da9"
   dominio_perfiles       = "amazon-connect-de-monitoring-test"
   # El dominio del sandbox está cifrado con la KMS de la app (alias/diners-carga-perfiles-dev). Su ARN:
   #   aws customer-profiles get-domain --domain-name amazon-connect-de-monitoring-test --query DefaultEncryptionKey
   kms_dominio_perfiles_arn = "<arn-devuelto>"
   crear_cognito_pruebas    = true
   concurrencia_escritura   = 2
   ```

4. **Plan.**
   ```powershell
   $env:AWS_PROFILE = "sandbox"
   terraform -chdir=carga-perfiles/terraform/stack init
   terraform -chdir=carga-perfiles/terraform/stack plan -var-file=envs/dev.tfvars -out=dev.tfplan
   ```
   Comprueba la tabla de arriba: 3 recursos olvidados, 1 movido y 0 destruidos.

5. **Apply** del plan revisado y retira la carpeta anterior. No vuelvas a ejecutar `terraform` en `app-carga-perfiles/infra/terraform/envs/dev`: su estado ya no representa la realidad.

6. **Que el stack de Connect adopte el dominio.** Con bloques `import` en ese stack. Los formatos de ID de `awscc` siguen el identificador primario de CloudFormation. Verifícalos con `terraform plan` antes del apply:
   ```hcl
   import {
     to = aws_customerprofiles_domain.connect
     id = "amazon-connect-de-monitoring-test"
   }
   import {
     to = awscc_customerprofiles_object_type.ctr
     id = "amazon-connect-de-monitoring-test|CTR"
   }
   import {
     to = awscc_customerprofiles_integration.connect
     id = "amazon-connect-de-monitoring-test|arn:aws:connect:us-east-1:433193941444:instance/04a65692-6cd7-4056-bba9-2a3939b71da9"
   }
   ```

## Riesgo: la KMS del dominio del sandbox es de la app

En el sandbox, el dominio está cifrado con la KMS que crea este stack (`aws_kms_key.app`). Mientras eso no cambie:

- **No destruyas este stack.** El destroy programa el borrado de la KMS, y a los 30 días el dominio queda ilegible.
- Si el stack de Connect importa el dominio, su `default_encryption_key` tiene que apuntar a esa misma KMS, o el plan intentará cambiarla.

La solución de fondo es que el stack de Connect cree su propia KMS para el dominio. En el sandbox lo más simple es crear un dominio nuevo desde el stack de Connect y volver a cargar los socios de prueba, en lugar de migrar el existente.
