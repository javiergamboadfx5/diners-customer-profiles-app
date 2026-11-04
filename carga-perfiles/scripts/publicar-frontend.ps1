# Compila el frontend y lo publica en el bucket del sitio que crea el stack.
# Lee los outputs del stack con el backend que este inicializado en terraform/stack.
# Uso: ./scripts/publicar-frontend.ps1 -Ambiente dev [-Profile <perfil>]
param(
  [Parameter(Mandatory)][ValidateSet("dev", "qa", "prod")][string]$Ambiente,
  [string]$Profile = $env:AWS_PROFILE
)
$ErrorActionPreference = "Stop"
$raiz = Split-Path $PSScriptRoot -Parent
$app = Join-Path $raiz "app"
$stack = Join-Path $raiz "terraform/stack"
if ($Profile) { $env:AWS_PROFILE = $Profile }

$salida = terraform -chdir="$stack" output -json app | ConvertFrom-Json
if (-not $salida.bucket_sitio) { throw "Sin outputs en $stack. Ejecuta init y apply del stack primero." }
# Evita publicar en otro ambiente si el backend inicializado no es el esperado.
if ($salida.ambiente -ne $Ambiente) {
  throw "El stack inicializado es '$($salida.ambiente)', no '$Ambiente'. Repite el init con envs/$Ambiente.s3.tfbackend."
}

Push-Location $app
try {
  npm ci
  if ($LASTEXITCODE -ne 0) { throw "Fallo npm ci" }
  npm run build
  if ($LASTEXITCODE -ne 0) { throw "Fallo el build" }
  # Assets con hash: cache largo. index.html: sin cache. config.json lo administra Terraform.
  aws s3 sync dist "s3://$($salida.bucket_sitio)" --delete --exclude index.html --exclude config.json `
    --cache-control "public,max-age=31536000,immutable"
  if ($LASTEXITCODE -ne 0) { throw "Fallo la sincronizacion con S3" }
  aws s3 cp dist/index.html "s3://$($salida.bucket_sitio)/index.html" --cache-control "no-cache"
  if ($LASTEXITCODE -ne 0) { throw "Fallo la copia de index.html" }
  aws cloudfront create-invalidation --distribution-id $salida.distribucion_id --paths "/index.html" | Out-Null
} finally { Pop-Location }

Write-Host "Publicado ($Ambiente): $($salida.url_app)"
