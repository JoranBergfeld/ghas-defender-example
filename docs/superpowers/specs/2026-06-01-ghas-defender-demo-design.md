# GHAS + Defender for Cloud Demo — Design

**Date:** 2026-06-01
**Status:** Approved (brainstorming)
**Owner:** Joran Bergfeld
**Repository:** [`JoranBergfeld/ghas-defender-example`](https://github.com/JoranBergfeld/ghas-defender-example)

---

## 1. Goal & Demo Narrative

A self-contained, `azd up`-deployable demo that proves the joint value of **GitHub Advanced Security (GHAS)** for shift-left "block at the source" and **Microsoft Defender for Cloud / Containers** for runtime/admission "block at the gate" — with end-to-end **code-to-cloud correlation** in Defender for Cloud (GA May 2026).

### Audience

Engineers and architects evaluating GHAS + Defender. The demo can be driven live or self-paced via `docs/DEMO.md`.

### The four "money moments"

Each maps to a scenario in `docs/DEMO.md`.

1. **Secret pushed → blocked at `git push`** by GitHub Secret Scanning *push protection*. Never reaches the server.
2. **PR with SQL injection → CodeQL fails the required check** on the `secure` branch. PR cannot merge.
3. **Vulnerable container image reaches ACR → Defender for Containers scans it → AKS admission controller (Azure Policy add-on, Defender-managed policy) blocks the Deployment** on the `vulnerable` branch.
4. **Defender for Cloud DevOps blade shows GHAS findings tied to the running AKS workload** via the GitHub connector (code-to-cloud correlation).

### Branch model

| Branch | Role | Branch protection | Deployment behaviour |
| --- | --- | --- | --- |
| `main` | Development trunk | PR + CI required | CI runs, no deploys |
| `secure` | "Happy path" demo branch (cherry-picked from `main`) | PR + CodeQL + CI + what-if required | `azd provision` + `azd deploy` succeed end-to-end |
| `vulnerable` | "Failure path" demo branch (cherry-picked from `main`, plus seeded vulns) | Same as `secure` | CodeQL alerts fire; container build succeeds and reaches ACR; AKS admission controller denies the Deployment |

### Non-goals

Multi-environment (single `demo` env), custom domains/TLS beyond AKS default, WAF, autoscaling, GitOps (Flux/Argo), production-grade RBAC or cost hardening.

---

## 2. Repository Layout

```
.
├── azure.yaml                       # azd manifest: services + hooks
├── README.md                        # Setup + bootstrap
├── docs/
│   ├── DEMO.md                      # Four-scenario walkthrough
│   ├── ARCHITECTURE.md              # Mermaid diagrams + component table
│   └── superpowers/specs/           # Brainstorm + plan artifacts (this file)
├── infra/
│   ├── main.bicep                   # Subscription-scoped entry
│   ├── main.parameters.json
│   └── modules/
│       ├── network.bicep            # vnet, subnets, NSGs, private DNS zones
│       ├── identity.bicep           # UAMIs + federated credentials + role assignments
│       ├── acr.bicep                # Premium ACR + private endpoint
│       ├── aks.bicep                # AKS + Azure Policy add-on + Defender profile + ingress
│       ├── postgres.bicep           # PostgreSQL Flexible Server + private endpoint
│       ├── swa.bicep                # Static Web Apps Standard
│       ├── keyvault.bicep           # KV (RBAC auth, private endpoint)
│       ├── loganalytics.bicep       # Workspace + diagnostic-settings collector
│       └── defender.bicep           # Subscription-scoped Defender plans + GH connector
├── src/
│   ├── frontend/                    # React (Vite + TypeScript)
│   │   ├── package.json
│   │   ├── src/
│   │   └── staticwebapp.config.json
│   └── backend/                     # Spring Boot (Java 21, Maven)
│       ├── pom.xml
│       ├── src/main/java/...
│       ├── src/main/resources/
│       ├── Dockerfile               # Intentionally insecure on `vulnerable` branch
│       └── k8s/
│           ├── deployment.yaml
│           ├── service.yaml
│           └── ingress.yaml
├── scripts/
│   ├── azd-hooks/                   # postprovision, predeploy, etc.
│   ├── setup-repo.sh                # Sets GH repo vars, enables scanning, applies branch protection
│   └── seed-vulnerabilities.md      # Inventory of which branch has which seeded issue
└── .github/
    ├── dependabot.yml
    ├── CODEOWNERS
    ├── codeql-config.yml            # Shared CodeQL config (queries, paths)
    └── workflows/
        ├── frontend-ci.yml          # Build, test, CodeQL JS/TS, deploy to SWA
        ├── backend-ci.yml           # Build, test, CodeQL Java, image build & push to ACR, AKS deploy
        └── infra.yml                # Bicep lint + what-if on PR; provision on push to demo branches
```

### Layout conventions

- Each Bicep module exports only typed outputs other modules need; modules do not reference each other directly. `main.bicep` is the single wiring layer.
- `src/backend/k8s/` ships raw manifests (no Helm/Kustomize) for readability. The image tag is patched at deploy time via `kubectl set image` (or by `azd deploy` when using `host: aks`).
- `scripts/azd-hooks/postprovision` handles non-declarative bootstrap (kubeconfig, Flyway job, ingress IP capture).

---

## 3. Application Architecture

### Frontend

- React 18 + TypeScript + Vite, deployed to **Azure Static Web Apps (Standard)**.
- Talks to backend via HTTPS through its public AKS ingress URL, configured at build time via `VITE_API_BASE_URL` (set as an SWA app setting and injected during build).
- Backend CORS allowlist includes the SWA hostname.

### Backend

- Java 21, Spring Boot 3.x, Maven.
- Single REST module exposing `/api/items` (CRUD over PostgreSQL) and `/api/auth/login` (JWT).
- JPA + Hibernate against PostgreSQL Flexible Server.
- Spring profile `cloud` resolves secrets from Azure Key Vault via **AKS Workload Identity** (federated to a UAMI with the `Key Vault Secrets User` role). No secrets in environment variables or manifests.
- Schema (`items`, `users`) is bootstrapped by a one-time **Flyway `Job`** applied by the azd `postprovision` hook. Backend pods do **not** run Flyway on start (keeps app pods stateless and avoids race conditions on rollout).

### Container image

Multi-stage Dockerfile (`src/backend/Dockerfile`):

- **Build stage:** `eclipse-temurin:21-jdk` with Maven wrapper.
- **Runtime stage:**
  - `secure` branch — `eclipse-temurin:21-jre-alpine`, `USER 1001`, `HEALTHCHECK`, minimal copy surface.
  - `vulnerable` branch — `eclipse-temurin:21-jdk` (large, many OS CVEs), runs as `root`, no `HEALTHCHECK`, copies whole build context.
- Pushed to ACR as `backend:<git-sha>` and tagged with the branch name.

### Persistence

- Azure Database for **PostgreSQL Flexible Server**, private access only.
- Subnet delegation to `Microsoft.DBforPostgreSQL/flexibleServers`.
- Private DNS zone `privatelink.postgres.database.azure.com` linked to the vnet.
- Single `appdb` database, single `app` user; admin password generated by Bicep `newGuid()` and stored in Key Vault.

### Networking

Single vnet (no hub), CIDR `10.40.0.0/16`:

| Subnet | CIDR | Purpose |
| --- | --- | --- |
| `snet-aks` | `10.40.0.0/22` | Azure CNI Overlay node pool |
| `snet-pg` | `10.40.4.0/27` | Delegated to PostgreSQL Flexible Server |
| `snet-pe` | `10.40.4.32/27` | Private endpoints (Key Vault, ACR) |

AKS uses a **public API server** (acceptable for a demo). Ingress via the built-in **NGINX Ingress Controller** add-on (`ingressProfile.webAppRouting.enabled = true`); external IP exposed via a LoadBalancer service.

### Identity in the cluster

- AKS OIDC issuer + Workload Identity add-on enabled.
- One Kubernetes ServiceAccount (`backend`) in namespace `app`, federated to a UAMI (`id-backend`) granted `Key Vault Secrets User` and `AcrPull`.
- AKS pulls from ACR via the kubelet identity (configured by `--attach-acr`).

---

## 4. Seeded Vulnerabilities

Each item is **present on `vulnerable`, absent on `secure`**. The full inventory lives in `scripts/seed-vulnerabilities.md`; a single `git diff secure vulnerable` shows ~10–15 surgical changes, each labelled with `// SEEDED VULN #N — see scripts/seed-vulnerabilities.md`.

| # | Category | Where | Concrete seed |
| --- | --- | --- | --- |
| 1 | **SAST — SQL injection** (CodeQL Java `java/sql-injection`) | `backend/.../ItemController.java` | `entityManager.createNativeQuery("SELECT * FROM items WHERE name LIKE '%" + q + "%'")` instead of a parameterized query |
| 2 | **SAST — XSS** (CodeQL JS `js/xss`) | `frontend/src/components/SearchResults.tsx` | `dangerouslySetInnerHTML={{ __html: serverResponse }}` on unescaped backend payload |
| 3 | **SAST — Hardcoded crypto key** (CodeQL Java `java/hardcoded-credentials`) | `backend/.../JwtConfig.java` | `private static final String JWT_SECRET = "supersecret_demo_key_do_not_use";` |
| 4 | **Secret Scanning — Pushed token** | `backend/src/main/resources/application-local.yml` | A realistic-looking **GitHub PAT-pattern token** (`ghp_<40 chars>`) generated dynamically at seed time. Triggers push protection on demo branches. |
| 5 | **Dependency (Dependabot)** | `backend/pom.xml`, `frontend/package.json` | Pin a known-vulnerable older `org.springframework:spring-core` and an older `axios`. Dependabot opens alerts + auto-PRs. |
| 6 | **Container** (Defender for Containers) | `backend/Dockerfile` | Base on `eclipse-temurin:21-jdk`, run as `root`, no `HEALTHCHECK`, copy whole build context |
| 7 | **IaC misconfig** (CodeQL for IaC) | `infra/modules/aks.bicep`, `infra/modules/postgres.bicep` | AKS with `enableRbac: false` and empty `authorizedIpRanges`; PostgreSQL with `publicNetworkAccess: 'Enabled'` and weak admin user |

### Safety guardrails

- The "secret" in #4 is a **fake token generated at seed time** matching GitHub's PAT pattern detector. Never a real credential. The seeding script is documented in `scripts/seed-vulnerabilities.md`; the token only ever exists in the history of the `vulnerable` branch.
- The vulnerable container in #6 still *runs* if you bypass admission control. The demo's point is that Defender's admission controller prevents that in AKS.
- The IaC misconfigurations in #7 are deliberately scoped so that even if applied, they affect only the demo subscription/RG.

---

## 5. Azure Infrastructure (Bicep)

### Scope and entry point

- `main.bicep` deploys at **subscription scope** so it can create the resource group and enable Defender plans in one shot.
- Single resource group: `rg-ghas-defender-<azd_env_name>` (default `rg-ghas-defender-demo`).

### Module wiring

```
main.bicep (subscription)
 ├── defender.bicep         (sub-scope) → enables Defender plans + GH connector
 ├── resourceGroup
 └── module group (rg-scope) in dependency order:
      ├── network          → vnet, subnets, NSGs, private DNS zones
      ├── loganalytics     → workspace + diagnostic-settings collector
      ├── identity         → UAMI for backend + UAMI for GH Actions + role assignments
      ├── keyvault         → KV w/ private endpoint, RBAC auth
      ├── acr              → Premium ACR w/ private endpoint
      ├── postgres         → Flexible Server (private), Flyway-friendly schema setup
      ├── aks              → Managed cluster (see config below)
      ├── swa              → Static Web Apps Standard
      └── (defender.bicep's GH connector output wired back as readable info)
```

### Defender plans enabled (subscription-wide)

- **Defender CSPM (Standard)** — required for code-to-cloud correlation.
- **Defender for Containers** — ACR image scanning, runtime sensor, Defender admission policy.
- **Defender for Key Vault**.
- **Defender for Open-Source Relational Databases** — covers PostgreSQL Flex.
- **Defender for Resource Manager**.

### AKS configuration

- Kubernetes ≥ 1.30, system node pool `Standard_D2as_v5` × 2.
- **Azure CNI Overlay** networking.
- **OIDC issuer + Workload Identity** add-ons enabled.
- **Azure Policy add-on** enabled (Gatekeeper engine).
- **Defender profile** enabled: `securityProfile.defender.securityMonitoring.enabled = true` (deploys Defender sensor DaemonSet + admission webhook).
- **NGINX Ingress** via `ingressProfile.webAppRouting.enabled = true`.
- **Azure Policy assignment** at RG scope: the built-in Defender policy *"[Preview] Microsoft Defender for Containers should be enabled to block container images with high severity vulnerabilities"* in `deny` mode. This is what physically denies the pod on the `vulnerable` branch.

### GitHub connector for Defender for Cloud

- `Microsoft.Security/securityConnectors` of kind `GitHub`, created in Bicep.
- The **GitHub OAuth handshake** in the Azure portal must be completed once by a human (documented in README); Bicep cannot automate consent.

### Parameters

`main.parameters.json` is driven by azd env vars:

- `environmentName` ← `${AZURE_ENV_NAME}`
- `location` ← `${AZURE_LOCATION}` (default `westeurope`)
- `principalId` ← `${AZURE_PRINCIPAL_ID}` (developer running `azd up`; granted KV admin + ACR push for inspection)
- `githubOrg`, `githubRepo` — for the connector and federated credentials

---

## 6. GitHub Actions Workflows

Three workflows, all using **OIDC federated credentials** (no client secrets). Path filters keep them independent.

### `infra.yml`

- **Triggers:** `pull_request` and `push` against `main` / `secure` / `vulnerable` when `infra/**` or `azure.yaml` changes.
- **PR job:**
  - `bicep build` and `az bicep lint`.
  - `az deployment sub what-if` against the demo subscription; post a sticky PR comment with the diff (e.g., `marocchino/sticky-pull-request-comment`).
  - **CodeQL for IaC** (`config-files` language) + **PSRule for Azure** (advisory).
- **Push job (demo branches only):** `azd provision` against the matching environment.

### `backend-ci.yml`

- **Triggers:** `pull_request` and `push` to `main` / `secure` / `vulnerable` when `src/backend/**` changes.
- **Jobs (parallel where possible):**
  - `build-test` — Maven build + unit tests, Surefire SARIF upload.
  - `codeql` — `github/codeql-action/init@v3` with `java-kotlin`, autobuild, analyze; fail on severity ≥ high via `.github/codeql-config.yml`.
  - `dependency-review` — `actions/dependency-review-action@v4` on PRs only.
- **On push to demo branches (sequential after the above):**
  - `deploy` — single job that runs `azd deploy backend` (with `host: aks` from `azure.yaml`, azd builds the image, OIDC-pushes to ACR as `backend:${{ github.sha }}` + `backend:<branch>`, applies `src/backend/k8s/*.yaml` with the image tag substituted, and waits on rollout). No CI-side scan; Defender does it post-push. On `vulnerable` the rollout fails because the admission controller denies the pod creation — the workflow exits non-zero, which **is** the demo moment.

### `frontend-ci.yml`

- **Triggers:** `pull_request` and `push` when `src/frontend/**` changes.
- **Jobs (parallel where possible):**
  - `build-test` — `npm ci` → lint → Vitest → `npm run build`.
  - `codeql` — separate job: `github/codeql-action/init@v3` with `javascript-typescript`, analyze; fail on severity ≥ high via `.github/codeql-config.yml`.
- **On push to demo branches (after the above):** single `deploy` job runs `azd deploy frontend` (with `host: staticwebapp` from `azure.yaml`, azd fetches the SWA deployment token via OIDC and uploads `dist/`).

### Shared `.github/codeql-config.yml`

- `queries: security-extended` for both languages.
- Path filters exclude `**/test/**` and `**/*.spec.ts`.

### Reusable patterns

- `permissions:` block is least-privilege per job: only OIDC-using jobs get `id-token: write`.
- `concurrency` group per branch prevents overlapping deploys.
- **Required status checks for branch protection:** `infra / what-if`, `backend-ci / codeql`, `backend-ci / build-test`, `frontend-ci / codeql`, `frontend-ci / build-test`.

---

## 7. azd Integration

### `azure.yaml`

```yaml
name: ghas-defender-example
metadata:
  template: ghas-defender-example@1.0.0
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

- **`host: aks`** — `azd` builds the image, pushes to the linked ACR, applies `src/backend/k8s/*.yaml` with image-tag substitution.
- **`host: staticwebapp`** — `azd` runs `npm run build` and uploads `dist/` to SWA using the deployment token from infra outputs.

### Infra ↔ azd outputs

| Output | Consumer |
| --- | --- |
| `AZURE_CONTAINER_REGISTRY_ENDPOINT` | `azd deploy backend` (`host: aks`) |
| `AZURE_AKS_CLUSTER_NAME`, `AZURE_RESOURCE_GROUP` | `azd deploy backend` + `kubectl` steps |
| `AZURE_AKS_NAMESPACE` (default `app`) | k8s manifests + ServiceAccount binding |
| `AZURE_STATIC_WEB_APP_NAME` | `azd deploy frontend` |
| `VITE_API_BASE_URL` | Frontend build (set by `postprovision` after ingress IP is assigned) |

### `postprovision` hook

Handles non-declarative bootstrap:

1. `az aks get-credentials` to populate kubeconfig.
2. Create the `app` namespace + ServiceAccount + Workload Identity annotations.
3. Apply a one-time `Job` running Flyway against PostgreSQL.
4. Wait for the NGINX ingress public IP, then `azd env set VITE_API_BASE_URL "https://${IP}.nip.io"`.

### Local vs CI parity

- **Local:** `az login` interactive → `azd up`. Region/env name prompted on first run.
- **CI:** `azure/login@v2` with OIDC → `azd provision` (in `infra.yml`) → `azd deploy` per service (in `backend-ci.yml` / `frontend-ci.yml`). Same `azure.yaml`.

---

## 8. Authentication, Identity & Secrets

### Three distinct identities

| Identity | Type | Purpose | Roles |
| --- | --- | --- | --- |
| `id-gha-deployer` | UAMI | GitHub Actions principal for CI/CD | `Contributor` on RG (for `azd provision`), `AcrPush` on ACR, `Azure Kubernetes Service Cluster User` + `AKS RBAC Cluster Admin` on AKS, `Static Web Apps Contributor` on SWA, `Reader` on subscription (for `what-if`) |
| `id-backend` | UAMI | Federated to the `backend` ServiceAccount in AKS via Workload Identity | `Key Vault Secrets User` on KV, `AcrPull` on ACR (also covered by `--attach-acr`) |
| `id-defender-aks` | System-assigned MI on AKS | Cluster identity, managed by Azure | Standard AKS-managed roles |

### Federated credentials on `id-gha-deployer`

Created in Bicep, four subjects (one per branch + one for PRs):

```
repo:JoranBergfeld/ghas-defender-example:ref:refs/heads/main
repo:JoranBergfeld/ghas-defender-example:ref:refs/heads/secure
repo:JoranBergfeld/ghas-defender-example:ref:refs/heads/vulnerable
repo:JoranBergfeld/ghas-defender-example:pull_request
```

### Secret inventory

| Secret | Storage | Lifecycle |
| --- | --- | --- |
| PostgreSQL admin password | Key Vault (`postgres-admin-password`) | Generated by Bicep `newGuid()`, never returned as a deployment output |
| SWA deployment token | None (fetched on demand) | Workflow runs `az staticwebapp secrets list` via OIDC; never persisted |
| JWT signing key | Key Vault (`jwt-signing-key`) on `secure`; hard-coded on `vulnerable` (seed #3) | Generated on first start (secure); inline string (vulnerable) |

### GitHub repo settings

Documented in `README.md` and scripted in `scripts/setup-repo.sh` (uses `gh` CLI):

- Secret scanning + push protection: **on**.
- Dependabot alerts + security updates: **on**.
- Branch protection on `main`, `secure`, `vulnerable`: PR required, required checks from §6, dismiss stale reviews, require linear history.
- Repo **variables** (non-sensitive): `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`.

### Bootstrapping order

1. `git clone` and `cd`.
2. `az login` and `azd auth login`.
3. `azd env new demo` → `azd env set AZURE_LOCATION westeurope`.
4. `azd up` — provisions infra (UAMIs, federated credentials, Defender plans, GitHub connector resource).
5. One-time human steps:
   - Complete the Defender for Cloud GitHub OAuth handshake in the Azure portal.
   - Run `./scripts/setup-repo.sh` to set the three repo variables, enable secret scanning, apply branch protection.
6. Push to `secure` or `vulnerable` to trigger the demo.

---

## 9. Documentation, Testing & Out-of-Scope

### `README.md` (setup-focused, ~300 lines)

1. What this demo proves (link to `DEMO.md`).
2. Architecture diagram (Mermaid).
3. Prerequisites: Azure subscription with **Owner** permissions (needed for sub-scope Defender plan enablement), `azd ≥ 1.10`, `gh`, `kubectl`, Docker, Java 21, Node 20.
4. **Cost estimate** — concrete monthly $ for the chosen dev SKUs; `azd down` teardown command prominent.
5. Bootstrap walkthrough (the 6 steps from §8).
6. Pointer to `docs/ARCHITECTURE.md`.
7. Troubleshooting (Defender plan propagation, GitHub connector OAuth, PostgreSQL private DNS, NGINX ingress IP, etc.).

### `docs/DEMO.md` (~400 lines, one section per money moment)

- **Scenario 1 — Secret pushed, blocked:** exact `git` commands, screenshot placeholders.
- **Scenario 2 — PR with SQLi blocks merge:** open PR from feature → `secure`, observe failing required check.
- **Scenario 3 — Vulnerable container, Defender denies pod:** push to `vulnerable`; show workflow log with `admission webhook "azurepolicy-…" denied the request: container image "<acr>/backend:<sha>" has N high-severity vulnerabilities`.
- **Scenario 4 — Code-to-cloud correlation:** navigate Defender for Cloud → DevOps Security → see GHAS findings tied to the AKS Deployment.
- **Reset the demo:** clean state between runs (revert seeds, redeploy `secure`).

### `docs/ARCHITECTURE.md`

- Mermaid C4-style diagrams (Context + Container).
- Per-component table linking each component to its Bicep module or source folder.
- Short, reference-style.

### Testing strategy

This is a demo, not a product. Tests are light but deliberate:

- **Backend:** a handful of unit tests (`@SpringBootTest` slice tests for controllers + a JPA slice test against H2). One integration test asserting the *secure* `ItemController` rejects malicious input.
- **Frontend:** one Vitest component test on `SearchResults` asserting the *secure* version safely escapes input.
- **Bicep:** validated by `bicep build` + `az deployment sub what-if --no-pretty-print` in the `infra.yml` PR job.
- **CI itself:** not run via `act`. Validated against `main` first before demo branches.

### Explicitly out of scope

- Multiple azd environments (dev/staging/prod).
- Custom domain, Front Door, WAF, Application Gateway.
- Autoscaling, HPA, PDBs, multi-region.
- GitOps (Flux / Argo) — we use direct `kubectl set image`.
- Image signing (Notary v2 / Cosign), Image Integrity admission policy.
- Defender for APIs, Defender for Storage, Defender for App Service.
- Cost-control automation, budget alerts, auto-shutdown.
- Localization, accessibility, hardened production CORS.

---

## 10. Open Decisions / Assumptions

None outstanding at the time of writing. Assumptions captured in §1–§9 were validated through the brainstorming conversation. Decisions worth re-checking before implementation:

- The Azure Policy that physically denies vulnerable images is currently in **preview**. If it becomes unavailable or changes name in `westeurope` at implementation time, fall back to a custom Gatekeeper `ConstraintTemplate` populated from Defender's image-scan findings.
- Defender for Cloud's GitHub connector still requires a one-time portal OAuth grant. If `Microsoft.Security/securityConnectors` adds programmatic consent before implementation, prefer it.
