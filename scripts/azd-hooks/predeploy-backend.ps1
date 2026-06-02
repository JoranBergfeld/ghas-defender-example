$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir '..\..')
Set-Location $repoRoot

function Require-Env([string] $Name) {
    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Missing required environment variable: $Name"
    }
}

function Expand-AzdTemplate([string] $Path) {
    $text = Get-Content -Path $Path -Raw
    return [regex]::Replace($text, '\{\{\s*\.Env\.([A-Za-z_][A-Za-z0-9_]*)\s*\}\}', {
        param($match)
        $name = $match.Groups[1].Value
        $value = [Environment]::GetEnvironmentVariable($name)
        if ([string]::IsNullOrWhiteSpace($value)) {
            throw "Missing required environment variable while rendering ${Path}: $name"
        }
        return $value
    })
}

Require-Env "AZURE_RESOURCE_GROUP"
Require-Env "AZURE_AKS_CLUSTER_NAME"
Require-Env "AZURE_BACKEND_IDENTITY_CLIENT_ID"
Require-Env "AZURE_POSTGRES_HOST"
Require-Env "AZURE_KEY_VAULT_URI"
Require-Env "AZURE_STATIC_WEB_APP_HOSTNAME"
Require-Env "SERVICE_BACKEND_IMAGE_NAME"

$localBin = Join-Path $HOME '.local/bin'
New-Item -ItemType Directory -Force -Path $localBin | Out-Null
if (-not (($env:PATH -split [System.IO.Path]::PathSeparator) -contains $localBin)) {
    $env:PATH = "$localBin$([System.IO.Path]::PathSeparator)$env:PATH"
}

if (-not (Get-Command kubelogin -ErrorAction SilentlyContinue) -or -not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    $kubectlPath = Join-Path $localBin 'kubectl'
    $kubeloginPath = Join-Path $localBin 'kubelogin'
    az aks install-cli `
        --install-location $kubectlPath `
        --kubelogin-install-location $kubeloginPath | Out-Null
}

az aks get-credentials `
    --resource-group $env:AZURE_RESOURCE_GROUP `
    --name $env:AZURE_AKS_CLUSTER_NAME `
    --overwrite-existing

kubelogin convert-kubeconfig -l azurecli

kubectl apply -f src/backend/k8s/namespace.yaml
Expand-AzdTemplate "src/backend/k8s/serviceaccount.tmpl.yaml" | kubectl apply -f -
kubectl apply -f src/backend/k8s/service.yaml
kubectl apply -f src/backend/k8s/ingress.yaml

$existingJob = kubectl get job flyway-init -n app --ignore-not-found
if (-not [string]::IsNullOrWhiteSpace($existingJob)) {
    kubectl delete job flyway-init -n app --wait=true
}

Expand-AzdTemplate "src/backend/k8s/flyway-job.tmpl.yaml" | kubectl apply -f -

kubectl wait --for=condition=complete job/flyway-init -n app --timeout=300s
if ($LASTEXITCODE -ne 0) {
    kubectl logs job/flyway-init -n app --all-containers=true
    exit 1
}

kubectl logs job/flyway-init -n app --all-containers=true
