# Publica el build del frontend en el bucket que crea Terraform.
# Uso: ./infra/publicar-frontend.ps1 -Ambiente dev [-Profile <perfil>]
param(
  [ValidateSet("dev", "qa", "prod")][string]$Ambiente = "dev",
  [string]$Profile = $env:AWS_PROFILE
)
$ErrorActionPreference = "Stop"
$raiz = Split-Path $PSScriptRoot -Parent
$tf = Join-Path $PSScriptRoot "terraform/envs/$Ambiente"
if ($Profile) { $env:AWS_PROFILE = $Profile }

$salida = terraform -chdir="$tf" output -json app | ConvertFrom-Json
if (-not $salida.bucket_sitio) { throw "Sin outputs de Terraform en $tf. Ejecuta terraform apply primero." }

Push-Location $raiz
try {
  npm run build
  if ($LASTEXITCODE -ne 0) { throw "Fallo el build" }
  # Assets con hash: cache largo. index.html: sin cache. config.json lo administra Terraform.
  aws s3 sync dist "s3://$($salida.bucket_sitio)" --delete --exclude index.html --exclude config.json `
    --cache-control "public,max-age=31536000,immutable"
  aws s3 cp dist/index.html "s3://$($salida.bucket_sitio)/index.html" --cache-control "no-cache"
  aws cloudfront create-invalidation --distribution-id $salida.distribucion_id --paths "/index.html" | Out-Null
} finally { Pop-Location }

Write-Host "Publicado: $($salida.url_app)"
