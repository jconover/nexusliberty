# NexusLiberty Application

Jakarta EE 10 / MicroProfile 6.1 application running on Open Liberty, demonstrating enterprise middleware patterns for the NexusLiberty modernization platform.

## Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /app/api/health` | Application health status (app name, version) |
| `GET /app/api/info` | Runtime info (Java version, OS, runtime) |
| `GET /health/ready` | MicroProfile Readiness probe |
| `GET /health/live` | MicroProfile Liveness probe (deadlock detection) |
| `GET /metrics` | MicroProfile Metrics (Prometheus format) |
| `GET /openapi` | OpenAPI 3.0 specification |
| `GET /openapi/ui` | Swagger UI |

## Build

```bash
# Compile and package
mvn clean package

# Run integration tests (starts Liberty, runs REST Assured tests)
mvn verify
```

## Run Locally

```bash
# Development mode (hot reload)
mvn liberty:dev

# App available at http://localhost:9080/app/
```

## Run in Container

```bash
# Build from repo root (Dockerfile uses multi-stage build)
docker build -t nexusliberty-app:latest -f docker/liberty-app/Dockerfile .

# Run
docker run -p 9080:9080 -p 9443:9443 nexusliberty-app:latest
```

## Project Structure

```
app/
├── pom.xml                          # Maven build (Open Liberty runtime plugin)
└── src/
    ├── main/
    │   ├── java/io/devopsnexus/nexusapp/
    │   │   ├── NexusApplication.java    # JAX-RS root + OpenAPI definition
    │   │   ├── HealthResource.java      # /api/health
    │   │   ├── InfoResource.java        # /api/info
    │   │   ├── LivenessCheck.java       # MP Health liveness (deadlock check)
    │   │   └── ReadinessCheck.java      # MP Health readiness
    │   ├── resources/META-INF/
    │   │   └── microprofile-config.properties
    │   └── webapp/index.html
    └── test/
        ├── java/io/devopsnexus/nexusapp/
        │   └── EndpointIT.java          # REST Assured integration tests
        └── liberty/config/
            └── server.xml               # Lightweight test server config
```
