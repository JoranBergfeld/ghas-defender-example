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

test_path = Path("src/backend/src/test/java/com/example/ghasdefender/web/ItemControllerTest.java")
test_text = test_path.read_text(encoding="utf-8")

old_test_imports = (
    "import com.example.ghasdefender.security.JwtService;\n"
    "import java.util.List;\n"
)
new_test_imports = (
    "import com.example.ghasdefender.security.JwtService;\n"
    "import jakarta.persistence.EntityManager;\n"
    "import jakarta.persistence.Query;\n"
    "import java.util.List;\n"
)
if old_test_imports in test_text:
    test_text = test_text.replace(old_test_imports, new_test_imports, 1)

old_mockbean = (
    "    @MockBean\n"
    "    private ItemRepository itemRepository;\n\n"
    "    @MockBean\n"
    "    private JwtService jwtService;\n"
)
new_mockbean = (
    "    @MockBean\n"
    "    private ItemRepository itemRepository;\n\n"
    "    @MockBean\n"
    "    private JwtService jwtService;\n\n"
    "    // SEEDED VULN #1 — see scripts/seed-vulnerabilities.md\n"
    "    @MockBean\n"
    "    private EntityManager entityManager;\n"
)
if old_mockbean in test_text:
    test_text = test_text.replace(old_mockbean, new_mockbean, 1)

old_search_returns = (
    "    @Test\n"
    "    void searchItemsReturnsRepositoryMatches() throws Exception {\n"
    "        when(itemRepository.searchByName(\"Alpha\")).thenReturn(List.of(\n"
    "                new Item(\"Demo Item Alpha\", \"First clean demo item\")\n"
    "        ));\n\n"
    "        mockMvc.perform(get(\"/api/items/search\").param(\"q\", \"Alpha\"))\n"
    "                .andExpect(status().isOk())\n"
    "                .andExpect(jsonPath(\"$\", hasSize(1)))\n"
    "                .andExpect(jsonPath(\"$[0].name\").value(\"Demo Item Alpha\"));\n"
    "    }\n\n"
    "    @Test\n"
    "    void searchItemsPassesInjectionTextAsPlainQueryParameter() throws Exception {\n"
    "        String injection = \"' OR '1'='1\";\n"
    "        when(itemRepository.searchByName(injection)).thenReturn(List.of());\n\n"
    "        mockMvc.perform(get(\"/api/items/search\").param(\"q\", injection))\n"
    "                .andExpect(status().isOk())\n"
    "                .andExpect(jsonPath(\"$\", hasSize(0)));\n\n"
    "        verify(itemRepository).searchByName(injection);\n"
    "    }\n"
)
new_search_returns = (
    "    @Test\n"
    "    void searchItemsReturnsRepositoryMatches() throws Exception {\n"
    "        // SEEDED VULN #1 — controller now uses native query, not the safe repository method\n"
    "        Query nativeQuery = org.mockito.Mockito.mock(Query.class);\n"
    "        when(entityManager.createNativeQuery(any(String.class), org.mockito.ArgumentMatchers.eq(Item.class)))\n"
    "                .thenReturn(nativeQuery);\n"
    "        when(nativeQuery.getResultList()).thenReturn(List.of(\n"
    "                new Item(\"Demo Item Alpha\", \"First clean demo item\")\n"
    "        ));\n\n"
    "        mockMvc.perform(get(\"/api/items/search\").param(\"q\", \"Alpha\"))\n"
    "                .andExpect(status().isOk())\n"
    "                .andExpect(jsonPath(\"$\", hasSize(1)))\n"
    "                .andExpect(jsonPath(\"$[0].name\").value(\"Demo Item Alpha\"));\n"
    "    }\n\n"
    "    @Test\n"
    "    void searchItemsPassesInjectionTextAsPlainQueryParameter() throws Exception {\n"
    "        // SEEDED VULN #1 — assert the native query string concatenates user input verbatim\n"
    "        String injection = \"' OR '1'='1\";\n"
    "        Query nativeQuery = org.mockito.Mockito.mock(Query.class);\n"
    "        when(entityManager.createNativeQuery(\n"
    "                org.mockito.ArgumentMatchers.contains(injection),\n"
    "                org.mockito.ArgumentMatchers.eq(Item.class)))\n"
    "                .thenReturn(nativeQuery);\n"
    "        when(nativeQuery.getResultList()).thenReturn(List.of());\n\n"
    "        mockMvc.perform(get(\"/api/items/search\").param(\"q\", injection))\n"
    "                .andExpect(status().isOk())\n"
    "                .andExpect(jsonPath(\"$\", hasSize(0)));\n\n"
    "        verify(entityManager).createNativeQuery(\n"
    "                org.mockito.ArgumentMatchers.contains(injection),\n"
    "                org.mockito.ArgumentMatchers.eq(Item.class));\n"
    "    }\n"
)
if old_search_returns in test_text:
    test_text = test_text.replace(old_search_returns, new_search_returns, 1)
test_path.write_text(test_text, encoding="utf-8")
PY
  commit_paths "vuln: seed #1 SQL injection in ItemController#search" \
    src/backend/src/main/java/com/example/ghasdefender/web/ItemController.java \
    src/backend/src/test/java/com/example/ghasdefender/web/ItemControllerTest.java
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

test_path = Path("src/backend/src/test/java/com/example/ghasdefender/security/JwtServiceTest.java")
test_text = test_path.read_text(encoding="utf-8")
old_assertions = (
    "    @Test\n"
    "    void emptyConfiguredKeyFailsFast() {\n"
    "        assertThatThrownBy(() -> new JwtConfig().localJwtSigningKey(\"\"))\n"
    "                .isInstanceOf(IllegalStateException.class)\n"
    "                .hasMessageContaining(\"JWT signing key must decode to at least 32 bytes\");\n"
    "    }\n\n"
    "    @Test\n"
    "    void shortConfiguredKeyFailsFast() {\n"
    "        // c2hvcnQ= is base64 for \"short\" (5 bytes), well under the 32-byte minimum.\n"
    "        assertThatThrownBy(() -> new JwtConfig().localJwtSigningKey(\"c2hvcnQ=\"))\n"
    "                .isInstanceOf(IllegalStateException.class)\n"
    "                .hasMessageContaining(\"JWT signing key must decode to at least 32 bytes\");\n"
    "    }\n"
)
new_assertions = (
    "    @Test\n"
    "    void emptyConfiguredKeyFailsFast() {\n"
    "        // SEEDED VULN #3 — seeded JwtConfig#localJwtSigningKey returns hardcoded key\n"
    "        // regardless of input; assertion adjusted to confirm the insecure behavior.\n"
    "        SecretKey key = new JwtConfig().localJwtSigningKey(\"\");\n"
    "        assertThat(key).isNotNull();\n"
    "    }\n\n"
    "    @Test\n"
    "    void shortConfiguredKeyFailsFast() {\n"
    "        // SEEDED VULN #3 — same as above; seeded code no longer validates the input key.\n"
    "        SecretKey key = new JwtConfig().localJwtSigningKey(\"c2hvcnQ=\");\n"
    "        assertThat(key).isNotNull();\n"
    "    }\n"
)
if old_assertions in test_text:
    test_path.write_text(test_text.replace(old_assertions, new_assertions, 1), encoding="utf-8")
PY
  commit_paths "vuln: seed #3 hardcoded JWT secret" \
    src/backend/src/main/java/com/example/ghasdefender/config/JwtConfig.java \
    src/backend/src/test/java/com/example/ghasdefender/security/JwtServiceTest.java
}

seed_vulnerable_dependencies() {
  python3 - <<'PY'
from pathlib import Path
import json

pom = Path("src/backend/pom.xml")
pom_text = pom.read_text(encoding="utf-8")
if "commons-fileupload" in pom_text:
    print("commons-fileupload seed already present")
else:
    dependency = (
        "        <!-- SEEDED VULN #5 — see scripts/seed-vulnerabilities.md -->\n"
        "        <dependency>\n"
        "            <groupId>commons-fileupload</groupId>\n"
        "            <artifactId>commons-fileupload</artifactId>\n"
        "            <version>1.3.1</version>\n"
        "        </dependency>\n"
    )
    anchor = (
        "        <dependency>\n"
        "            <groupId>io.jsonwebtoken</groupId>\n"
        "            <artifactId>jjwt-jackson</artifactId>\n"
        "            <version>${jjwt.version}</version>\n"
        "            <scope>runtime</scope>\n"
        "        </dependency>\n"
    )
    idx = pom_text.find(anchor)
    if idx == -1:
        raise SystemExit("Could not locate jjwt-jackson dependency anchor in pom.xml")
    insert_at = idx + len(anchor)
    pom_text = pom_text[:insert_at] + dependency + pom_text[insert_at:]
    pom.write_text(pom_text, encoding="utf-8")

package_json = Path("src/frontend/package.json")
data = json.loads(package_json.read_text(encoding="utf-8"))
dependencies = data.setdefault("dependencies", {})
dependencies["axios"] = "0.21.0"
comment_key = "// SEEDED VULN #5"
data[comment_key] = "see scripts/seed-vulnerabilities.md; axios 0.21.0 is intentionally vulnerable on the vulnerable branch"
package_json.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

# Refactor api/client.ts to work with axios 0.21 (no AxiosHeaders export).
client = Path("src/frontend/src/api/client.ts")
client_text = client.read_text(encoding="utf-8")
if "AxiosHeaders" in client_text:
    client_text = (
        "import axios from 'axios';\n\n"
        "export const AUTH_TOKEN_STORAGE_KEY = 'auth_token';\n\n"
        "export const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:8080';\n\n"
        "export const apiClient = axios.create({\n"
        "  baseURL: API_BASE_URL,\n"
        "  headers: { 'Content-Type': 'application/json' },\n"
        "});\n\n"
        "apiClient.interceptors.request.use((config) => {\n"
        "  const token =\n"
        "    typeof window === 'undefined' ? null : window.localStorage.getItem(AUTH_TOKEN_STORAGE_KEY);\n\n"
        "  if (token) {\n"
        "    config.headers = {\n"
        "      ...(config.headers ?? {}),\n"
        "      Authorization: `Bearer ${token}`,\n"
        "    };\n"
        "  }\n\n"
        "  return config;\n"
        "});\n"
    )
    client.write_text(client_text, encoding="utf-8")

client_test = Path("src/frontend/src/__tests__/api/client.test.ts")
client_test_text = client_test.read_text(encoding="utf-8")
old_test_block = (
    "import { API_BASE_URL, AUTH_TOKEN_STORAGE_KEY, apiClient } from '../../api/client';\n\n"
    "type RequestInterceptor = (config: { headers?: unknown }) => {\n"
    "  headers?: { get: (name: string) => string | undefined };\n"
    "};\n\n"
    "describe('api client', () => {\n"
)
new_test_block = (
    "import { API_BASE_URL, AUTH_TOKEN_STORAGE_KEY, apiClient } from '../../api/client';\n\n"
    "describe('api client', () => {\n"
)
if old_test_block in client_test_text:
    client_test_text = client_test_text.replace(old_test_block, new_test_block, 1)
old_assertion = (
    "  it('adds Authorization header when token is present', () => {\n"
    "    window.localStorage.setItem(AUTH_TOKEN_STORAGE_KEY, 'test-token');\n"
    "    const interceptor = axiosMocks.instance.interceptors.request.use.mock.calls[0][0] as RequestInterceptor;\n\n"
    "    const result = interceptor({ headers: {} });\n\n"
    "    expect(result.headers?.get('Authorization')).toBe('Bearer test-token');\n"
    "  });\n"
)
new_assertion = (
    "  it('adds Authorization header when token is present', () => {\n"
    "    window.localStorage.setItem(AUTH_TOKEN_STORAGE_KEY, 'test-token');\n"
    "    const interceptor = axiosMocks.instance.interceptors.request.use.mock.calls[0][0] as (\n"
    "      config: { headers?: Record<string, string> }\n"
    "    ) => { headers?: Record<string, string> };\n\n"
    "    const result = interceptor({ headers: {} });\n\n"
    "    expect(result.headers?.Authorization).toBe('Bearer test-token');\n"
    "  });\n"
)
if old_assertion in client_test_text:
    client_test_text = client_test_text.replace(old_assertion, new_assertion, 1)
client_test.write_text(client_test_text, encoding="utf-8")
PY
  npm --prefix src/frontend install --package-lock-only --no-audit --no-fund --legacy-peer-deps
  commit_paths "vuln: seed #5 vulnerable dependency pins" \
    src/backend/pom.xml \
    src/frontend/package.json \
    src/frontend/package-lock.json \
    src/frontend/src/api/client.ts \
    src/frontend/src/__tests__/api/client.test.ts
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
