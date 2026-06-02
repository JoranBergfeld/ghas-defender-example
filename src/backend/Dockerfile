# SEEDED VULN #6 — see scripts/seed-vulnerabilities.md
FROM eclipse-temurin:21-jdk

WORKDIR /app
COPY . .
RUN ./mvnw -B -DskipTests package && cp target/*.jar /app/app.jar

USER root
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
