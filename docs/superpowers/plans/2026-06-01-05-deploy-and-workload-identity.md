# Plan 5 — azd Deploy + Workload Identity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After this plan, `azd deploy backend` and `azd deploy frontend` deploy the clean `main` branch app end-to-end: backend runs on AKS with Workload Identity, reads PostgreSQL and JWT secrets from Key Vault, runs Flyway before rollout, exposes `/api/items` through public ingress, and the Static Web Apps frontend calls that backend.

**Architecture:** `azure.yaml` uses native `azd` hosts: `host: aks` for the Spring Boot backend and `host: staticwebapp` for the Vite frontend. AKS manifests live under `src/backend/k8s/`; files that need azd environment values use azd's Go-template format and the `.tmpl.yaml` suffix so `azd` renders image names and provision outputs before applying them. The `postprovision` hook configures kube access, pre-creates stable Kubernetes resources, and captures ingress/SWA hostnames; the backend `predeploy` hook runs the Flyway Job with the freshly published backend image before `azd` rolls the Deployment.

**Tech Stack:** Azure Developer CLI, AKS Web App Routing, Azure Workload Identity, Azure Key Vault, Spring Boot 3.x, Spring Cloud Azure 5.x, Java 21, Maven, Flyway, PostgreSQL, React 18, Vite, Azure Static Web Apps.

---

## Required Context

- The design spec is the source of truth: `docs/superpowers/specs/2026-06-01-ghas-defender-demo-design.md`.
- The repository instructions require clean code on `main`, no seeded vulnerabilities in this plan, no GitHub Actions YAML, and no CI-side container scanning.
- Plan 4 must provide these azd environment outputs before this plan is executed:
  - `AZURE_CONTAINER_REGISTRY_ENDPOINT`
  - `AZURE_AKS_CLUSTER_NAME`
  - `AZURE_RESOURCE_GROUP`
  - `AZURE_KEY_VAULT_NAME`
  - `AZURE_KEY_VAULT_URI`
  - `AZURE_POSTGRES_HOST`
  - `AZURE_POSTGRES_DATABASE` with value `appdb`
  - `AZURE_STATIC_WEB_APP_NAME`
  - `AZURE_BACKEND_IDENTITY_CLIENT_ID`
- Plan 2 must already provide a runnable Spring Boot backend with `/api/items`, Flyway migrations, local/cloud profiles, and JWT-based auth wiring that consumes a `SecretKey` bean from `JwtConfig`.
- Plan 3 must already provide a runnable Vite React frontend that reads `VITE_API_BASE_URL` at build time.

## Resolved azd Decisions

I verified current azd AKS behavior against the public azd schema and azd source implementation:

- `host: aks` uses `k8s.deploymentPath`; when omitted, azd defaults to `manifests`. Because this repo uses `src/backend/k8s`, set `k8s.deploymentPath: k8s` in `azure.yaml`.
- azd writes the pushed backend image to `SERVICE_BACKEND_IMAGE_NAME` during publish.
- azd renders Kubernetes manifests only when a YAML file name ends with `.tmpl.yaml` or `.tmpl.yml`. Use `deployment.tmpl.yaml`, `serviceaccount.tmpl.yaml`, and `flyway-job.tmpl.yaml`; a plain `deployment.yaml` containing template expressions would be applied without rendering.
- No image-substitution hook is needed for the Deployment. The backend `predeploy` hook is used only to run Flyway with the same rendered image before the Deployment rollout.
- The Flyway Job cannot run in `postprovision` on a fresh `azd up` because the backend image has not been built or pushed yet. `postprovision` prepares namespace/ServiceAccount/Service/Ingress and captures URLs; backend `predeploy` runs Flyway after publish and before rollout.

## File Map

- Modify `azure.yaml`: declare backend and frontend services, configure AKS deployment path/name/namespace, and register project/service hooks.
- Create `src/backend/Dockerfile`: secure multi-stage Java 21 image, non-root runtime user `1001`, actuator healthcheck.
- Create `src/backend/.dockerignore`: keep Docker build context small and prevent local artifacts from entering the image.
- Modify `src/backend/pom.xml`: add Spring Cloud Azure BOM, Key Vault starter, direct Azure SDK dependencies for `SecretClient`, and Actuator.
- Modify `src/backend/src/main/resources/application-cloud.yml`: configure Key Vault property source, PostgreSQL from azd env, and disable app-pod Flyway.
- Create `src/backend/src/main/java/com/example/ghasdefender/security/JwtKeyBootstrap.java`: read or create `jwt-signing-key` in Key Vault via `SecretClient` and `DefaultAzureCredential`.
- Modify `src/backend/src/main/java/com/example/ghasdefender/config/JwtConfig.java`: local profile uses existing local signing key; cloud profile uses `JwtKeyBootstrap`.
- Create `src/backend/src/test/java/com/example/ghasdefender/security/JwtKeyBootstrapTest.java`: prove Key Vault writes happen only when the secret is absent.
- Create `src/backend/k8s/namespace.yaml`: Kubernetes namespace `app`.
- Create `src/backend/k8s/serviceaccount.tmpl.yaml`: Workload Identity ServiceAccount bound to Plan 4's backend UAMI client ID.
- Create `src/backend/k8s/service.yaml`: ClusterIP service `backend`, port 80 to container port 8080.
- Create `src/backend/k8s/ingress.yaml`: AKS Web App Routing ingress for `/api` with no host constraint.
- Create `src/backend/k8s/deployment.tmpl.yaml`: backend Deployment with Workload Identity labels, rendered backend image, env vars, probes, and resources.
- Create `src/backend/k8s/flyway-job.tmpl.yaml`: one-shot Flyway Job using the rendered backend image and cloud profile.
- Modify `scripts/azd-hooks/postprovision.sh` and `scripts/azd-hooks/postprovision.ps1`: configure kube credentials, apply stable resources, capture ingress IP and SWA hostname into azd env.
- Create `scripts/azd-hooks/predeploy-backend.sh` and `scripts/azd-hooks/predeploy-backend.ps1`: render/apply Workload Identity and Flyway Job, wait for completion, show logs on failure.
- Modify `src/frontend/staticwebapp.config.json`: add CSP allowing the ingress hostname pattern used by `VITE_API_BASE_URL`.

## Task 0: Pre-flight Validation

**Files:** None.

- [ ] **Step 1: Confirm branch and clean status**

Run:

```bash
git --no-pager branch --show-current
git --no-pager status --short
```

Expected output:

```text
main
```

The second command must print no file changes. If it prints files, inspect each listed file with `git --no-pager diff -- path/from/status` before editing.

- [ ] **Step 2: Confirm Plan 4 azd outputs are available**

Run:

```bash
azd env get-values | grep -E '^(AZURE_CONTAINER_REGISTRY_ENDPOINT|AZURE_AKS_CLUSTER_NAME|AZURE_RESOURCE_GROUP|AZURE_KEY_VAULT_NAME|AZURE_KEY_VAULT_URI|AZURE_POSTGRES_HOST|AZURE_POSTGRES_DATABASE|AZURE_STATIC_WEB_APP_NAME|AZURE_BACKEND_IDENTITY_CLIENT_ID)='
```

Expected output shape:

```text
AZURE_AKS_CLUSTER_NAME="aks-demo"
AZURE_BACKEND_IDENTITY_CLIENT_ID="00000000-0000-0000-0000-000000000000"
AZURE_CONTAINER_REGISTRY_ENDPOINT="<acr-name>.azurecr.io"
AZURE_KEY_VAULT_NAME="<kv-name>"
AZURE_KEY_VAULT_URI="https://<kv-name>.vault.azure.net/"
AZURE_POSTGRES_DATABASE="appdb"
AZURE_POSTGRES_HOST="pg-demo-<random>.postgres.database.azure.com"
AZURE_RESOURCE_GROUP="rg-ghas-defender-demo"
AZURE_STATIC_WEB_APP_NAME="swa-demo"
```

- [ ] **Step 3: Confirm local toolchain commands exist**

Run:

```bash
command -v azd && command -v az && command -v kubectl && command -v docker && command -v java
```

Expected output shape:

```text
/usr/local/bin/azd
/usr/bin/az
/usr/local/bin/kubectl
/usr/bin/docker
/usr/bin/java
```

## Task 1: Add Secure Backend Container Baseline

**Files:**
- Create: `src/backend/Dockerfile`
- Create: `src/backend/.dockerignore`

- [ ] **Step 1: Create `src/backend/Dockerfile`**

Write this full file:

```dockerfile
FROM eclipse-temurin:21-jdk-alpine AS build

WORKDIR /workspace

COPY .mvn/ .mvn/
COPY mvnw pom.xml ./
RUN chmod +x mvnw && ./mvnw -B -DskipTests dependency:go-offline

COPY src/ src/
RUN ./mvnw -B -DskipTests package

FROM eclipse-temurin:21-jre-alpine

WORKDIR /app

RUN addgroup -S app && adduser -S app -G app -u 1001

COPY --from=build /workspace/target/*.jar /app/app.jar
RUN chown -R 1001:0 /app

USER 1001
EXPOSE 8080

ENV JAVA_OPTS="-XX:MaxRAMPercentage=75.0"

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/actuator/health/liveness || exit 1

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar /app/app.jar"]
```

- [ ] **Step 2: Create `src/backend/.dockerignore`**

Write this full file:

```gitignore
.git
.gitignore
.github
.mvn/wrapper/maven-wrapper.jar
README.md
Dockerfile
.dockerignore
target
**/target
*.iml
.idea
.vscode
.DS_Store
```

- [ ] **Step 3: Build the backend image locally**

Run:

```bash
docker build -t backend:test src/backend
```

Expected output ending:

```text
Successfully tagged backend:test
```

- [ ] **Step 4: Run the container with the local profile**

Run:

```bash
docker run --rm --name backend-test -e SPRING_PROFILES_ACTIVE=local -p 8080:8080 backend:test
```

Expected output includes:

```text
Started GhasDefenderApplication
```

Keep this command running for the next step.

- [ ] **Step 5: Verify actuator health from another shell**

Run:

```bash
curl -i http://127.0.0.1:8080/actuator/health
```

Expected output:

```text
HTTP/1.1 200
Content-Type: application/vnd.spring-boot.actuator.v3+json

{"status":"UP"}
```

- [ ] **Step 6: Stop the local container**

Run:

```bash
docker stop backend-test
```

Expected output:

```text
backend-test
```

- [ ] **Step 7: Commit the secure container baseline**

Run:

```bash
git add src/backend/Dockerfile src/backend/.dockerignore
git commit -m "build: add secure backend container baseline" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

Expected output:

```text
[main 1234abc] build: add secure backend container baseline
 2 files changed
 create mode 100644 src/backend/.dockerignore
 create mode 100644 src/backend/Dockerfile
```

## Task 2: Add Spring Cloud Azure Key Vault and Actuator Dependencies

**Files:**
- Modify: `src/backend/pom.xml`

- [ ] **Step 1: Replace `src/backend/pom.xml` with dependency-managed Java 21 configuration**

If Plan 2 already added project-specific dependencies, keep them, but the finished file must contain the dependency management and dependencies shown here. When in doubt, use this full file and re-add only Plan 2 source packages that fail compilation.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>3.4.6</version>
        <relativePath/>
    </parent>

    <groupId>com.example</groupId>
    <artifactId>ghas-defender-backend</artifactId>
    <version>0.0.1-SNAPSHOT</version>
    <name>ghas-defender-backend</name>
    <description>Spring Boot backend for the GHAS and Defender for Cloud demo</description>

    <properties>
        <java.version>21</java.version>
        <spring-cloud-azure.version>5.22.0</spring-cloud-azure.version>
        <jjwt.version>0.12.6</jjwt.version>
    </properties>

    <dependencyManagement>
        <dependencies>
            <dependency>
                <groupId>com.azure.spring</groupId>
                <artifactId>spring-cloud-azure-dependencies</artifactId>
                <version>${spring-cloud-azure.version}</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>
        </dependencies>
    </dependencyManagement>

    <dependencies>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-actuator</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-data-jpa</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-security</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-validation</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>
        <dependency>
            <groupId>com.azure.spring</groupId>
            <artifactId>spring-cloud-azure-starter-keyvault-secrets</artifactId>
        </dependency>
        <dependency>
            <groupId>com.azure</groupId>
            <artifactId>azure-identity</artifactId>
        </dependency>
        <dependency>
            <groupId>com.azure</groupId>
            <artifactId>azure-security-keyvault-secrets</artifactId>
        </dependency>
        <dependency>
            <groupId>org.flywaydb</groupId>
            <artifactId>flyway-core</artifactId>
        </dependency>
        <dependency>
            <groupId>org.flywaydb</groupId>
            <artifactId>flyway-database-postgresql</artifactId>
        </dependency>
        <dependency>
            <groupId>org.postgresql</groupId>
            <artifactId>postgresql</artifactId>
            <scope>runtime</scope>
        </dependency>
        <dependency>
            <groupId>io.jsonwebtoken</groupId>
            <artifactId>jjwt-api</artifactId>
            <version>${jjwt.version}</version>
        </dependency>
        <dependency>
            <groupId>io.jsonwebtoken</groupId>
            <artifactId>jjwt-impl</artifactId>
            <version>${jjwt.version}</version>
            <scope>runtime</scope>
        </dependency>
        <dependency>
            <groupId>io.jsonwebtoken</groupId>
            <artifactId>jjwt-jackson</artifactId>
            <version>${jjwt.version}</version>
            <scope>runtime</scope>
        </dependency>
        <dependency>
            <groupId>com.h2database</groupId>
            <artifactId>h2</artifactId>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>org.springframework.security</groupId>
            <artifactId>spring-security-test</artifactId>
            <scope>test</scope>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
            </plugin>
        </plugins>
    </build>
</project>
```

- [ ] **Step 2: Run Maven verification**

Run:

```bash
./mvnw -f src/backend/pom.xml verify
```

Expected output ending:

```text
[INFO] BUILD SUCCESS
```

- [ ] **Step 3: Commit dependency changes**

Run:

```bash
git add src/backend/pom.xml
git commit -m "build: add key vault and actuator dependencies" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

Expected output:

```text
[main 2345bcd] build: add key vault and actuator dependencies
 1 file changed
```

## Task 3: Wire Key Vault Secrets and JWT Bootstrap

**Files:**
- Modify: `src/backend/src/main/resources/application-cloud.yml`
- Create: `src/backend/src/main/java/com/example/ghasdefender/security/JwtKeyBootstrap.java`
- Modify: `src/backend/src/main/java/com/example/ghasdefender/config/JwtConfig.java`
- Create: `src/backend/src/test/java/com/example/ghasdefender/security/JwtKeyBootstrapTest.java`

- [ ] **Step 1: Replace `application-cloud.yml`**

Write this full file:

```yaml
spring:
  application:
    name: ghas-defender-backend
  cloud:
    azure:
      credential:
        client-id: ${AZURE_CLIENT_ID:${AZURE_BACKEND_IDENTITY_CLIENT_ID:}}
      keyvault:
        secret:
          endpoint: ${AZURE_KEY_VAULT_URI}
          property-sources:
            - name: ghas-defender-key-vault
              endpoint: ${AZURE_KEY_VAULT_URI}
  datasource:
    url: jdbc:postgresql://${POSTGRES_HOST}:5432/${POSTGRES_DATABASE:appdb}?sslmode=require
    username: ${POSTGRES_USERNAME:app}
    password: ${postgres-admin-password}
  flyway:
    enabled: false
  jpa:
    hibernate:
      ddl-auto: validate
    open-in-view: false

server:
  port: 8080

management:
  endpoint:
    health:
      probes:
        enabled: true
  endpoints:
    web:
      exposure:
        include: health,info

app:
  cors:
    allowed-origins: ${CORS_ALLOWED_ORIGINS}
```

- [ ] **Step 2: Create `JwtKeyBootstrap.java`**

Write this full file:

```java
package com.example.ghasdefender.security;

import com.azure.core.exception.ResourceNotFoundException;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.security.keyvault.secrets.SecretClient;
import com.azure.security.keyvault.secrets.SecretClientBuilder;
import com.azure.security.keyvault.secrets.models.KeyVaultSecret;
import java.security.SecureRandom;
import java.util.Base64;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

@Component
@Profile("cloud")
public class JwtKeyBootstrap {

    public static final String SECRET_NAME = "jwt-signing-key";
    private static final int SIGNING_KEY_BYTES = 32;

    private final SecretClient secretClient;
    private final SecureRandom secureRandom;

    public JwtKeyBootstrap(@Value("${AZURE_KEY_VAULT_URI:}") String keyVaultUri) {
        this(createSecretClient(keyVaultUri), new SecureRandom());
    }

    JwtKeyBootstrap(SecretClient secretClient, SecureRandom secureRandom) {
        this.secretClient = secretClient;
        this.secureRandom = secureRandom;
    }

    public String getOrCreateSigningKey() {
        try {
            return secretClient.getSecret(SECRET_NAME).getValue();
        } catch (ResourceNotFoundException ex) {
            String generatedKey = generateSigningKey();
            secretClient.setSecret(new KeyVaultSecret(SECRET_NAME, generatedKey));
            return generatedKey;
        }
    }

    private String generateSigningKey() {
        byte[] key = new byte[SIGNING_KEY_BYTES];
        secureRandom.nextBytes(key);
        return Base64.getEncoder().encodeToString(key);
    }

    private static SecretClient createSecretClient(String keyVaultUri) {
        if (!StringUtils.hasText(keyVaultUri)) {
            throw new IllegalStateException("AZURE_KEY_VAULT_URI must be set when the cloud profile is active");
        }

        return new SecretClientBuilder()
                .vaultUrl(keyVaultUri)
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildClient();
    }
}
```

- [ ] **Step 3: Replace `JwtConfig.java`**

Write this full file:

```java
package com.example.ghasdefender.config;

import com.example.ghasdefender.security.JwtKeyBootstrap;
import io.jsonwebtoken.security.Keys;
import java.util.Base64;
import javax.crypto.SecretKey;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;

@Configuration
public class JwtConfig {

    @Bean
    @Profile("cloud")
    public SecretKey cloudJwtSigningKey(JwtKeyBootstrap jwtKeyBootstrap) {
        return hmacSigningKey(jwtKeyBootstrap.getOrCreateSigningKey());
    }

    @Bean
    @Profile("!cloud")
    public SecretKey localJwtSigningKey(@Value("${app.jwt.signing-key}") String signingKey) {
        return hmacSigningKey(signingKey);
    }

    private SecretKey hmacSigningKey(String base64SigningKey) {
        byte[] decodedKey = Base64.getDecoder().decode(base64SigningKey);
        if (decodedKey.length < 32) {
            throw new IllegalStateException("JWT signing key must decode to at least 32 bytes");
        }
        return Keys.hmacShaKeyFor(decodedKey);
    }
}
```

- [ ] **Step 4: Create `JwtKeyBootstrapTest.java`**

Write this full file:

```java
package com.example.ghasdefender.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.azure.core.exception.ResourceNotFoundException;
import com.azure.security.keyvault.secrets.SecretClient;
import com.azure.security.keyvault.secrets.models.KeyVaultSecret;
import java.security.SecureRandom;
import java.util.Base64;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

class JwtKeyBootstrapTest {

    @Test
    void returnsExistingSecretWithoutWritingANewVersion() {
        SecretClient secretClient = org.mockito.Mockito.mock(SecretClient.class);
        String existingKey = Base64.getEncoder().encodeToString("0123456789abcdef0123456789abcdef".getBytes());
        when(secretClient.getSecret(JwtKeyBootstrap.SECRET_NAME))
                .thenReturn(new KeyVaultSecret(JwtKeyBootstrap.SECRET_NAME, existingKey));

        JwtKeyBootstrap bootstrap = new JwtKeyBootstrap(secretClient, new SecureRandom(new byte[] {1, 2, 3, 4}));

        String actualKey = bootstrap.getOrCreateSigningKey();

        assertThat(actualKey).isEqualTo(existingKey);
        verify(secretClient, never()).setSecret(any(KeyVaultSecret.class));
    }

    @Test
    void createsSecretWhenItIsAbsent() {
        SecretClient secretClient = org.mockito.Mockito.mock(SecretClient.class);
        when(secretClient.getSecret(JwtKeyBootstrap.SECRET_NAME))
                .thenThrow(new ResourceNotFoundException("missing secret", null));
        when(secretClient.setSecret(any(KeyVaultSecret.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        JwtKeyBootstrap bootstrap = new JwtKeyBootstrap(secretClient, new SecureRandom(new byte[] {5, 6, 7, 8}));

        String generatedKey = bootstrap.getOrCreateSigningKey();

        byte[] decodedKey = Base64.getDecoder().decode(generatedKey);
        assertThat(decodedKey).hasSize(32);

        ArgumentCaptor<KeyVaultSecret> captor = ArgumentCaptor.forClass(KeyVaultSecret.class);
        verify(secretClient).setSecret(captor.capture());
        assertThat(captor.getValue().getName()).isEqualTo(JwtKeyBootstrap.SECRET_NAME);
        assertThat(captor.getValue().getValue()).isEqualTo(generatedKey);
    }
}
```

- [ ] **Step 5: Run the focused unit test**

Run:

```bash
./mvnw -f src/backend/pom.xml -Dtest=JwtKeyBootstrapTest test
```

Expected output ending:

```text
[INFO] Tests run: 2, Failures: 0, Errors: 0, Skipped: 0
[INFO] BUILD SUCCESS
```

- [ ] **Step 6: Run full backend verification**

Run:

```bash
./mvnw -f src/backend/pom.xml verify
```

Expected output ending:

```text
[INFO] BUILD SUCCESS
```

- [ ] **Step 7: Commit Key Vault and JWT changes**

Run:

```bash
git add src/backend/src/main/resources/application-cloud.yml src/backend/src/main/java/com/example/ghasdefender/security/JwtKeyBootstrap.java src/backend/src/main/java/com/example/ghasdefender/config/JwtConfig.java src/backend/src/test/java/com/example/ghasdefender/security/JwtKeyBootstrapTest.java
git commit -m "feat: bootstrap jwt signing key from key vault" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

Expected output:

```text
[main 3456cde] feat: bootstrap jwt signing key from key vault
 4 files changed
```

## Task 4: Add Kubernetes Manifests

**Files:**
- Create: `src/backend/k8s/namespace.yaml`
- Create: `src/backend/k8s/serviceaccount.tmpl.yaml`
- Create: `src/backend/k8s/service.yaml`
- Create: `src/backend/k8s/ingress.yaml`
- Create: `src/backend/k8s/deployment.tmpl.yaml`
- Create: `src/backend/k8s/flyway-job.tmpl.yaml`

- [ ] **Step 1: Create `namespace.yaml`**

Write this full file:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: app
  labels:
    app.kubernetes.io/part-of: ghas-defender-example
```

- [ ] **Step 2: Validate `namespace.yaml`**

Run:

```bash
kubectl --dry-run=client apply -f src/backend/k8s/namespace.yaml
```

Expected output:

```text
namespace/app created (dry run)
```

- [ ] **Step 3: Create `serviceaccount.tmpl.yaml`**

Write this full file:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backend
  namespace: app
  labels:
    app.kubernetes.io/name: backend
    app.kubernetes.io/part-of: ghas-defender-example
    azure.workload.identity/use: "true"
  annotations:
    azure.workload.identity/client-id: "{{ .Env.AZURE_BACKEND_IDENTITY_CLIENT_ID }}"
```

- [ ] **Step 4: Validate `serviceaccount.tmpl.yaml`**

Run:

```bash
kubectl --dry-run=client apply -f src/backend/k8s/serviceaccount.tmpl.yaml
```

Expected output:

```text
serviceaccount/backend created (dry run)
```

- [ ] **Step 5: Create `service.yaml`**

Write this full file:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend
  namespace: app
  labels:
    app.kubernetes.io/name: backend
    app.kubernetes.io/part-of: ghas-defender-example
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: backend
  ports:
    - name: http
      port: 80
      targetPort: 8080
```

- [ ] **Step 6: Validate `service.yaml`**

Run:

```bash
kubectl --dry-run=client apply -f src/backend/k8s/service.yaml
```

Expected output:

```text
service/backend created (dry run)
```

- [ ] **Step 7: Create `ingress.yaml`**

Write this full file:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: backend
  namespace: app
  labels:
    app.kubernetes.io/name: backend
    app.kubernetes.io/part-of: ghas-defender-example
  annotations:
    kubernetes.azure.com/ingress.class: webapprouting.kubernetes.azure.com
spec:
  ingressClassName: webapprouting.kubernetes.azure.com
  rules:
    - http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: backend
                port:
                  number: 80
```

- [ ] **Step 8: Validate `ingress.yaml`**

Run:

```bash
kubectl --dry-run=client apply -f src/backend/k8s/ingress.yaml
```

Expected output:

```text
ingress.networking.k8s.io/backend created (dry run)
```

- [ ] **Step 9: Create `deployment.tmpl.yaml`**

Write this full file:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: app
  labels:
    app.kubernetes.io/name: backend
    app.kubernetes.io/part-of: ghas-defender-example
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: backend
  template:
    metadata:
      labels:
        app.kubernetes.io/name: backend
        app.kubernetes.io/part-of: ghas-defender-example
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: backend
      containers:
        - name: backend
          image: "{{ .Env.SERVICE_BACKEND_IMAGE_NAME }}"
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 8080
          env:
            - name: SPRING_PROFILES_ACTIVE
              value: cloud
            - name: POSTGRES_HOST
              value: "{{ .Env.AZURE_POSTGRES_HOST }}"
            - name: POSTGRES_DATABASE
              value: appdb
            - name: POSTGRES_USERNAME
              value: app
            - name: AZURE_KEY_VAULT_URI
              value: "{{ .Env.AZURE_KEY_VAULT_URI }}"
            - name: CORS_ALLOWED_ORIGINS
              value: "https://{{ .Env.AZURE_STATIC_WEB_APP_HOSTNAME }}"
          readinessProbe:
            httpGet:
              path: /actuator/health/readiness
              port: 8080
            initialDelaySeconds: 20
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 6
          livenessProbe:
            httpGet:
              path: /actuator/health/liveness
              port: 8080
            initialDelaySeconds: 60
            periodSeconds: 20
            timeoutSeconds: 3
            failureThreshold: 3
          resources:
            requests:
              cpu: 200m
              memory: 512Mi
            limits:
              cpu: 500m
              memory: 1Gi
```

- [ ] **Step 10: Validate `deployment.tmpl.yaml`**

Run:

```bash
kubectl --dry-run=client apply -f src/backend/k8s/deployment.tmpl.yaml
```

Expected output:

```text
deployment.apps/backend created (dry run)
```

- [ ] **Step 11: Create `flyway-job.tmpl.yaml`**

Write this full file:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: flyway-init
  namespace: app
  labels:
    app.kubernetes.io/name: flyway-init
    app.kubernetes.io/part-of: ghas-defender-example
spec:
  backoffLimit: 3
  ttlSecondsAfterFinished: 86400
  template:
    metadata:
      labels:
        app.kubernetes.io/name: flyway-init
        app.kubernetes.io/part-of: ghas-defender-example
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: backend
      restartPolicy: OnFailure
      containers:
        - name: flyway
          image: "{{ .Env.SERVICE_BACKEND_IMAGE_NAME }}"
          imagePullPolicy: IfNotPresent
          command:
            - java
          args:
            - -jar
            - /app/app.jar
            - --spring.main.web-application-type=none
            - --spring.flyway.enabled=true
            - --spring.jpa.hibernate.ddl-auto=none
          env:
            - name: SPRING_PROFILES_ACTIVE
              value: cloud
            - name: POSTGRES_HOST
              value: "{{ .Env.AZURE_POSTGRES_HOST }}"
            - name: POSTGRES_DATABASE
              value: appdb
            - name: POSTGRES_USERNAME
              value: app
            - name: AZURE_KEY_VAULT_URI
              value: "{{ .Env.AZURE_KEY_VAULT_URI }}"
            - name: CORS_ALLOWED_ORIGINS
              value: "https://{{ .Env.AZURE_STATIC_WEB_APP_HOSTNAME }}"
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
```

- [ ] **Step 12: Validate `flyway-job.tmpl.yaml`**

Run:

```bash
kubectl --dry-run=client apply -f src/backend/k8s/flyway-job.tmpl.yaml
```

Expected output:

```text
job.batch/flyway-init created (dry run)
```

- [ ] **Step 13: Commit Kubernetes manifests**

Run:

```bash
git add src/backend/k8s/namespace.yaml src/backend/k8s/serviceaccount.tmpl.yaml src/backend/k8s/service.yaml src/backend/k8s/ingress.yaml src/backend/k8s/deployment.tmpl.yaml src/backend/k8s/flyway-job.tmpl.yaml
git commit -m "feat: add aks workload identity manifests" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

Expected output:

```text
[main 4567def] feat: add aks workload identity manifests
 6 files changed
```

## Task 5: Configure azd Services and Deployment Hooks

**Files:**
- Modify: `azure.yaml`
- Modify: `scripts/azd-hooks/postprovision.sh`
- Modify: `scripts/azd-hooks/postprovision.ps1`
- Create: `scripts/azd-hooks/predeploy-backend.sh`
- Create: `scripts/azd-hooks/predeploy-backend.ps1`

- [ ] **Step 1: Replace `azure.yaml`**

Write this full file:

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
    k8s:
      deploymentPath: k8s
      namespace: app
      deployment:
        name: backend
      service:
        name: backend
      ingress:
        name: backend
        relativePath: /api
    hooks:
      predeploy:
        posix:
          shell: sh
          run: ./scripts/azd-hooks/predeploy-backend.sh
        windows:
          shell: pwsh
          run: ./scripts/azd-hooks/predeploy-backend.ps1
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

- [ ] **Step 2: Create or replace `postprovision.sh`**

Write this full file and set executable permissions in Step 4:

```sh
#!/usr/bin/env sh
set -eu

require_env() {
  name="$1"
  eval "value=\${$name:-}"
  if [ -z "$value" ]; then
    echo "Missing required environment variable: $name" >&2
    exit 1
  fi
}

render_template() {
  template_path="$1"
  python3 - "$template_path" <<'PY'
import os
import re
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    text = handle.read()

pattern = re.compile(r"\{\{\s*\.Env\.([A-Za-z_][A-Za-z0-9_]*)\s*\}\}")

def replace(match):
    name = match.group(1)
    value = os.environ.get(name)
    if value is None or value == "":
        raise SystemExit(f"Missing required environment variable while rendering {path}: {name}")
    return value

print(pattern.sub(replace, text), end="")
PY
}

require_env AZURE_RESOURCE_GROUP
require_env AZURE_AKS_CLUSTER_NAME
require_env AZURE_BACKEND_IDENTITY_CLIENT_ID
require_env AZURE_STATIC_WEB_APP_NAME

az aks get-credentials \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --name "$AZURE_AKS_CLUSTER_NAME" \
  --overwrite-existing

kubectl apply -f src/backend/k8s/namespace.yaml
render_template src/backend/k8s/serviceaccount.tmpl.yaml | kubectl apply -f -
kubectl apply -f src/backend/k8s/service.yaml
kubectl apply -f src/backend/k8s/ingress.yaml

SWA_HOSTNAME="$(az staticwebapp show \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --name "$AZURE_STATIC_WEB_APP_NAME" \
  --query defaultHostname \
  --output tsv)"

if [ -z "$SWA_HOSTNAME" ]; then
  echo "Static Web Apps default hostname was empty" >&2
  exit 1
fi

azd env set AZURE_STATIC_WEB_APP_HOSTNAME "$SWA_HOSTNAME"

INGRESS_IP=""
ATTEMPTS=60
while [ "$ATTEMPTS" -gt 0 ]; do
  INGRESS_IP="$(kubectl get ingress backend -n app -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  if [ -n "$INGRESS_IP" ]; then
    break
  fi
  ATTEMPTS=$((ATTEMPTS - 1))
  sleep 5
done

if [ -z "$INGRESS_IP" ]; then
  echo "Ingress IP was not assigned within 5 minutes" >&2
  kubectl get ingress backend -n app -o wide || true
  exit 1
fi

azd env set AZURE_BACKEND_INGRESS_IP "$INGRESS_IP"
azd env set AZURE_BACKEND_INGRESS_HOSTNAME "${INGRESS_IP}.nip.io"
azd env set VITE_API_BASE_URL "http://${INGRESS_IP}.nip.io/api"

echo "Configured VITE_API_BASE_URL=http://${INGRESS_IP}.nip.io/api"
echo "Configured AZURE_STATIC_WEB_APP_HOSTNAME=$SWA_HOSTNAME"
```

- [ ] **Step 3: Create or replace `postprovision.ps1`**

Write this full file:

```powershell
$ErrorActionPreference = "Stop"

function Require-Env([string] $Name) {
    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Missing required environment variable: $Name"
    }
}

function Expand-AzdTemplate([string] $Path) {
    $text = Get-Content -Path $Path -Raw
    return [regex]::Replace($text, '\{\{\s*\.Env\.([A-Za-z_][A-Za-z0-9_]*)\s*\}\}', {
        param($match)
        $name = $match.Groups[1].Value
        $value = [Environment]::GetEnvironmentVariable($name)
        if ([string]::IsNullOrWhiteSpace($value)) {
            throw "Missing required environment variable while rendering ${Path}: $name"
        }
        return $value
    })
}

Require-Env "AZURE_RESOURCE_GROUP"
Require-Env "AZURE_AKS_CLUSTER_NAME"
Require-Env "AZURE_BACKEND_IDENTITY_CLIENT_ID"
Require-Env "AZURE_STATIC_WEB_APP_NAME"

az aks get-credentials `
    --resource-group $env:AZURE_RESOURCE_GROUP `
    --name $env:AZURE_AKS_CLUSTER_NAME `
    --overwrite-existing

kubectl apply -f src/backend/k8s/namespace.yaml
Expand-AzdTemplate "src/backend/k8s/serviceaccount.tmpl.yaml" | kubectl apply -f -
kubectl apply -f src/backend/k8s/service.yaml
kubectl apply -f src/backend/k8s/ingress.yaml

$swaHostname = az staticwebapp show `
    --resource-group $env:AZURE_RESOURCE_GROUP `
    --name $env:AZURE_STATIC_WEB_APP_NAME `
    --query defaultHostname `
    --output tsv

if ([string]::IsNullOrWhiteSpace($swaHostname)) {
    throw "Static Web Apps default hostname was empty"
}

azd env set AZURE_STATIC_WEB_APP_HOSTNAME $swaHostname

$ingressIp = ""
for ($attempt = 0; $attempt -lt 60; $attempt++) {
    $ingressIp = kubectl get ingress backend -n app -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
    if (-not [string]::IsNullOrWhiteSpace($ingressIp)) {
        break
    }
    Start-Sleep -Seconds 5
}

if ([string]::IsNullOrWhiteSpace($ingressIp)) {
    kubectl get ingress backend -n app -o wide
    throw "Ingress IP was not assigned within 5 minutes"
}

azd env set AZURE_BACKEND_INGRESS_IP $ingressIp
azd env set AZURE_BACKEND_INGRESS_HOSTNAME "$ingressIp.nip.io"
azd env set VITE_API_BASE_URL "http://$ingressIp.nip.io/api"

Write-Host "Configured VITE_API_BASE_URL=http://$ingressIp.nip.io/api"
Write-Host "Configured AZURE_STATIC_WEB_APP_HOSTNAME=$swaHostname"
```

- [ ] **Step 4: Create `predeploy-backend.sh`**

Write this full file:

```sh
#!/usr/bin/env sh
set -eu

require_env() {
  name="$1"
  eval "value=\${$name:-}"
  if [ -z "$value" ]; then
    echo "Missing required environment variable: $name" >&2
    exit 1
  fi
}

render_template() {
  template_path="$1"
  python3 - "$template_path" <<'PY'
import os
import re
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    text = handle.read()

pattern = re.compile(r"\{\{\s*\.Env\.([A-Za-z_][A-Za-z0-9_]*)\s*\}\}")

def replace(match):
    name = match.group(1)
    value = os.environ.get(name)
    if value is None or value == "":
        raise SystemExit(f"Missing required environment variable while rendering {path}: {name}")
    return value

print(pattern.sub(replace, text), end="")
PY
}

require_env AZURE_RESOURCE_GROUP
require_env AZURE_AKS_CLUSTER_NAME
require_env AZURE_BACKEND_IDENTITY_CLIENT_ID
require_env AZURE_POSTGRES_HOST
require_env AZURE_KEY_VAULT_URI
require_env AZURE_STATIC_WEB_APP_HOSTNAME
require_env SERVICE_BACKEND_IMAGE_NAME

az aks get-credentials \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --name "$AZURE_AKS_CLUSTER_NAME" \
  --overwrite-existing

kubectl apply -f src/backend/k8s/namespace.yaml
render_template src/backend/k8s/serviceaccount.tmpl.yaml | kubectl apply -f -
kubectl apply -f src/backend/k8s/service.yaml
kubectl apply -f src/backend/k8s/ingress.yaml

if kubectl get job flyway-init -n app >/dev/null 2>&1; then
  kubectl delete job flyway-init -n app --wait=true
fi

render_template src/backend/k8s/flyway-job.tmpl.yaml | kubectl apply -f -

if ! kubectl wait --for=condition=complete job/flyway-init -n app --timeout=300s; then
  kubectl logs job/flyway-init -n app --all-containers=true || true
  exit 1
fi

kubectl logs job/flyway-init -n app --all-containers=true || true
```

- [ ] **Step 5: Create `predeploy-backend.ps1`**

Write this full file:

```powershell
$ErrorActionPreference = "Stop"

function Require-Env([string] $Name) {
    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Missing required environment variable: $Name"
    }
}

function Expand-AzdTemplate([string] $Path) {
    $text = Get-Content -Path $Path -Raw
    return [regex]::Replace($text, '\{\{\s*\.Env\.([A-Za-z_][A-Za-z0-9_]*)\s*\}\}', {
        param($match)
        $name = $match.Groups[1].Value
        $value = [Environment]::GetEnvironmentVariable($name)
        if ([string]::IsNullOrWhiteSpace($value)) {
            throw "Missing required environment variable while rendering ${Path}: $name"
        }
        return $value
    })
}

Require-Env "AZURE_RESOURCE_GROUP"
Require-Env "AZURE_AKS_CLUSTER_NAME"
Require-Env "AZURE_BACKEND_IDENTITY_CLIENT_ID"
Require-Env "AZURE_POSTGRES_HOST"
Require-Env "AZURE_KEY_VAULT_URI"
Require-Env "AZURE_STATIC_WEB_APP_HOSTNAME"
Require-Env "SERVICE_BACKEND_IMAGE_NAME"

az aks get-credentials `
    --resource-group $env:AZURE_RESOURCE_GROUP `
    --name $env:AZURE_AKS_CLUSTER_NAME `
    --overwrite-existing

kubectl apply -f src/backend/k8s/namespace.yaml
Expand-AzdTemplate "src/backend/k8s/serviceaccount.tmpl.yaml" | kubectl apply -f -
kubectl apply -f src/backend/k8s/service.yaml
kubectl apply -f src/backend/k8s/ingress.yaml

$existingJob = kubectl get job flyway-init -n app --ignore-not-found
if (-not [string]::IsNullOrWhiteSpace($existingJob)) {
    kubectl delete job flyway-init -n app --wait=true
}

Expand-AzdTemplate "src/backend/k8s/flyway-job.tmpl.yaml" | kubectl apply -f -

kubectl wait --for=condition=complete job/flyway-init -n app --timeout=300s
if ($LASTEXITCODE -ne 0) {
    kubectl logs job/flyway-init -n app --all-containers=true
    exit 1
}

kubectl logs job/flyway-init -n app --all-containers=true
```

- [ ] **Step 6: Set POSIX hook scripts executable**

Run:

```bash
chmod +x scripts/azd-hooks/postprovision.sh scripts/azd-hooks/predeploy-backend.sh
```

Expected output: no output.

- [ ] **Step 7: Validate YAML syntax for `azure.yaml`**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
import yaml
for path in [Path('azure.yaml')]:
    yaml.safe_load(path.read_text())
    print(f'{path}: ok')
PY
```

Expected output:

```text
azure.yaml: ok
```

- [ ] **Step 8: Validate shell syntax**

Run:

```bash
sh -n scripts/azd-hooks/postprovision.sh
sh -n scripts/azd-hooks/predeploy-backend.sh
```

Expected output: no output.

- [ ] **Step 9: Commit azd service and hook configuration**

Run:

```bash
git add azure.yaml scripts/azd-hooks/postprovision.sh scripts/azd-hooks/postprovision.ps1 scripts/azd-hooks/predeploy-backend.sh scripts/azd-hooks/predeploy-backend.ps1
git commit -m "feat: configure azd aks and swa deploys" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

Expected output:

```text
[main 5678ef0] feat: configure azd aks and swa deploys
 5 files changed
```

## Task 6: Deploy and Verify Backend on AKS

**Files:** None.

- [ ] **Step 1: Provision or refresh the demo environment**

Run:

```bash
azd provision --no-prompt
```

Expected output includes:

```text
SUCCESS: Your application was provisioned in Azure
```

- [ ] **Step 2: Confirm postprovision captured frontend and ingress values**

Run:

```bash
azd env get-values | grep -E '^(AZURE_STATIC_WEB_APP_HOSTNAME|AZURE_BACKEND_INGRESS_IP|AZURE_BACKEND_INGRESS_HOSTNAME|VITE_API_BASE_URL)='
```

Expected output shape:

```text
AZURE_BACKEND_INGRESS_HOSTNAME="20.31.42.55.nip.io"
AZURE_BACKEND_INGRESS_IP="20.31.42.55"
AZURE_STATIC_WEB_APP_HOSTNAME="purple-coast-012345678.4.azurestaticapps.net"
VITE_API_BASE_URL="http://20.31.42.55.nip.io/api"
```

- [ ] **Step 3: Deploy the backend service**

Run:

```bash
azd deploy backend --no-prompt
```

Expected output includes:

```text
Packaging services (azd package)
  (✓) Done: Packaging service backend

Publishing services (azd publish)
  (✓) Done: Publishing service backend

Running service hooks (azd deploy backend predeploy)
job.batch/flyway-init condition met

Deploying services (azd deploy)
  (✓) Done: Deploying service backend
```

- [ ] **Step 4: Verify rollout status**

Run:

```bash
kubectl rollout status deployment/backend -n app --timeout=300s
```

Expected output:

```text
deployment "backend" successfully rolled out
```

- [ ] **Step 5: Verify Workload Identity labels and annotations**

Run:

```bash
kubectl get serviceaccount backend -n app -o jsonpath='{.metadata.annotations.azure\.workload\.identity/client-id}{"\n"}{.metadata.labels.azure\.workload\.identity/use}{"\n"}'
kubectl get pod -n app -l app.kubernetes.io/name=backend -o jsonpath='{.items[0].metadata.labels.azure\.workload\.identity/use}{"\n"}{.items[0].spec.serviceAccountName}{"\n"}'
```

Expected output shape:

```text
00000000-0000-0000-0000-000000000000
true
true
backend
```

- [ ] **Step 6: Verify Flyway completed**

Run:

```bash
kubectl get job flyway-init -n app
kubectl logs job/flyway-init -n app --all-containers=true | tail -20
```

Expected output includes:

```text
NAME          STATUS     COMPLETIONS   DURATION   AGE
flyway-init   Complete   1/1
Successfully applied
```

- [ ] **Step 7: Verify backend health through ingress**

Run:

```bash
INGRESS_HOSTNAME=$(azd env get-value AZURE_BACKEND_INGRESS_HOSTNAME)
curl -i "http://${INGRESS_HOSTNAME}/actuator/health"
```

Expected output:

```text
HTTP/1.1 200 OK

{"status":"UP"}
```

- [ ] **Step 8: Verify `/api/items` returns seeded data**

Run:

```bash
INGRESS_HOSTNAME=$(azd env get-value AZURE_BACKEND_INGRESS_HOSTNAME)
curl -s "http://${INGRESS_HOSTNAME}/api/items" | jq 'length > 0 and all(.[]; has("id") and has("name"))'
```

Expected output:

```text
true
```

- [ ] **Step 9: Commit backend deploy verification adjustments if any were needed**

If no files changed, skip this commit. If hook or manifest fixes were required, run:

```bash
git add azure.yaml scripts/azd-hooks src/backend/k8s src/backend/src/main/resources/application-cloud.yml src/backend/src/main/java/com/example/ghasdefender
git commit -m "fix: stabilize backend aks deployment" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

Expected output when a fix was committed:

```text
[main 6789f01] fix: stabilize backend aks deployment
```

## Task 7: Configure Frontend CSP and Deploy Static Web App

**Files:**
- Modify: `src/frontend/staticwebapp.config.json`

- [ ] **Step 1: Replace `staticwebapp.config.json`**

Write this full file:

```json
{
  "globalHeaders": {
    "Content-Security-Policy": "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:; connect-src 'self' http://*.nip.io https://*.nip.io; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'"
  },
  "navigationFallback": {
    "rewrite": "/index.html",
    "exclude": ["/assets/*", "/api/*"]
  },
  "routes": [
    {
      "route": "/assets/*",
      "headers": {
        "Cache-Control": "public, max-age=31536000, immutable"
      }
    }
  ]
}
```

- [ ] **Step 2: Validate JSON syntax**

Run:

```bash
python3 -m json.tool src/frontend/staticwebapp.config.json >/dev/null
```

Expected output: no output.

- [ ] **Step 3: Run frontend tests and build**

Run:

```bash
npm --prefix src/frontend ci
npm --prefix src/frontend test
npm --prefix src/frontend run build
```

Expected output includes:

```text
added
Test Files  passed
✓ built in
```

- [ ] **Step 4: Deploy the frontend service**

Run:

```bash
azd deploy frontend --no-prompt
```

Expected output includes:

```text
Deploying services (azd deploy)
  (✓) Done: Deploying service frontend
```

- [ ] **Step 5: Verify SWA serves the app**

Run:

```bash
SWA_HOSTNAME=$(azd env get-value AZURE_STATIC_WEB_APP_HOSTNAME)
curl -I "https://${SWA_HOSTNAME}"
```

Expected output includes:

```text
HTTP/2 200
content-type: text/html
```

- [ ] **Step 6: Verify the built frontend points to the backend API**

Run:

```bash
API_BASE_URL=$(azd env get-value VITE_API_BASE_URL)
echo "$API_BASE_URL"
```

Expected output shape:

```text
http://20.31.42.55.nip.io/api
```

Then open `https://$SWA_HOSTNAME` in a browser, open DevTools Network and Console tabs, refresh, and confirm:

```text
GET http://20.31.42.55.nip.io/api/items 200 OK
No Content-Security-Policy violation messages are logged.
```

- [ ] **Step 7: Commit frontend CSP change**

Run:

```bash
git add src/frontend/staticwebapp.config.json
git commit -m "feat: allow backend ingress in swa csp" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

Expected output:

```text
[main 7890f12] feat: allow backend ingress in swa csp
 1 file changed
```

## Task 8: Fresh `azd up` End-to-End Validation

**Files:** None unless validation exposes a defect in files from earlier tasks.

- [ ] **Step 1: Tear down the demo environment**

Run only when the subscription is safe to reset:

```bash
azd down --purge --force --no-prompt
```

Expected output includes:

```text
SUCCESS: Your application was removed from Azure
```

- [ ] **Step 2: Recreate and deploy the whole stack**

Run:

```bash
azd up --no-prompt
```

Expected output includes these phases in order:

```text
SUCCESS: Your application was provisioned in Azure
Configured VITE_API_BASE_URL=http://20.31.42.55.nip.io/api
job.batch/flyway-init condition met
SUCCESS: Your application was deployed to Azure
```

- [ ] **Step 3: Verify backend API after fresh deploy**

Run:

```bash
INGRESS_HOSTNAME=$(azd env get-value AZURE_BACKEND_INGRESS_HOSTNAME)
curl -s "http://${INGRESS_HOSTNAME}/api/items" | jq 'length > 0 and all(.[]; has("id") and has("name"))'
```

Expected output:

```text
true
```

- [ ] **Step 4: Verify frontend after fresh deploy**

Run:

```bash
SWA_HOSTNAME=$(azd env get-value AZURE_STATIC_WEB_APP_HOSTNAME)
curl -I "https://${SWA_HOSTNAME}"
```

Expected output includes:

```text
HTTP/2 200
```

- [ ] **Step 5: Verify no files were accidentally changed by hooks**

Run:

```bash
git --no-pager status --short
```

Expected output: no output.

- [ ] **Step 6: Commit validation fixes if any were required**

If no files changed, skip this commit. If a fix was required, run:

```bash
git add azure.yaml scripts/azd-hooks src/backend src/frontend/staticwebapp.config.json
git commit -m "fix: complete azd end-to-end deployment" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

Expected output when a fix was committed:

```text
[main 8901f23] fix: complete azd end-to-end deployment
```

## Cross-Plan Contracts for Later Plans

- Plan 6 workflows must call `azd deploy backend --no-prompt` and `azd deploy frontend --no-prompt`; they must not add custom Docker push, Kubernetes image patching, or container scanning steps.
- Plan 6 OIDC auth must provide the same azd env values used locally and must let azd hooks run unchanged.
- Plan 7's `vulnerable` branch should modify only the Dockerfile security baseline for the container demo: switch runtime base image to a larger JDK image, run as root, remove `HEALTHCHECK`, and copy an overly broad build context. It must not change Workload Identity, Key Vault, azd hooks, or the clean `main` behavior.
- Plan 8 documentation should describe the `VITE_API_BASE_URL` value with a concrete example such as `http://20.31.42.55.nip.io/api` and explain that the hostless ingress rule accepts the `nip.io` hostname.

## Open Questions Appendix

None remain open for Plan 5. The azd behavior that looked ambiguous is resolved above: use `.tmpl.yaml` files for rendered manifests, set `k8s.deploymentPath: k8s`, omit image-patching hooks, and use backend `predeploy` only for Flyway.

## Self-Review Checklist

- Spec coverage: backend container, AKS manifests, Workload Identity, Key Vault secret resolution, Flyway, frontend SWA deploy, CSP, and azd hooks are covered by Tasks 1-8.
- Scope boundaries: no GitHub Actions YAML, no seeded vulnerabilities, no demo walkthrough, and no GitOps tooling are included.
- Template scan: the plan contains concrete file contents, exact commands, and expected outputs. The only templating syntax is executable azd manifest syntax.
- Type consistency: `JwtKeyBootstrap.SECRET_NAME`, `JwtConfig` bean names, k8s resource names, azd env names, and hook script paths match across tasks.
