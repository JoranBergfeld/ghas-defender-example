# Demo Runbook

This runbook drives the four GHAS + Microsoft Defender for Cloud money moments for `ghas-defender-example`. It assumes the infrastructure and repository settings from the README bootstrap have already been applied, including GHAS enablement, branch protection, Defender plans, the Defender for Cloud GitHub connector, and `azd` environment outputs.

## Presenter checklist

Run these checks before the first scenario:

```bash
git --no-pager status --short --branch
gh auth status
az account show --query '{subscription:id, tenant:tenantId}' -o table
azd env get-values | grep -E 'AZURE_(LOCATION|RESOURCE_GROUP|AKS_CLUSTER_NAME|CONTAINER_REGISTRY_ENDPOINT)|VITE_API_BASE_URL'
```

Expected:

```text
## main...origin/main
Logged in to github.com as <your-user>
Subscription                          Tenant
------------------------------------  ------------------------------------
<subscription-id>                     <tenant-id>
AZURE_LOCATION="westeurope"
AZURE_RESOURCE_GROUP="rg-ghas-defender-demo"
AZURE_AKS_CLUSTER_NAME="aks-demo"
AZURE_CONTAINER_REGISTRY_ENDPOINT="<acr-name>.azurecr.io"
VITE_API_BASE_URL="https://<ingress-ip>.nip.io"
```

Use `secure` for successful deployment moments and `vulnerable` for failure-path moments. Do not remove seeded vulnerabilities from `vulnerable`; they are the demo.

---

## Scenario 1 — Secret pushed, blocked by push protection

### What this demonstrates

GitHub secret scanning push protection blocks a realistic token pattern at `git push`, before the fake credential reaches the remote repository.

### Prerequisites

- Work from a disposable local branch created from `secure`.
- Secret scanning and push protection are enabled on the repository.
- The setup command below injects only seeded vulnerability #4, using the path and label documented in `scripts/seed-vulnerabilities.md`.
- The fake token is generated locally from string pieces so the documentation never stores a complete token-shaped value; never use a real credential.
- The working tree is clean before creating the disposable branch.

### Setup

Run:

```bash
git fetch origin secure
git switch -c demo/secret-push origin/secure
python3 - <<'PY'
from pathlib import Path
path = Path('src/backend/src/main/resources/application-local.yml')
path.parent.mkdir(parents=True, exist_ok=True)
existing = path.read_text() if path.exists() else ''
if 'SEEDED VULN #4' not in existing:
    fake_token = 'ghp_' + ('A' * 40)
    addition = '\n# SEEDED VULN #4 — see scripts/seed-vulnerabilities.md\ngithub-token: ' + fake_token + '\n'
    path.write_text(existing.rstrip() + addition)
print(f'wrote fake token seed to {path}')
PY
git status --short
grep -n 'ghp_' src/backend/src/main/resources/application-local.yml | sed -E 's/(ghp_)[A-Za-z0-9_]+/\1<redacted fake token>/'
```

Expected:

```text
branch 'demo/secret-push' set up to track 'origin/secure'.
Switched to a new branch 'demo/secret-push'
wrote fake token seed to src/backend/src/main/resources/application-local.yml
 M src/backend/src/main/resources/application-local.yml
12:github-token: ghp_<redacted fake token>
```

### The demo action

Run:

```bash
git add src/backend/src/main/resources/application-local.yml
git commit -m "demo: add fake token for push protection"
git push origin HEAD:refs/heads/demo/secret-push
```

### What you see

Expected push rejection excerpt:

```text
Enumerating objects: 1, done.
Counting objects: 100% (1/1), done.
Writing objects: 100% (1/1), done.
remote: error: GH013: Repository rule violations found for refs/heads/demo/secret-push.
remote:
remote: - GITHUB PUSH PROTECTION
remote:   —————————————————————————————————————————
remote:     Resolve the following secrets before pushing again.
remote:
remote:     GitHub Personal Access Token
remote:     locations:
remote:       - commit: <commit-sha>
remote:         path: src/backend/src/main/resources/application-local.yml:<line>
remote:
remote:     To push, remove secret from commit(s) or follow the provided GitHub URL to review the blocked secret.
To github.com:JoranBergfeld/ghas-defender-example.git
 ! [remote rejected] HEAD -> demo/secret-push (push declined due to repository rule violations)
error: failed to push some refs to 'github.com:JoranBergfeld/ghas-defender-example.git'
```

In the GitHub web UI, the push protection page names the detector as `GitHub Personal Access Token`, shows the repository and path, and offers remediation guidance. Do not allow the fake token unless the presenter intentionally wants to demonstrate the bypass review flow.

### Screenshot anchor

<!-- Screenshot: scenario-1-push-protection.png — should show the GitHub push protection rejection for `src/backend/src/main/resources/application-local.yml`, including the `GitHub Personal Access Token` detector and remediation guidance. -->

### Why this matters

This is the cleanest shift-left moment in the demo: a credential-shaped value is stopped before it becomes repository history. GHAS reduces blast radius by preventing secret exposure at the source, while the audit trail and remediation guidance give security teams a consistent workflow that does not depend on a later scan catching the issue.

### Reset

Run:

```bash
git switch main
git branch -D demo/secret-push
git ls-remote --heads origin demo/secret-push
```

Expected:

```text
Switched to branch 'main'
Deleted branch demo/secret-push (was <commit>).
```

`git ls-remote` should print no matching remote branch because push protection blocked the branch creation.

---

## Scenario 2 — PR with SQL injection, blocked by CodeQL

### What this demonstrates

CodeQL detects a SQL injection in a pull request and the required `backend-ci / codeql` check prevents the vulnerable change from merging into `secure`.

### Prerequisites

- `secure` is up to date and clean.
- `vulnerable` contains seeded vulnerability #1 in `ItemController.java`.
- Branch protection on `secure` requires `backend-ci / codeql`.
- The presenter can create and close pull requests in the repository.

### Setup

Run:

```bash
git fetch origin secure vulnerable
git switch -c demo/sqli origin/secure
ITEM_CONTROLLER="$(git ls-files 'src/backend/src/main/java/**/ItemController.java' | head -n 1)"
printf 'Using %s\n' "$ITEM_CONTROLLER"
git checkout origin/vulnerable -- "$ITEM_CONTROLLER"
git diff -- "$ITEM_CONTROLLER"
```

Expected diff excerpt:

```diff
Using src/backend/src/main/java/<package>/items/ItemController.java
-        return itemRepository.searchByName(q);
+        // SEEDED VULN #1 — see scripts/seed-vulnerabilities.md
+        return entityManager
+            .createNativeQuery("SELECT * FROM items WHERE name LIKE '%" + q + "%'", Item.class)
+            .getResultList();
```

Commit and push the demo branch:

```bash
git add "$ITEM_CONTROLLER"
git commit -m "demo: introduce sql injection for codeql"
git push -u origin demo/sqli
```

Expected:

```text
[demo/sqli <commit>] demo: introduce sql injection for codeql
 1 file changed, <insertions> insertions(+), <deletions> deletions(-)
branch 'demo/sqli' set up to track 'origin/demo/sqli'.
```

### The demo action

Run:

```bash
gh pr create \
  --base secure \
  --head demo/sqli \
  --title "Demo: SQL injection should be blocked" \
  --body "Introduces seeded vulnerability #1 so CodeQL can block the PR."

gh pr checks --watch
```

### What you see

Expected `gh pr checks --watch` excerpt after the workflow completes:

```text
backend-ci / build-test     pass     <duration>  https://github.com/JoranBergfeld/ghas-defender-example/actions/runs/<run-id>
backend-ci / codeql         fail     <duration>  https://github.com/JoranBergfeld/ghas-defender-example/actions/runs/<run-id>
frontend-ci / build-test    skipped  <duration>  https://github.com/JoranBergfeld/ghas-defender-example/actions/runs/<run-id>
infra / what-if             skipped  <duration>  https://github.com/JoranBergfeld/ghas-defender-example/actions/runs/<run-id>
```

Expected CodeQL alert details in the GitHub UI:

```text
Database query built from user-controlled sources
Rule ID: java/sql-injection
Severity: error
Path: src/backend/src/main/java/<package>/items/ItemController.java
Branch: demo/sqli
```

Expected pull request merge box text:

```text
Merging is blocked
1 required status check failed
backend-ci / codeql
```

You can also inspect the alert through the API:

```bash
gh api repos/JoranBergfeld/ghas-defender-example/code-scanning/alerts \
  -f state=open \
  -f ref=refs/heads/demo/sqli \
  --jq '.[] | select(.rule.id == "java/sql-injection") | [.rule.id, .rule.severity, .most_recent_instance.location.path] | @tsv'
```

Expected:

```text
java/sql-injection	error	src/backend/src/main/java/<package>/items/ItemController.java
```

### Screenshot anchor

<!-- Screenshot: scenario-2-codeql-required-check.png — should show the pull request into `secure` with `backend-ci / codeql` failing, the merge box blocked, and the CodeQL `java/sql-injection` alert details. -->

### Why this matters

This scenario shows the policy value of GHAS: the vulnerable change is visible to the developer with a precise code location, but branch protection prevents it from becoming the trusted `secure` demo baseline. Security review moves from an after-the-fact audit to an enforceable pull request gate.

### Reset

Run:

```bash
PR_NUMBER="$(gh pr list --head demo/sqli --state open --json number --jq '.[0].number // empty')"
if [ -n "$PR_NUMBER" ]; then
  gh pr close "$PR_NUMBER" --delete-branch
else
  git push origin --delete demo/sqli || true
fi
git switch secure
git branch -D demo/sqli
```

Expected:

```text
✓ Closed pull request JoranBergfeld/ghas-defender-example#<number> (Demo: SQL injection should be blocked)
✓ Deleted branch demo/sqli and switched to branch secure
Deleted branch demo/sqli (was <commit>).
```

---

## Scenario 3 — Vulnerable container reaches ACR, Defender denies the AKS pod

### What this demonstrates

Defender for Containers scans the vulnerable image after it reaches ACR and the Defender-managed AKS admission policy denies the Deployment before vulnerable pods run.

### Prerequisites

- `secure` has deployed successfully at least once.
- `vulnerable` contains seeded vulnerability #6 in `src/backend/Dockerfile`.
- Defender for Containers, the AKS Defender profile, and the Azure Policy add-on are enabled.
- The Defender image assessment has had time to process images in ACR; allow 10–30 minutes after first enablement in a fresh subscription.
- Scenario 1 injects seeded vulnerability #4 into a disposable branch created from `secure`; it does not change `vulnerable`, so this push demonstrates Defender admission rather than push protection.

### Setup

Run:

```bash
git fetch origin secure vulnerable
git switch vulnerable
git pull --ff-only origin vulnerable
azd env select demo
RG="$(azd env get-value AZURE_RESOURCE_GROUP)"
AKS="$(azd env get-value AZURE_AKS_CLUSTER_NAME)"
ACR="$(azd env get-value AZURE_CONTAINER_REGISTRY_ENDPOINT)"
az aks get-credentials --resource-group "$RG" --name "$AKS" --overwrite-existing
kubectl get deployment backend -n app
printf 'ACR endpoint: %s\n' "$ACR"
```

Expected:

```text
Switched to branch 'vulnerable'
Already up to date.
Merged "aks-demo" as current context in <kubeconfig>
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
backend   1/1     1            1           <age>
ACR endpoint: <acr-name>.azurecr.io
```

Check that the vulnerable Dockerfile seed is present:

```bash
grep -n 'SEEDED VULN #6' src/backend/Dockerfile
```

Expected:

```text
<line>:# SEEDED VULN #6 — see scripts/seed-vulnerabilities.md
```

### The demo action

Run the backend path-filter trigger and push the `vulnerable` branch:

```bash
date -u +%Y-%m-%dT%H:%M:%SZ > src/backend/.demo-trigger
git add src/backend/.demo-trigger
git commit -m "demo: redeploy vulnerable backend image"
git push origin vulnerable
gh run watch --workflow backend-ci.yml --branch vulnerable --exit-status
```

### What you see

Expected GitHub Actions deploy failure excerpt from `backend-ci.yml`:

```text
Run azd deploy backend --no-prompt
Packaging service backend...
Pushing image <acr-name>.azurecr.io/backend:<commit-sha>...
Applying Kubernetes manifests...
Error from server (Forbidden): error when creating "STDIN": admission webhook "validation.gatekeeper.sh" denied the request:
[azurepolicy-container-vulnerability-assessment] Container image "<acr-name>.azurecr.io/backend:<commit-sha>" has high severity vulnerabilities and is not allowed by Microsoft Defender for Containers policy.
Error: deployment failed: backend rollout did not complete
```

Expected Kubernetes event excerpt:

```bash
kubectl get events -n app --sort-by=.lastTimestamp | tail -n 12
```

```text
LAST SEEN   TYPE      REASON        OBJECT                            MESSAGE
<time>      Warning   FailedCreate  replicaset/backend-<hash>          Error creating: admission webhook "validation.gatekeeper.sh" denied the request: [azurepolicy-container-vulnerability-assessment] Container image "<acr-name>.azurecr.io/backend:<commit-sha>" has high severity vulnerabilities
```

Expected rollout status:

```bash
kubectl rollout status deployment/backend -n app --timeout=60s
```

```text
error: deployment "backend" exceeded its progress deadline
```

Expected Defender for Cloud container image assessment signal in Azure CLI:

```bash
az graph query -q "securityresources | where type =~ 'microsoft.security/assessments/subassessments' | where tostring(properties.resourceDetails.id) has 'backend' | project assessment=tostring(properties.displayName), status=tostring(properties.status.code), severity=tostring(properties.status.severity), resource=tostring(properties.resourceDetails.id) | take 5" -o table
```

```text
Assessment                                      Status     Severity  Resource
---------------------------------------------- ---------- --------- ----------------------------------------------
Container registry images should have findings Unhealthy  High      <acr-image-resource-id-containing-backend>
```

### Screenshot anchor

<!-- Screenshot: scenario-3-defender-admission-deny.png — should show the failed `backend-ci.yml` deploy log or AKS event where `validation.gatekeeper.sh` denies `<acr-name>.azurecr.io/backend:<commit-sha>` because Defender found high-severity container vulnerabilities. -->

### Why this matters

This is the runtime gate: even when a risky image is built and pushed, Defender for Containers supplies a Kubernetes admission control decision that prevents the vulnerable workload from starting. GHAS blocks issues earlier in the lifecycle; Defender adds cloud-aware enforcement at the deployment boundary.

### Reset

Run:

```bash
git switch secure
git pull --ff-only origin secure
date -u +%Y-%m-%dT%H:%M:%SZ > src/backend/.demo-trigger
git add src/backend/.demo-trigger
git commit -m "demo: redeploy secure backend image"
git push origin secure
gh run watch --workflow backend-ci.yml --branch secure --exit-status
kubectl rollout status deployment/backend -n app --timeout=180s
```

Expected:

```text
Switched to branch 'secure'
Already up to date.
[secure <commit>] demo: redeploy secure backend image
 1 file changed, 1 insertion(+)
✓ backend-ci.yml completed successfully
Waiting for deployment "backend" rollout to finish: 1 old replicas are pending termination...
deployment "backend" successfully rolled out
```

---

## Scenario 4 — Code-to-cloud correlation in Defender for Cloud

### What this demonstrates

Defender for Cloud DevOps Security connects GHAS findings from the repository to the deployed AKS workload so teams can prioritize source fixes by cloud exposure.

### Prerequisites

- The Defender for Cloud GitHub connector exists and the GitHub OAuth handshake has been completed in the Azure portal.
- Defender CSPM Standard and Defender for Containers are enabled.
- `secure` is deployed and running on AKS.
- At least one GHAS finding exists on `vulnerable` or a demo pull request branch, such as the SQL injection from Scenario 2.
- Defender ingestion has had time to refresh. In a new environment, wait 15–45 minutes after connector authorization or after the first GHAS alert appears.

### Setup

Run:

```bash
azd env select demo
SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
RG="$(azd env get-value AZURE_RESOURCE_GROUP)"
AKS="$(azd env get-value AZURE_AKS_CLUSTER_NAME)"
AKS_ID="$(az resource show --resource-group "$RG" --name "$AKS" --resource-type Microsoft.ContainerService/managedClusters --query id -o tsv)"
printf 'Subscription: %s\nResource group: %s\nAKS resource ID: %s\n' "$SUBSCRIPTION_ID" "$RG" "$AKS_ID"

gh api repos/JoranBergfeld/ghas-defender-example/code-scanning/alerts \
  -f state=open \
  -f per_page=10 \
  --jq '.[] | [.rule.id, .rule.severity, .most_recent_instance.location.path] | @tsv'
```

Expected:

```text
Subscription: <subscription-id>
Resource group: rg-ghas-defender-demo
AKS resource ID: /subscriptions/<subscription-id>/resourceGroups/rg-ghas-defender-demo/providers/Microsoft.ContainerService/managedClusters/aks-demo
java/sql-injection	error	src/backend/src/main/java/<package>/items/ItemController.java
js/xss	error	src/frontend/src/components/SearchResults.tsx
```

Open the Defender for Cloud portal:

```bash
az portal dashboard show >/dev/null 2>&1 || true
printf 'Open: https://portal.azure.com/#view/Microsoft_Azure_Security/SecurityMenuBlade/~/DevOpsSecurity\n'
```

Expected:

```text
Open: https://portal.azure.com/#view/Microsoft_Azure_Security/SecurityMenuBlade/~/DevOpsSecurity
```

### The demo action

In the Azure portal:

1. Open **Microsoft Defender for Cloud**.
2. Select **DevOps Security**.
3. Select the GitHub connector for `JoranBergfeld/ghas-defender-example`.
4. Open the repository view and filter to open code scanning findings.
5. Select the SQL injection finding from `ItemController.java` or the XSS finding from `SearchResults.tsx`.
6. Open the related cloud resource or attack path panel that references the AKS workload, image, or Kubernetes Deployment.

### What you see

Expected portal text and layout:

```text
Defender for Cloud > DevOps Security
Connector: GitHub
Repository: JoranBergfeld/ghas-defender-example
Branch: vulnerable
Tool: GitHub Advanced Security / CodeQL
Finding: java/sql-injection
File: src/backend/src/main/java/<package>/items/ItemController.java
Related cloud resource: aks-demo / namespace app / deployment backend
Exposure: Running workload or container image associated with the repository finding
```

Expected Azure Resource Graph sanity check for DevOps connector resources:

```bash
az graph query -q "resources | where type =~ 'microsoft.security/securityconnectors' | project name, type, location, resourceGroup | take 10" -o table
```

```text
Name                         Type                                   Location    ResourceGroup
---------------------------  -------------------------------------  ----------  ---------------------
github-ghas-defender-demo     microsoft.security/securityconnectors  westeurope  rg-ghas-defender-demo
```

Expected Defender assessment sanity check for the AKS resource:

```bash
az graph query -q "securityresources | where type =~ 'microsoft.security/assessments' | where tostring(properties.resourceDetails.Id) has 'aks-demo' | project displayName=tostring(properties.displayName), status=tostring(properties.status.code) | take 5" -o table
```

```text
DisplayName                                      Status
-----------------------------------------------  ---------
Microsoft Defender for Containers should be enabled Healthy
Kubernetes clusters should not allow vulnerable images Unhealthy
```

### Screenshot anchor

<!-- Screenshot: scenario-4-code-to-cloud-correlation.png — should show Defender for Cloud DevOps Security for `JoranBergfeld/ghas-defender-example` with a GHAS CodeQL finding linked to the AKS `backend` workload or container image. -->

### Why this matters

This is the executive-level close of the demo. GHAS identifies the risky source change, Defender knows whether the affected code is connected to a running cloud workload, and security teams can prioritize remediation based on real exposure instead of treating all repository alerts as equal.

### Reset

Scenario 4 is read-only. To return the environment to a clean demo state, close any demo pull requests from Scenario 2 and redeploy `secure` after Scenario 3:

```bash
git switch secure
git pull --ff-only origin secure
kubectl rollout status deployment/backend -n app --timeout=180s
gh pr list --state open --search 'head:demo/sqli' --json number,title
```

Expected:

```text
Switched to branch 'secure'
Already up to date.
deployment "backend" successfully rolled out
[]
```

---

## Reset the demo between full runs

Use this sequence after running all scenarios or whenever the environment needs to return to the clean `secure` baseline.

### 1. Close demo pull requests and delete demo branches

```bash
for branch in demo/sqli demo/secret-push; do
  pr_number="$(gh pr list --head "$branch" --state open --json number --jq '.[0].number // empty')"
  if [ -n "$pr_number" ]; then
    gh pr close "$pr_number" --delete-branch
  else
    git push origin --delete "$branch" 2>/dev/null || true
  fi
  git branch -D "$branch" 2>/dev/null || true
done
```

Expected:

```text
✓ Closed pull request JoranBergfeld/ghas-defender-example#<number> (<title>)
Deleted branch demo/sqli (was <commit>).
```

If a branch never reached GitHub because push protection blocked it, the delete command is allowed to print nothing.

### 2. Return the local worktree to `secure`

```bash
git fetch origin secure vulnerable main
git switch secure
git reset --hard origin/secure
git clean -fd
git status --short --branch
```

Expected:

```text
Switched to branch 'secure'
HEAD is now at <commit> <secure branch commit subject>
## secure...origin/secure
```

### 3. Redeploy the clean backend and frontend

```bash
azd env select demo
azd deploy backend --no-prompt
azd deploy frontend --no-prompt
RG="$(azd env get-value AZURE_RESOURCE_GROUP)"
AKS="$(azd env get-value AZURE_AKS_CLUSTER_NAME)"
az aks get-credentials --resource-group "$RG" --name "$AKS" --overwrite-existing
kubectl rollout status deployment/backend -n app --timeout=180s
```

Expected:

```text
Deploying service backend...
SUCCESS: Your application was deployed to Azure in <duration>.
Deploying service frontend...
SUCCESS: Your application was deployed to Azure in <duration>.
deployment "backend" successfully rolled out
```

### 4. Confirm endpoint values and backend readiness

```bash
API_BASE_URL="$(azd env get-value VITE_API_BASE_URL)"
printf 'API: %s\n' "$API_BASE_URL"
kubectl get ingress -n app
kubectl get pods -n app -l app=backend
```

Expected:

```text
API: https://<ingress-ip>.nip.io
NAME      CLASS   HOSTS                 ADDRESS        PORTS   AGE
backend   webapprouting.kubernetes.azure.com   <ingress-ip>.nip.io   <ingress-ip>   80      <age>
NAME                       READY   STATUS    RESTARTS   AGE
backend-<replicaset>-<pod> 1/1     Running   0          <age>
```

### 5. Tear down Azure resources when the demo is finished

```bash
azd down --purge
```

Expected:

```text
? Total resources to delete: <count>, are you sure you want to continue? Yes
Deleting resource group rg-ghas-defender-demo...
SUCCESS: Your application was removed from Azure in <duration>.
```

Run teardown when the environment is not needed. The demo uses paid Azure resources, including AKS nodes, ACR Premium, Static Web Apps Standard, PostgreSQL, Log Analytics ingestion, and Defender plans.
