#!/usr/bin/env sh
set -eu

require_env() {
  name="$1"
  eval "value=\${$name:-}"
  if [ -z "$value" ]; then
    echo "Missing required environment variable: $name" >&2
    exit 1
  fi
}

render_template() {
  template_path="$1"
  python3 - "$template_path" <<'PY'
import os
import re
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    text = handle.read()

pattern = re.compile(r"\{\{\s*\.Env\.([A-Za-z_][A-Za-z0-9_]*)\s*\}\}")

def replace(match):
    name = match.group(1)
    value = os.environ.get(name)
    if value is None or value == "":
        raise SystemExit(f"Missing required environment variable while rendering {path}: {name}")
    return value

print(pattern.sub(replace, text), end="")
PY
}

require_env AZURE_RESOURCE_GROUP
require_env AZURE_AKS_CLUSTER_NAME
require_env AZURE_BACKEND_IDENTITY_CLIENT_ID
require_env AZURE_STATIC_WEB_APP_NAME

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

az aks get-credentials \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --name "$AZURE_AKS_CLUSTER_NAME" \
  --overwrite-existing

kubelogin convert-kubeconfig -l azurecli

kubectl apply -f src/backend/k8s/namespace.yaml
render_template src/backend/k8s/serviceaccount.tmpl.yaml | kubectl apply -f -
kubectl apply -f src/backend/k8s/service.yaml
kubectl apply -f src/backend/k8s/ingress.yaml

SWA_HOSTNAME="$(az staticwebapp show \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --name "$AZURE_STATIC_WEB_APP_NAME" \
  --query defaultHostname \
  --output tsv)"

if [ -z "$SWA_HOSTNAME" ]; then
  echo "Static Web Apps default hostname was empty" >&2
  exit 1
fi

azd env set AZURE_STATIC_WEB_APP_HOSTNAME "$SWA_HOSTNAME"

INGRESS_IP=""
ATTEMPTS=60
while [ "$ATTEMPTS" -gt 0 ]; do
  INGRESS_IP="$(kubectl get ingress backend -n app -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  if [ -n "$INGRESS_IP" ]; then
    break
  fi
  ATTEMPTS=$((ATTEMPTS - 1))
  sleep 5
done

if [ -z "$INGRESS_IP" ]; then
  echo "Ingress IP was not assigned within 5 minutes" >&2
  kubectl get ingress backend -n app -o wide || true
  exit 1
fi

LOCATION="$(az group show --name "$AZURE_RESOURCE_GROUP" --query location --output tsv)"
DNS_LABEL="ghas-defender-$(printf '%s' "$AZURE_RESOURCE_GROUP" | md5sum | cut -c1-10)"

kubectl annotate service nginx -n app-routing-system \
  "service.beta.kubernetes.io/azure-dns-label-name=${DNS_LABEL}" \
  --overwrite >/dev/null

INGRESS_FQDN=""
ATTEMPTS=24
while [ "$ATTEMPTS" -gt 0 ]; do
  INGRESS_FQDN="$(az network public-ip list \
    --query "[?ipAddress=='${INGRESS_IP}'].dnsSettings.fqdn | [0]" \
    --output tsv 2>/dev/null || true)"
  if [ -n "$INGRESS_FQDN" ] && [ "$INGRESS_FQDN" != "None" ]; then
    break
  fi
  ATTEMPTS=$((ATTEMPTS - 1))
  sleep 5
done

if [ -z "$INGRESS_FQDN" ] || [ "$INGRESS_FQDN" = "None" ]; then
  INGRESS_FQDN="${DNS_LABEL}.${LOCATION}.cloudapp.azure.com"
fi

azd env set AZURE_BACKEND_INGRESS_IP "$INGRESS_IP"
azd env set AZURE_BACKEND_INGRESS_HOSTNAME "$INGRESS_FQDN"
azd env set VITE_API_BASE_URL "http://${INGRESS_FQDN}/api"

if kubectl get deployment backend -n app >/dev/null 2>&1; then
  echo "Restarting backend deployment so it picks up rotated KeyVault secrets..."
  kubectl rollout restart deployment/backend -n app >/dev/null
  kubectl rollout status deployment/backend -n app --timeout=180s || true
fi

echo "Configured VITE_API_BASE_URL=http://${INGRESS_FQDN}/api"
echo "Configured AZURE_STATIC_WEB_APP_HOSTNAME=$SWA_HOSTNAME"
