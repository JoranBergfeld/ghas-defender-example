# Plan 7 — Demo Branches & Seeded Vulnerabilities Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the `secure` and `vulnerable` demo branches, then seed exactly seven labelled vulnerabilities on `vulnerable` while keeping `main` clean.

**Architecture:** Documentation and seeding scripts are committed to `main`; `secure` is an idempotent fast-forward copy of `main`; `vulnerable` starts from `main` and receives one commit per seeded vulnerability. Secret seed #4 is deliberately manual so GitHub Secret Scanning push protection can block the push and become the demo moment.

**Tech Stack:** Bash, Git/GitHub CLI, Java 21, Spring Boot 3, JPA, Maven, React 18, TypeScript, Vite, npm, Docker, Azure Bicep, GHAS CodeQL/Secret Scanning/Dependabot, Microsoft Defender for Cloud/Containers.

---

## File Structure and Responsibilities

- Modify: `scripts/seed-vulnerabilities.md` — authoritative inventory for the seven seeded vulnerabilities and expected detectors/blocking layers.
- Create: `scripts/seed-secret.sh` — generates a fake GitHub PAT-pattern token at demo time and writes it to `src/backend/src/main/resources/application-local.yml` without committing or pushing.
- Create: `scripts/seed-vulnerable-branch.sh` — idempotently creates/pushes `secure`, creates `vulnerable`, applies seeds #1, #2, #3, #5, #6, and #7 as separate commits, pushes `vulnerable`, and prints the manual seed #4 instructions.
- Modify on `vulnerable` only: `src/backend/src/main/java/com/example/ghasdefender/web/ItemController.java` — seed #1 SQL injection.
- Modify on `vulnerable` only: `src/frontend/src/components/SearchResults.tsx` — seed #2 XSS.
- Modify on `vulnerable` only: `src/backend/src/main/java/com/example/ghasdefender/config/JwtConfig.java` — seed #3 hardcoded JWT secret.
- Modify on `vulnerable` only: `src/backend/src/main/resources/application-local.yml` — seed #4 fake leaked PAT-pattern token, only during the manual push-protection scenario.
- Modify on `vulnerable` only: `src/backend/pom.xml` and `src/frontend/package.json` — seed #5 vulnerable dependency pins.
- Modify on `vulnerable` only: `src/backend/Dockerfile` — seed #6 insecure container image.
- Modify on `vulnerable` only: `infra/modules/aks.bicep` and `infra/modules/postgres.bicep` — seed #7 IaC misconfiguration.

## Cross-Plan Assumptions

- Plan 1 created `scripts/seed-vulnerabilities.md` as a skeleton and the `scripts/` directory exists by the time this plan is executed.
- Plans 1–5 created the secure baseline application and infrastructure on `main` with the paths listed above.
- Plan 6 enabled GHAS, Dependabot, push protection, CodeQL workflows, branch protection, and Defender deployment workflows for `main`, `secure`, and `vulnerable`.
- The secure backend exposes `ItemController#search` using a parameterized repository query, not `EntityManager#createNativeQuery`.
- The secure frontend renders search text as React text content, not `dangerouslySetInnerHTML`.
- The secure backend resolves JWT signing material from configuration/Key Vault through `JwtConfig`, not a literal string.
- The Plan 7 user contract uses the seed #3 literal `supersecret_demo_key_do_not_use_in_production`; that explicit contract supersedes the shorter literal in design §4.
- The secure AKS module uses `enableRBAC: true` and a non-empty `authorizedIpRanges` parameter; the secure PostgreSQL module uses private networking and non-demo admin values.
- The Bicep seeded-label contract from the spec is `# SEEDED VULN #N — see scripts/seed-vulnerabilities.md`; write that exact line inside a Bicep block comment so `az bicep build` still succeeds.

## Global Implementation Rules

- Run every task from the repository root: `/home/jbergfeld/vcs/ghas-defender-example`.
- Never seed #4 on `main` or `secure`.
- Do not put a real secret in any file, commit message, issue, or PR description.
- Do not add CI-side container scanning; Defender for Containers owns the container demo moment.
- Use Conventional Commits and this trailer on every commit:

```text
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```

---

### Task 1: Write the Seeded Vulnerability Inventory

**Files:**
- Modify: `scripts/seed-vulnerabilities.md`

- [ ] **Step 1: Confirm clean `main`**

Run:

```bash
git switch main
git status --short
```

Expected output from `git status --short`: no output.

- [ ] **Step 2: Replace the inventory file**

Run:

```bash
mkdir -p scripts
cat > scripts/seed-vulnerabilities.md <<'MARKDOWN'
# Seeded Vulnerabilities Inventory

This file is the source of truth for vulnerabilities intentionally present on the `vulnerable` branch and absent on `main` and `secure`.

## Branch Contract

| Branch | Purpose | Seeded vulnerabilities |
| --- | --- | --- |
| `main` | Development trunk | None |
| `secure` | Clean demo branch | None |
| `vulnerable` | Failure-path demo branch | Seeds #1 through #7 |

## Required Labels

| File type | Label format |
| --- | --- |
| Java, JavaScript, TypeScript | `// SEEDED VULN #N — see scripts/seed-vulnerabilities.md` |
| YAML, Dockerfile, Bicep | `# SEEDED VULN #N — see scripts/seed-vulnerabilities.md` |

## Inventory

| # | Category | File | Concrete seed | Expected detector | Expected blocking layer |
| --- | --- | --- | --- | --- | --- |
| 1 | SAST — SQL injection | `src/backend/src/main/java/com/example/ghasdefender/web/ItemController.java` | `entityManager.createNativeQuery("SELECT * FROM items WHERE name LIKE '%" + q + "%'")` replacing the secure parameterized JPA query | CodeQL rule `java/sql-injection`, alert title `Database query built from user-controlled sources` | Required check `backend-ci / codeql` blocks PR merge into `secure` |
| 2 | SAST — XSS | `src/frontend/src/components/SearchResults.tsx` | `dangerouslySetInnerHTML={{ __html: serverResponse }}` on unescaped backend payload | CodeQL rule `js/xss`, alert title `Client-side cross-site scripting` | Required check `frontend-ci / codeql` blocks PR merge into `secure` |
| 3 | SAST — Hardcoded credentials | `src/backend/src/main/java/com/example/ghasdefender/config/JwtConfig.java` | `private static final String JWT_SECRET = "supersecret_demo_key_do_not_use_in_production";` | CodeQL rule `java/hardcoded-credentials`, alert title `Hard-coded credentials` | Required check `backend-ci / codeql` blocks PR merge into `secure` |
| 4 | Secret Scanning — pushed token | `src/backend/src/main/resources/application-local.yml` | Fake GitHub PAT-pattern token generated by `scripts/seed-secret.sh` as `ghp_` plus 40 random alphanumeric characters | GitHub Secret Scanning pattern `GitHub personal access token` | Push protection rejects `git push` before the commit reaches GitHub |
| 5 | Dependency — Dependabot | `src/backend/pom.xml`; `src/frontend/package.json` | Pin `org.springframework:spring-core:5.3.18` and `axios:0.21.0` | Dependabot alerts for CVE-2022-22965 and CVE-2021-3749 | Dependabot alert and security update PR; dependency-review blocks PRs when configured by Plan 6 |
| 6 | Container — Defender for Containers | `src/backend/Dockerfile` | `eclipse-temurin:21-jdk` runtime image, `USER root`, no `HEALTHCHECK`, and `COPY . .` | Defender for Containers image vulnerability assessment in ACR | AKS admission controller denies the deployment after Defender scan propagation |
| 7 | IaC misconfig — CodeQL for IaC + Defender for Cloud DevOps | `infra/modules/aks.bicep`; `infra/modules/postgres.bicep` | AKS `enableRBAC: false`, empty `authorizedIpRanges`, PostgreSQL `publicNetworkAccess: 'Enabled'`, admin username `admin`, demo password `Password123!` | CodeQL IaC security queries and Defender for Cloud DevOps IaC recommendations | Required check `infra / what-if` or CodeQL IaC blocks PR merge; Defender DevOps blade correlates the findings |

## Secret Seed Safety

`scripts/seed-secret.sh` generates seed #4 dynamically. It does not run `git add`, `git commit`, or `git push`. The operator runs those commands manually on a disposable branch off `vulnerable` and expects push protection to reject the push. Automation must not use `--allow-secret-scanning-bypass`.
MARKDOWN
```

Expected output: no output.

- [ ] **Step 3: Verify the inventory has exactly seven rows**

Run:

```bash
grep -E '^\| [1-7] \|' scripts/seed-vulnerabilities.md | wc -l
```

Expected output:

```text
7
```

- [ ] **Step 4: Commit the inventory on `main`**

Run:

```bash
git add scripts/seed-vulnerabilities.md
git commit -m "docs: document seeded vulnerability inventory" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

Expected output contains:

```text
[main
```

---

### Task 2: Create the Secret Seed Generator

**Files:**
- Create: `scripts/seed-secret.sh`

- [ ] **Step 1: Write `scripts/seed-secret.sh`**

Run:

```bash
cat > scripts/seed-secret.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

target_file="src/backend/src/main/resources/application-local.yml"

token_body="$(python3 - <<'PY'
import secrets
import string
alphabet = string.ascii_letters + string.digits
print(''.join(secrets.choice(alphabet) for _ in range(40)))
PY
)"
token="ghp_${token_body}"

python3 - "${target_file}" "${token}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
token = sys.argv[2]
label = " # SEEDED VULN #4 — see scripts/seed-vulnerabilities.md"
key = "leakedGitHubPat:"
replacement_value = f'{key} "{token}"{label}'

path.parent.mkdir(parents=True, exist_ok=True)
if path.exists():
    lines = path.read_text(encoding="utf-8").splitlines()
else:
    lines = []

replaced = False
for index, line in enumerate(lines):
    if line.strip().startswith(key):
        indent = line[: len(line) - len(line.lstrip())]
        lines[index] = f"{indent}{replacement_value}"
        replaced = True
        break

if not replaced:
    if lines and lines[-1] != "":
        lines.append("")
    lines.extend([
        "# Local-only demo values; never used by the cloud profile.",
        "demo:",
        f"  {replacement_value}",
    ])

path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

cat <<EOF
WARNING: generated a fake GitHub PAT-pattern token for the GHAS push-protection demo.
Token written to: ${target_file}
Token value: ${token}

This script does not run git add, git commit, or git push.
Run it only on a disposable feature branch created from vulnerable.
Commit and push manually when demonstrating seed #4; the expected result is a push-protection rejection.
Do not use --allow-secret-scanning-bypass in automation because the rejection is the demo moment.
EOF
BASH
chmod +x scripts/seed-secret.sh
```

Expected output: no output.

- [ ] **Step 2: Validate shell syntax**

Run:

```bash
bash -n scripts/seed-secret.sh
```

Expected output: no output.

- [ ] **Step 3: Verify no full PAT-pattern token is hardcoded in the script**

Run:

```bash
if grep -E 'ghp_[[:alnum:]]{40}' scripts/seed-secret.sh; then
  echo "unexpected hardcoded PAT-pattern token"
  exit 1
else
  echo "no hardcoded PAT-pattern token found"
fi
```

Expected output:

```text
no hardcoded PAT-pattern token found
```

- [ ] **Step 4: Verify the script can generate and write a fake token without committing it**

Run:

```bash
./scripts/seed-secret.sh | sed -E 's/ghp_[[:alnum:]]{40}/ghp_REDACTED_FOR_PLAN_OUTPUT/'
grep -n 'SEEDED VULN #4' src/backend/src/main/resources/application-local.yml
if git ls-files --error-unmatch src/backend/src/main/resources/application-local.yml >/dev/null 2>&1; then
  git restore src/backend/src/main/resources/application-local.yml
else
  rm -f src/backend/src/main/resources/application-local.yml
fi
git status --short src/backend/src/main/resources/application-local.yml
```

Expected output contains:

```text
WARNING: generated a fake GitHub PAT-pattern token for the GHAS push-protection demo.
Token value: ghp_REDACTED_FOR_PLAN_OUTPUT
```

Expected `grep` output format:

```text
N:  leakedGitHubPat: "ghp_<40 random alphanumeric characters>" # SEEDED VULN #4 — see scripts/seed-vulnerabilities.md
```

Expected output from `git status --short src/backend/src/main/resources/application-local.yml`: no output.

- [ ] **Step 5: Commit the generator on `main`**

Run:

```bash
git add scripts/seed-secret.sh
git commit -m "feat: add seeded secret generator" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

Expected output contains:

```text
[main
```

---

### Task 3: Create the Vulnerable Branch Seeder

**Files:**
- Create: `scripts/seed-vulnerable-branch.sh`

- [ ] **Step 1: Write `scripts/seed-vulnerable-branch.sh`**

Run:

```bash
cat > scripts/seed-vulnerable-branch.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

remote="${REMOTE:-origin}"
coauthor="Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"

require_clean_tree() {
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Working tree has uncommitted changes; commit or restore them before seeding branches." >&2
    exit 1
  fi
}

commit_paths() {
  local message="$1"
  shift
  git add "$@"
  if git diff --cached --quiet; then
    echo "No staged changes for ${message}; seed already present."
  else
    git commit -m "${message}" -m "${coauthor}"
  fi
}

checkout_or_create_from_main() {
  local branch="$1"
  if git show-ref --verify --quiet "refs/heads/${branch}"; then
    git switch "${branch}"
    git merge --ff-only main
  else
    git switch -c "${branch}" main
  fi
}

seed_sql_injection() {
  python3 - <<'PY'
from pathlib import Path
path = Path("src/backend/src/main/java/com/example/ghasdefender/web/ItemController.java")
text = path.read_text(encoding="utf-8")
label = "// SEEDED VULN #1 — see scripts/seed-vulnerabilities.md"
if label in text:
    print("seed #1 already present")
    raise SystemExit(0)
text = text.replace(
    "import org.springframework.web.bind.annotation.RequestParam;\n",
    "import jakarta.persistence.EntityManager;\nimport org.springframework.web.bind.annotation.RequestParam;\n",
    1,
)
text = text.replace(
    "  private final ItemRepository itemRepository;\n\n"
    "  public ItemController(ItemRepository itemRepository) {\n"
    "    this.itemRepository = itemRepository;\n"
    "  }\n",
    "  private final ItemRepository itemRepository;\n"
    "  private final EntityManager entityManager;\n\n"
    "  public ItemController(ItemRepository itemRepository, EntityManager entityManager) {\n"
    "    this.itemRepository = itemRepository;\n"
    "    this.entityManager = entityManager;\n"
    "  }\n",
    1,
)
old_method = """  @GetMapping
  public List<ItemResponse> search(@RequestParam(defaultValue = "") String q) {
    return itemRepository.findByNameContainingIgnoreCase(q).stream()
        .map(ItemResponse::from)
        .toList();
  }
"""
new_method = """  @GetMapping
  @SuppressWarnings("unchecked")
  public List<ItemResponse> search(@RequestParam(defaultValue = "") String q) {
    var rows = entityManager
        // SEEDED VULN #1 — see scripts/seed-vulnerabilities.md
        .createNativeQuery("SELECT * FROM items WHERE name LIKE '%" + q + "%'")
        .getResultList();

    return rows.stream()
        .map(row -> (Object[]) row)
        .map(columns -> new ItemResponse(
            ((Number) columns[0]).longValue(),
            (String) columns[1],
            (String) columns[2]))
        .toList();
  }
"""
if old_method not in text:
    raise SystemExit("Expected secure ItemController#search snippet not found; reconcile with Plan 7 before seeding #1.")
path.write_text(text.replace(old_method, new_method, 1), encoding="utf-8")
PY
  commit_paths "vuln: seed #1 SQL injection in ItemController#search" \
    src/backend/src/main/java/com/example/ghasdefender/web/ItemController.java
}

seed_xss() {
  python3 - <<'PY'
from pathlib import Path
path = Path("src/frontend/src/components/SearchResults.tsx")
text = path.read_text(encoding="utf-8")
label = "// SEEDED VULN #2 — see scripts/seed-vulnerabilities.md"
if label in text:
    print("seed #2 already present")
    raise SystemExit(0)
old = """export function SearchResults({ serverResponse }: SearchResultsProps) {
  return <p data-testid="search-summary">{serverResponse}</p>;
}
"""
new = """export function SearchResults({ serverResponse }: SearchResultsProps) {
  return (
    <p
      data-testid="search-summary"
      // SEEDED VULN #2 — see scripts/seed-vulnerabilities.md
      dangerouslySetInnerHTML={{ __html: serverResponse }}
    />
  );
}
"""
if old not in text:
    raise SystemExit("Expected secure SearchResults snippet not found; reconcile with Plan 7 before seeding #2.")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
PY
  commit_paths "vuln: seed #2 XSS via dangerouslySetInnerHTML" \
    src/frontend/src/components/SearchResults.tsx
}

seed_hardcoded_jwt_secret() {
  python3 - <<'PY'
from pathlib import Path
path = Path("src/backend/src/main/java/com/example/ghasdefender/config/JwtConfig.java")
text = path.read_text(encoding="utf-8")
label = "// SEEDED VULN #3 — see scripts/seed-vulnerabilities.md"
if label in text:
    print("seed #3 already present")
    raise SystemExit(0)
old = """@ConfigurationProperties(prefix = "app.jwt")
public record JwtConfig(String issuer, Duration tokenTtl, String signingKey) {
}
"""
new = """@ConfigurationProperties(prefix = "app.jwt")
public record JwtConfig(String issuer, Duration tokenTtl, String signingKey) {
  // SEEDED VULN #3 — see scripts/seed-vulnerabilities.md
  private static final String JWT_SECRET = "supersecret_demo_key_do_not_use_in_production";

  @Override
  public String signingKey() {
    return JWT_SECRET;
  }
}
"""
if old not in text:
    raise SystemExit("Expected secure JwtConfig snippet not found; reconcile with Plan 7 before seeding #3.")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
PY
  commit_paths "vuln: seed #3 hardcoded JWT secret" \
    src/backend/src/main/java/com/example/ghasdefender/config/JwtConfig.java
}

seed_vulnerable_dependencies() {
  python3 - <<'PY'
from pathlib import Path
import json

pom = Path("src/backend/pom.xml")
pom_text = pom.read_text(encoding="utf-8")
if "<artifactId>spring-core</artifactId>" not in pom_text:
    dependency = """    <dependency>
      <!-- SEEDED VULN #5 — see scripts/seed-vulnerabilities.md -->
      <groupId>org.springframework</groupId>
      <artifactId>spring-core</artifactId>
      <version>5.3.18</version>
    </dependency>
"""
    pom_text = pom_text.replace("  </dependencies>\n", dependency + "  </dependencies>\n", 1)
    pom.write_text(pom_text, encoding="utf-8")
else:
    print("spring-core seed already present")

package_json = Path("src/frontend/package.json")
data = json.loads(package_json.read_text(encoding="utf-8"))
dependencies = data.setdefault("dependencies", {})
dependencies["axios"] = "0.21.0"
comment_key = "// SEEDED VULN #5"
data[comment_key] = "see scripts/seed-vulnerabilities.md; axios 0.21.0 is intentionally vulnerable on the vulnerable branch"
package_json.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
  npm --prefix src/frontend install --package-lock-only
  commit_paths "vuln: seed #5 vulnerable dependency pins" \
    src/backend/pom.xml src/frontend/package.json src/frontend/package-lock.json
}

seed_insecure_dockerfile() {
  cat > src/backend/Dockerfile <<'DOCKERFILE'
# SEEDED VULN #6 — see scripts/seed-vulnerabilities.md
FROM eclipse-temurin:21-jdk

WORKDIR /app
COPY . .
RUN ./mvnw -B -DskipTests package

USER root
ENTRYPOINT ["java", "-jar", "target/ghas-defender-backend.jar"]
DOCKERFILE
  commit_paths "vuln: seed #6 insecure backend container" src/backend/Dockerfile
}

seed_iac_misconfig() {
  python3 - <<'PY'
from pathlib import Path

aks = Path("infra/modules/aks.bicep")
aks_text = aks.read_text(encoding="utf-8")
if "SEEDED VULN #7" not in aks_text:
    aks_text = aks_text.replace("enableRBAC: true", "/*\n    # SEEDED VULN #7 — see scripts/seed-vulnerabilities.md\n    */\n    enableRBAC: false", 1)
    aks_text = aks_text.replace("authorizedIpRanges: authorizedIpRanges", "authorizedIpRanges: []", 1)
    aks.write_text(aks_text, encoding="utf-8")

postgres = Path("infra/modules/postgres.bicep")
pg_text = postgres.read_text(encoding="utf-8")
if "SEEDED VULN #7" not in pg_text:
    pg_text = pg_text.replace("publicNetworkAccess: 'Disabled'", "/*\n    # SEEDED VULN #7 — see scripts/seed-vulnerabilities.md\n    */\n    publicNetworkAccess: 'Enabled'", 1)
    pg_text = pg_text.replace("administratorLogin: postgresAdminUsername", "administratorLogin: 'admin'", 1)
    pg_text = pg_text.replace("administratorLoginPassword: postgresAdminPassword", "administratorLoginPassword: 'Password123!'", 1)
    postgres.write_text(pg_text, encoding="utf-8")
PY
  commit_paths "vuln: seed #7 insecure AKS and PostgreSQL IaC" \
    infra/modules/aks.bicep infra/modules/postgres.bicep
}

require_clean_tree
git switch main
checkout_or_create_from_main secure
git push -u "${remote}" secure

git switch main
checkout_or_create_from_main vulnerable
seed_sql_injection
seed_xss
seed_hardcoded_jwt_secret
seed_vulnerable_dependencies
seed_insecure_dockerfile
seed_iac_misconfig

git push -u "${remote}" vulnerable

cat <<'EOF'
Seed #4 is intentionally manual:
  git switch -c demo/seed-secret vulnerable
  ./scripts/seed-secret.sh
  git add src/backend/src/main/resources/application-local.yml
  git commit -m "vuln: seed #4 leaked GitHub PAT pattern" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
  git push -u origin demo/seed-secret
Expected result: GitHub rejects the push with push protection.
EOF
BASH
chmod +x scripts/seed-vulnerable-branch.sh
```

Expected output: no output.

- [ ] **Step 2: Validate shell syntax**

Run:

```bash
bash -n scripts/seed-vulnerable-branch.sh
```

Expected output: no output.

- [ ] **Step 3: Commit the branch seeder on `main`**

Run:

```bash
git add scripts/seed-vulnerable-branch.sh
git commit -m "feat: add vulnerable branch seeder" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

Expected output contains:

```text
[main
```

**Execution note:** Tasks 4–12 show the manual branch and seeding workflow. Running `./scripts/seed-vulnerable-branch.sh` performs the same branch creation, non-secret seeding, commits, lockfile refresh, and pushes; when using the script, run the verification steps in Tasks 4–12 and skip manual edit/commit steps that the script already completed.

---

### Task 4: Create and Push the `secure` Branch

**Files:**
- No file changes

- [ ] **Step 1: Ensure local `main` is clean and current**

Run:

```bash
git switch main
git status --short
git log --oneline -3
```

Expected output from `git status --short`: no output.

Expected `git log` output contains the three Task 1–3 commits:

```text
feat: add vulnerable branch seeder
feat: add seeded secret generator
docs: document seeded vulnerability inventory
```

- [ ] **Step 2: Create or fast-forward `secure` from `main`**

Run:

```bash
if git show-ref --verify --quiet refs/heads/secure; then
  git switch secure
  git merge --ff-only main
else
  git switch -c secure main
fi
```

Expected output contains either:

```text
Switched to a new branch 'secure'
```

or:

```text
Already up to date.
```

- [ ] **Step 3: Push `secure`**

Run:

```bash
git push -u origin secure
```

Expected output contains:

```text
branch 'secure' set up to track 'origin/secure'
```

- [ ] **Step 4: Verify `secure` has no seeded vulnerability labels**

Run:

```bash
git grep -n 'SEEDED VULN' -- ':!scripts/seed-vulnerabilities.md' ':!scripts/seed-vulnerable-branch.sh' ':!scripts/seed-secret.sh' || true
```

Expected output: no output.

---

### Task 5: Create the `vulnerable` Branch from `main`

**Files:**
- No file changes

- [ ] **Step 1: Create or fast-forward `vulnerable` from `main`**

Run:

```bash
git switch main
if git show-ref --verify --quiet refs/heads/vulnerable; then
  git switch vulnerable
  git merge --ff-only main
else
  git switch -c vulnerable main
fi
```

Expected output contains either:

```text
Switched to a new branch 'vulnerable'
```

or:

```text
Already up to date.
```

- [ ] **Step 2: Verify the branch is still clean before seeding**

Run:

```bash
git status --short
git grep -n 'SEEDED VULN' -- ':!scripts/seed-vulnerabilities.md' ':!scripts/seed-vulnerable-branch.sh' ':!scripts/seed-secret.sh' || true
```

Expected output from `git status --short`: no output.

Expected `git grep` output: no output.

---

### Task 6: Vuln #1 — SQL Injection in `ItemController#search`

**Files:**
- Modify: `src/backend/src/main/java/com/example/ghasdefender/web/ItemController.java`

- [ ] **Step 1: Apply the exact vulnerable diff**

Diff from `secure` to `vulnerable`:

```diff
diff --git a/src/backend/src/main/java/com/example/ghasdefender/web/ItemController.java b/src/backend/src/main/java/com/example/ghasdefender/web/ItemController.java
--- a/src/backend/src/main/java/com/example/ghasdefender/web/ItemController.java
+++ b/src/backend/src/main/java/com/example/ghasdefender/web/ItemController.java
@@
+import jakarta.persistence.EntityManager;
 import org.springframework.web.bind.annotation.RequestParam;
@@
   private final ItemRepository itemRepository;
+  private final EntityManager entityManager;
 
-  public ItemController(ItemRepository itemRepository) {
+  public ItemController(ItemRepository itemRepository, EntityManager entityManager) {
     this.itemRepository = itemRepository;
+    this.entityManager = entityManager;
   }
 
   @GetMapping
+  @SuppressWarnings("unchecked")
   public List<ItemResponse> search(@RequestParam(defaultValue = "") String q) {
-    return itemRepository.findByNameContainingIgnoreCase(q).stream()
-        .map(ItemResponse::from)
+    var rows = entityManager
+        // SEEDED VULN #1 — see scripts/seed-vulnerabilities.md
+        .createNativeQuery("SELECT * FROM items WHERE name LIKE '%" + q + "%'")
+        .getResultList();
+
+    return rows.stream()
+        .map(row -> (Object[]) row)
+        .map(columns -> new ItemResponse(
+            ((Number) columns[0]).longValue(),
+            (String) columns[1],
+            (String) columns[2]))
         .toList();
   }
```

Run:

```bash
python3 - <<'PY'
from pathlib import Path
path = Path("src/backend/src/main/java/com/example/ghasdefender/web/ItemController.java")
text = path.read_text(encoding="utf-8")
text = text.replace(
    "import org.springframework.web.bind.annotation.RequestParam;\n",
    "import jakarta.persistence.EntityManager;\nimport org.springframework.web.bind.annotation.RequestParam;\n",
    1,
)
text = text.replace(
    "  private final ItemRepository itemRepository;\n\n"
    "  public ItemController(ItemRepository itemRepository) {\n"
    "    this.itemRepository = itemRepository;\n"
    "  }\n",
    "  private final ItemRepository itemRepository;\n"
    "  private final EntityManager entityManager;\n\n"
    "  public ItemController(ItemRepository itemRepository, EntityManager entityManager) {\n"
    "    this.itemRepository = itemRepository;\n"
    "    this.entityManager = entityManager;\n"
    "  }\n",
    1,
)
old_method = """  @GetMapping
  public List<ItemResponse> search(@RequestParam(defaultValue = "") String q) {
    return itemRepository.findByNameContainingIgnoreCase(q).stream()
        .map(ItemResponse::from)
        .toList();
  }
"""
new_method = """  @GetMapping
  @SuppressWarnings("unchecked")
  public List<ItemResponse> search(@RequestParam(defaultValue = "") String q) {
    var rows = entityManager
        // SEEDED VULN #1 — see scripts/seed-vulnerabilities.md
        .createNativeQuery("SELECT * FROM items WHERE name LIKE '%" + q + "%'")
        .getResultList();

    return rows.stream()
        .map(row -> (Object[]) row)
        .map(columns -> new ItemResponse(
            ((Number) columns[0]).longValue(),
            (String) columns[1],
            (String) columns[2]))
        .toList();
  }
"""
if old_method not in text:
    raise SystemExit("secure ItemController#search snippet not found")
path.write_text(text.replace(old_method, new_method, 1), encoding="utf-8")
PY
```

Expected output: no output.

- [ ] **Step 2: Verify the label and native query are present**

Run:

```bash
grep -n 'SEEDED VULN #1' src/backend/src/main/java/com/example/ghasdefender/web/ItemController.java
grep -n 'createNativeQuery("SELECT \* FROM items WHERE name LIKE' src/backend/src/main/java/com/example/ghasdefender/web/ItemController.java
```

Expected output format:

```text
N:        // SEEDED VULN #1 — see scripts/seed-vulnerabilities.md
N:        .createNativeQuery("SELECT * FROM items WHERE name LIKE '%" + q + "%'")
```

- [ ] **Step 3: Run a backend compile/package check without secure-behavior tests**

Run:

```bash
./mvnw -f src/backend/pom.xml -DskipTests package
```

Expected output contains:

```text
BUILD SUCCESS
```

The focused secure-behavior `ItemControllerTest` may fail on `vulnerable` because seed #1 is intentionally unsafe; do not treat that failure as a reason to remove the seed.

- [ ] **Step 4: Commit seed #1**

Run:

```bash
git add src/backend/src/main/java/com/example/ghasdefender/web/ItemController.java
git commit -m "vuln: seed #1 SQL injection in ItemController#search" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

Expected output contains:

```text
[vulnerable
```

- [ ] **Step 5: Record expected detector output after push**

Expected CodeQL alert after Task 12 push:

```text
Rule ID: java/sql-injection
Alert title: Database query built from user-controlled sources
File: src/backend/src/main/java/com/example/ghasdefender/web/ItemController.java
Sink text: createNativeQuery("SELECT * FROM items WHERE name LIKE '%" + q + "%'")
Required check: backend-ci / codeql
PR effect: merge into secure is blocked because a required status check failed
```

Verification command after push:

```bash
gh api 'repos/JoranBergfeld/ghas-defender-example/code-scanning/alerts?ref=refs/heads/vulnerable&state=open' --jq '.[] | select(.rule.id=="java/sql-injection") | [.rule.id, .rule.description, .most_recent_instance.location.path] | @tsv'
```

Expected output format:

```text
java/sql-injection	Database query built from user-controlled sources	src/backend/src/main/java/com/example/ghasdefender/web/ItemController.java
```

---

### Task 7: Vuln #2 — XSS in `SearchResults.tsx`

**Files:**
- Modify: `src/frontend/src/components/SearchResults.tsx`

- [ ] **Step 1: Apply the exact vulnerable diff**

Diff from `secure` to `vulnerable`:

```diff
diff --git a/src/frontend/src/components/SearchResults.tsx b/src/frontend/src/components/SearchResults.tsx
--- a/src/frontend/src/components/SearchResults.tsx
+++ b/src/frontend/src/components/SearchResults.tsx
@@
 export function SearchResults({ serverResponse }: SearchResultsProps) {
-  return <p data-testid="search-summary">{serverResponse}</p>;
+  return (
+    <p
+      data-testid="search-summary"
+      // SEEDED VULN #2 — see scripts/seed-vulnerabilities.md
+      dangerouslySetInnerHTML={{ __html: serverResponse }}
+    />
+  );
 }
```

Run:

```bash
python3 - <<'PY'
from pathlib import Path
path = Path("src/frontend/src/components/SearchResults.tsx")
text = path.read_text(encoding="utf-8")
old = """export function SearchResults({ serverResponse }: SearchResultsProps) {
  return <p data-testid="search-summary">{serverResponse}</p>;
}
"""
new = """export function SearchResults({ serverResponse }: SearchResultsProps) {
  return (
    <p
      data-testid="search-summary"
      // SEEDED VULN #2 — see scripts/seed-vulnerabilities.md
      dangerouslySetInnerHTML={{ __html: serverResponse }}
    />
  );
}
"""
if old not in text:
    raise SystemExit("secure SearchResults snippet not found")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
PY
```

Expected output: no output.

- [ ] **Step 2: Verify the label and XSS sink are present**

Run:

```bash
grep -n 'SEEDED VULN #2' src/frontend/src/components/SearchResults.tsx
grep -n 'dangerouslySetInnerHTML={{ __html: serverResponse }}' src/frontend/src/components/SearchResults.tsx
```

Expected output format:

```text
N:      // SEEDED VULN #2 — see scripts/seed-vulnerabilities.md
N:      dangerouslySetInnerHTML={{ __html: serverResponse }}
```

- [ ] **Step 3: Run a frontend build check without secure-behavior component tests**

Run:

```bash
npm --prefix src/frontend run build
```

Expected output contains:

```text
built
```

The secure-behavior `SearchResults` Vitest case may fail on `vulnerable` because seed #2 intentionally uses `dangerouslySetInnerHTML`; do not treat that failure as a reason to remove the seed.

- [ ] **Step 4: Commit seed #2**

Run:

```bash
git add src/frontend/src/components/SearchResults.tsx
git commit -m "vuln: seed #2 XSS via dangerouslySetInnerHTML" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

Expected output contains:

```text
[vulnerable
```

- [ ] **Step 5: Record expected detector output after push**

Expected CodeQL alert after Task 12 push:

```text
Rule ID: js/xss
Alert title: Client-side cross-site scripting
File: src/frontend/src/components/SearchResults.tsx
Sink text: dangerouslySetInnerHTML={{ __html: serverResponse }}
Required check: frontend-ci / codeql
PR effect: merge into secure is blocked because a required status check failed
```

Verification command after push:

```bash
gh api 'repos/JoranBergfeld/ghas-defender-example/code-scanning/alerts?ref=refs/heads/vulnerable&state=open' --jq '.[] | select(.rule.id=="js/xss") | [.rule.id, .rule.description, .most_recent_instance.location.path] | @tsv'
```

Expected output format:

```text
js/xss	Client-side cross-site scripting	src/frontend/src/components/SearchResults.tsx
```

---

### Task 8: Vuln #3 — Hardcoded JWT Secret in `JwtConfig.java`

**Files:**
- Modify: `src/backend/src/main/java/com/example/ghasdefender/config/JwtConfig.java`

- [ ] **Step 1: Apply the exact vulnerable diff**

Diff from `secure` to `vulnerable`:

```diff
diff --git a/src/backend/src/main/java/com/example/ghasdefender/config/JwtConfig.java b/src/backend/src/main/java/com/example/ghasdefender/config/JwtConfig.java
--- a/src/backend/src/main/java/com/example/ghasdefender/config/JwtConfig.java
+++ b/src/backend/src/main/java/com/example/ghasdefender/config/JwtConfig.java
@@
 @ConfigurationProperties(prefix = "app.jwt")
 public record JwtConfig(String issuer, Duration tokenTtl, String signingKey) {
+  // SEEDED VULN #3 — see scripts/seed-vulnerabilities.md
+  private static final String JWT_SECRET = "supersecret_demo_key_do_not_use_in_production";
+
+  @Override
+  public String signingKey() {
+    return JWT_SECRET;
+  }
 }
```

Run:

```bash
python3 - <<'PY'
from pathlib import Path
path = Path("src/backend/src/main/java/com/example/ghasdefender/config/JwtConfig.java")
text = path.read_text(encoding="utf-8")
old = """@ConfigurationProperties(prefix = "app.jwt")
public record JwtConfig(String issuer, Duration tokenTtl, String signingKey) {
}
"""
new = """@ConfigurationProperties(prefix = "app.jwt")
public record JwtConfig(String issuer, Duration tokenTtl, String signingKey) {
  // SEEDED VULN #3 — see scripts/seed-vulnerabilities.md
  private static final String JWT_SECRET = "supersecret_demo_key_do_not_use_in_production";

  @Override
  public String signingKey() {
    return JWT_SECRET;
  }
}
"""
if old not in text:
    raise SystemExit("secure JwtConfig snippet not found")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
PY
```

Expected output: no output.

- [ ] **Step 2: Verify the label and literal are present**

Run:

```bash
grep -n 'SEEDED VULN #3' src/backend/src/main/java/com/example/ghasdefender/config/JwtConfig.java
grep -n 'supersecret_demo_key_do_not_use_in_production' src/backend/src/main/java/com/example/ghasdefender/config/JwtConfig.java
```

Expected output format:

```text
N:  // SEEDED VULN #3 — see scripts/seed-vulnerabilities.md
N:  private static final String JWT_SECRET = "supersecret_demo_key_do_not_use_in_production";
```

- [ ] **Step 3: Run a backend compile/package check without secure-behavior tests**

Run:

```bash
./mvnw -f src/backend/pom.xml -DskipTests package
```

Expected output contains:

```text
BUILD SUCCESS
```

The secure-behavior `ItemControllerTest` may already fail because seed #1 is present on this branch; keep the seed and rely on CodeQL for the demo finding.

- [ ] **Step 4: Commit seed #3**

Run:

```bash
git add src/backend/src/main/java/com/example/ghasdefender/config/JwtConfig.java
git commit -m "vuln: seed #3 hardcoded JWT secret" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

Expected output contains:

```text
[vulnerable
```

- [ ] **Step 5: Record expected detector output after push**

Expected CodeQL alert after Task 12 push:

```text
Rule ID: java/hardcoded-credentials
Alert title: Hard-coded credentials
File: src/backend/src/main/java/com/example/ghasdefender/config/JwtConfig.java
Evidence text: JWT_SECRET = "supersecret_demo_key_do_not_use_in_production"
Required check: backend-ci / codeql
PR effect: merge into secure is blocked because a required status check failed
```

Verification command after push:

```bash
gh api 'repos/JoranBergfeld/ghas-defender-example/code-scanning/alerts?ref=refs/heads/vulnerable&state=open' --jq '.[] | select(.rule.id=="java/hardcoded-credentials") | [.rule.id, .rule.description, .most_recent_instance.location.path] | @tsv'
```

Expected output format:

```text
java/hardcoded-credentials	Hard-coded credentials	src/backend/src/main/java/com/example/ghasdefender/config/JwtConfig.java
```

---

### Task 9: Vuln #5 — Vulnerable Dependency Pins

**Files:**
- Modify: `src/backend/pom.xml`
- Modify: `src/frontend/package.json`

- [ ] **Step 1: Apply the exact Maven diff**

Diff from `secure` to `vulnerable`:

```diff
diff --git a/src/backend/pom.xml b/src/backend/pom.xml
--- a/src/backend/pom.xml
+++ b/src/backend/pom.xml
@@
   <dependencies>
+    <dependency>
+      <!-- SEEDED VULN #5 — see scripts/seed-vulnerabilities.md -->
+      <groupId>org.springframework</groupId>
+      <artifactId>spring-core</artifactId>
+      <version>5.3.18</version>
+    </dependency>
```

Run:

```bash
python3 - <<'PY'
from pathlib import Path
path = Path("src/backend/pom.xml")
text = path.read_text(encoding="utf-8")
if "<artifactId>spring-core</artifactId>" not in text:
    dependency = """    <dependency>
      <!-- SEEDED VULN #5 — see scripts/seed-vulnerabilities.md -->
      <groupId>org.springframework</groupId>
      <artifactId>spring-core</artifactId>
      <version>5.3.18</version>
    </dependency>
"""
    text = text.replace("  </dependencies>\n", dependency + "  </dependencies>\n", 1)
path.write_text(text, encoding="utf-8")
PY
```

Expected output: no output.

- [ ] **Step 2: Apply the exact npm diff**

Diff from `secure` to `vulnerable`:

```diff
diff --git a/src/frontend/package.json b/src/frontend/package.json
--- a/src/frontend/package.json
+++ b/src/frontend/package.json
@@
   "dependencies": {
+    "axios": "0.21.0",
@@
-  }
+  },
+  "// SEEDED VULN #5": "see scripts/seed-vulnerabilities.md; axios 0.21.0 is intentionally vulnerable on the vulnerable branch"
 }
```

Run:

```bash
python3 - <<'PY'
from pathlib import Path
import json
path = Path("src/frontend/package.json")
data = json.loads(path.read_text(encoding="utf-8"))
data.setdefault("dependencies", {})["axios"] = "0.21.0"
data["// SEEDED VULN #5"] = "see scripts/seed-vulnerabilities.md; axios 0.21.0 is intentionally vulnerable on the vulnerable branch"
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
```

Expected output: no output.

- [ ] **Step 3: Refresh lockfiles**

Run:

```bash
./mvnw -f src/backend/pom.xml -DskipTests dependency:tree -Dincludes=org.springframework:spring-core
npm --prefix src/frontend install --package-lock-only
```

Expected Maven output contains:

```text
org.springframework:spring-core:jar:5.3.18
```

Expected npm output contains:

```text
audited
```

Run:

```bash
node -p "require('./src/frontend/package-lock.json').packages['node_modules/axios'].version"
```

Expected output:

```text
0.21.0
```

- [ ] **Step 4: Verify labels and pins**

Run:

```bash
grep -n 'SEEDED VULN #5' src/backend/pom.xml src/frontend/package.json
grep -n '<version>5.3.18</version>' src/backend/pom.xml
grep -n '"axios": "0.21.0"' src/frontend/package.json
```

Expected output format:

```text
src/backend/pom.xml:N:      <!-- SEEDED VULN #5 — see scripts/seed-vulnerabilities.md -->
src/frontend/package.json:N:  "// SEEDED VULN #5": "see scripts/seed-vulnerabilities.md; axios 0.21.0 is intentionally vulnerable on the vulnerable branch"
src/backend/pom.xml:N:      <version>5.3.18</version>
src/frontend/package.json:N:    "axios": "0.21.0"
```

- [ ] **Step 5: Commit seed #5**

Run:

```bash
git add src/backend/pom.xml src/frontend/package.json src/frontend/package-lock.json
git commit -m "vuln: seed #5 vulnerable dependency pins" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

Expected output contains:

```text
[vulnerable
```

- [ ] **Step 6: Record expected detector output after push**

Expected Dependabot alerts after GitHub dependency graph processing:

```text
Package: org.springframework:spring-core
Version: 5.3.18
Advisory: CVE-2022-22965
Expected alert title contains: Spring Framework remote code execution
File: src/backend/pom.xml

Package: axios
Version: 0.21.0
Advisory: CVE-2021-3749
Expected alert title contains: Regular Expression Denial of Service in axios
File: src/frontend/package.json
```

Verification command after push:

```bash
gh api 'repos/JoranBergfeld/ghas-defender-example/dependabot/alerts?state=open' --jq '.[] | select(.dependency.package.name=="spring-core" or .dependency.package.name=="axios") | [.dependency.package.name, .dependency.manifest_path, .security_advisory.cve_id, .security_advisory.summary] | @tsv'
```

Expected output format:

```text
spring-core	src/backend/pom.xml	CVE-2022-22965	Spring Framework remote code execution
axios	src/frontend/package.json	CVE-2021-3749	Regular Expression Denial of Service in axios
```

---

### Task 10: Vuln #6 — Insecure Backend Dockerfile

**Files:**
- Modify: `src/backend/Dockerfile`

- [ ] **Step 1: Apply the exact vulnerable Dockerfile**

Diff from `secure` to `vulnerable`:

```diff
diff --git a/src/backend/Dockerfile b/src/backend/Dockerfile
--- a/src/backend/Dockerfile
+++ b/src/backend/Dockerfile
@@
-FROM eclipse-temurin:21-jdk AS build
-WORKDIR /workspace
-COPY mvnw pom.xml ./
-COPY .mvn .mvn
-RUN ./mvnw -B -DskipTests dependency:go-offline
-COPY src src
-RUN ./mvnw -B -DskipTests package
-
-FROM eclipse-temurin:21-jre-alpine
-WORKDIR /app
-COPY --from=build /workspace/target/ghas-defender-backend.jar /app/app.jar
-USER 1001
-HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --retries=3 CMD wget -qO- http://localhost:8080/actuator/health || exit 1
-ENTRYPOINT ["java", "-jar", "/app/app.jar"]
+# SEEDED VULN #6 — see scripts/seed-vulnerabilities.md
+FROM eclipse-temurin:21-jdk
+
+WORKDIR /app
+COPY . .
+RUN ./mvnw -B -DskipTests package
+
+USER root
+ENTRYPOINT ["java", "-jar", "target/ghas-defender-backend.jar"]
```

Run:

```bash
cat > src/backend/Dockerfile <<'DOCKERFILE'
# SEEDED VULN #6 — see scripts/seed-vulnerabilities.md
FROM eclipse-temurin:21-jdk

WORKDIR /app
COPY . .
RUN ./mvnw -B -DskipTests package

USER root
ENTRYPOINT ["java", "-jar", "target/ghas-defender-backend.jar"]
DOCKERFILE
```

Expected output: no output.

- [ ] **Step 2: Verify insecure container traits**

Run:

```bash
grep -n 'SEEDED VULN #6' src/backend/Dockerfile
grep -n '^FROM eclipse-temurin:21-jdk$' src/backend/Dockerfile
grep -n '^COPY \. \.$' src/backend/Dockerfile
grep -n '^USER root$' src/backend/Dockerfile
if grep -n '^HEALTHCHECK' src/backend/Dockerfile; then
  echo "unexpected HEALTHCHECK"
  exit 1
else
  echo "no HEALTHCHECK present"
fi
```

Expected output format:

```text
1:# SEEDED VULN #6 — see scripts/seed-vulnerabilities.md
2:FROM eclipse-temurin:21-jdk
5:COPY . .
8:USER root
no HEALTHCHECK present
```

- [ ] **Step 3: Build the image locally**

Run:

```bash
docker build -t ghas-defender-backend:vuln-seed src/backend
```

Expected output contains:

```text
Successfully tagged ghas-defender-backend:vuln-seed
```

- [ ] **Step 4: Commit seed #6**

Run:

```bash
git add src/backend/Dockerfile
git commit -m "vuln: seed #6 insecure backend container" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

Expected output contains:

```text
[vulnerable
```

- [ ] **Step 5: Record expected Defender output after push and deploy**

Expected workflow and Defender behavior after Task 12 push:

```text
Workflow: backend-ci
Job: deploy
Build/push: azd deploy backend builds and pushes backend:<git-sha> and backend:vulnerable to ACR
Admission failure format: admission webhook "validation.gatekeeper.sh" denied the request: [azurepolicy-container-vulnerability-assessment] container image "<acr>.azurecr.io/backend:<git-sha>" has high severity vulnerabilities and is not allowed by policy
Timing: Defender image assessment can take 5-15 minutes after the image reaches ACR before the admission denial is reproducible
```

Verification commands after push:

```bash
gh run list --workflow backend-ci.yml --branch vulnerable --limit 5
gh run view --log-failed
```

Expected failed-log text contains:

```text
admission webhook
high severity vulnerabilities
backend:
```

---

### Task 11: Vuln #7 — AKS and PostgreSQL IaC Misconfiguration

**Files:**
- Modify: `infra/modules/aks.bicep`
- Modify: `infra/modules/postgres.bicep`

- [ ] **Step 1: Apply the exact AKS diff**

Diff from `secure` to `vulnerable`:

```diff
diff --git a/infra/modules/aks.bicep b/infra/modules/aks.bicep
--- a/infra/modules/aks.bicep
+++ b/infra/modules/aks.bicep
@@
-    enableRBAC: true
+    /*
+    # SEEDED VULN #7 — see scripts/seed-vulnerabilities.md
+    */
+    enableRBAC: false
@@
-      authorizedIpRanges: authorizedIpRanges
+      authorizedIpRanges: []
```

Run:

```bash
python3 - <<'PY'
from pathlib import Path
path = Path("infra/modules/aks.bicep")
text = path.read_text(encoding="utf-8")
text = text.replace("enableRBAC: true", "/*\n    # SEEDED VULN #7 — see scripts/seed-vulnerabilities.md\n    */\n    enableRBAC: false", 1)
text = text.replace("authorizedIpRanges: authorizedIpRanges", "authorizedIpRanges: []", 1)
path.write_text(text, encoding="utf-8")
PY
```

Expected output: no output.

- [ ] **Step 2: Apply the exact PostgreSQL diff**

Diff from `secure` to `vulnerable`:

```diff
diff --git a/infra/modules/postgres.bicep b/infra/modules/postgres.bicep
--- a/infra/modules/postgres.bicep
+++ b/infra/modules/postgres.bicep
@@
-    publicNetworkAccess: 'Disabled'
+    /*
+    # SEEDED VULN #7 — see scripts/seed-vulnerabilities.md
+    */
+    publicNetworkAccess: 'Enabled'
@@
-    administratorLogin: postgresAdminUsername
-    administratorLoginPassword: postgresAdminPassword
+    administratorLogin: 'admin'
+    administratorLoginPassword: 'Password123!'
```

Run:

```bash
python3 - <<'PY'
from pathlib import Path
path = Path("infra/modules/postgres.bicep")
text = path.read_text(encoding="utf-8")
text = text.replace("publicNetworkAccess: 'Disabled'", "/*\n    # SEEDED VULN #7 — see scripts/seed-vulnerabilities.md\n    */\n    publicNetworkAccess: 'Enabled'", 1)
text = text.replace("administratorLogin: postgresAdminUsername", "administratorLogin: 'admin'", 1)
text = text.replace("administratorLoginPassword: postgresAdminPassword", "administratorLoginPassword: 'Password123!'", 1)
path.write_text(text, encoding="utf-8")
PY
```

Expected output: no output.

- [ ] **Step 3: Verify labels and insecure IaC values**

Run:

```bash
grep -n 'SEEDED VULN #7' infra/modules/aks.bicep infra/modules/postgres.bicep
grep -n 'enableRBAC: false' infra/modules/aks.bicep
grep -n 'authorizedIpRanges: \[\]' infra/modules/aks.bicep
grep -n "publicNetworkAccess: 'Enabled'" infra/modules/postgres.bicep
grep -n "administratorLogin: 'admin'" infra/modules/postgres.bicep
grep -n "administratorLoginPassword: 'Password123!'" infra/modules/postgres.bicep
```

Expected output format:

```text
infra/modules/aks.bicep:N:    # SEEDED VULN #7 — see scripts/seed-vulnerabilities.md
infra/modules/postgres.bicep:N:    # SEEDED VULN #7 — see scripts/seed-vulnerabilities.md
infra/modules/aks.bicep:N:    enableRBAC: false
infra/modules/aks.bicep:N:      authorizedIpRanges: []
infra/modules/postgres.bicep:N:    publicNetworkAccess: 'Enabled'
infra/modules/postgres.bicep:N:    administratorLogin: 'admin'
infra/modules/postgres.bicep:N:    administratorLoginPassword: 'Password123!'
```

- [ ] **Step 4: Run Bicep syntax validation**

Run:

```bash
az bicep build --file infra/main.bicep
```

Expected output: no output.

- [ ] **Step 5: Commit seed #7**

Run:

```bash
git add infra/modules/aks.bicep infra/modules/postgres.bicep
git commit -m "vuln: seed #7 insecure AKS and PostgreSQL IaC" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

Expected output contains:

```text
[vulnerable
```

- [ ] **Step 6: Record expected detector output after push**

Expected CodeQL/Defender IaC findings after Task 12 push:

```text
File: infra/modules/aks.bicep
Finding: Kubernetes cluster RBAC is disabled
Evidence: enableRBAC: false

File: infra/modules/aks.bicep
Finding: Kubernetes API server allows unrestricted network access
Evidence: authorizedIpRanges: []

File: infra/modules/postgres.bicep
Finding: PostgreSQL server has public network access enabled
Evidence: publicNetworkAccess: 'Enabled'

File: infra/modules/postgres.bicep
Finding: Weak or default administrator credential values are present in IaC
Evidence: administratorLogin: 'admin' and administratorLoginPassword: 'Password123!'
```

Verification commands after push:

```bash
gh run list --workflow infra.yml --branch vulnerable --limit 5
gh api 'repos/JoranBergfeld/ghas-defender-example/code-scanning/alerts?ref=refs/heads/vulnerable&state=open' --jq '.[] | select(.most_recent_instance.location.path | test("infra/modules/(aks|postgres)\\.bicep")) | [.rule.id, .rule.description, .most_recent_instance.location.path] | @tsv'
```

Expected output format:

```text
<iac-rule-id>	<AKS RBAC, AKS API access, PostgreSQL public access, or weak credential finding>	infra/modules/aks.bicep
<iac-rule-id>	<PostgreSQL public access or weak credential finding>	infra/modules/postgres.bicep
```

---

### Task 12: Push `vulnerable` and Observe Automated Findings

**Files:**
- No new file changes

- [ ] **Step 1: Verify exactly six non-secret vulnerability numbers are present before push**

Run:

```bash
git grep -h -o 'SEEDED VULN #[0-9]' -- ':!scripts/seed-vulnerabilities.md' ':!scripts/seed-vulnerable-branch.sh' ':!scripts/seed-secret.sh' | sort -u | wc -l
```

Expected output:

```text
6
```

- [ ] **Step 2: Verify the branch contains one commit per non-secret seed**

Run:

```bash
git log --oneline main..vulnerable
```

Expected output contains these six commits:

```text
vuln: seed #7 insecure AKS and PostgreSQL IaC
vuln: seed #6 insecure backend container
vuln: seed #5 vulnerable dependency pins
vuln: seed #3 hardcoded JWT secret
vuln: seed #2 XSS via dangerouslySetInnerHTML
vuln: seed #1 SQL injection in ItemController#search
```

- [ ] **Step 3: Push `vulnerable`**

Run:

```bash
git push -u origin vulnerable
```

Expected output contains:

```text
branch 'vulnerable' set up to track 'origin/vulnerable'
```

- [ ] **Step 4: Watch workflow runs**

Run:

```bash
gh run list --branch vulnerable --limit 10
```

Expected output contains runs for:

```text
backend-ci
frontend-ci
infra
```

- [ ] **Step 5: Verify CodeQL alerts for #1, #2, #3, and #7**

Run:

```bash
gh api 'repos/JoranBergfeld/ghas-defender-example/code-scanning/alerts?ref=refs/heads/vulnerable&state=open' --jq '.[] | [.rule.id, .rule.description, .most_recent_instance.location.path] | @tsv'
```

Expected output includes these rows or rows with the same rule IDs and files:

```text
java/sql-injection	Database query built from user-controlled sources	src/backend/src/main/java/com/example/ghasdefender/web/ItemController.java
js/xss	Client-side cross-site scripting	src/frontend/src/components/SearchResults.tsx
java/hardcoded-credentials	Hard-coded credentials	src/backend/src/main/java/com/example/ghasdefender/config/JwtConfig.java
<iac-rule-id>	<AKS or PostgreSQL IaC security finding>	infra/modules/aks.bicep
<iac-rule-id>	<AKS or PostgreSQL IaC security finding>	infra/modules/postgres.bicep
```

- [ ] **Step 6: Verify Dependabot alerts for #5**

Run:

```bash
gh api 'repos/JoranBergfeld/ghas-defender-example/dependabot/alerts?state=open' --jq '.[] | select(.dependency.package.name=="spring-core" or .dependency.package.name=="axios") | [.dependency.package.name, .dependency.manifest_path, .security_advisory.cve_id, .security_advisory.summary] | @tsv'
```

Expected output includes:

```text
spring-core	src/backend/pom.xml	CVE-2022-22965	Spring Framework remote code execution
axios	src/frontend/package.json	CVE-2021-3749	Regular Expression Denial of Service in axios
```

- [ ] **Step 7: Verify Defender admission denial for #6**

Run after Defender has had 5-15 minutes to assess the pushed image:

```bash
gh run list --workflow backend-ci.yml --branch vulnerable --limit 5
gh run view --log-failed
```

Expected failed-log text format:

```text
admission webhook "validation.gatekeeper.sh" denied the request: [azurepolicy-container-vulnerability-assessment] container image "<acr>.azurecr.io/backend:<git-sha>" has high severity vulnerabilities
```

- [ ] **Step 8: Capture exact UI strings for Plan 8**

Run these commands and save the terminal output for the Plan 8 author:

```bash
gh run view --log-failed > docs/superpowers/plans/plan-7-vulnerable-run-log.txt
gh api 'repos/JoranBergfeld/ghas-defender-example/code-scanning/alerts?ref=refs/heads/vulnerable&state=open' > docs/superpowers/plans/plan-7-code-scanning-alerts.json
gh api 'repos/JoranBergfeld/ghas-defender-example/dependabot/alerts?state=open' > docs/superpowers/plans/plan-7-dependabot-alerts.json
```

Expected output: no terminal output; the three local evidence files exist for Plan 8 drafting and are not committed.

---

### Task 13: Manually Exercise Vuln #4 — Secret Push Protection

**Files:**
- Modify on disposable branch only: `src/backend/src/main/resources/application-local.yml`

- [ ] **Step 1: Create a disposable feature branch from `vulnerable`**

Run:

```bash
git switch vulnerable
git switch -c demo/seed-secret
```

Expected output:

```text
Switched to a new branch 'demo/seed-secret'
```

- [ ] **Step 2: Generate the fake PAT-pattern token**

Run:

```bash
./scripts/seed-secret.sh
```

Expected output format:

```text
WARNING: generated a fake GitHub PAT-pattern token for the GHAS push-protection demo.
Token written to: src/backend/src/main/resources/application-local.yml
Token value: ghp_<40 random alphanumeric characters>

This script does not run git add, git commit, or git push.
Run it only on a disposable feature branch created from vulnerable.
Commit and push manually when demonstrating seed #4; the expected result is a push-protection rejection.
Do not use --allow-secret-scanning-bypass in automation because the rejection is the demo moment.
```

- [ ] **Step 3: Verify the file contains seed #4 and only a fake PAT-pattern token**

Run:

```bash
grep -n 'SEEDED VULN #4' src/backend/src/main/resources/application-local.yml
grep -E 'ghp_[[:alnum:]]{40}' src/backend/src/main/resources/application-local.yml | wc -l
```

Expected output format:

```text
N:  leakedGitHubPat: "ghp_<40 random alphanumeric characters>" # SEEDED VULN #4 — see scripts/seed-vulnerabilities.md
1
```

- [ ] **Step 4: Commit seed #4 locally**

Run:

```bash
git add src/backend/src/main/resources/application-local.yml
git commit -m "vuln: seed #4 leaked GitHub PAT pattern" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

Expected output contains:

```text
[demo/seed-secret
```

- [ ] **Step 5: Push and expect protection to reject it**

Run:

```bash
git push -u origin demo/seed-secret
```

Expected output contains:

```text
remote: error: GH013: Repository rule violations found for refs/heads/demo/seed-secret.
remote: Push declined due to a detected secret.
remote: GitHub Personal Access Token
remote: To push, remove secret from commit(s) or follow the URL to allow the secret.
```

- [ ] **Step 6: Recover the disposable local branch without bypassing**

Run:

```bash
git reset --hard vulnerable
git switch vulnerable
git branch -D demo/seed-secret
```

Expected output contains:

```text
HEAD is now at
Deleted branch demo/seed-secret
```

- [ ] **Step 7: Optional bypass demonstration for a presenter-controlled run**

Use this path only when the presenter intentionally wants to show GitHub's audited bypass UI. Do not add bypass flags to scripts.

Run:

```bash
git switch -c demo/seed-secret-bypass vulnerable
./scripts/seed-secret.sh
git add src/backend/src/main/resources/application-local.yml
git commit -m "vuln: seed #4 leaked GitHub PAT pattern" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
git push -u origin demo/seed-secret-bypass
```

Expected output again contains `Push declined due to a detected secret`. The presenter opens the URL printed by GitHub, chooses the web UI bypass reason, then retries:

```bash
git push -u origin demo/seed-secret-bypass
```

Expected output after web UI bypass contains:

```text
branch 'demo/seed-secret-bypass' set up to track 'origin/demo/seed-secret-bypass'
```

Immediately remove the bypass branch after the demo:

```bash
git push origin --delete demo/seed-secret-bypass
git switch vulnerable
git branch -D demo/seed-secret-bypass
```

Expected output contains:

```text
- [deleted]         demo/seed-secret-bypass
Deleted branch demo/seed-secret-bypass
```

---

### Task 14: Final Verification and Handoff to Plan 8

**Files:**
- No committed file changes beyond Tasks 1–13

- [ ] **Step 1: Verify `main` has scripts and inventory but no seeded application/infra vulnerabilities**

Run:

```bash
git switch main
git grep -n 'SEEDED VULN' -- ':!scripts/seed-vulnerabilities.md' ':!scripts/seed-vulnerable-branch.sh' ':!scripts/seed-secret.sh' || true
```

Expected output: no output.

- [ ] **Step 2: Verify `secure` matches `main`**

Run:

```bash
git switch secure
git diff --stat main..secure
```

Expected output: no output.

- [ ] **Step 3: Verify `vulnerable` has the expected committed non-secret seed label locations**

Run:

```bash
git switch vulnerable
git grep -n 'SEEDED VULN' -- ':!scripts/seed-vulnerabilities.md' ':!scripts/seed-vulnerable-branch.sh' ':!scripts/seed-secret.sh'
```

Expected output includes exactly these six labels:

```text
infra/modules/aks.bicep:N:    # SEEDED VULN #7 — see scripts/seed-vulnerabilities.md
infra/modules/postgres.bicep:N:    # SEEDED VULN #7 — see scripts/seed-vulnerabilities.md
src/backend/Dockerfile:1:# SEEDED VULN #6 — see scripts/seed-vulnerabilities.md
src/backend/pom.xml:N:      <!-- SEEDED VULN #5 — see scripts/seed-vulnerabilities.md -->
src/backend/src/main/java/com/example/ghasdefender/config/JwtConfig.java:N:  // SEEDED VULN #3 — see scripts/seed-vulnerabilities.md
src/backend/src/main/java/com/example/ghasdefender/web/ItemController.java:N:        // SEEDED VULN #1 — see scripts/seed-vulnerabilities.md
src/frontend/package.json:N:  "// SEEDED VULN #5": "see scripts/seed-vulnerabilities.md; axios 0.21.0 is intentionally vulnerable on the vulnerable branch"
src/frontend/src/components/SearchResults.tsx:N:      // SEEDED VULN #2 — see scripts/seed-vulnerabilities.md
```

The command shows eight label locations because #5 and #7 each touch two files; it represents six committed non-secret vulnerability numbers.

- [ ] **Step 4: Verify no fake PAT-pattern token was committed to `vulnerable`**

Run:

```bash
if git grep -E 'ghp_[[:alnum:]]{40}' vulnerable -- .; then
  echo "unexpected PAT-pattern token committed to vulnerable"
  exit 1
else
  echo "no PAT-pattern token committed to vulnerable"
fi
```

Expected output:

```text
no PAT-pattern token committed to vulnerable
```

- [ ] **Step 5: Verify Plan 8 has exact filenames and detector strings available**

Run:

```bash
printf '%s\n' \
  'src/backend/src/main/java/com/example/ghasdefender/web/ItemController.java — java/sql-injection — Database query built from user-controlled sources' \
  'src/frontend/src/components/SearchResults.tsx — js/xss — Client-side cross-site scripting' \
  'src/backend/src/main/java/com/example/ghasdefender/config/JwtConfig.java — java/hardcoded-credentials — Hard-coded credentials' \
  'src/backend/src/main/resources/application-local.yml — GitHub Personal Access Token — Push declined due to a detected secret' \
  'src/backend/pom.xml — CVE-2022-22965 — Spring Framework remote code execution' \
  'src/frontend/package.json — CVE-2021-3749 — Regular Expression Denial of Service in axios' \
  'src/backend/Dockerfile — Defender for Containers — admission webhook denied high severity vulnerable image' \
  'infra/modules/aks.bicep — CodeQL/Defender IaC — AKS RBAC/API server misconfiguration' \
  'infra/modules/postgres.bicep — CodeQL/Defender IaC — PostgreSQL public access and weak demo admin values'
```

Expected output is the nine lines printed by `printf`; give them to the Plan 8 DEMO.md author.

---

## Open Questions and Execution Risks

1. **Bicep label syntax:** The shared contract requires a `# SEEDED VULN #7 — see scripts/seed-vulnerabilities.md` label for Bicep. This plan preserves that exact label inside a Bicep block comment (`/* ... */`) so the file remains valid Bicep.
2. **Dependency advisory accuracy:** The user contract for Plan 7 mandates `org.springframework:spring-core:5.3.18` with `CVE-2022-22965` and `axios:0.21.0` with `CVE-2021-3749`. Before execution, confirm GitHub Advisory Database still maps those exact versions to the expected CVEs; if GitHub reports a different advisory for `spring-core:5.3.18`, keep the mandated version and record the observed advisory title for Plan 8.
3. **Dependabot alert titles:** The advisory IDs are intended to be stable, but GitHub Advisory Database summaries can be revised. Plan 8 should quote the exact UI title observed after Task 12 instead of relying only on this plan's expected wording.
4. **Secret push protection bypass:** The default demo flow does not bypass; the block is scenario 1. The optional bypass branch is only for a presenter-controlled run that demonstrates GitHub's audited bypass UI and must be deleted immediately afterward.
5. **Defender admission timing:** Defender for Containers assessment can lag image push by 5-15 minutes. If the first `azd deploy backend` reaches AKS before the assessment is available, rerun the backend deploy workflow after the Defender ACR finding appears.
6. **Inactive branch protection bootstrapping:** If Plan 6 applies branch protection before `secure` and `vulnerable` exist, Task 4 and Task 12 pushes may require an admin token or temporarily adjusted repository rules. Preserve the final required checks and push protection on all three branches.
