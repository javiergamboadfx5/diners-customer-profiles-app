# Migracion desde la version anterior del modulo (app-carga-perfiles/infra), que creaba el dominio.
# En un estado nuevo estos bloques no hacen nada. En un estado que ya tenia esos recursos:
#   - removed: Terraform los saca del estado SIN borrarlos en AWS. El stack de Connect los importa despues.
#   - moved: el object type deja de tener count; se conserva sin reemplazo (reemplazarlo borraria los perfiles).
# Ver docs/MIGRACION-SANDBOX.md. Se pueden borrar cuando ningun estado tenga las direcciones antiguas.

removed {
  from = aws_customerprofiles_domain.socios
  lifecycle {
    destroy = false
  }
}

removed {
  from = awscc_customerprofiles_object_type.ctr
  lifecycle {
    destroy = false
  }
}

removed {
  from = awscc_customerprofiles_integration.connect
  lifecycle {
    destroy = false
  }
}

moved {
  from = awscc_customerprofiles_object_type.socio[0]
  to   = awscc_customerprofiles_object_type.socio
}
