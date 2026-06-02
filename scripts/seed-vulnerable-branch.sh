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
label = "SEEDED VULN #1"
if label in text:
    print("seed #1 already present")
    raise SystemExit(0)

old_import = "import jakarta.validation.Valid;\n"
new_import = "import jakarta.persistence.EntityManager;\nimport jakarta.validation.Valid;\n"
if old_import not in text:
    raise SystemExit("Expected `import jakarta.validation.Valid;` not found in ItemController.java; reconcile baseline before seeding #1.")
text = text.replace(old_import, new_import, 1)

old_field_ctor = (
    "    private final ItemRepository itemRepository;\n\n"
    "    public ItemController(ItemRepository itemRepository) {\n"
    "        this.itemRepository = itemRepository;\n"
    "    }\n"
)
new_field_ctor = (
    "    private final ItemRepository itemRepository;\n"
    "    private final EntityManager entityManager;\n\n"
    "    public ItemController(ItemRepository itemRepository, EntityManager entityManager) {\n"
    "        this.itemRepository = itemRepository;\n"
    "        this.entityManager = entityManager;\n"
    "    }\n"
)
if old_field_ctor not in text:
    raise SystemExit("Expected ItemController field+constructor block not found; reconcile baseline before seeding #1.")
text = text.replace(old_field_ctor, new_field_ctor, 1)

old_search = (
    '    @GetMapping("/search")\n'
    '    public List<Item> search(@RequestParam("q") String query) {\n'
    '        return itemRepository.searchByName(query);\n'
    '    }\n'
)
new_search = (
    '    @GetMapping("/search")\n'
    '    @SuppressWarnings("unchecked")\n'
    '    public List<Item> search(@RequestParam("q") String query) {\n'
    '        // SEEDED VULN #1 — see scripts/seed-vulnerabilities.md\n'
    '        return entityManager\n'
    '                .createNativeQuery("SELECT * FROM items WHERE name LIKE \'%" + query + "%\'", Item.class)\n'
    '                .getResultList();\n'
    '    }\n'
)
if old_search not in text:
    raise SystemExit("Expected ItemController#search method not found; reconcile baseline before seeding #1.")
text = text.replace(old_search, new_search, 1)
path.write_text(text, encoding="utf-8")
PY
  commit_paths "vuln: seed #1 SQL injection in ItemController#search" \
    src/backend/src/main/java/com/example/ghasdefender/web/ItemController.java
}

seed_xss() {
  python3 - <<'PY'
from pathlib import Path
path = Path("src/frontend/src/components/SearchResults.tsx")
text = path.read_text(encoding="utf-8")
label = "SEEDED VULN #2"
if label in text:
    print("seed #2 already present")
    raise SystemExit(0)
old = (
    "            <article className=\"card\" key={item.id}>\n"
    "              <h2>{item.name}</h2>\n"
    "              <p>{item.description}</p>\n"
    "            </article>\n"
)
new = (
    "            <article className=\"card\" key={item.id}>\n"
    "              <h2>{item.name}</h2>\n"
    "              {/* SEEDED VULN #2 — see scripts/seed-vulnerabilities.md */}\n"
    "              <p dangerouslySetInnerHTML={{ __html: item.description }} />\n"
    "            </article>\n"
)
if old not in text:
    raise SystemExit("Expected SearchResults card snippet not found; reconcile baseline before seeding #2.")
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
label = "SEEDED VULN #3"
if label in text:
    print("seed #3 already present")
    raise SystemExit(0)
old = (
    "    @Bean\n"
    "    @Profile(\"!cloud\")\n"
    "    public SecretKey localJwtSigningKey(@Value(\"${app.jwt.signing-key}\") String signingKey) {\n"
    "        return hmacSigningKey(signingKey);\n"
    "    }\n"
)
new = (
    "    // SEEDED VULN #3 — see scripts/seed-vulnerabilities.md\n"
    "    private static final String JWT_SECRET = \"supersecret_demo_key_do_not_use_in_production\";\n\n"
    "    @Bean\n"
    "    @Profile(\"!cloud\")\n"
    "    public SecretKey localJwtSigningKey(@Value(\"${app.jwt.signing-key:}\") String signingKey) {\n"
    "        return Keys.hmacShaKeyFor(JWT_SECRET.getBytes(java.nio.charset.StandardCharsets.UTF_8));\n"
    "    }\n"
)
if old not in text:
    raise SystemExit("Expected JwtConfig localJwtSigningKey bean not found; reconcile baseline before seeding #3.")
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
if "<artifactId>spring-core</artifactId>" in pom_text:
    print("spring-core seed already present")
else:
    dependency = (
        "    <dependency>\n"
        "      <!-- SEEDED VULN #5 — see scripts/seed-vulnerabilities.md -->\n"
        "      <groupId>org.springframework</groupId>\n"
        "      <artifactId>spring-core</artifactId>\n"
        "      <version>5.3.18</version>\n"
        "    </dependency>\n"
    )
    closing = "    </dependencies>\n"
    idx = pom_text.find(closing)
    if idx == -1:
        raise SystemExit("Could not locate first `</dependencies>` in pom.xml")
    pom_text = pom_text[:idx] + dependency + pom_text[idx:]
    pom.write_text(pom_text, encoding="utf-8")

package_json = Path("src/frontend/package.json")
data = json.loads(package_json.read_text(encoding="utf-8"))
dependencies = data.setdefault("dependencies", {})
dependencies["axios"] = "0.21.0"
comment_key = "// SEEDED VULN #5"
data[comment_key] = "see scripts/seed-vulnerabilities.md; axios 0.21.0 is intentionally vulnerable on the vulnerable branch"
package_json.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
  npm --prefix src/frontend install --package-lock-only --no-audit --no-fund --legacy-peer-deps
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
    aks_text = aks_text.replace(
        "    enableRBAC: true\n",
        "    /*\n    # SEEDED VULN #7 — see scripts/seed-vulnerabilities.md\n    */\n    enableRBAC: false\n",
        1,
    )
    aks.write_text(aks_text, encoding="utf-8")

postgres = Path("infra/modules/postgres.bicep")
pg_text = postgres.read_text(encoding="utf-8")
if "SEEDED VULN #7" not in pg_text:
    pg_text = pg_text.replace(
        "      publicNetworkAccess: 'Disabled'\n",
        "      /*\n      # SEEDED VULN #7 — see scripts/seed-vulnerabilities.md\n      */\n      publicNetworkAccess: 'Enabled'\n",
        1,
    )
    pg_text = pg_text.replace(
        "    administratorLogin: 'pgadmin'\n",
        "    administratorLogin: 'admin'\n",
        1,
    )
    pg_text = pg_text.replace(
        "    administratorLoginPassword: administratorPassword\n",
        "    administratorLoginPassword: 'Password123!'\n",
        1,
    )
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
