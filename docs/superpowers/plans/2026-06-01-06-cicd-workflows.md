# Plan 6 — CI/CD Workflows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add GHAS-aware CI/CD workflows and repository bootstrap automation so PRs run the required checks, pushes run CI again, and demo-branch pushes use Azure OIDC with `azd` for infrastructure and application delivery.

**Architecture:** Three path-filtered GitHub Actions workflows run independently for infrastructure, backend, and frontend changes while sharing one CodeQL configuration. Azure-touching jobs authenticate with GitHub OIDC against the `id-gha-deployer` user-assigned managed identity, using repo variables populated by `scripts/setup-repo.sh`. Repository security settings and branch protection are applied with `gh` so Plan 7 can rely on required checks and push protection.

**Tech Stack:** GitHub Actions, CodeQL, Azure CLI, Azure Developer CLI (`azd`), GitHub CLI (`gh`), Bash, Java 21/Maven, Node 20/npm, actionlint, optional shellcheck.

---

## Source-of-truth inputs

- Design spec: `docs/superpowers/specs/2026-06-01-ghas-defender-demo-design.md`, especially §6 GitHub Actions Workflows and §8 Authentication, Identity & Secrets.
- Repo instructions: `.github/copilot-instructions.md`.
- Branches: `main`, `secure`, `vulnerable`.
- Federated credential subjects already created by Plan 4:
  - `repo:JoranBergfeld/ghas-defender-example:ref:refs/heads/main`
  - `repo:JoranBergfeld/ghas-defender-example:ref:refs/heads/secure`
  - `repo:JoranBergfeld/ghas-defender-example:ref:refs/heads/vulnerable`
  - `repo:JoranBergfeld/ghas-defender-example:pull_request`
- Bicep output already available in the local azd environment: `AZURE_GHA_DEPLOYER_CLIENT_ID`.
- Repo variables set by this plan: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`.
- Default CI environment values: `AZURE_ENV_NAME=demo`, `AZURE_LOCATION=westeurope`.

## File responsibility map

- `.github/codeql-config.yml` — shared CodeQL query suite and path exclusions for Java, JavaScript/TypeScript, and IaC/config scans.
- `.github/workflows/backend-ci.yml` — backend Maven build/test, Java CodeQL, dependency review on PRs, and `azd deploy backend` on demo branches.
- `.github/workflows/frontend-ci.yml` — frontend npm lint/test/build, JavaScript/TypeScript CodeQL, and `azd deploy frontend` on demo branches.
- `.github/workflows/infra.yml` — Bicep build and subscription `what-if` on PRs, CodeQL for IaC/config, and `azd provision` on branch pushes.
- `scripts/setup-repo.sh` — one-time repo bootstrap: reads local `azd env get-values`, sets GitHub repo variables, enables secret scanning/push protection and Dependabot security updates, and applies branch protection rules.
- `README.md` — adds CI/CD status badges plus the bootstrap order `azd up` → `./scripts/setup-repo.sh`.

## Required status checks

Branch protection must require these exact status check contexts:

- `infra / what-if`
- `backend-ci / build-test`
- `backend-ci / codeql`
- `frontend-ci / build-test`
- `frontend-ci / codeql`

## Scope boundaries

- Do not seed vulnerabilities in this plan.
- Do not create `docs/DEMO.md` in this plan.
- Do not add Trivy, Grype, Snyk, or any other CI-side container image scanner.
- Do not add automatic Dependabot auto-merge.
- Do not replace `azd deploy backend` or `azd deploy frontend` with hand-written Docker, ACR, Static Web Apps, or `kubectl` deployment steps.

## Task 1: Create the shared CodeQL configuration

**Files:**
- Create: `.github/codeql-config.yml`

- [ ] **Step 1: Ensure the `.github` directory exists**

Run:

```bash
mkdir -p .github
```

Expected output: no output and exit code `0`.

- [ ] **Step 2: Write `.github/codeql-config.yml`**

Run:

```bash
cat > .github/codeql-config.yml <<'YAML'
name: ghas-defender-codeql

queries:
  - uses: security-extended

paths-ignore:
  - '**/test/**'
  - '**/*.test.ts'
  - '**/*.spec.ts'
YAML
```

Expected output: no output and exit code `0`.

Full file content after this step:

```yaml
name: ghas-defender-codeql

queries:
  - uses: security-extended

paths-ignore:
  - '**/test/**'
  - '**/*.test.ts'
  - '**/*.spec.ts'
```

- [ ] **Step 3: Verify the CodeQL configuration contains the required query suite and exclusions**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
path = Path('.github/codeql-config.yml')
text = path.read_text()
required = [
    'uses: security-extended',
    "'**/test/**'",
    "'**/*.test.ts'",
    "'**/*.spec.ts'",
]
missing = [item for item in required if item not in text]
if missing:
    raise SystemExit(f'Missing required CodeQL config entries: {missing}')
print('CodeQL config includes security-extended and test path exclusions.')
PY
```

Expected output:

```text
CodeQL config includes security-extended and test path exclusions.
```

- [ ] **Step 4: Commit the shared CodeQL configuration**

Run:

```bash
git add .github/codeql-config.yml
git commit -m $'ci: add shared CodeQL configuration\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
```

Expected output: exit code `0`; the commit summary contains `ci: add shared CodeQL configuration` and lists `.github/codeql-config.yml` as created.

## Task 2: Create the backend CI workflow

**Files:**
- Create: `.github/workflows/backend-ci.yml`

- [ ] **Step 1: Ensure the workflow directory exists**

Run:

```bash
mkdir -p .github/workflows
```

Expected output: no output and exit code `0`.

- [ ] **Step 2: Write `.github/workflows/backend-ci.yml`**

Run:

```bash
cat > .github/workflows/backend-ci.yml <<'YAML'
name: backend-ci

on:
  pull_request:
    branches:
      - main
      - secure
      - vulnerable
    paths:
      - 'src/backend/**'
      - '.github/workflows/backend-ci.yml'
  push:
    branches:
      - main
      - secure
      - vulnerable
    paths:
      - 'src/backend/**'
      - '.github/workflows/backend-ci.yml'

env:
  AZURE_ENV_NAME: demo
  AZURE_LOCATION: westeurope

jobs:
  build-test:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'
          cache: maven

      - name: Run Maven verify
        run: ./mvnw -f src/backend/pom.xml -B verify

      - name: Upload Surefire reports
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: backend-surefire-reports
          path: |
            src/backend/target/surefire-reports/**
            src/backend/target/failsafe-reports/**
          if-no-files-found: ignore

  codeql:
    runs-on: ubuntu-latest
    permissions:
      actions: read
      contents: read
      packages: read
      security-events: write
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'
          cache: maven

      - uses: github/codeql-action/init@v3
        with:
          languages: java-kotlin
          config-file: ./.github/codeql-config.yml

      - uses: github/codeql-action/autobuild@v3

      - uses: github/codeql-action/analyze@v3
        with:
          category: /language:java-kotlin
          output: codeql-results

      - name: Fail on high or critical CodeQL findings
        if: github.event_name == 'pull_request'
        shell: bash
        run: |
          python3 - <<'PY'
          import json
          from pathlib import Path
          
          threshold = 7.0
          sarif_files = list(Path('codeql-results').rglob('*.sarif'))
          if not sarif_files:
              raise SystemExit('No CodeQL SARIF files found in codeql-results')
          
          findings = []
          for sarif_file in sarif_files:
              data = json.loads(sarif_file.read_text())
              for run in data.get('runs', []):
                  rules = {
                      rule.get('id'): rule
                      for rule in run.get('tool', {}).get('driver', {}).get('rules', [])
                  }
                  for result in run.get('results', []):
                      rule_id = result.get('ruleId')
                      rule = rules.get(rule_id, {})
                      properties = rule.get('properties', {})
                      raw_score = properties.get('security-severity')
                      if raw_score is None:
                          continue
                      try:
                          score = float(raw_score)
                      except ValueError:
                          continue
                      if score >= threshold:
                          message = result.get('message', {}).get('text', 'No message')
                          findings.append(f'{rule_id}: security-severity {score} - {message}')
          
          if findings:
              print('High or critical CodeQL findings:')
              for finding in findings:
                  print(f'- {finding}')
              raise SystemExit(1)
          
          print('No high or critical CodeQL findings found.')
          PY

  dependency-review:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: read
    steps:
      - uses: actions/checkout@v4

      - uses: actions/dependency-review-action@v4

  deploy:
    if: github.event_name == 'push' && (github.ref_name == 'secure' || github.ref_name == 'vulnerable')
    needs:
      - build-test
      - codeql
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    concurrency:
      group: backend-deploy-${{ github.ref_name }}
      cancel-in-progress: false
    steps:
      - uses: actions/checkout@v4

      - uses: azure/login@v2
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID }}
          tenant-id: ${{ vars.AZURE_TENANT_ID }}
          subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}

      - uses: Azure/setup-azd@v1

      - name: Prepare azd environment
        shell: bash
        run: |
          azd env new "${AZURE_ENV_NAME}" --no-prompt || azd env select "${AZURE_ENV_NAME}"
          azd env set AZURE_LOCATION "${AZURE_LOCATION}"
          azd env set AZURE_SUBSCRIPTION_ID "${{ vars.AZURE_SUBSCRIPTION_ID }}"
          azd env set AZURE_TENANT_ID "${{ vars.AZURE_TENANT_ID }}"
          principal_id="$(az ad sp show --id "${{ vars.AZURE_CLIENT_ID }}" --query id -o tsv)"
          azd env set AZURE_PRINCIPAL_ID "${principal_id}"

      - name: Refresh azd environment outputs
        run: azd env refresh --no-prompt

      - name: Deploy backend
        continue-on-error: false
        run: azd deploy backend --no-prompt
YAML
```

Expected output: no output and exit code `0`.

Full file content after this step:

```yaml
name: backend-ci

on:
  pull_request:
    branches:
      - main
      - secure
      - vulnerable
    paths:
      - 'src/backend/**'
      - '.github/workflows/backend-ci.yml'
  push:
    branches:
      - main
      - secure
      - vulnerable
    paths:
      - 'src/backend/**'
      - '.github/workflows/backend-ci.yml'

env:
  AZURE_ENV_NAME: demo
  AZURE_LOCATION: westeurope

jobs:
  build-test:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'
          cache: maven

      - name: Run Maven verify
        run: ./mvnw -f src/backend/pom.xml -B verify

      - name: Upload Surefire reports
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: backend-surefire-reports
          path: |
            src/backend/target/surefire-reports/**
            src/backend/target/failsafe-reports/**
          if-no-files-found: ignore

  codeql:
    runs-on: ubuntu-latest
    permissions:
      actions: read
      contents: read
      packages: read
      security-events: write
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'
          cache: maven

      - uses: github/codeql-action/init@v3
        with:
          languages: java-kotlin
          config-file: ./.github/codeql-config.yml

      - uses: github/codeql-action/autobuild@v3

      - uses: github/codeql-action/analyze@v3
        with:
          category: /language:java-kotlin
          output: codeql-results

      - name: Fail on high or critical CodeQL findings
        if: github.event_name == 'pull_request'
        shell: bash
        run: |
          python3 - <<'PY'
          import json
          from pathlib import Path
          
          threshold = 7.0
          sarif_files = list(Path('codeql-results').rglob('*.sarif'))
          if not sarif_files:
              raise SystemExit('No CodeQL SARIF files found in codeql-results')
          
          findings = []
          for sarif_file in sarif_files:
              data = json.loads(sarif_file.read_text())
              for run in data.get('runs', []):
                  rules = {
                      rule.get('id'): rule
                      for rule in run.get('tool', {}).get('driver', {}).get('rules', [])
                  }
                  for result in run.get('results', []):
                      rule_id = result.get('ruleId')
                      rule = rules.get(rule_id, {})
                      properties = rule.get('properties', {})
                      raw_score = properties.get('security-severity')
                      if raw_score is None:
                          continue
                      try:
                          score = float(raw_score)
                      except ValueError:
                          continue
                      if score >= threshold:
                          message = result.get('message', {}).get('text', 'No message')
                          findings.append(f'{rule_id}: security-severity {score} - {message}')
          
          if findings:
              print('High or critical CodeQL findings:')
              for finding in findings:
                  print(f'- {finding}')
              raise SystemExit(1)
          
          print('No high or critical CodeQL findings found.')
          PY

  dependency-review:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: read
    steps:
      - uses: actions/checkout@v4

      - uses: actions/dependency-review-action@v4

  deploy:
    if: github.event_name == 'push' && (github.ref_name == 'secure' || github.ref_name == 'vulnerable')
    needs:
      - build-test
      - codeql
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    concurrency:
      group: backend-deploy-${{ github.ref_name }}
      cancel-in-progress: false
    steps:
      - uses: actions/checkout@v4

      - uses: azure/login@v2
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID }}
          tenant-id: ${{ vars.AZURE_TENANT_ID }}
          subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}

      - uses: Azure/setup-azd@v1

      - name: Prepare azd environment
        shell: bash
        run: |
          azd env new "${AZURE_ENV_NAME}" --no-prompt || azd env select "${AZURE_ENV_NAME}"
          azd env set AZURE_LOCATION "${AZURE_LOCATION}"
          azd env set AZURE_SUBSCRIPTION_ID "${{ vars.AZURE_SUBSCRIPTION_ID }}"
          azd env set AZURE_TENANT_ID "${{ vars.AZURE_TENANT_ID }}"
          principal_id="$(az ad sp show --id "${{ vars.AZURE_CLIENT_ID }}" --query id -o tsv)"
          azd env set AZURE_PRINCIPAL_ID "${principal_id}"

      - name: Refresh azd environment outputs
        run: azd env refresh --no-prompt

      - name: Deploy backend
        continue-on-error: false
        run: azd deploy backend --no-prompt
```

- [ ] **Step 3: Install or expose actionlint**

Run:

```bash
if ! command -v actionlint >/dev/null 2>&1; then
  bash <(curl -sSL https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash)
  export PATH="$PWD:$PATH"
fi
actionlint -version
```

Expected output: a single line beginning with `actionlint` and exit code `0`.

- [ ] **Step 4: Validate the backend workflow with actionlint**

Run:

```bash
actionlint .github/workflows/backend-ci.yml
```

Expected output: no output and exit code `0`.

- [ ] **Step 5: Commit the backend workflow**

Run:

```bash
git add .github/workflows/backend-ci.yml
git commit -m $'ci: add backend CI workflow\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
```

Expected output: exit code `0`; the commit summary contains `ci: add backend CI workflow` and lists `.github/workflows/backend-ci.yml` as created.

## Task 3: Create the frontend CI workflow

**Files:**
- Create: `.github/workflows/frontend-ci.yml`

- [ ] **Step 1: Write `.github/workflows/frontend-ci.yml`**

Run:

```bash
cat > .github/workflows/frontend-ci.yml <<'YAML'
name: frontend-ci

on:
  pull_request:
    branches:
      - main
      - secure
      - vulnerable
    paths:
      - 'src/frontend/**'
      - '.github/workflows/frontend-ci.yml'
  push:
    branches:
      - main
      - secure
      - vulnerable
    paths:
      - 'src/frontend/**'
      - '.github/workflows/frontend-ci.yml'

env:
  AZURE_ENV_NAME: demo
  AZURE_LOCATION: westeurope

jobs:
  build-test:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: npm
          cache-dependency-path: src/frontend/package-lock.json

      - name: Install frontend dependencies
        run: npm --prefix src/frontend ci

      - name: Lint frontend
        run: npm --prefix src/frontend run lint

      - name: Run frontend tests
        run: npm --prefix src/frontend test -- --run

      - name: Build frontend
        run: npm --prefix src/frontend run build

  codeql:
    runs-on: ubuntu-latest
    permissions:
      actions: read
      contents: read
      security-events: write
    steps:
      - uses: actions/checkout@v4

      - uses: github/codeql-action/init@v3
        with:
          languages: javascript-typescript
          config-file: ./.github/codeql-config.yml

      - uses: github/codeql-action/analyze@v3
        with:
          category: /language:javascript-typescript
          output: codeql-results

      - name: Fail on high or critical CodeQL findings
        if: github.event_name == 'pull_request'
        shell: bash
        run: |
          python3 - <<'PY'
          import json
          from pathlib import Path
          
          threshold = 7.0
          sarif_files = list(Path('codeql-results').rglob('*.sarif'))
          if not sarif_files:
              raise SystemExit('No CodeQL SARIF files found in codeql-results')
          
          findings = []
          for sarif_file in sarif_files:
              data = json.loads(sarif_file.read_text())
              for run in data.get('runs', []):
                  rules = {
                      rule.get('id'): rule
                      for rule in run.get('tool', {}).get('driver', {}).get('rules', [])
                  }
                  for result in run.get('results', []):
                      rule_id = result.get('ruleId')
                      rule = rules.get(rule_id, {})
                      properties = rule.get('properties', {})
                      raw_score = properties.get('security-severity')
                      if raw_score is None:
                          continue
                      try:
                          score = float(raw_score)
                      except ValueError:
                          continue
                      if score >= threshold:
                          message = result.get('message', {}).get('text', 'No message')
                          findings.append(f'{rule_id}: security-severity {score} - {message}')
          
          if findings:
              print('High or critical CodeQL findings:')
              for finding in findings:
                  print(f'- {finding}')
              raise SystemExit(1)
          
          print('No high or critical CodeQL findings found.')
          PY

  deploy:
    if: github.event_name == 'push' && (github.ref_name == 'secure' || github.ref_name == 'vulnerable')
    needs:
      - build-test
      - codeql
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    concurrency:
      group: frontend-deploy-${{ github.ref_name }}
      cancel-in-progress: false
    steps:
      - uses: actions/checkout@v4

      - uses: azure/login@v2
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID }}
          tenant-id: ${{ vars.AZURE_TENANT_ID }}
          subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}

      - uses: Azure/setup-azd@v1

      - name: Prepare azd environment
        shell: bash
        run: |
          azd env new "${AZURE_ENV_NAME}" --no-prompt || azd env select "${AZURE_ENV_NAME}"
          azd env set AZURE_LOCATION "${AZURE_LOCATION}"
          azd env set AZURE_SUBSCRIPTION_ID "${{ vars.AZURE_SUBSCRIPTION_ID }}"
          azd env set AZURE_TENANT_ID "${{ vars.AZURE_TENANT_ID }}"
          principal_id="$(az ad sp show --id "${{ vars.AZURE_CLIENT_ID }}" --query id -o tsv)"
          azd env set AZURE_PRINCIPAL_ID "${principal_id}"

      - name: Refresh azd environment outputs
        run: azd env refresh --no-prompt

      - name: Deploy frontend
        run: azd deploy frontend --no-prompt
YAML
```

Expected output: no output and exit code `0`.

Full file content after this step:

```yaml
name: frontend-ci

on:
  pull_request:
    branches:
      - main
      - secure
      - vulnerable
    paths:
      - 'src/frontend/**'
      - '.github/workflows/frontend-ci.yml'
  push:
    branches:
      - main
      - secure
      - vulnerable
    paths:
      - 'src/frontend/**'
      - '.github/workflows/frontend-ci.yml'

env:
  AZURE_ENV_NAME: demo
  AZURE_LOCATION: westeurope

jobs:
  build-test:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: npm
          cache-dependency-path: src/frontend/package-lock.json

      - name: Install frontend dependencies
        run: npm --prefix src/frontend ci

      - name: Lint frontend
        run: npm --prefix src/frontend run lint

      - name: Run frontend tests
        run: npm --prefix src/frontend test -- --run

      - name: Build frontend
        run: npm --prefix src/frontend run build

  codeql:
    runs-on: ubuntu-latest
    permissions:
      actions: read
      contents: read
      security-events: write
    steps:
      - uses: actions/checkout@v4

      - uses: github/codeql-action/init@v3
        with:
          languages: javascript-typescript
          config-file: ./.github/codeql-config.yml

      - uses: github/codeql-action/analyze@v3
        with:
          category: /language:javascript-typescript
          output: codeql-results

      - name: Fail on high or critical CodeQL findings
        if: github.event_name == 'pull_request'
        shell: bash
        run: |
          python3 - <<'PY'
          import json
          from pathlib import Path
          
          threshold = 7.0
          sarif_files = list(Path('codeql-results').rglob('*.sarif'))
          if not sarif_files:
              raise SystemExit('No CodeQL SARIF files found in codeql-results')
          
          findings = []
          for sarif_file in sarif_files:
              data = json.loads(sarif_file.read_text())
              for run in data.get('runs', []):
                  rules = {
                      rule.get('id'): rule
                      for rule in run.get('tool', {}).get('driver', {}).get('rules', [])
                  }
                  for result in run.get('results', []):
                      rule_id = result.get('ruleId')
                      rule = rules.get(rule_id, {})
                      properties = rule.get('properties', {})
                      raw_score = properties.get('security-severity')
                      if raw_score is None:
                          continue
                      try:
                          score = float(raw_score)
                      except ValueError:
                          continue
                      if score >= threshold:
                          message = result.get('message', {}).get('text', 'No message')
                          findings.append(f'{rule_id}: security-severity {score} - {message}')
          
          if findings:
              print('High or critical CodeQL findings:')
              for finding in findings:
                  print(f'- {finding}')
              raise SystemExit(1)
          
          print('No high or critical CodeQL findings found.')
          PY

  deploy:
    if: github.event_name == 'push' && (github.ref_name == 'secure' || github.ref_name == 'vulnerable')
    needs:
      - build-test
      - codeql
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    concurrency:
      group: frontend-deploy-${{ github.ref_name }}
      cancel-in-progress: false
    steps:
      - uses: actions/checkout@v4

      - uses: azure/login@v2
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID }}
          tenant-id: ${{ vars.AZURE_TENANT_ID }}
          subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}

      - uses: Azure/setup-azd@v1

      - name: Prepare azd environment
        shell: bash
        run: |
          azd env new "${AZURE_ENV_NAME}" --no-prompt || azd env select "${AZURE_ENV_NAME}"
          azd env set AZURE_LOCATION "${AZURE_LOCATION}"
          azd env set AZURE_SUBSCRIPTION_ID "${{ vars.AZURE_SUBSCRIPTION_ID }}"
          azd env set AZURE_TENANT_ID "${{ vars.AZURE_TENANT_ID }}"
          principal_id="$(az ad sp show --id "${{ vars.AZURE_CLIENT_ID }}" --query id -o tsv)"
          azd env set AZURE_PRINCIPAL_ID "${principal_id}"

      - name: Refresh azd environment outputs
        run: azd env refresh --no-prompt

      - name: Deploy frontend
        run: azd deploy frontend --no-prompt
```

- [ ] **Step 2: Validate the frontend workflow with actionlint**

Run:

```bash
actionlint .github/workflows/frontend-ci.yml
```

Expected output: no output and exit code `0`.

- [ ] **Step 3: Commit the frontend workflow**

Run:

```bash
git add .github/workflows/frontend-ci.yml
git commit -m $'ci: add frontend CI workflow\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
```

Expected output: exit code `0`; the commit summary contains `ci: add frontend CI workflow` and lists `.github/workflows/frontend-ci.yml` as created.

## Task 4: Create the infrastructure workflow

**Files:**
- Create: `.github/workflows/infra.yml`

- [ ] **Step 1: Write `.github/workflows/infra.yml`**

Run:

```bash
cat > .github/workflows/infra.yml <<'YAML'
name: infra

on:
  pull_request:
    branches:
      - main
      - secure
      - vulnerable
    paths:
      - 'infra/**'
      - 'azure.yaml'
  push:
    branches:
      - main
      - secure
      - vulnerable
    paths:
      - 'infra/**'
      - 'azure.yaml'

env:
  AZURE_ENV_NAME: demo
  AZURE_LOCATION: westeurope

jobs:
  what-if:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
      issues: write
      pull-requests: write
    steps:
      - uses: actions/checkout@v4

      - uses: azure/login@v2
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID }}
          tenant-id: ${{ vars.AZURE_TENANT_ID }}
          subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}

      - name: Export azd-compatible principal ID
        shell: bash
        run: |
          principal_id="$(az ad sp show --id "${{ vars.AZURE_CLIENT_ID }}" --query id -o tsv)"
          echo "AZURE_PRINCIPAL_ID=${principal_id}" >> "${GITHUB_ENV}"

      - name: Build Bicep
        run: az bicep build --file infra/main.bicep

      - name: Run subscription what-if
        shell: bash
        run: |
          set -o pipefail
          az deployment sub what-if \
            --location "${AZURE_LOCATION}" \
            --template-file infra/main.bicep \
            --parameters infra/main.parameters.json \
            --parameters environmentName="${AZURE_ENV_NAME}" \
            2>&1 | tee what-if.txt

      - name: Prepare what-if PR comment
        shell: bash
        run: |
          {
            echo '## Azure what-if'
            echo
            echo '```text'
            python3 - <<'PY'
from pathlib import Path
text = Path('what-if.txt').read_text(errors='replace')
limit = 60_000
if len(text) > limit:
    text = text[:limit] + '\n... truncated to 60KB ...\n'
print(text)
PY
            echo '```'
          } > what-if-comment.md

      - uses: marocchino/sticky-pull-request-comment@v2
        with:
          header: infra-what-if
          path: what-if-comment.md

  codeql-iac:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    permissions:
      actions: read
      contents: read
      security-events: write
    steps:
      - uses: actions/checkout@v4

      - uses: github/codeql-action/init@v3
        with:
          languages: config-files
          config-file: ./.github/codeql-config.yml

      - uses: github/codeql-action/analyze@v3
        with:
          category: /language:config-files
          upload: true

  provision:
    if: github.event_name == 'push'
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    concurrency:
      group: infra-provision-${{ github.ref_name }}
      cancel-in-progress: false
    steps:
      - uses: actions/checkout@v4

      - uses: azure/login@v2
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID }}
          tenant-id: ${{ vars.AZURE_TENANT_ID }}
          subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}

      - uses: Azure/setup-azd@v1

      - name: Prepare azd environment
        shell: bash
        run: |
          azd env new "${AZURE_ENV_NAME}" --no-prompt || azd env select "${AZURE_ENV_NAME}"
          azd env set AZURE_LOCATION "${AZURE_LOCATION}"
          azd env set AZURE_SUBSCRIPTION_ID "${{ vars.AZURE_SUBSCRIPTION_ID }}"
          azd env set AZURE_TENANT_ID "${{ vars.AZURE_TENANT_ID }}"
          principal_id="$(az ad sp show --id "${{ vars.AZURE_CLIENT_ID }}" --query id -o tsv)"
          azd env set AZURE_PRINCIPAL_ID "${principal_id}"

      - name: Provision Azure resources
        run: azd provision --no-prompt
YAML
```

Expected output: no output and exit code `0`.

Full file content after this step:

```yaml
name: infra

on:
  pull_request:
    branches:
      - main
      - secure
      - vulnerable
    paths:
      - 'infra/**'
      - 'azure.yaml'
  push:
    branches:
      - main
      - secure
      - vulnerable
    paths:
      - 'infra/**'
      - 'azure.yaml'

env:
  AZURE_ENV_NAME: demo
  AZURE_LOCATION: westeurope

jobs:
  what-if:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
      issues: write
      pull-requests: write
    steps:
      - uses: actions/checkout@v4

      - uses: azure/login@v2
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID }}
          tenant-id: ${{ vars.AZURE_TENANT_ID }}
          subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}

      - name: Export azd-compatible principal ID
        shell: bash
        run: |
          principal_id="$(az ad sp show --id "${{ vars.AZURE_CLIENT_ID }}" --query id -o tsv)"
          echo "AZURE_PRINCIPAL_ID=${principal_id}" >> "${GITHUB_ENV}"

      - name: Build Bicep
        run: az bicep build --file infra/main.bicep

      - name: Run subscription what-if
        shell: bash
        run: |
          set -o pipefail
          az deployment sub what-if \
            --location "${AZURE_LOCATION}" \
            --template-file infra/main.bicep \
            --parameters infra/main.parameters.json \
            --parameters environmentName="${AZURE_ENV_NAME}" \
            2>&1 | tee what-if.txt

      - name: Prepare what-if PR comment
        shell: bash
        run: |
          {
            echo '## Azure what-if'
            echo
            echo '```text'
            python3 - <<'PY'
from pathlib import Path
text = Path('what-if.txt').read_text(errors='replace')
limit = 60_000
if len(text) > limit:
    text = text[:limit] + '\n... truncated to 60KB ...\n'
print(text)
PY
            echo '```'
          } > what-if-comment.md

      - uses: marocchino/sticky-pull-request-comment@v2
        with:
          header: infra-what-if
          path: what-if-comment.md

  codeql-iac:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    permissions:
      actions: read
      contents: read
      security-events: write
    steps:
      - uses: actions/checkout@v4

      - uses: github/codeql-action/init@v3
        with:
          languages: config-files
          config-file: ./.github/codeql-config.yml

      - uses: github/codeql-action/analyze@v3
        with:
          category: /language:config-files
          upload: true

  provision:
    if: github.event_name == 'push'
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    concurrency:
      group: infra-provision-${{ github.ref_name }}
      cancel-in-progress: false
    steps:
      - uses: actions/checkout@v4

      - uses: azure/login@v2
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID }}
          tenant-id: ${{ vars.AZURE_TENANT_ID }}
          subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}

      - uses: Azure/setup-azd@v1

      - name: Prepare azd environment
        shell: bash
        run: |
          azd env new "${AZURE_ENV_NAME}" --no-prompt || azd env select "${AZURE_ENV_NAME}"
          azd env set AZURE_LOCATION "${AZURE_LOCATION}"
          azd env set AZURE_SUBSCRIPTION_ID "${{ vars.AZURE_SUBSCRIPTION_ID }}"
          azd env set AZURE_TENANT_ID "${{ vars.AZURE_TENANT_ID }}"
          principal_id="$(az ad sp show --id "${{ vars.AZURE_CLIENT_ID }}" --query id -o tsv)"
          azd env set AZURE_PRINCIPAL_ID "${principal_id}"

      - name: Provision Azure resources
        run: azd provision --no-prompt
```

- [ ] **Step 2: Validate the infrastructure workflow with actionlint**

Run:

```bash
actionlint .github/workflows/infra.yml
```

Expected output: no output and exit code `0`.

- [ ] **Step 3: Commit the infrastructure workflow**

Run:

```bash
git add .github/workflows/infra.yml
git commit -m $'ci: add infrastructure workflow\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
```

Expected output: exit code `0`; the commit summary contains `ci: add infrastructure workflow` and lists `.github/workflows/infra.yml` as created.

## Task 5: Create the repository bootstrap script

**Files:**
- Create: `scripts/setup-repo.sh`

- [ ] **Step 1: Ensure the scripts directory exists**

Run:

```bash
mkdir -p scripts
```

Expected output: no output and exit code `0`.

- [ ] **Step 2: Write `scripts/setup-repo.sh`**

Run:

```bash
cat > scripts/setup-repo.sh <<'BASH'
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
BASH
```

Expected output: no output and exit code `0`.

Full file content after this step:

```bash
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
```

- [ ] **Step 3: Make the script executable**

Run:

```bash
chmod +x scripts/setup-repo.sh
```

Expected output: no output and exit code `0`.

- [ ] **Step 4: Validate Bash syntax**

Run:

```bash
bash -n scripts/setup-repo.sh
```

Expected output: no output and exit code `0`.

- [ ] **Step 5: Run shellcheck when it is installed**

Run:

```bash
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck scripts/setup-repo.sh
else
  echo 'shellcheck not installed; skipped'
fi
```

Expected output when shellcheck is installed: no output and exit code `0`.

Expected output when shellcheck is not installed:

```text
shellcheck not installed; skipped
```

- [ ] **Step 6: Commit the bootstrap script**

Run:

```bash
git add scripts/setup-repo.sh
git commit -m $'ci: add repository security bootstrap script\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
```

Expected output: exit code `0`; the commit summary contains `ci: add repository security bootstrap script` and lists `scripts/setup-repo.sh` as created with executable mode.

## Task 6: Update the README with CI/CD status and bootstrap order

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Confirm README exists from the earlier plans**

Run:

```bash
test -f README.md
```

Expected output: no output and exit code `0`.

- [ ] **Step 2: Insert the CI/CD section**

Run:

````bash
python3 - <<'PY'
from pathlib import Path
path = Path('README.md')
text = path.read_text()
section = """## CI/CD

[![infra](https://github.com/JoranBergfeld/ghas-defender-example/actions/workflows/infra.yml/badge.svg?branch=main)](https://github.com/JoranBergfeld/ghas-defender-example/actions/workflows/infra.yml)
[![backend-ci](https://github.com/JoranBergfeld/ghas-defender-example/actions/workflows/backend-ci.yml/badge.svg?branch=main)](https://github.com/JoranBergfeld/ghas-defender-example/actions/workflows/backend-ci.yml)
[![frontend-ci](https://github.com/JoranBergfeld/ghas-defender-example/actions/workflows/frontend-ci.yml/badge.svg?branch=main)](https://github.com/JoranBergfeld/ghas-defender-example/actions/workflows/frontend-ci.yml)

This repository uses three path-filtered GitHub Actions workflows:

- `infra` runs Bicep build and subscription `what-if` on PRs that change `infra/**` or `azure.yaml`; branch pushes run `azd provision` through Azure OIDC.
- `backend-ci` runs Maven verify, Java/Kotlin CodeQL, and dependency review on PRs; pushes to `secure` and `vulnerable` run `azd deploy backend`.
- `frontend-ci` runs npm install, lint, Vitest, build, and JavaScript/TypeScript CodeQL; pushes to `secure` and `vulnerable` run `azd deploy frontend`.

Container image scanning is intentionally not performed in CI. Defender for Containers scans the image after it reaches ACR, and the AKS admission controller is the blocking point for the vulnerable-branch demo.

### Bootstrap

Run the one-time bootstrap in this order after cloning the repository:

```bash
az login
azd auth login
azd env new demo
azd env set AZURE_LOCATION westeurope
azd up
./scripts/setup-repo.sh
```

`azd up` provisions Azure infrastructure, the `id-gha-deployer` managed identity, and its federated credentials. `./scripts/setup-repo.sh` reads the local `azd` environment values, sets the GitHub repo variables, enables secret scanning with push protection, enables Dependabot security updates, and applies branch protection for `main`, `secure`, and `vulnerable`.
"""
if '## CI/CD\n' in text:
    raise SystemExit('README.md already contains a CI/CD section')
marker = '## Bootstrap\n'
if marker in text:
    text = text.replace(marker, section + '\n' + marker, 1)
else:
    text = text.rstrip() + '\n\n' + section
path.write_text(text)
PY
````

Expected output: no output and exit code `0`.

README section added by this step:

````markdown
## CI/CD

[![infra](https://github.com/JoranBergfeld/ghas-defender-example/actions/workflows/infra.yml/badge.svg?branch=main)](https://github.com/JoranBergfeld/ghas-defender-example/actions/workflows/infra.yml)
[![backend-ci](https://github.com/JoranBergfeld/ghas-defender-example/actions/workflows/backend-ci.yml/badge.svg?branch=main)](https://github.com/JoranBergfeld/ghas-defender-example/actions/workflows/backend-ci.yml)
[![frontend-ci](https://github.com/JoranBergfeld/ghas-defender-example/actions/workflows/frontend-ci.yml/badge.svg?branch=main)](https://github.com/JoranBergfeld/ghas-defender-example/actions/workflows/frontend-ci.yml)

This repository uses three path-filtered GitHub Actions workflows:

- `infra` runs Bicep build and subscription `what-if` on PRs that change `infra/**` or `azure.yaml`; branch pushes run `azd provision` through Azure OIDC.
- `backend-ci` runs Maven verify, Java/Kotlin CodeQL, and dependency review on PRs; pushes to `secure` and `vulnerable` run `azd deploy backend`.
- `frontend-ci` runs npm install, lint, Vitest, build, and JavaScript/TypeScript CodeQL; pushes to `secure` and `vulnerable` run `azd deploy frontend`.

Container image scanning is intentionally not performed in CI. Defender for Containers scans the image after it reaches ACR, and the AKS admission controller is the blocking point for the vulnerable-branch demo.

### Bootstrap

Run the one-time bootstrap in this order after cloning the repository:

```bash
az login
azd auth login
azd env new demo
azd env set AZURE_LOCATION westeurope
azd up
./scripts/setup-repo.sh
```

`azd up` provisions Azure infrastructure, the `id-gha-deployer` managed identity, and its federated credentials. `./scripts/setup-repo.sh` reads the local `azd` environment values, sets the GitHub repo variables, enables secret scanning with push protection, enables Dependabot security updates, and applies branch protection for `main`, `secure`, and `vulnerable`.
````

- [ ] **Step 3: Verify the README contains one status badge per workflow and the bootstrap order**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
text = Path('README.md').read_text()
required = [
    'actions/workflows/infra.yml/badge.svg?branch=main',
    'actions/workflows/backend-ci.yml/badge.svg?branch=main',
    'actions/workflows/frontend-ci.yml/badge.svg?branch=main',
    'azd up\n./scripts/setup-repo.sh',
    'Container image scanning is intentionally not performed in CI.',
]
missing = [item for item in required if item not in text]
if missing:
    raise SystemExit(f'Missing README CI/CD entries: {missing}')
print('README CI/CD section contains badges, bootstrap order, and Defender container-scan note.')
PY
```

Expected output:

```text
README CI/CD section contains badges, bootstrap order, and Defender container-scan note.
```

- [ ] **Step 4: Commit the README update**

Run:

```bash
git add README.md
git commit -m $'docs: document CI/CD workflows and bootstrap\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
```

Expected output: exit code `0`; the commit summary contains `docs: document CI/CD workflows and bootstrap` and lists `README.md` as modified.

## Task 7: Push to `main` and verify workflow syntax in GitHub Actions

**Files:**
- No file changes expected unless workflow failures require fixes.

- [ ] **Step 1: Confirm the local branch is `main` and the worktree is clean**

Run:

```bash
git branch --show-current
git status --short
```

Expected output:

```text
main
```

The second command prints no lines.

- [ ] **Step 2: Push the implementation commits to `main`**

Run:

```bash
git push origin main
```

Expected output: exit code `0`; the output contains `main -> main`.

- [ ] **Step 3: List recent workflow runs for the pushed commit**

Run:

```bash
gh run list --repo JoranBergfeld/ghas-defender-example --branch main --limit 10 --json databaseId,workflowName,status,conclusion,headSha --jq '.[] | [.databaseId, .workflowName, .status, (.conclusion // "none"), .headSha] | @tsv'
```

Expected output: one tab-separated line per run. For workflow-file-only changes, `backend-ci` and `frontend-ci` should appear because their path filters include their workflow files. `infra` appears on pushes that include `infra/**` or `azure.yaml` changes.

- [ ] **Step 4: Watch any queued or in-progress runs from this push**

Run one command per run identifier returned in Step 3:

```bash
gh run watch RUN_DATABASE_ID --repo JoranBergfeld/ghas-defender-example --exit-status
```

Expected output: exit code `0` for successful runs. If a workflow fails, the output identifies the failed job and step.

- [ ] **Step 5: Fix workflow failures and commit corrections when needed**

If Step 4 fails, inspect the failed run:

```bash
gh run view RUN_DATABASE_ID --repo JoranBergfeld/ghas-defender-example --log-failed
```

Expected output: log lines for the failed step.

After making a precise workflow fix, validate locally:

```bash
actionlint .github/workflows/backend-ci.yml .github/workflows/frontend-ci.yml .github/workflows/infra.yml
```

Expected output: no output and exit code `0`.

Commit the fix:

```bash
git add .github/workflows scripts/setup-repo.sh README.md .github/codeql-config.yml
git commit -m $'ci: fix workflow validation issue\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
git push origin main
```

Expected output: exit code `0`; the commit summary contains `ci: fix workflow validation issue`, and the push output contains `main -> main`.

## Task 8: Run repository bootstrap and verify branch protection

**Files:**
- No repository file changes expected.

- [ ] **Step 1: Run the bootstrap script after `azd up` has completed locally**

Run:

```bash
./scripts/setup-repo.sh
```

Expected output includes these lines in order:

```text
==> Verifying GitHub authentication for JoranBergfeld/ghas-defender-example
==> Reading azd values from environment demo
==> Setting repository variables
==> Enabling secret scanning and push protection
==> Enabling Dependabot alerts and security updates
==> Required status check contexts
   - infra / what-if
   - backend-ci / build-test
   - backend-ci / codeql
   - frontend-ci / build-test
   - frontend-ci / codeql
==> Applying branch protection for main
==> Applying branch protection for secure
==> Applying branch protection for vulnerable
==> Verifying main branch protection
   - infra / what-if
   - backend-ci / build-test
   - backend-ci / codeql
   - frontend-ci / build-test
   - frontend-ci / codeql
==> Repository bootstrap complete
```

`gh variable set` may also print confirmation lines for updated variables. Those lines are acceptable.

- [ ] **Step 2: Verify GitHub repo variables exist and do not expose secret values**

Run:

```bash
gh variable list --repo JoranBergfeld/ghas-defender-example --json name --jq '.[].name' | sort
```

Expected output contains exactly these required names, possibly with additional non-secret variables from earlier plans:

```text
AZURE_CLIENT_ID
AZURE_SUBSCRIPTION_ID
AZURE_TENANT_ID
```

- [ ] **Step 3: Verify `main` branch protection through the REST API**

Run:

```bash
gh api repos/JoranBergfeld/ghas-defender-example/branches/main/protection --jq '{contexts: .required_status_checks.contexts, strict: .required_status_checks.strict, code_owner_reviews: .required_pull_request_reviews.require_code_owner_reviews, linear_history: .required_linear_history.enabled}'
```

Expected output:

```json
{"contexts":["infra / what-if","backend-ci / build-test","backend-ci / codeql","frontend-ci / build-test","frontend-ci / codeql"],"strict":true,"code_owner_reviews":true,"linear_history":true}
```

- [ ] **Step 4: Verify branch protection rules for all three branch patterns**

Run:

```bash
gh api graphql \
  -f query='query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { branchProtectionRules(first: 100) { nodes { pattern requiresStatusChecks requiresStrictStatusChecks requiresCodeOwnerReviews requiresLinearHistory requiredStatusCheckContexts } } } }' \
  -F owner=JoranBergfeld \
  -F name=ghas-defender-example \
  --jq '.data.repository.branchProtectionRules.nodes[] | select(.pattern == "main" or .pattern == "secure" or .pattern == "vulnerable") | {pattern, requiresStatusChecks, requiresStrictStatusChecks, requiresCodeOwnerReviews, requiresLinearHistory, requiredStatusCheckContexts}'
```

Expected output: three JSON objects, one each for `main`, `secure`, and `vulnerable`, and each object has `requiresStatusChecks`, `requiresStrictStatusChecks`, `requiresCodeOwnerReviews`, and `requiresLinearHistory` set to `true`.

- [ ] **Step 5: Confirm the bootstrap did not modify tracked files**

Run:

```bash
git status --short
```

Expected output: no output.

## Task 9: Perform end-to-end CI verification with a disposable PR

**Files:**
- Temporary verification changes on a short-lived branch only:
  - `azure.yaml`
  - `src/backend/.ci-verification`
  - `src/frontend/.ci-verification`

- [ ] **Step 1: Create a verification branch**

Run:

```bash
git switch main
git pull --ff-only origin main
git switch -c ci-plan6-verification
```

Expected output: exit code `0`; the last line contains `Switched to a new branch 'ci-plan6-verification'`.

- [ ] **Step 2: Add harmless path-filter trigger files**

Run:

```bash
mkdir -p src/backend src/frontend
printf 'Plan 6 backend CI path-filter verification.\n' > src/backend/.ci-verification
printf 'Plan 6 frontend CI path-filter verification.\n' > src/frontend/.ci-verification
printf '\n# Plan 6 CI path-filter verification.\n' >> azure.yaml
```

Expected output: no output and exit code `0`.

- [ ] **Step 3: Commit and push the verification branch**

Run:

```bash
git add azure.yaml src/backend/.ci-verification src/frontend/.ci-verification
git commit -m $'chore: verify CI path filters\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
git push -u origin ci-plan6-verification
```

Expected output: exit code `0`; the commit summary contains `chore: verify CI path filters`, and the push output contains `ci-plan6-verification -> ci-plan6-verification`.

- [ ] **Step 4: Open the verification PR to `main`**

Run:

```bash
gh pr create \
  --repo JoranBergfeld/ghas-defender-example \
  --base main \
  --head ci-plan6-verification \
  --title 'chore: verify CI workflows' \
  --body 'Disposable Plan 6 verification PR that touches the configured path filters so all required checks run.'
```

Expected output: a GitHub pull request URL for `JoranBergfeld/ghas-defender-example`.

- [ ] **Step 5: Watch required PR checks**

Run:

```bash
gh pr checks --repo JoranBergfeld/ghas-defender-example --watch
```

Expected output: all required checks complete successfully on the verification PR:

```text
infra / what-if	pass
backend-ci / build-test	pass
backend-ci / codeql	pass
frontend-ci / build-test	pass
frontend-ci / codeql	pass
```

Additional checks such as `infra / codeql-iac` and `backend-ci / dependency-review` may also appear and should pass.

- [ ] **Step 6: Close the disposable verification PR without merging**

Run:

```bash
gh pr close --repo JoranBergfeld/ghas-defender-example --delete-branch
git switch main
git branch -D ci-plan6-verification
```

Expected output: exit code `0`; the pull request is closed, the remote branch is deleted, and the local verification branch is deleted.

- [ ] **Step 7: Verify application deploy jobs on the demo branches after Plan 7 creates them**

After Plan 7 creates `secure` and `vulnerable`, run:

```bash
git fetch origin secure vulnerable
gh run list --repo JoranBergfeld/ghas-defender-example --branch secure --workflow backend-ci.yml --limit 1
gh run list --repo JoranBergfeld/ghas-defender-example --branch secure --workflow frontend-ci.yml --limit 1
gh run list --repo JoranBergfeld/ghas-defender-example --branch vulnerable --workflow backend-ci.yml --limit 1
```

Expected output: one recent run for each command. On `secure`, `backend-ci / deploy` and `frontend-ci / deploy` succeed. On `vulnerable`, `backend-ci / deploy` exits non-zero when Defender-managed AKS admission denies the vulnerable backend rollout; that visible failure is the container-blocking demo moment.

- [ ] **Step 8: Verify Defender for Cloud DevOps correlation after workflow data has propagated**

In the Azure portal, navigate to **Microsoft Defender for Cloud → DevOps security** and open `JoranBergfeld/ghas-defender-example`.

Expected result: the repo is listed. GHAS alerts and code-to-cloud correlation can take up to 24 hours to populate after the GitHub connector OAuth handshake and first workflow runs.

## Self-review checklist for the implementer

- [ ] The workflow names are exactly `infra`, `backend-ci`, and `frontend-ci`.
- [ ] Required job identifiers are exactly `what-if`, `build-test`, and `codeql` so required status checks resolve to the expected contexts.
- [ ] Every Azure-touching job has `permissions.id-token: write`, `permissions.contents: read`, `actions/checkout@v4`, and `azure/login@v2` with `vars.AZURE_CLIENT_ID`, `vars.AZURE_TENANT_ID`, and `vars.AZURE_SUBSCRIPTION_ID`.
- [ ] No workflow references `secrets.*` for Azure credentials.
- [ ] No workflow includes Trivy, Grype, Snyk, or another container scanner.
- [ ] `backend-ci` uses `./mvnw -f src/backend/pom.xml -B verify`.
- [ ] `frontend-ci` uses `npm --prefix src/frontend ci`, lint, Vitest with `-- --run`, and build.
- [ ] CodeQL jobs write SARIF to `codeql-results` and fail PRs when a finding has `security-severity` greater than or equal to `7.0`; push runs still upload alerts so `vulnerable` can reach the Defender admission demo.
- [ ] `azd deploy backend --no-prompt` and `azd deploy frontend --no-prompt` are the only application deploy commands.
- [ ] `scripts/setup-repo.sh` reads `AZURE_GHA_DEPLOYER_CLIENT_ID` from `azd env get-values` and writes it to the repo variable `AZURE_CLIENT_ID`.
- [ ] `README.md` includes one badge per workflow and the bootstrap order `azd up` followed by `./scripts/setup-repo.sh`.

## Open Questions / Ambiguities

1. The requested path filters mean an empty PR will not trigger all required checks. This plan uses a disposable verification PR that touches `azure.yaml`, `src/backend/**`, and `src/frontend/**`, then closes it without merging.
2. The requested goal says pushes to `main` run workflows without application deploys, while the infra workflow requirements include `azd provision` on pushes to `main`, `secure`, and `vulnerable`. This plan keeps application deploys limited to `secure` and `vulnerable`; `infra / provision` runs on any configured branch push that changes `infra/**` or `azure.yaml`.
3. Code owner review enforcement requires `.github/CODEOWNERS` to exist for automatic code owner review requests. This plan enables the branch protection setting and warns if the file is not present, but it does not create CODEOWNERS because it is outside the Plan 6 file list.
