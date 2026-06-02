$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($env:AZURE_RESOURCE_GROUP)) {
    throw 'AZURE_RESOURCE_GROUP is required'
}

if ([string]::IsNullOrWhiteSpace($env:AZURE_AKS_CLUSTER_NAME)) {
    throw 'AZURE_AKS_CLUSTER_NAME is required'
}

Write-Host "Fetching AKS credentials for $($env:AZURE_AKS_CLUSTER_NAME) in $($env:AZURE_RESOURCE_GROUP)..."
az aks get-credentials `
    --resource-group $env:AZURE_RESOURCE_GROUP `
    --name $env:AZURE_AKS_CLUSTER_NAME `
    --overwrite-existing

Write-Host 'Verifying AKS nodes...'
kubectl get nodes
