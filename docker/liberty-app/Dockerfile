# =============================================================================
# Stage 1 — Maven build
# Build context: repo root (docker build -f docker/liberty-app/Dockerfile .)
# =============================================================================
FROM docker.io/library/maven:3.9-eclipse-temurin-17 AS build

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
FROM icr.io/appcafe/open-liberty:kernel-slim-java17-openj9-ubi-minimal AS runtime

# Copy server configuration
COPY --chown=1001:0 docker/liberty-app/server.xml /config/server.xml
COPY --chown=1001:0 docker/liberty-app/server.env /config/server.env

# Copy Hazelcast session cache config
COPY --chown=1001:0 docker/liberty-app/hazelcast.xml /config/hazelcast.xml

# features.sh is an Open Liberty base image script that reads server.xml,
# resolves the declared features (webProfile, microProfile, sessionCache),
# and installs only those features into the runtime — keeping the image minimal.
RUN features.sh

# Download Hazelcast JAR for JCache session replication.
# Hazelcast 5.x includes Kubernetes discovery built-in — no separate
# hazelcast-kubernetes plugin needed (that plugin is for Hazelcast 4.x).
ARG HAZELCAST_VERSION=5.3.6
# SHA256 checksums for integrity verification — update when changing HAZELCAST_VERSION.
# Obtain new checksums from: https://repo1.maven.org/maven2/com/hazelcast/hazelcast/<version>/
ARG HAZELCAST_SHA256=72d70778f79c656dae8b4b5361b39af177b48b5bd980984098ce1d5aa992bbec
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN mkdir -p /opt/ol/wlp/usr/shared/resources/hazelcast && \
    curl -fsSL -o /opt/ol/wlp/usr/shared/resources/hazelcast/hazelcast-${HAZELCAST_VERSION}.jar \
      "https://repo1.maven.org/maven2/com/hazelcast/hazelcast/${HAZELCAST_VERSION}/hazelcast-${HAZELCAST_VERSION}.jar" && \
    echo "${HAZELCAST_SHA256}  /opt/ol/wlp/usr/shared/resources/hazelcast/hazelcast-${HAZELCAST_VERSION}.jar" | sha256sum -c -

# Copy the application WAR from the build stage
COPY --chown=1001:0 --from=build /build/target/nexus-app.war /config/apps/nexus-app.war

# configure.sh is an Open Liberty base image script that validates server.xml,
# generates the default TLS keystore, and optimizes the server for container use.
RUN configure.sh

# Open Liberty runs as non-root by default (uid 1001 / group root)
HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
    CMD curl -f http://localhost:9080/health/ready || exit 1

EXPOSE 9080 9443
