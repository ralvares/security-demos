# -----------------------------------------------------------------------------
# Stage 1: The Builder
# Standard Maven image. Podman will pull the specific architecture image 
# (amd64 or arm64) for each build thread automatically.
# -----------------------------------------------------------------------------
FROM docker.io/library/maven:3.8-openjdk-8 AS builder

WORKDIR /app

# Cache dependencies
COPY pom.xml .
RUN mvn dependency:go-offline

# Compile
COPY src ./src
RUN mvn package -DskipTests

# -----------------------------------------------------------------------------
# Stage 2: The Runtime
# -----------------------------------------------------------------------------
FROM registry.access.redhat.com/ubi8/openjdk-8-runtime:latest

WORKDIR /app

ENV exploit=false
USER 1001

# Copy the JAR from the builder stage
COPY --from=builder /app/target/gateway-1.0-jar-with-dependencies.jar /deployments/gateway-1.0-jar-with-dependencies.jar