#!/usr/bin/env sh
set -eu

: "${AZURE_RESOURCE_GROUP:?AZURE_RESOURCE_GROUP is required}"
: "${AZURE_AKS_CLUSTER_NAME:?AZURE_AKS_CLUSTER_NAME is required}"

LOCAL_BIN="${HOME}/.local/bin"
mkdir -p "${LOCAL_BIN}"
case ":${PATH}:" in
  *":${LOCAL_BIN}:"*) ;;
  *) PATH="${LOCAL_BIN}:${PATH}"; export PATH ;;
esac

if ! command -v kubelogin >/dev/null 2>&1 || ! command -v kubectl >/dev/null 2>&1; then
  echo "Installing kubectl and kubelogin into ${LOCAL_BIN}..."
  az aks install-cli \
    --install-location "${LOCAL_BIN}/kubectl" \
    --kubelogin-install-location "${LOCAL_BIN}/kubelogin" >/dev/null
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
