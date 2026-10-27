# Despliega el stack de hosting y publica el build de la app.
# Uso: ./infra/deploy.ps1 -Profile sandbox -Ambiente dev
param(
  [string]$Profile = "sandbox",
  [string]$Region = "us-east-1",
  [ValidateSet("dev", "qa", "prod")][string]$Ambiente = "dev"
)
$ErrorActionPreference = "Stop"
$stack = "diners-carga-perfiles-$Ambiente"
$raiz = Split-Path $PSScriptRoot -Parent

aws cloudformation deploy --stack-name $stack --template-file "$PSScriptRoot/hosting.yaml" `
  --parameter-overrides "Ambiente=$Ambiente" --profile $Profile --region $Region --no-fail-on-empty-changeset
if ($LASTEXITCODE -ne 0) { throw "Fallo el deploy del stack" }

$out = aws cloudformation describe-stacks --stack-name $stack --profile $Profile --region $Region `
  --query "Stacks[0].Outputs" --output json | ConvertFrom-Json
$bucket = ($out | Where-Object OutputKey -eq "BucketSitio").OutputValue
$distId = ($out | Where-Object OutputKey -eq "DistribucionId").OutputValue
$url = ($out | Where-Object OutputKey -eq "UrlApp").OutputValue

Push-Location $raiz
try {
  npm run build
  if ($LASTEXITCODE -ne 0) { throw "Fallo el build" }
  # Assets con hash: cache largo. index.html: sin cache.
  aws s3 sync dist "s3://$bucket" --delete --exclude index.html --cache-control "public,max-age=31536000,immutable" --profile $Profile --region $Region
  aws s3 cp dist/index.html "s3://$bucket/index.html" --cache-control "no-cache" --profile $Profile --region $Region
  aws cloudfront create-invalidation --distribution-id $distId --paths "/index.html" --profile $Profile | Out-Null
} finally { Pop-Location }

Write-Host "Listo: $url"
