$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($env:AZURE_RESOURCE_GROUP)) {
    throw 'AZURE_RESOURCE_GROUP is required'
}

if ([string]::IsNullOrWhiteSpace($env:AZURE_AKS_CLUSTER_NAME)) {
    throw 'AZURE_AKS_CLUSTER_NAME is required'
}

$localBin = Join-Path $HOME '.local/bin'
New-Item -ItemType Directory -Force -Path $localBin | Out-Null
if (-not (($env:PATH -split [System.IO.Path]::PathSeparator) -contains $localBin)) {
    $env:PATH = "$localBin$([System.IO.Path]::PathSeparator)$env:PATH"
}

if (-not (Get-Command kubelogin -ErrorAction SilentlyContinue) -or -not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Host "Installing kubectl and kubelogin into $localBin..."
    $kubectlPath = Join-Path $localBin 'kubectl'
    $kubeloginPath = Join-Path $localBin 'kubelogin'
    az aks install-cli `
        --install-location $kubectlPath `
        --kubelogin-install-location $kubeloginPath | Out-Null
}

Write-Host "Fetching AKS credentials for $($env:AZURE_AKS_CLUSTER_NAME) in $($env:AZURE_RESOURCE_GROUP)..."
az aks get-credentials `
    --resource-group $env:AZURE_RESOURCE_GROUP `
    --name $env:AZURE_AKS_CLUSTER_NAME `
    --overwrite-existing

Write-Host 'Converting kubeconfig to reuse the azure-cli login (no interactive AAD prompt)...'
kubelogin convert-kubeconfig -l azurecli

Write-Host 'Verifying AKS nodes...'
kubectl get nodes
