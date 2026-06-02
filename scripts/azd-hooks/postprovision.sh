#!/usr/bin/env sh
set -eu

: "${AZURE_RESOURCE_GROUP:?AZURE_RESOURCE_GROUP is required}"
: "${AZURE_AKS_CLUSTER_NAME:?AZURE_AKS_CLUSTER_NAME is required}"

if ! command -v kubelogin >/dev/null 2>&1; then
  echo "kubelogin not found, installing kubectl and kubelogin via 'az aks install-cli'..."
  az aks install-cli >/dev/null
fi

echo "Fetching AKS credentials for ${AZURE_AKS_CLUSTER_NAME} in ${AZURE_RESOURCE_GROUP}..."
az aks get-credentials \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --name "${AZURE_AKS_CLUSTER_NAME}" \
  --overwrite-existing

echo "Converting kubeconfig to reuse the azure-cli login (no interactive AAD prompt)..."
kubelogin convert-kubeconfig -l azurecli

echo "Verifying AKS nodes..."
kubectl get nodes
