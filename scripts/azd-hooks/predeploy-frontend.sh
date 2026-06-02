#!/usr/bin/env sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [ -z "${VITE_API_BASE_URL:-}" ]; then
  echo "VITE_API_BASE_URL is not set; cannot build frontend with backend API target." >&2
  echo "Run 'azd provision' first (postprovision hook computes the value)." >&2
  exit 1
fi

ENV_FILE="${REPO_ROOT}/src/frontend/.env.production"
cat > "${ENV_FILE}" <<EOF
VITE_API_BASE_URL=${VITE_API_BASE_URL}
EOF

echo "Wrote ${ENV_FILE} with VITE_API_BASE_URL=${VITE_API_BASE_URL}"
