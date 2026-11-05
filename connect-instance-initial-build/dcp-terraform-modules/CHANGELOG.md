# Changelog

## compute/ec2-instance v1.0.0

### Agregado
- Módulo nuevo para una instancia EC2 de aplicación en subredes app-private compartidas.
- Security Group propio con reglas por parámetro SSM o por SG; bloquea `0.0.0.0/0`.
- Rol IAM con permission boundary, Session Manager y política de runtime opcional (`rds-db:connect`, secretos propios).
- Log group `/dcp/<domain>/<env>/<workload>/<purpose>`.
- Publicación del SG como contrato en Parameter Store.
- Pruebas con `terraform test` y ejemplos `basic` y `production`.

### Dependencias de catálogo
- Agrega el código de recurso `ec2` a `catalogos-cloud.yaml` y a la regla TFLint de naming.

## data/aurora-postgresql v1.3.0

- (release existente; sin cambios en este PR)
