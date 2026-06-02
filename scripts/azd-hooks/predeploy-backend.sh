#!/usr/bin/env sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

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
require_env AZURE_POSTGRES_HOST
require_env AZURE_KEY_VAULT_URI
require_env AZURE_STATIC_WEB_APP_HOSTNAME
require_env SERVICE_BACKEND_IMAGE_NAME

LOCAL_BIN="${HOME}/.local/bin"
mkdir -p "${LOCAL_BIN}"
case ":${PATH}:" in
  *":${LOCAL_BIN}:"*) ;;
  *) PATH="${LOCAL_BIN}:${PATH}"; export PATH ;;
esac

if ! command -v kubelogin >/dev/null 2>&1 || ! command -v kubectl >/dev/null 2>&1; then
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

if kubectl get job flyway-init -n app >/dev/null 2>&1; then
  kubectl delete job flyway-init -n app --wait=true
fi

render_template src/backend/k8s/flyway-job.tmpl.yaml | kubectl apply -f -

if ! kubectl wait --for=condition=complete job/flyway-init -n app --timeout=300s; then
  kubectl logs job/flyway-init -n app --all-containers=true || true
  exit 1
fi

kubectl logs job/flyway-init -n app --all-containers=true || true
