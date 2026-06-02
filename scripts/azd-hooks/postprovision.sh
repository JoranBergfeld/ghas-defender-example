#!/usr/bin/env sh
set -eu

: "${AZURE_RESOURCE_GROUP:?AZURE_RESOURCE_GROUP is required}"
: "${AZURE_AKS_CLUSTER_NAME:?AZURE_AKS_CLUSTER_NAME is required}"

echo "Fetching AKS credentials for ${AZURE_AKS_CLUSTER_NAME} in ${AZURE_RESOURCE_GROUP}..."
az aks get-credentials \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --name "${AZURE_AKS_CLUSTER_NAME}" \
  --overwrite-existing

echo "Verifying AKS nodes..."
kubectl get nodes
