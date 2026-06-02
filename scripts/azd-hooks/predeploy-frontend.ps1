$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir '..\..')

if ([string]::IsNullOrWhiteSpace($env:VITE_API_BASE_URL)) {
    Write-Error "VITE_API_BASE_URL is not set; cannot build frontend with backend API target. Run 'azd provision' first (postprovision hook computes the value)."
    exit 1
}

$envFile = Join-Path $repoRoot 'src/frontend/.env.production'
"VITE_API_BASE_URL=$env:VITE_API_BASE_URL" | Out-File -FilePath $envFile -Encoding utf8

Write-Host "Wrote $envFile with VITE_API_BASE_URL=$env:VITE_API_BASE_URL"
