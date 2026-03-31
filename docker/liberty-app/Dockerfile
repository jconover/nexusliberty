# =============================================================================
# Stage 1 — Maven build
# Build context: repo root (docker build -f docker/liberty-app/Dockerfile .)
# =============================================================================
FROM maven:3.9-eclipse-temurin-17 AS build

WORKDIR /build

# Copy POM first for layer caching
COPY app/pom.xml ./pom.xml

# Download dependencies in a separate layer
RUN mvn dependency:go-offline -B

# Copy source and build
COPY app/src ./src
RUN mvn clean package -B

# =============================================================================
# Stage 2 — Open Liberty runtime
# =============================================================================
FROM icr.io/appcafe/open-liberty:kernel-slim-java17-openj9-ubi AS runtime

# Copy server configuration
COPY --chown=1001:0 docker/liberty-app/server.xml /config/server.xml

# Copy Hazelcast session cache config
COPY --chown=1001:0 docker/liberty-app/hazelcast.xml /config/hazelcast.xml

# Install only the Liberty features declared in server.xml
RUN features.sh

# Download Hazelcast JARs for JCache session replication
ARG HAZELCAST_VERSION=5.3.6
RUN mkdir -p /opt/ol/wlp/usr/shared/resources/hazelcast && \
    curl -fsSL -o /opt/ol/wlp/usr/shared/resources/hazelcast/hazelcast-${HAZELCAST_VERSION}.jar \
      "https://repo1.maven.org/maven2/com/hazelcast/hazelcast/${HAZELCAST_VERSION}/hazelcast-${HAZELCAST_VERSION}.jar" && \
    curl -fsSL -o /opt/ol/wlp/usr/shared/resources/hazelcast/hazelcast-kubernetes-2.2.3.jar \
      "https://repo1.maven.org/maven2/com/hazelcast/hazelcast-kubernetes/2.2.3/hazelcast-kubernetes-2.2.3.jar"

# Copy the application WAR from the build stage
COPY --chown=1001:0 --from=build /build/target/nexus-app.war /config/apps/nexus-app.war

# Finalize and optimize the image (sets up keystore, validates config, etc.)
RUN configure.sh

# Open Liberty runs as non-root by default (uid 1001 / group root)
HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
    CMD curl -f http://localhost:9080/health/ready || exit 1

EXPOSE 9080 9443
