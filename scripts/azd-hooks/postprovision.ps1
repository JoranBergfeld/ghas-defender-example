$ErrorActionPreference = "Stop"

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

$certManagerVersion = "v1.15.3"
# If LETSENCRYPT_EMAIL is unset, the ClusterIssuer is created without a contact email.
# LE rejects placeholder domains (example.com, *.invalid, *.test). Set to a real email
# you control (or omit entirely) before running `azd up` in production.
$letsEncryptEmail = $env:LETSENCRYPT_EMAIL

Require-Env "AZURE_RESOURCE_GROUP"
Require-Env "AZURE_AKS_CLUSTER_NAME"
Require-Env "AZURE_BACKEND_IDENTITY_CLIENT_ID"
Require-Env "AZURE_STATIC_WEB_APP_NAME"

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

az aks get-credentials `
    --resource-group $env:AZURE_RESOURCE_GROUP `
    --name $env:AZURE_AKS_CLUSTER_NAME `
    --overwrite-existing `
    --admin

kubectl apply -f src/backend/k8s/namespace.yaml
Expand-AzdTemplate "src/backend/k8s/serviceaccount.tmpl.yaml" | kubectl apply -f -
kubectl apply -f src/backend/k8s/service.yaml

$swaHostname = az staticwebapp show `
    --resource-group $env:AZURE_RESOURCE_GROUP `
    --name $env:AZURE_STATIC_WEB_APP_NAME `
    --query defaultHostname `
    --output tsv

if ([string]::IsNullOrWhiteSpace($swaHostname)) {
    throw "Static Web Apps default hostname was empty"
}

azd env set AZURE_STATIC_WEB_APP_HOSTNAME $swaHostname

$location = az group show --name $env:AZURE_RESOURCE_GROUP --query location --output tsv
$md5 = [System.Security.Cryptography.MD5]::Create()
$hashBytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($env:AZURE_RESOURCE_GROUP))
$dnsLabel = "ghas-defender-" + (([System.BitConverter]::ToString($hashBytes) -replace '-','').ToLower().Substring(0,10))

kubectl annotate service nginx -n app-routing-system `
    "service.beta.kubernetes.io/azure-dns-label-name=$dnsLabel" `
    --overwrite | Out-Null

$ingressIp = ""
for ($attempt = 0; $attempt -lt 60; $attempt++) {
    $ingressIp = kubectl get service nginx -n app-routing-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
    if (-not [string]::IsNullOrWhiteSpace($ingressIp)) {
        break
    }
    Start-Sleep -Seconds 5
}

if ([string]::IsNullOrWhiteSpace($ingressIp)) {
    kubectl get service nginx -n app-routing-system -o wide
    throw "App Routing nginx LoadBalancer IP was not assigned within 5 minutes"
}

$ingressFqdn = ""
for ($attempt = 0; $attempt -lt 24; $attempt++) {
    $ingressFqdn = az network public-ip list `
        --query "[?ipAddress=='$ingressIp'].dnsSettings.fqdn | [0]" `
        --output tsv 2>$null
    if (-not [string]::IsNullOrWhiteSpace($ingressFqdn) -and $ingressFqdn -ne 'None') {
        break
    }
    Start-Sleep -Seconds 5
}

if ([string]::IsNullOrWhiteSpace($ingressFqdn) -or $ingressFqdn -eq 'None') {
    $ingressFqdn = "$dnsLabel.$location.cloudapp.azure.com"
}

azd env set AZURE_BACKEND_INGRESS_IP $ingressIp
azd env set AZURE_BACKEND_INGRESS_HOSTNAME $ingressFqdn
azd env set VITE_API_BASE_URL "https://$ingressFqdn"
$env:AZURE_BACKEND_INGRESS_HOSTNAME = $ingressFqdn

Write-Host "Installing cert-manager $certManagerVersion..."
kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/$certManagerVersion/cert-manager.yaml" | Out-Null
kubectl -n cert-manager rollout status deploy/cert-manager --timeout=180s | Out-Null
kubectl -n cert-manager rollout status deploy/cert-manager-cainjector --timeout=180s | Out-Null
kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=180s | Out-Null

$acmeEmailLine = if ([string]::IsNullOrWhiteSpace($letsEncryptEmail)) { "" } else { "    email: $letsEncryptEmail" }

$clusterIssuer = @"
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
$acmeEmailLine
    privateKeySecretRef:
      name: letsencrypt-prod-account
    solvers:
      - http01:
          ingress:
            ingressClassName: webapprouting.kubernetes.azure.com
"@
$clusterIssuer | kubectl apply -f -

Expand-AzdTemplate "src/backend/k8s/ingress.tmpl.yaml" | kubectl apply -f -

Write-Host "Waiting up to 5 minutes for Let's Encrypt cert (backend-tls)..."
$certReady = ""
for ($attempt = 0; $attempt -lt 60; $attempt++) {
    $certReady = kubectl get certificate backend-tls -n app -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>$null
    if ($certReady -eq "True") {
        break
    }
    Start-Sleep -Seconds 5
}

if ($certReady -ne "True") {
    Write-Warning "backend-tls certificate not Ready yet; HTTPS may be unavailable until cert-manager finishes"
    kubectl describe certificate backend-tls -n app
    kubectl get challenge -n app
} else {
    Write-Host "Let's Encrypt certificate backend-tls is Ready"
}

$backendExists = kubectl get deployment backend -n app 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Restarting backend deployment so it picks up rotated KeyVault secrets..."
    kubectl rollout restart deployment/backend -n app | Out-Null
    kubectl rollout status deployment/backend -n app --timeout=180s
}

Write-Host "Configured VITE_API_BASE_URL=https://$ingressFqdn"
Write-Host "Configured AZURE_STATIC_WEB_APP_HOSTNAME=$swaHostname"
