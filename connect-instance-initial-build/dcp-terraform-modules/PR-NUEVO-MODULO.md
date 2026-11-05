# Cómo agregar un módulo que no existe (ejemplo: compute/ec2-instance)

El módulo se crea en `dcp-terraform-modules`, **nunca** dentro del repo live del proyecto.

## 1. Antes de escribir código

- [ ] Confirmar que no existe un módulo equivalente (revisar `modules/` y `compatibility.yaml`).
- [ ] Abrir un issue con propósito, límites, owner y consumidores esperados.
- [ ] Si el recurso no tiene código de naming, pedir el alta en `catalogos-cloud.yaml` (aquí: `ec2`). Lo aprueba Arquitectura.

## 2. Estructura mínima (L03)

```
modules/compute/ec2-instance/
├── main.tf
├── variables.tf      # validaciones de catálogo en cada pieza del nombre
├── outputs.tf
├── versions.tf       # Terraform >= 1.15.8, < 1.16.0; aws >= 6.47.0, < 7.0.0
├── locals.tf         # nombres calculados según L07 a L10
├── README.md         # propósito, recursos, inputs, seguridad, costos, reemplazo
├── examples/
│   ├── basic/
│   └── production/
└── tests/
    └── ec2_instance.tftest.hcl
```

Reglas de diseño que este módulo cumple:

- No contiene IDs de cuenta, VPC, subred ni AMI: los lee de parámetros SSM publicados por Networking y Platform.
- No contiene secretos y rechaza `user_data` que parezca tenerlos.
- Aplica `Name` en cada recurso; los demás tags obligatorios llegan por `default_tags` del provider.
- Todo rol lleva el permission boundary `dcp-platform-permission-boundary`.

## 3. Pull request

El pipeline del repo de módulos corre, por cada módulo cambiado:

```
terraform fmt -check -recursive
terraform init -backend=false        # providers desde el mirror de Nexus
terraform validate
tflint --recursive                   # incluye la regla de naming con el código ec2
checkov -d modules/compute/ec2-instance
terraform test                       # provider simulado, sin credenciales AWS
```

Aprobación: 1 owner del módulo (`Grp_GH_Infrastructure`) y 1 de Arquitectura (`Grp_GH_Architecture`) porque agrega un código al catálogo.

## 4. Release

```bash
git tag -s compute/ec2-instance/v1.0.0 -m "compute/ec2-instance v1.0.0"
git push origin compute/ec2-instance/v1.0.0
git rev-list -n 1 compute/ec2-instance/v1.0.0   # SHA que va a compatibility.yaml
```

> Decidido (28/10/2026): el tag lleva la ruta del módulo (`<categoría>/<módulo>/vX.Y.Z`). `compatibility.yaml` sigue siendo la fuente del SHA que consumen los repos live.

## 5. Consumo desde el repo live

```hcl
terraform {
  source = "git::ssh://git@github.com/Diners/dcp-terraform-modules.git//modules/compute/ec2-instance?ref=<SHA de compatibility.yaml>"
}
```

Nunca `?ref=main`, `?ref=v1.0.0` ni una rama: el pipeline lo rechaza.
