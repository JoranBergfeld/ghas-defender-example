# SEEDED VULN #6 — see scripts/seed-vulnerabilities.md
FROM eclipse-temurin:21-jdk

WORKDIR /app
COPY . .
RUN ./mvnw -B -DskipTests package

USER root
ENTRYPOINT ["java", "-jar", "target/ghas-defender-backend.jar"]
