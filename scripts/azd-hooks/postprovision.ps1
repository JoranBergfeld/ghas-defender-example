$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($env:AZURE_RESOURCE_GROUP)) {
    throw 'AZURE_RESOURCE_GROUP is required'
}

if ([string]::IsNullOrWhiteSpace($env:AZURE_AKS_CLUSTER_NAME)) {
    throw 'AZURE_AKS_CLUSTER_NAME is required'
}

if (-not (Get-Command kubelogin -ErrorAction SilentlyContinue)) {
    Write-Host "kubelogin not found, installing kubectl and kubelogin via 'az aks install-cli'..."
    az aks install-cli | Out-Null
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
