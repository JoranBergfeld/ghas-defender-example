# Plan 4 — Infrastructure (Bicep) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `azd provision` succeeds for the `demo` environment, creates the private Azure foundation, and leaves an empty AKS cluster reachable with `kubectl get nodes`.

**Architecture:** A subscription-scoped `infra/main.bicep` creates the demo resource group, enables Defender plans, and wires focused resource-group modules through typed outputs. Modules do not reference each other directly; `main.bicep` is the only wiring layer. No application workloads, Kubernetes manifests, Flyway jobs, or GitHub workflow YAML are included in this plan.

**Tech Stack:** Azure Bicep, Azure Developer CLI (`azd`), Azure CLI, AKS, ACR Premium, Key Vault RBAC, PostgreSQL Flexible Server, Static Web Apps, Microsoft Defender for Cloud, GitHub OIDC federated credentials.

---

## Required context

- Source-of-truth design: `docs/superpowers/specs/2026-06-01-ghas-defender-demo-design.md`, especially §5.
- Repo instruction source: `.github/copilot-instructions.md`.
- Current branch should be `main` before implementation.
- This repository is a demo. Do not introduce production-hardening features outside the approved design.

## File map

- Create `infra/main.bicep`: subscription-scoped orchestration, RG creation, module wiring, azd outputs.
- Create `infra/main.parameters.json`: azd-compatible parameters using `${AZURE_ENV_NAME}`, `${AZURE_LOCATION}`, `${AZURE_PRINCIPAL_ID}`, `${GITHUB_ORG}`, `${GITHUB_REPO}`.
- Create `infra/abbreviations.json`: Azure naming abbreviations for future azd-aware tooling.
- Create `infra/modules/network.bicep`: VNet, three subnets, NSGs, private DNS zones, vnet links.
- Create `infra/modules/loganalytics.bicep`: Log Analytics workspace, 30-day default retention.
- Create `infra/modules/identity.bicep`: `id-gha-deployer`, `id-backend`, GitHub federated credentials, RG Contributor role.
- Create `infra/modules/keyvault.bicep`: RBAC Key Vault, private endpoint, DNS zone group, developer and backend role assignments.
- Create `infra/modules/postgres.bicep`: PostgreSQL Flexible Server private access, generated admin password stored in Key Vault, `appdb`.
- Create `infra/modules/aks.bicep`: AKS with CNI Overlay, OIDC, Workload Identity, Azure Policy, Defender profile, NGINX ingress, backend federated credential.
- Create `infra/modules/acr.bicep`: Premium ACR, private endpoint, DNS zone group, AcrPush/AcrPull role assignments including kubelet identity.
- Create `infra/modules/policy.bicep`: RG-scope built-in Defender admission-blocking policy assignment in `Deny` mode.
- Create `infra/modules/swa.bicep`: Standard Static Web App in `westeurope`, deployer role assignment.
- Create `infra/modules/defender.bicep`: subscription-scope Defender plan enablement.
- Create `infra/modules/githubConnector.bicep`: GitHub Defender connector resource. Current Bicep type metadata only permits resource-group deployment; see Open Questions.
- Create `scripts/azd-hooks/postprovision.sh`: POSIX kubeconfig + node smoke test.
- Create `scripts/azd-hooks/postprovision.ps1`: PowerShell kubeconfig + node smoke test.
- Create `infra/tests/*.test.bicep`: compile-only module signature tests.
- Modify or create `azure.yaml`: azd infra path/module plus Plan 4 postprovision hooks.

## Implementation rule for this plan

When a task says to write a file, use the exact full content from the matching Appendix section. The code is kept once in the Appendix so later workers do not copy divergent versions.

## Tasks

### Task 1: Bootstrap infrastructure entry point and network

**Files:**
- Create directories: `infra/`, `infra/modules/`, `infra/tests/`.
- Create: `infra/modules/network.bicep` from Appendix A.4.
- Create: `infra/main.parameters.json` from Appendix A.2.
- Create: `infra/abbreviations.json` from Appendix A.3.

- [ ] **Step 1: Create directories**

Run:
```bash
mkdir -p infra/modules infra/tests
```
Expected: command exits `0` with no output.

- [ ] **Step 2: Write network module**

Write `infra/modules/network.bicep` with Appendix A.4 exactly.

- [ ] **Step 3: Write parameters and abbreviations**

Write `infra/main.parameters.json` with Appendix A.2 exactly.
Write `infra/abbreviations.json` with Appendix A.3 exactly.

- [ ] **Step 4: Build the network module**

Run:
```bash
az bicep build --file infra/modules/network.bicep
```
Expected: exits `0`; no Bicep errors or warnings. Azure CLI may print a standalone Bicep version notice.

- [ ] **Step 5: Commit**

Run:
```bash
git add infra/main.parameters.json infra/abbreviations.json infra/modules/network.bicep
git commit -m "feat: bootstrap azure infrastructure" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
Expected: one commit is created.

### Task 2: Wire azd manifest and preview provisioning

**Files:**
- Create or replace: `azure.yaml` from Appendix A.16.

- [ ] **Step 1: Write azd manifest**

Write `azure.yaml` with Appendix A.16 exactly. If a Plan 1 skeleton already exists, replace it with the Appendix content.

- [ ] **Step 2: Create/select the demo azd environment**

Run:
```bash
azd env list | grep -q '^demo[[:space:]]' && azd env select demo || azd env new demo
azd env set AZURE_LOCATION westeurope
azd env set GITHUB_ORG JoranBergfeld
azd env set GITHUB_REPO ghas-defender-example
```
Expected: `demo` is selected; three env values are set.

- [ ] **Step 3: Verify azd environment values**

Run:
```bash
azd env get-values | grep -E '^(AZURE_LOCATION|GITHUB_ORG|GITHUB_REPO)='
```
Expected: output contains `AZURE_LOCATION`, `GITHUB_ORG`, and `GITHUB_REPO`. Full azd preview waits until Task 15, after final `infra/main.bicep` wiring exists.

- [ ] **Step 4: Commit**

Run:
```bash
git add azure.yaml
git commit -m "feat: wire azd infrastructure manifest" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
Expected: one commit is created.

### Task 3: Add Log Analytics workspace

**Files:**
- Create: `infra/modules/loganalytics.bicep` from Appendix A.5.

- [ ] **Step 1: Write module**

Write `infra/modules/loganalytics.bicep` with Appendix A.5 exactly.

- [ ] **Step 2: Build Bicep**

Run:
```bash
az bicep build --file infra/modules/loganalytics.bicep
```
Expected: exits `0`; no Bicep errors or warnings.

- [ ] **Step 3: Commit**

Run:
```bash
git add infra/modules/loganalytics.bicep
git commit -m "feat: add log analytics infrastructure" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
Expected: one commit is created.

### Task 4: Add managed identities and GitHub federation

**Files:**
- Create: `infra/modules/identity.bicep` from Appendix A.6.
- Appendix A.1 assigns subscription Reader to `id-gha-deployer` when final wiring is added in Task 15.

- [ ] **Step 1: Write identity module**

Write `infra/modules/identity.bicep` with Appendix A.6 exactly.

- [ ] **Step 2: Build Bicep**

Run:
```bash
az bicep build --file infra/modules/identity.bicep
```
Expected: exits `0`; no Bicep errors or warnings.

- [ ] **Step 3: Commit**

Run:
```bash
git add infra/modules/identity.bicep
git commit -m "feat: add deployment managed identities" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
Expected: one commit is created.

### Task 5: Add Key Vault with RBAC and private endpoint

**Files:**
- Create: `infra/modules/keyvault.bicep` from Appendix A.7.

- [ ] **Step 1: Write Key Vault module**

Write `infra/modules/keyvault.bicep` with Appendix A.7 exactly.

- [ ] **Step 2: Build Bicep**

Run:
```bash
az bicep build --file infra/modules/keyvault.bicep
```
Expected: exits `0`; no Bicep errors or warnings.

- [ ] **Step 3: Commit**

Run:
```bash
git add infra/modules/keyvault.bicep
git commit -m "feat: add private key vault" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
Expected: one commit is created.

### Task 6: Add private PostgreSQL Flexible Server

**Files:**
- Create: `infra/modules/postgres.bicep` from Appendix A.8.

- [ ] **Step 1: Write PostgreSQL module**

Write `infra/modules/postgres.bicep` with Appendix A.8 exactly.

- [ ] **Step 2: Build Bicep**

Run:
```bash
az bicep build --file infra/modules/postgres.bicep
```
Expected: exits `0`; no Bicep errors or warnings.

- [ ] **Step 3: Commit**

Run:
```bash
git add infra/modules/postgres.bicep
git commit -m "feat: add private postgres flexible server" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
Expected: one commit is created.

### Task 7: Add AKS with Defender, Azure Policy, ingress, and backend federation

**Files:**
- Create: `infra/modules/aks.bicep` from Appendix A.9.

- [ ] **Step 1: Verify AKS version availability**

Run:
```bash
az aks get-versions --location westeurope --query "values[?starts_with(version, '1.30.')].version | [0]" -o tsv
```
Expected: prints an AKS patch version beginning with `1.30.`. If Azure no longer offers 1.30 in `westeurope`, use the latest supported minor version greater than 1.30 and record that in the PR description.

- [ ] **Step 2: Write AKS module**

Write `infra/modules/aks.bicep` with Appendix A.9 exactly.

- [ ] **Step 3: Build Bicep**

Run:
```bash
az bicep build --file infra/modules/aks.bicep
```
Expected: exits `0`; no Bicep errors or warnings.

- [ ] **Step 4: Commit**

Run:
```bash
git add infra/modules/aks.bicep
git commit -m "feat: add defender-enabled aks cluster" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
Expected: one commit is created.

### Task 8: Add Premium ACR and declarative AKS pull access

**Files:**
- Create: `infra/modules/acr.bicep` from Appendix A.10.

- [ ] **Step 1: Write ACR module**

Write `infra/modules/acr.bicep` with Appendix A.10 exactly.

- [ ] **Step 2: Build Bicep**

Run:
```bash
az bicep build --file infra/modules/acr.bicep
```
Expected: exits `0`; no Bicep errors or warnings. The template includes `AcrPull` for the AKS kubelet identity instead of a postprovision `az aks update --attach-acr` command.

- [ ] **Step 3: Commit**

Run:
```bash
git add infra/modules/acr.bicep
git commit -m "feat: add private container registry" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
Expected: one commit is created.

### Task 9: Add Defender admission policy assignment

**Files:**
- Create: `infra/modules/policy.bicep` from Appendix A.11.

- [ ] **Step 1: Confirm built-in policy exists**

Run:
```bash
az policy definition show --name af1b4f6f-8c7a-4a47-9013-f8e17bd45cec --query displayName -o tsv
```
Expected: prints `[Preview] Microsoft Defender for Containers should be enabled to block container images with high severity vulnerabilities`.

- [ ] **Step 2: Write policy module**

Write `infra/modules/policy.bicep` with Appendix A.11 exactly.

- [ ] **Step 3: Build Bicep**

Run:
```bash
az bicep build --file infra/modules/policy.bicep
```
Expected: exits `0`; no Bicep errors or warnings.

- [ ] **Step 4: Commit**

Run:
```bash
git add infra/modules/policy.bicep
git commit -m "feat: add defender admission policy" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
Expected: one commit is created.

### Task 10: Add Static Web App

**Files:**
- Create: `infra/modules/swa.bicep` from Appendix A.12.

- [ ] **Step 1: Verify Static Web Apps region**

Run:
```bash
az staticwebapp list-locations --query "[?name=='West Europe' || name=='westeurope']" -o table
```
Expected: output includes a West Europe / `westeurope` location row.

- [ ] **Step 2: Write SWA module**

Write `infra/modules/swa.bicep` with Appendix A.12 exactly.

- [ ] **Step 3: Build Bicep**

Run:
```bash
az bicep build --file infra/modules/swa.bicep
```
Expected: exits `0`; no Bicep errors or warnings.

- [ ] **Step 4: Commit**

Run:
```bash
git add infra/modules/swa.bicep
git commit -m "feat: add static web app infrastructure" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
Expected: one commit is created.

### Task 11: Enable Defender plans at subscription scope

**Files:**
- Create: `infra/modules/defender.bicep` from Appendix A.13.

- [ ] **Step 1: Write Defender module**

Write `infra/modules/defender.bicep` with Appendix A.13 exactly.

- [ ] **Step 2: Build Bicep**

Run:
```bash
az bicep build --file infra/modules/defender.bicep
```
Expected: exits `0`; no Bicep errors or warnings.

- [ ] **Step 3: Commit**

Run:
```bash
git add infra/modules/defender.bicep
git commit -m "feat: enable defender cloud plans" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
Expected: one commit is created.

### Task 12: Add Defender for Cloud GitHub connector resource

**Files:**
- Create: `infra/modules/githubConnector.bicep` from Appendix A.14.

- [ ] **Step 1: Write GitHub connector module**

Write `infra/modules/githubConnector.bicep` with Appendix A.14 exactly.

- [ ] **Step 2: Build Bicep**

Run:
```bash
az bicep build --file infra/modules/githubConnector.bicep
```
Expected: exits `0`; no Bicep errors or warnings.

- [ ] **Step 3: Record manual OAuth handoff**

Add this sentence to the PR description for this task:
```text
Defender for Cloud creates the GitHub connector resource through Bicep, but a human must complete the one-time GitHub OAuth handshake in the Azure portal before code-to-cloud correlation works.
```
Expected: reviewers see the manual portal step before merging.

- [ ] **Step 4: Commit**

Run:
```bash
git add infra/modules/githubConnector.bicep
git commit -m "feat: add defender github connector" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
Expected: one commit is created.

### Task 13: Add azd postprovision hooks

**Files:**
- Create: `scripts/azd-hooks/postprovision.sh` from Appendix A.17.
- Create: `scripts/azd-hooks/postprovision.ps1` from Appendix A.18.

- [ ] **Step 1: Create hooks directory**

Run:
```bash
mkdir -p scripts/azd-hooks
```
Expected: command exits `0`.

- [ ] **Step 2: Write POSIX hook**

Write `scripts/azd-hooks/postprovision.sh` with Appendix A.17 exactly.

- [ ] **Step 3: Write PowerShell hook**

Write `scripts/azd-hooks/postprovision.ps1` with Appendix A.18 exactly.

- [ ] **Step 4: Mark POSIX hook executable**

Run:
```bash
chmod +x scripts/azd-hooks/postprovision.sh
```
Expected: command exits `0`.

- [ ] **Step 5: Validate POSIX hook syntax**

Run:
```bash
sh -n scripts/azd-hooks/postprovision.sh
test -x scripts/azd-hooks/postprovision.sh
```
Expected: both commands exit `0` with no output.

- [ ] **Step 6: Commit**

Run:
```bash
git add azure.yaml scripts/azd-hooks/postprovision.sh scripts/azd-hooks/postprovision.ps1
git commit -m "feat: add azd postprovision aks smoke test" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
Expected: one commit is created.

### Task 14: Add compile-only module tests

**Files:**
- Create all files from Appendix B.

- [ ] **Step 1: Write test files**

Write each file in Appendix B exactly under `infra/tests/`.

- [ ] **Step 2: Build every test file**

Run:
```bash
for file in infra/tests/*.test.bicep; do echo "building ${file}"; az bicep build --file "${file}" >/dev/null; done
```
Expected: each file name is printed once; command exits `0`; no Bicep diagnostics.

- [ ] **Step 3: Commit**

Run:
```bash
git add infra/tests
git commit -m "test: add bicep module compile tests" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
Expected: one commit is created.

### Task 15: Run full pre-provision verification

**Files:**
- Create: `infra/main.bicep` from Appendix A.1.
- Verify all files from Appendices A and B exist.

- [ ] **Step 1: Write final subscription template**

Write `infra/main.bicep` with Appendix A.1 exactly.

- [ ] **Step 2: Build main template**

Run:
```bash
az bicep build --file infra/main.bicep
```
Expected: exits `0`; no Bicep errors or warnings.

- [ ] **Step 3: Export raw CLI parameter values**

Run:
```bash
export AZURE_PRINCIPAL_ID="$(az ad signed-in-user show --query id -o tsv)"
export GITHUB_ORG="JoranBergfeld"
export GITHUB_REPO="ghas-defender-example"
```
Expected: variables are set in the current shell.

- [ ] **Step 4: Run subscription what-if with explicit overrides**

Run:
```bash
az deployment sub what-if \
  --location westeurope \
  --template-file infra/main.bicep \
  --parameters infra/main.parameters.json \
  --parameters environmentName=demo location=westeurope principalId="$AZURE_PRINCIPAL_ID" githubOrg="$GITHUB_ORG" githubRepo="$GITHUB_REPO"
```
Expected: exits `0`; what-if lists creates/updates and no validation errors.

- [ ] **Step 5: Run azd preview**

Run:
```bash
azd provision --preview
```
Expected: exits `0`; output is a successful what-if for the `demo` environment.

- [ ] **Step 6: Commit final main template**

Run:
```bash
git add infra/main.bicep
git commit -m "feat: wire infrastructure modules" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
Expected: one commit is created for `infra/main.bicep`.

### Task 16: Provision and smoke-test the empty cluster

**Files:**
- No new files.

- [ ] **Step 1: Provision only**

Run:
```bash
azd provision
```
Expected: exits `0`; resources are created in `rg-ghas-defender-demo`; postprovision hook runs `kubectl get nodes`.

- [ ] **Step 2: Verify kubeconfig manually**

Run:
```bash
az aks get-credentials --resource-group rg-ghas-defender-demo --name aks-demo --overwrite-existing
kubectl get nodes
```
Expected: output shows exactly two AKS nodes with `STATUS` `Ready`.

- [ ] **Step 3: Verify azd outputs consumed by later plans**

Run:
```bash
azd env get-values | grep '^AZURE_'
```
Expected: output contains all of these names: `AZURE_RESOURCE_GROUP`, `AZURE_LOCATION`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_CONTAINER_REGISTRY_ENDPOINT`, `AZURE_CONTAINER_REGISTRY_NAME`, `AZURE_AKS_CLUSTER_NAME`, `AZURE_AKS_NAMESPACE`, `AZURE_STATIC_WEB_APP_NAME`, `AZURE_KEY_VAULT_NAME`, `AZURE_KEY_VAULT_URI`, `AZURE_POSTGRES_HOST`, `AZURE_POSTGRES_DATABASE`, `AZURE_BACKEND_IDENTITY_CLIENT_ID`, `AZURE_GHA_DEPLOYER_CLIENT_ID`.

- [ ] **Step 4: Verify private DNS zones**

Run:
```bash
az network private-dns zone list --resource-group rg-ghas-defender-demo --query "[].name" -o tsv | sort
```
Expected:
```text
privatelink.azurecr.io
privatelink.postgres.database.azure.com
privatelink.vaultcore.azure.net
```

- [ ] **Step 5: Verify Defender plans**

Run:
```bash
az security pricing list --query "value[?name=='CloudPosture' || name=='Containers' || name=='KeyVaults' || name=='OpenSourceRelationalDatabases' || name=='Arm'].{name:name,tier:pricingTier}" -o table
```
Expected: five rows, each with `Standard` tier.

### Task 17: Final review and handoff

**Files:**
- No new files unless Task 15 found intentional drift.

- [ ] **Step 1: Run placeholder scan**

Run:
```bash
grep -RInE 'T[B]D|TO[D]O|similar t[o]|add appropriat[e]|fill i[n]' infra azure.yaml scripts/azd-hooks || true
```
Expected: no matches.

- [ ] **Step 2: Run final status check**

Run:
```bash
git status --short
```
Expected: no output after all task commits.

- [ ] **Step 3: Document cross-plan handoff in PR body**

Use this PR body text:
```text
Plan 4 provisions the Azure infrastructure only. Plan 5 consumes azd outputs, creates the app namespace and backend ServiceAccount, applies Kubernetes manifests, and runs Flyway. Plan 6 consumes AZURE_GHA_DEPLOYER_CLIENT_ID, AZURE_TENANT_ID, and AZURE_SUBSCRIPTION_ID to configure repository variables and branch protection. The Defender GitHub connector resource exists, but the one-time portal OAuth handshake remains manual.
```
Expected: reviewers understand the Plan 5 and Plan 6 dependencies.

## Appendix A: Full file contents

### A.1 `infra/main.bicep`

```bicep
targetScope = 'subscription'

@description('Azd environment name. The demo environment is "demo".')
param environmentName string

@description('Azure region for regional resources. Default is westeurope.')
param location string = 'westeurope'

@description('Object ID of the signed-in user or service principal running azd provision.')
param principalId string

@description('GitHub organization or user that owns the repository.')
param githubOrg string = 'JoranBergfeld'

@description('GitHub repository name.')
param githubRepo string = 'ghas-defender-example'

var resourceGroupName = 'rg-ghas-defender-${environmentName}'
var ghaDeployerName = 'id-gha-deployer'
var readerRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
}

module defender 'modules/defender.bicep' = {
  name: 'defender-${environmentName}'
  scope: subscription()
}

module network 'modules/network.bicep' = {
  name: 'network-${environmentName}'
  scope: resourceGroup
  params: {
    environmentName: environmentName
    location: location
  }
}

module logAnalytics 'modules/loganalytics.bicep' = {
  name: 'loganalytics-${environmentName}'
  scope: resourceGroup
  params: {
    environmentName: environmentName
    location: location
  }
}

module identity 'modules/identity.bicep' = {
  name: 'identity-${environmentName}'
  scope: resourceGroup
  params: {
    environmentName: environmentName
    githubOrg: githubOrg
    githubRepo: githubRepo
    location: location
  }
}

resource ghaSubscriptionReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroupName, ghaDeployerName, readerRoleDefinitionId)
  properties: {
    principalId: identity.outputs.ghaDeployerPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: readerRoleDefinitionId
  }
}

module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault-${environmentName}'
  scope: resourceGroup
  params: {
    backendPrincipalId: identity.outputs.backendPrincipalId
    developerPrincipalId: principalId
    environmentName: environmentName
    keyVaultPrivateDnsZoneId: network.outputs.keyVaultPrivateDnsZoneId
    location: location
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
  }
}

module aks 'modules/aks.bicep' = {
  name: 'aks-${environmentName}'
  scope: resourceGroup
  params: {
    aksSubnetId: network.outputs.aksSubnetId
    backendIdentityName: identity.outputs.backendIdentityName
    environmentName: environmentName
    ghaDeployerPrincipalId: identity.outputs.ghaDeployerPrincipalId
    location: location
    logAnalyticsWorkspaceResourceId: logAnalytics.outputs.workspaceId
  }
}

module acr 'modules/acr.bicep' = {
  name: 'acr-${environmentName}'
  scope: resourceGroup
  params: {
    backendPrincipalId: identity.outputs.backendPrincipalId
    developerPrincipalId: principalId
    environmentName: environmentName
    ghaDeployerPrincipalId: identity.outputs.ghaDeployerPrincipalId
    kubeletIdentityObjectId: aks.outputs.kubeletIdentityObjectId
    location: location
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    registryPrivateDnsZoneId: network.outputs.acrPrivateDnsZoneId
  }
}

module postgres 'modules/postgres.bicep' = {
  name: 'postgres-${environmentName}'
  scope: resourceGroup
  params: {
    environmentName: environmentName
    keyVaultName: keyVault.outputs.keyVaultName
    location: location
    postgresPrivateDnsZoneId: network.outputs.postgresPrivateDnsZoneId
    postgresSubnetId: network.outputs.postgresSubnetId
  }
}

module staticWebApp 'modules/swa.bicep' = {
  name: 'swa-${environmentName}'
  scope: resourceGroup
  params: {
    environmentName: environmentName
    ghaDeployerPrincipalId: identity.outputs.ghaDeployerPrincipalId
  }
}

module policy 'modules/policy.bicep' = {
  name: 'policy-${environmentName}'
  scope: resourceGroup
  params: {
    environmentName: environmentName
  }
  dependsOn: [
    aks
  ]
}

module githubConnector 'modules/githubConnector.bicep' = {
  name: 'github-connector-${environmentName}'
  scope: resourceGroup
  params: {
    environmentName: environmentName
    githubOrg: githubOrg
    githubRepo: githubRepo
    location: location
  }
}

output AZURE_RESOURCE_GROUP string = resourceGroup.name
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_SUBSCRIPTION_ID string = subscription().subscriptionId
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = acr.outputs.loginServer
output AZURE_CONTAINER_REGISTRY_NAME string = acr.outputs.registryName
output AZURE_AKS_CLUSTER_NAME string = aks.outputs.clusterName
output AZURE_AKS_NAMESPACE string = 'app'
output AZURE_STATIC_WEB_APP_NAME string = staticWebApp.outputs.staticWebAppName
output AZURE_KEY_VAULT_NAME string = keyVault.outputs.keyVaultName
output AZURE_KEY_VAULT_URI string = keyVault.outputs.keyVaultUri
output AZURE_POSTGRES_HOST string = postgres.outputs.postgresHost
output AZURE_POSTGRES_DATABASE string = postgres.outputs.databaseName
output AZURE_BACKEND_IDENTITY_CLIENT_ID string = identity.outputs.backendClientId
output AZURE_GHA_DEPLOYER_CLIENT_ID string = identity.outputs.ghaDeployerClientId
```

### A.2 `infra/main.parameters.json`

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "environmentName": {
      "value": "${AZURE_ENV_NAME}"
    },
    "location": {
      "value": "${AZURE_LOCATION}"
    },
    "principalId": {
      "value": "${AZURE_PRINCIPAL_ID}"
    },
    "githubOrg": {
      "value": "${GITHUB_ORG}"
    },
    "githubRepo": {
      "value": "${GITHUB_REPO}"
    }
  }
}
```

### A.3 `infra/abbreviations.json`

```json
{
  "Microsoft.Authorization/roleAssignments": "ra",
  "Microsoft.ContainerRegistry/registries": "cr",
  "Microsoft.ContainerService/managedClusters": "aks",
  "Microsoft.DBforPostgreSQL/flexibleServers": "pg",
  "Microsoft.KeyVault/vaults": "kv",
  "Microsoft.ManagedIdentity/userAssignedIdentities": "id",
  "Microsoft.Network/networkSecurityGroups": "nsg",
  "Microsoft.Network/privateDnsZones": "pdnsz",
  "Microsoft.Network/privateEndpoints": "pe",
  "Microsoft.Network/virtualNetworks": "vnet",
  "Microsoft.OperationalInsights/workspaces": "log",
  "Microsoft.Resources/resourceGroups": "rg",
  "Microsoft.Security/securityConnectors": "sc",
  "Microsoft.Web/staticSites": "swa"
}
```

### A.4 `infra/modules/network.bicep`

```bicep
targetScope = 'resourceGroup'

param environmentName string
param location string

var vnetName = 'vnet-${environmentName}'
var aksSubnetName = 'snet-aks'
var postgresSubnetName = 'snet-pg'
var privateEndpointSubnetName = 'snet-pe'
var postgresPrivateDnsZoneName = 'privatelink.postgres.database.azure.com'
var keyVaultPrivateDnsZoneName = 'privatelink.vaultcore.azure.net'
var acrPrivateDnsZoneName = 'privatelink.azurecr.io'

resource aksNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-${environmentName}-aks'
  location: location
  properties: {
    securityRules: []
  }
}

resource postgresNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-${environmentName}-pg'
  location: location
  properties: {
    securityRules: []
  }
}

resource privateEndpointNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-${environmentName}-pe'
  location: location
  properties: {
    securityRules: []
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.40.0.0/16'
      ]
    }
    subnets: [
      {
        name: aksSubnetName
        properties: {
          addressPrefix: '10.40.0.0/22'
          networkSecurityGroup: {
            id: aksNsg.id
          }
        }
      }
      {
        name: postgresSubnetName
        properties: {
          addressPrefix: '10.40.4.0/27'
          delegations: [
            {
              name: 'postgres-flexible-servers'
              properties: {
                serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'
              }
            }
          ]
          networkSecurityGroup: {
            id: postgresNsg.id
          }
        }
      }
      {
        name: privateEndpointSubnetName
        properties: {
          addressPrefix: '10.40.4.32/27'
          privateEndpointNetworkPolicies: 'Disabled'
          networkSecurityGroup: {
            id: privateEndpointNsg.id
          }
        }
      }
    ]
  }
}

resource postgresPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: postgresPrivateDnsZoneName
  location: 'global'
}

resource keyVaultPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: keyVaultPrivateDnsZoneName
  location: 'global'
}

resource acrPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: acrPrivateDnsZoneName
  location: 'global'
}

resource postgresPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: postgresPrivateDnsZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource keyVaultPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: keyVaultPrivateDnsZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource acrPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: acrPrivateDnsZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output aksSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, aksSubnetName)
output postgresSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, postgresSubnetName)
output privateEndpointSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, privateEndpointSubnetName)
output postgresPrivateDnsZoneId string = postgresPrivateDnsZone.id
output keyVaultPrivateDnsZoneId string = keyVaultPrivateDnsZone.id
output acrPrivateDnsZoneId string = acrPrivateDnsZone.id
```

### A.5 `infra/modules/loganalytics.bicep`

```bicep
targetScope = 'resourceGroup'

param environmentName string
param location string
param retentionInDays int = 30

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${environmentName}'
  location: location
  properties: {
    retentionInDays: retentionInDays
    sku: {
      name: 'PerGB2018'
    }
  }
}

output workspaceId string = workspace.id
output workspaceName string = workspace.name
output workspaceCustomerId string = workspace.properties.customerId
```

### A.6 `infra/modules/identity.bicep`

```bicep
targetScope = 'resourceGroup'

param environmentName string
param location string
param githubOrg string
param githubRepo string

var ghaDeployerName = 'id-gha-deployer'
var backendName = 'id-backend'
var contributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
var githubIssuer = 'https://token.actions.githubusercontent.com'
var githubAudiences = [
  'api://AzureADTokenExchange'
]
var githubFederatedCredentials = [
  {
    name: 'gha-main'
    subject: 'repo:${githubOrg}/${githubRepo}:ref:refs/heads/main'
  }
  {
    name: 'gha-secure'
    subject: 'repo:${githubOrg}/${githubRepo}:ref:refs/heads/secure'
  }
  {
    name: 'gha-vulnerable'
    subject: 'repo:${githubOrg}/${githubRepo}:ref:refs/heads/vulnerable'
  }
  {
    name: 'gha-pull-request'
    subject: 'repo:${githubOrg}/${githubRepo}:pull_request'
  }
]

resource ghaDeployer 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: ghaDeployerName
  location: location
  tags: {
    azdEnvName: environmentName
  }
}

resource backend 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: backendName
  location: location
  tags: {
    azdEnvName: environmentName
  }
}

resource ghaContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, ghaDeployerName, contributorRoleDefinitionId)
  properties: {
    principalId: ghaDeployer.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: contributorRoleDefinitionId
  }
}

resource ghaFederatedIdentityCredentials 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = [for credential in githubFederatedCredentials: {
  parent: ghaDeployer
  name: credential.name
  properties: {
    audiences: githubAudiences
    issuer: githubIssuer
    subject: credential.subject
  }
}]

output ghaDeployerName string = ghaDeployer.name
output ghaDeployerClientId string = ghaDeployer.properties.clientId
output ghaDeployerPrincipalId string = ghaDeployer.properties.principalId
output backendIdentityName string = backend.name
output backendClientId string = backend.properties.clientId
output backendPrincipalId string = backend.properties.principalId
```

### A.7 `infra/modules/keyvault.bicep`

```bicep
targetScope = 'resourceGroup'

param environmentName string
param location string
param privateEndpointSubnetId string
param keyVaultPrivateDnsZoneId string
param developerPrincipalId string
param backendPrincipalId string

var keyVaultName = 'kv-${uniqueString(resourceGroup().id)}'
var keyVaultAdministratorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74483')
var keyVaultSecretsUserRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    tenantId: tenant().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enablePurgeProtection: true
    enableRbacAuthorization: true
    enableSoftDelete: true
    publicNetworkAccess: 'Disabled'
    softDeleteRetentionInDays: 90
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
  }
}

resource developerKeyVaultAdministrator 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, 'developer', keyVaultAdministratorRoleDefinitionId)
  properties: {
    principalId: developerPrincipalId
    principalType: 'User'
    roleDefinitionId: keyVaultAdministratorRoleDefinitionId
  }
}

resource backendKeyVaultSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, 'id-backend', keyVaultSecretsUserRoleDefinitionId)
  properties: {
    principalId: backendPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: keyVaultSecretsUserRoleDefinitionId
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${keyVaultName}'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'kv-${environmentName}'
        properties: {
          groupIds: [
            'vault'
          ]
          privateLinkServiceId: keyVault.id
        }
      }
    ]
  }
}

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'vaultcore'
        properties: {
          privateDnsZoneId: keyVaultPrivateDnsZoneId
        }
      }
    ]
  }
}

output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
```

### A.8 `infra/modules/postgres.bicep`

```bicep
targetScope = 'resourceGroup'

param environmentName string
param location string
param postgresSubnetId string
param postgresPrivateDnsZoneId string
param keyVaultName string
@secure()
param administratorPassword string = newGuid()

var serverName = 'pg-${environmentName}-${uniqueString(resourceGroup().id)}'
var databaseName = 'appdb'

resource server 'Microsoft.DBforPostgreSQL/flexibleServers@2023-06-01-preview' = {
  name: serverName
  location: location
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    administratorLogin: 'pgadmin'
    administratorLoginPassword: administratorPassword
    authConfig: {
      activeDirectoryAuth: 'Disabled'
      passwordAuth: 'Enabled'
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    network: {
      delegatedSubnetResourceId: postgresSubnetId
      privateDnsZoneArmResourceId: postgresPrivateDnsZoneId
      publicNetworkAccess: 'Disabled'
    }
    storage: {
      storageSizeGB: 32
    }
    version: '16'
  }
}

resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-06-01-preview' = {
  parent: server
  name: databaseName
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

resource uuidExtensionConfig 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2023-06-01-preview' = {
  parent: server
  name: 'azure.extensions'
  properties: {
    source: 'user-override'
    value: 'UUID-OSSP'
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource postgresAdminPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'postgres-admin-password'
  properties: {
    value: administratorPassword
  }
}

output postgresServerName string = server.name
output postgresHost string = server.properties.fullyQualifiedDomainName
output databaseName string = database.name
```

### A.9 `infra/modules/aks.bicep`

```bicep
targetScope = 'resourceGroup'

param environmentName string
param location string
param aksSubnetId string
param logAnalyticsWorkspaceResourceId string
param ghaDeployerPrincipalId string
param backendIdentityName string
param kubernetesVersion string = '1.30'

var clusterName = 'aks-${environmentName}'
var clusterUserRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4abbcc35-e782-43d8-92c5-2d3f1bd2253f')
var clusterRbacAdminRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b')

resource cluster 'Microsoft.ContainerService/managedClusters@2024-05-01' = {
  name: clusterName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    aadProfile: {
      enableAzureRBAC: true
      managed: true
    }
    addonProfiles: {
      azurepolicy: {
        enabled: true
      }
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceResourceId
        }
      }
    }
    agentPoolProfiles: [
      {
        name: 'systempool'
        count: 2
        enableAutoScaling: false
        mode: 'System'
        osSKU: 'Ubuntu'
        osType: 'Linux'
        type: 'VirtualMachineScaleSets'
        vmSize: 'Standard_D2as_v5'
        vnetSubnetID: aksSubnetId
      }
    ]
    dnsPrefix: clusterName
    enableRBAC: true
    ingressProfile: {
      webAppRouting: {
        enabled: true
      }
    }
    kubernetesVersion: kubernetesVersion
    networkProfile: {
      dnsServiceIP: '10.41.0.10'
      loadBalancerSku: 'standard'
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkPolicy: 'azure'
      outboundType: 'loadBalancer'
      podCidr: '10.42.0.0/16'
      serviceCidr: '10.41.0.0/16'
    }
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      defender: {
        logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
        securityMonitoring: {
          enabled: true
        }
      }
      workloadIdentity: {
        enabled: true
      }
    }
  }
}

resource ghaClusterUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: cluster
  name: guid(cluster.id, 'id-gha-deployer', clusterUserRoleDefinitionId)
  properties: {
    principalId: ghaDeployerPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: clusterUserRoleDefinitionId
  }
}

resource ghaClusterRbacAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: cluster
  name: guid(cluster.id, 'id-gha-deployer', clusterRbacAdminRoleDefinitionId)
  properties: {
    principalId: ghaDeployerPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: clusterRbacAdminRoleDefinitionId
  }
}

resource backendIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: backendIdentityName
}

resource backendFederatedIdentityCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: backendIdentity
  name: 'aks-app-backend'
  properties: {
    audiences: [
      'api://AzureADTokenExchange'
    ]
    issuer: cluster.properties.oidcIssuerProfile.issuerURL
    subject: 'system:serviceaccount:app:backend'
  }
}

output clusterName string = cluster.name
output oidcIssuerUrl string = cluster.properties.oidcIssuerProfile.issuerURL
output kubeletIdentityObjectId string = cluster.properties.identityProfile.kubeletidentity.objectId
```

### A.10 `infra/modules/acr.bicep`

```bicep
targetScope = 'resourceGroup'

param environmentName string
param location string
param privateEndpointSubnetId string
param registryPrivateDnsZoneId string
param ghaDeployerPrincipalId string
param backendPrincipalId string
param kubeletIdentityObjectId string
param developerPrincipalId string

var registryName = 'cr${uniqueString(resourceGroup().id)}'
var acrPushRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8311e382-0749-4cb8-b61a-304f252e45ec')
var acrPullRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: registryName
  location: location
  sku: {
    name: 'Premium'
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
    networkRuleBypassOptions: 'AzureServices'
  }
}

resource ghaAcrPush 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: registry
  name: guid(registry.id, 'id-gha-deployer', acrPushRoleDefinitionId)
  properties: {
    principalId: ghaDeployerPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: acrPushRoleDefinitionId
  }
}

resource developerAcrPush 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: registry
  name: guid(registry.id, 'developer', acrPushRoleDefinitionId)
  properties: {
    principalId: developerPrincipalId
    principalType: 'User'
    roleDefinitionId: acrPushRoleDefinitionId
  }
}

resource backendAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: registry
  name: guid(registry.id, 'id-backend', acrPullRoleDefinitionId)
  properties: {
    principalId: backendPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: acrPullRoleDefinitionId
  }
}

resource kubeletAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: registry
  name: guid(registry.id, 'aks-kubelet', acrPullRoleDefinitionId)
  properties: {
    principalId: kubeletIdentityObjectId
    principalType: 'ServicePrincipal'
    roleDefinitionId: acrPullRoleDefinitionId
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${registryName}'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'acr-${environmentName}'
        properties: {
          groupIds: [
            'registry'
          ]
          privateLinkServiceId: registry.id
        }
      }
    ]
  }
}

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'azurecr'
        properties: {
          privateDnsZoneId: registryPrivateDnsZoneId
        }
      }
    ]
  }
}

output registryName string = registry.name
output loginServer string = registry.properties.loginServer
```

### A.11 `infra/modules/policy.bicep`

```bicep
targetScope = 'resourceGroup'

param environmentName string

var policyDefinitionId = subscriptionResourceId('Microsoft.Authorization/policyDefinitions', 'af1b4f6f-8c7a-4a47-9013-f8e17bd45cec')

resource denyHighSeverityVulnerableImages 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'deny-high-sev-images'
  properties: {
    description: 'Blocks Kubernetes deployments that use container images with high severity vulnerabilities reported by Microsoft Defender for Containers.'
    displayName: '[Preview] Microsoft Defender for Containers should be enabled to block container images with high severity vulnerabilities'
    enforcementMode: 'Default'
    metadata: {
      assignedBy: 'ghas-defender-example-${environmentName}'
    }
    parameters: {
      effect: {
        value: 'Deny'
      }
    }
    policyDefinitionId: policyDefinitionId
  }
}

output assignmentName string = denyHighSeverityVulnerableImages.name
```

### A.12 `infra/modules/swa.bicep`

```bicep
targetScope = 'resourceGroup'

param environmentName string
param ghaDeployerPrincipalId string
param staticWebAppLocation string = 'westeurope'

var staticWebAppName = 'swa-${environmentName}'
var staticWebAppsContributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '554bd744-a2ac-4c1b-8f29-cd6d120cee34')

resource staticWebApp 'Microsoft.Web/staticSites@2023-12-01' = {
  name: staticWebAppName
  location: staticWebAppLocation
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {}
}

resource ghaStaticWebAppsContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: staticWebApp
  name: guid(staticWebApp.id, 'id-gha-deployer', staticWebAppsContributorRoleDefinitionId)
  properties: {
    principalId: ghaDeployerPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: staticWebAppsContributorRoleDefinitionId
  }
}

output staticWebAppName string = staticWebApp.name
output staticWebAppDefaultHostname string = staticWebApp.properties.defaultHostname
```

### A.13 `infra/modules/defender.bicep`

```bicep
targetScope = 'subscription'

var planNames = [
  'CloudPosture'
  'Containers'
  'KeyVaults'
  'OpenSourceRelationalDatabases'
  'Arm'
]

resource defenderPlans 'Microsoft.Security/pricings@2024-01-01' = [for planName in planNames: {
  name: planName
  properties: {
    pricingTier: 'Standard'
  }
}]

output enabledPlans array = [for (planName, i) in planNames: defenderPlans[i].name]
```

### A.14 `infra/modules/githubConnector.bicep`

```bicep
targetScope = 'resourceGroup'

param environmentName string
param location string
param githubOrg string
param githubRepo string

var connectorName = 'ghas-github-${environmentName}-${uniqueString(subscription().subscriptionId, githubOrg, githubRepo)}'

resource githubConnector 'Microsoft.Security/securityConnectors@2024-08-01-preview' = {
  name: connectorName
  location: location
  kind: 'GitHub'
  properties: {
    environmentData: {
      environmentType: 'GithubScope'
    }
    environmentName: 'GitHub'
    hierarchyIdentifier: '${githubOrg}/${githubRepo}'
    offerings: [
      {
        offeringType: 'CspmMonitorGithub'
      }
    ]
  }
}

output connectorName string = githubConnector.name
output connectorId string = githubConnector.id
```

### A.15 `infra/modules` creation command

```bash
mkdir -p infra/modules infra/tests
```

### A.16 `azure.yaml`

```yaml
name: ghas-defender-example
metadata:
  template: ghas-defender-example@1.0.0
infra:
  provider: bicep
  path: ./infra
  module: main
services:
  backend:
    project: ./src/backend
    language: java
    host: aks
    docker:
      path: ./Dockerfile
      context: .
  frontend:
    project: ./src/frontend
    language: ts
    host: staticwebapp
    dist: dist
hooks:
  postprovision:
    posix:
      shell: sh
      run: ./scripts/azd-hooks/postprovision.sh
    windows:
      shell: pwsh
      run: ./scripts/azd-hooks/postprovision.ps1
```

### A.17 `scripts/azd-hooks/postprovision.sh`

```sh
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
```

### A.18 `scripts/azd-hooks/postprovision.ps1`

```powershell
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
```

## Appendix B: Compile-only Bicep test files

### B.1 `infra/tests/network.test.bicep`

```bicep
targetScope = 'resourceGroup'

module network '../modules/network.bicep' = {
  name: 'network-test'
  params: {
    environmentName: 'test'
    location: 'westeurope'
  }
}

output vnetName string = network.outputs.vnetName
```

### B.2 `infra/tests/loganalytics.test.bicep`

```bicep
targetScope = 'resourceGroup'

module logAnalytics '../modules/loganalytics.bicep' = {
  name: 'loganalytics-test'
  params: {
    environmentName: 'test'
    location: 'westeurope'
  }
}

output workspaceName string = logAnalytics.outputs.workspaceName
```

### B.3 `infra/tests/identity.test.bicep`

```bicep
targetScope = 'resourceGroup'

module identity '../modules/identity.bicep' = {
  name: 'identity-test'
  params: {
    environmentName: 'test'
    githubOrg: 'JoranBergfeld'
    githubRepo: 'ghas-defender-example'
    location: 'westeurope'
  }
}

output backendClientId string = identity.outputs.backendClientId
```

### B.4 `infra/tests/keyvault.test.bicep`

```bicep
targetScope = 'resourceGroup'

module keyVault '../modules/keyvault.bicep' = {
  name: 'keyvault-test'
  params: {
    backendPrincipalId: '00000000-0000-0000-0000-000000000002'
    developerPrincipalId: '00000000-0000-0000-0000-000000000001'
    environmentName: 'test'
    keyVaultPrivateDnsZoneId: '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net'
    location: 'westeurope'
    privateEndpointSubnetId: '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-pe'
  }
}

output keyVaultName string = keyVault.outputs.keyVaultName
```

### B.5 `infra/tests/postgres.test.bicep`

```bicep
targetScope = 'resourceGroup'

module postgres '../modules/postgres.bicep' = {
  name: 'postgres-test'
  params: {
    environmentName: 'test'
    keyVaultName: 'kvtest1234567890'
    location: 'westeurope'
    postgresPrivateDnsZoneId: '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/privateDnsZones/privatelink.postgres.database.azure.com'
    postgresSubnetId: '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-pg'
  }
}

output postgresHost string = postgres.outputs.postgresHost
```

### B.6 `infra/tests/aks.test.bicep`

```bicep
targetScope = 'resourceGroup'

module aks '../modules/aks.bicep' = {
  name: 'aks-test'
  params: {
    aksSubnetId: '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-aks'
    backendIdentityName: 'id-backend'
    environmentName: 'test'
    ghaDeployerPrincipalId: '00000000-0000-0000-0000-000000000003'
    location: 'westeurope'
    logAnalyticsWorkspaceResourceId: '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/log-test'
  }
}

output oidcIssuerUrl string = aks.outputs.oidcIssuerUrl
```

### B.7 `infra/tests/acr.test.bicep`

```bicep
targetScope = 'resourceGroup'

module acr '../modules/acr.bicep' = {
  name: 'acr-test'
  params: {
    backendPrincipalId: '00000000-0000-0000-0000-000000000002'
    developerPrincipalId: '00000000-0000-0000-0000-000000000001'
    environmentName: 'test'
    ghaDeployerPrincipalId: '00000000-0000-0000-0000-000000000003'
    kubeletIdentityObjectId: '00000000-0000-0000-0000-000000000004'
    location: 'westeurope'
    privateEndpointSubnetId: '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-pe'
    registryPrivateDnsZoneId: '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io'
  }
}

output loginServer string = acr.outputs.loginServer
```

### B.8 `infra/tests/policy.test.bicep`

```bicep
targetScope = 'resourceGroup'

module policy '../modules/policy.bicep' = {
  name: 'policy-test'
  params: {
    environmentName: 'test'
  }
}

output assignmentName string = policy.outputs.assignmentName
```

### B.9 `infra/tests/swa.test.bicep`

```bicep
targetScope = 'resourceGroup'

module staticWebApp '../modules/swa.bicep' = {
  name: 'swa-test'
  params: {
    environmentName: 'test'
    ghaDeployerPrincipalId: '00000000-0000-0000-0000-000000000003'
  }
}

output staticWebAppName string = staticWebApp.outputs.staticWebAppName
```

### B.10 `infra/tests/defender.test.bicep`

```bicep
targetScope = 'subscription'

module defender '../modules/defender.bicep' = {
  name: 'defender-test'
}

output enabledPlans array = defender.outputs.enabledPlans
```

### B.11 `infra/tests/githubConnector.test.bicep`

```bicep
targetScope = 'resourceGroup'

module githubConnector '../modules/githubConnector.bicep' = {
  name: 'github-connector-test'
  params: {
    environmentName: 'test'
    githubOrg: 'JoranBergfeld'
    githubRepo: 'ghas-defender-example'
    location: 'westeurope'
  }
}

output connectorName string = githubConnector.outputs.connectorName
```

## Full verification commands

Run these after Task 14 and before opening a PR:

```bash
az bicep build --file infra/main.bicep
for file in infra/tests/*.test.bicep; do echo "building ${file}"; az bicep build --file "${file}" >/dev/null; done
export AZURE_PRINCIPAL_ID="$(az ad signed-in-user show --query id -o tsv)"
az deployment sub what-if \
  --location westeurope \
  --template-file infra/main.bicep \
  --parameters infra/main.parameters.json \
  --parameters environmentName=demo location=westeurope principalId="$AZURE_PRINCIPAL_ID" githubOrg=JoranBergfeld githubRepo=ghas-defender-example
azd provision
az aks get-credentials --resource-group rg-ghas-defender-demo --name aks-demo --overwrite-existing
kubectl get nodes
azd env get-values | grep '^AZURE_'
```

Expected final smoke output from `kubectl get nodes`:

```text
NAME                                STATUS   ROLES    AGE   VERSION
aks-systempool-00000000-vmss000000  Ready    <none>   10m   v1.30.x
aks-systempool-00000000-vmss000001  Ready    <none>   10m   v1.30.x
```

## Cross-plan assumptions

- Plan 5 will create namespace `app`, ServiceAccount `backend`, Kubernetes manifests, Flyway job, and ingress/IP app settings. Plan 4 only creates the UAMI federated credential for subject `system:serviceaccount:app:backend`.
- Plan 5 expects `AZURE_AKS_NAMESPACE=app`, ACR outputs, AKS cluster name, Key Vault outputs, and PostgreSQL outputs to be present in `azd env get-values`.
- Plan 6 expects `AZURE_GHA_DEPLOYER_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID` for repository variables.
- Plan 6 setup documentation will cover the one-time Defender for Cloud GitHub OAuth handshake.
- Plan 7 can seed IaC vulnerabilities by modifying `infra/modules/aks.bicep` and `infra/modules/postgres.bicep` on the `vulnerable` branch only.

## Open Questions

1. `Microsoft.Security/securityConnectors@2024-08-01-preview` is resource-group scoped in current Bicep type metadata. The user contract says subscription-scoped; this plan uses a resource-group-scoped module called from subscription `main.bicep` so `az bicep build` can succeed.
2. The Defender blocking policy is preview. If policy ID `af1b4f6f-8c7a-4a47-9013-f8e17bd45cec` is unavailable in the target tenant, replace only `infra/modules/policy.bicep` with the updated built-in policy ID and keep `Deny` mode.
3. AKS `1.30` may age out of `westeurope`. If unavailable, use the latest supported minor greater than `1.30` and update the PR body.
4. Static Web Apps regional support should be verified with `az staticwebapp list-locations`; this plan sets `westeurope` per the shared contract.
5. Raw `az deployment sub what-if` does not substitute azd `${...}` parameter placeholders; the plan uses explicit CLI parameter overrides for raw what-if and leaves `infra/main.parameters.json` azd-compatible.
