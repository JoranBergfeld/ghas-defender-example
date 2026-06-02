#!/usr/bin/env bash
set -euo pipefail

REPO="${GH_REPO:-JoranBergfeld/ghas-defender-example}"
AZD_ENV_NAME="${AZURE_ENV_NAME:-demo}"
BRANCH_PATTERNS=(main secure vulnerable)
REQUIRED_CHECK_CONTEXTS=(
  "infra / what-if"
  "backend-ci / build-test"
  "backend-ci / codeql"
  "frontend-ci / build-test"
  "frontend-ci / codeql"
)

log() {
  printf '==> %s\n' "$*"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is required on PATH"
}

get_azd_value() {
  local wanted="$1"
  local line key raw
  while IFS= read -r line; do
    key="${line%%=*}"
    raw="${line#*=}"
    if [[ "$key" == "$wanted" ]]; then
      raw="${raw%$'\r'}"
      raw="${raw#\"}"
      raw="${raw%\"}"
      [[ -n "$raw" ]] || die "azd value ${wanted} is empty"
      printf '%s' "$raw"
      return 0
    fi
  done <<< "$azd_values"
  die "azd value ${wanted} was not found; run azd up before this script"
}

require_command gh
require_command azd
require_command python3

[[ "$REPO" == */* ]] || die "GH_REPO must be owner/name"
OWNER="${REPO%%/*}"
NAME="${REPO#*/}"

log "Verifying GitHub authentication for ${REPO}"
gh auth status >/dev/null

if [[ ! -f .github/CODEOWNERS ]]; then
  printf 'warning: .github/CODEOWNERS is missing; code owner review enforcement will activate when that file exists.\n' >&2
fi

log "Reading azd values from environment ${AZD_ENV_NAME}"
azd_values="$(azd env get-values --environment "$AZD_ENV_NAME")"
azure_client_id="$(get_azd_value AZURE_GHA_DEPLOYER_CLIENT_ID)"
azure_tenant_id="$(get_azd_value AZURE_TENANT_ID)"
azure_subscription_id="$(get_azd_value AZURE_SUBSCRIPTION_ID)"

log "Setting repository variables"
gh variable set AZURE_CLIENT_ID --repo "$REPO" --body "$azure_client_id"
gh variable set AZURE_TENANT_ID --repo "$REPO" --body "$azure_tenant_id"
gh variable set AZURE_SUBSCRIPTION_ID --repo "$REPO" --body "$azure_subscription_id"

log "Enabling secret scanning and push protection"
gh api --method PATCH "repos/${REPO}" --silent --input - <<'JSON'
{
  "security_and_analysis": {
    "secret_scanning": { "status": "enabled" },
    "secret_scanning_push_protection": { "status": "enabled" }
  }
}
JSON

log "Enabling Dependabot alerts and security updates"
gh api --method PUT "repos/${REPO}/vulnerability-alerts" --silent
gh api --method PUT "repos/${REPO}/automated-security-fixes" --silent

log "Required status check contexts"
printf '   - %s\n' "${REQUIRED_CHECK_CONTEXTS[@]}"

repo_id="$(gh api graphql \
  -f query='query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { id } }' \
  -F owner="$OWNER" \
  -F name="$NAME" \
  --jq '.data.repository.id')"

read -r -d '' create_branch_protection_mutation <<'GRAPHQL' || true
mutation($repositoryId: ID!, $pattern: String!) {
  createBranchProtectionRule(input: {
    repositoryId: $repositoryId,
    pattern: $pattern,
    requiresApprovingReviews: true,
    requiredApprovingReviewCount: 1,
    dismissesStaleReviews: true,
    requiresCodeOwnerReviews: true,
    requiresStatusChecks: true,
    requiresStrictStatusChecks: true,
    requiredStatusCheckContexts: [
      "infra / what-if",
      "backend-ci / build-test",
      "backend-ci / codeql",
      "frontend-ci / build-test",
      "frontend-ci / codeql"
    ],
    requiresLinearHistory: true,
    requiresConversationResolution: true,
    allowsDeletions: false,
    allowsForcePushes: false
  }) {
    branchProtectionRule { id pattern }
  }
}
GRAPHQL

read -r -d '' update_branch_protection_mutation <<'GRAPHQL' || true
mutation($branchProtectionRuleId: ID!, $pattern: String!) {
  updateBranchProtectionRule(input: {
    branchProtectionRuleId: $branchProtectionRuleId,
    pattern: $pattern,
    requiresApprovingReviews: true,
    requiredApprovingReviewCount: 1,
    dismissesStaleReviews: true,
    requiresCodeOwnerReviews: true,
    requiresStatusChecks: true,
    requiresStrictStatusChecks: true,
    requiredStatusCheckContexts: [
      "infra / what-if",
      "backend-ci / build-test",
      "backend-ci / codeql",
      "frontend-ci / build-test",
      "frontend-ci / codeql"
    ],
    requiresLinearHistory: true,
    requiresConversationResolution: true,
    allowsDeletions: false,
    allowsForcePushes: false
  }) {
    branchProtectionRule { id pattern }
  }
}
GRAPHQL

for pattern in "${BRANCH_PATTERNS[@]}"; do
  log "Applying branch protection for ${pattern}"
  existing_rule_id="$(gh api graphql \
    -f query='query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { branchProtectionRules(first: 100) { nodes { id pattern } } } }' \
    -F owner="$OWNER" \
    -F name="$NAME" \
    --jq ".data.repository.branchProtectionRules.nodes[] | select(.pattern == \"${pattern}\") | .id" || true)"

  if [[ -n "$existing_rule_id" ]]; then
    gh api graphql \
      -f query="$update_branch_protection_mutation" \
      -F branchProtectionRuleId="$existing_rule_id" \
      -F pattern="$pattern" \
      --jq '.data.updateBranchProtectionRule.branchProtectionRule.pattern' >/dev/null
  else
    gh api graphql \
      -f query="$create_branch_protection_mutation" \
      -F repositoryId="$repo_id" \
      -F pattern="$pattern" \
      --jq '.data.createBranchProtectionRule.branchProtectionRule.pattern' >/dev/null
  fi
done

log "Verifying main branch protection"
gh api "repos/${REPO}/branches/main/protection" \
  --jq '.required_status_checks.contexts[]' | sed 's/^/   - /'

log "Repository bootstrap complete"
