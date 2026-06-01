# Copilot Instructions for `ghas-defender-example`

## Read the spec first

The design at **`docs/superpowers/specs/2026-06-01-ghas-defender-demo-design.md`** is the source of truth for what this repo is, what it deploys, and why. Read it before proposing any change to code, infrastructure, or workflows. When the spec and the code disagree, prefer the spec unless the user explicitly says otherwise — but flag the divergence.

Implementation plans (when present) live in `docs/superpowers/plans/`. New design specs go in `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`.

## Repo status

This repo is a **demonstration project**, not a product. Its job is to show how GitHub Advanced Security (GHAS) and Microsoft Defender for Cloud interact end-to-end. "Production-grade" tradeoffs (hardened RBAC, autoscaling, multi-region, custom domains, WAF, GitOps) are **explicitly out of scope** — see §9 of the spec.

## Three-branch model — critical context

| Branch | Purpose | What lives there |
| --- | --- | --- |
| `main` | Development trunk | Clean code only; CI runs but no deploys |
| `secure` | Demo "happy path" | Clean code; deploys end-to-end successfully |
| `vulnerable` | Demo "failure path" | **Intentionally vulnerable** code; CI and Defender admission controller block it |

**Never propose "fixing" the seeded vulnerabilities on the `vulnerable` branch.** They are the demo. Each one is labelled `// SEEDED VULN #N — see scripts/seed-vulnerabilities.md` and catalogued in that file. Removing or hiding them breaks the demo. If asked to add a new vulnerability, append a new numbered entry to `scripts/seed-vulnerabilities.md` and include the label in the code comment.

Always check the **current branch** before making changes. A "fix unused import" on `vulnerable` may delete a seeded XSS sink.

## Architecture (big picture)

- **Frontend** — React 18 + TypeScript + Vite → **Azure Static Web Apps** (Standard).
- **Backend** — Spring Boot 3.x (Java 21, Maven) → containerized → **AKS** behind the built-in NGINX ingress.
- **Database** — **Azure Database for PostgreSQL Flexible Server**, private-access only via vnet integration + private DNS zone.
- **Registry** — Premium ACR, private endpoint.
- **Identity** — Three identities with distinct roles (see §8 of spec). AKS uses **Workload Identity** federated to a UAMI; GitHub Actions authenticate via **OIDC federated credentials**, one per branch + one for PRs. No client secrets in either system.
- **Security** — Defender CSPM (Standard), Defender for Containers (provides the AKS admission webhook via the Azure Policy add-on), Defender for Key Vault, Defender for OSS DBs, Defender for Resource Manager. The Defender for Cloud **GitHub connector** correlates GHAS findings with running AKS workloads.

The Bicep entry point (`infra/main.bicep`) is **subscription-scoped** so it can create the RG and enable Defender plans in one shot. Modules in `infra/modules/` communicate only through typed outputs wired by `main.bicep`; they never reference each other directly.

## azd integration

`azure.yaml` declares two services with native azd hosts:

- `backend` — `host: aks` (azd builds the image, OIDC-pushes to ACR, applies `src/backend/k8s/*.yaml` with image-tag substitution).
- `frontend` — `host: staticwebapp` (azd builds via `npm run build`, uploads `dist/`, fetches the deployment token via OIDC).

Workflows use `azd deploy <service>` — do **not** introduce hand-rolled `docker push` or `kubectl set image` steps. The local `azd up` flow and the CI flow must stay identical; if you change one, change both. The `postprovision` hook in `scripts/azd-hooks/` handles things azd can't do declaratively (kubeconfig, Flyway schema job, ingress IP capture into `VITE_API_BASE_URL`).

## CI/CD conventions

Three workflow files in `.github/workflows/`, each scoped by **path filter**:

- `infra.yml` — Bicep lint + `az deployment sub what-if` on PRs (posts sticky comment); `azd provision` on push to `main` / `secure` / `vulnerable`.
- `backend-ci.yml` — Maven build + tests + **CodeQL `java-kotlin`**; on push to demo branches, `azd deploy backend`.
- `frontend-ci.yml` — `npm` build + Vitest + **CodeQL `javascript-typescript`**; on push to demo branches, `azd deploy frontend`.

**No CI-side container scan.** Defender for Containers does the post-push scan, and the AKS admission controller is what blocks the bad image. Adding Trivy or similar would steal the demo moment.

Every Azure-touching job uses `azure/login@v2` with OIDC (`id-token: write` only on those jobs). Subscription/tenant/client IDs are repo **variables**, not secrets.

Required status checks (mirrored in branch protection): `infra / what-if`, `backend-ci / codeql`, `backend-ci / build-test`, `frontend-ci / codeql`, `frontend-ci / build-test`.

## Secrets handling

- Secrets in **Azure Key Vault** with RBAC auth and a private endpoint. Backend reads them via Workload Identity (`Key Vault Secrets User` on `id-backend`).
- PostgreSQL admin password generated by Bicep `newGuid()` and stored in KV. **Never** surfaced as a deployment output.
- SWA deployment token fetched on demand via `az staticwebapp secrets list` from the workflow — never persisted as a GitHub secret.
- Branch protection + Secret Scanning **push protection** must remain enabled on `main`, `secure`, `vulnerable`.

If you ever find yourself about to add a GitHub Actions `secrets.*` reference for an Azure credential, stop — it should be OIDC.

## Brainstorming workflow

For any non-trivial change (new feature, behavioural change, design decision), follow the superpowers `brainstorming` skill: explore context → clarifying questions one at a time → propose approaches → present design sections → write spec to `docs/superpowers/specs/` → user review → `writing-plans` skill. Do not jump straight to implementation skills.

## Build / test / lint commands

The codebase is in the spec stage; concrete commands will exist once each component is scaffolded. The expected entry points are:

- **Backend**: `./mvnw -f src/backend/pom.xml verify` (full), `./mvnw -f src/backend/pom.xml -Dtest=ItemControllerTest test` (single test class).
- **Frontend**: `npm --prefix src/frontend ci && npm --prefix src/frontend test` (full), `npm --prefix src/frontend test -- SearchResults` (single suite via Vitest filter).
- **Infra**: `az bicep build --file infra/main.bicep`, `az deployment sub what-if --location westeurope --template-file infra/main.bicep --parameters infra/main.parameters.json`.
- **End-to-end**: `azd up` (provision + deploy), `azd down --purge` (teardown). Default location is `westeurope`.

When you scaffold a component, update this section with the exact verified commands.

## Commit messages

Use Conventional Commits (`docs:`, `feat:`, `fix:`, `chore:`, `ci:`, `build:`). Include the Copilot co-author trailer:

```
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```
