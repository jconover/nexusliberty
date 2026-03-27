# Phase 2: Liberty Containerization + GHCR Deployment

Step-by-step guide to build a custom Open Liberty container image, push to GitHub Container Registry, and deploy to OKD via the Liberty Operator.

## Prerequisites

- Phase 1 complete (Liberty Operator installed and working)
- OKD cluster healthy (`oc get clusteroperators` — all AVAILABLE=True)
- `oc` CLI logged in
- Docker or Podman installed on your workstation
- GitHub account with GHCR access (`ghcr.io`)

## What We're Building

```
┌──────────────────────────────────────────────────────────┐
│  Multi-Stage Docker Build                                │
│                                                          │
│  Stage 1: maven:3.9-eclipse-temurin-17                   │
│    └─ Compiles app/src → nexus-app.war                   │
│                                                          │
│  Stage 2: open-liberty:kernel-slim-java17-openj9-ubi     │
│    ├─ Installs features from server.xml                  │
│    ├─ Copies nexus-app.war into /config/apps/            │
│    └─ Optimizes image with configure.sh                  │
└──────────────────────────────────────────────────────────┘
         │
         ▼
   ghcr.io/jconover/nexusliberty-app:latest
         │
         ▼
   WebSphereLibertyApplication CR → OKD Pod → Route
```

## Project Structure (Phase 2 files)

```
nexusliberty/
├── app/
│   ├── pom.xml                          # Jakarta EE 10 + MicroProfile 6.1
│   └── src/main/
│       ├── java/io/devopsnexus/nexusapp/
│       │   ├── NexusApplication.java    # JAX-RS @ApplicationPath("/api")
│       │   ├── HealthResource.java      # GET /api/health
│       │   ├── InfoResource.java        # GET /api/info
│       │   ├── LivenessCheck.java       # @Liveness  → /health/live
│       │   └── ReadinessCheck.java      # @Readiness → /health/ready
│       └── webapp/
│           └── index.html               # Landing page
├── docker/liberty-app/
│   ├── Dockerfile                       # Multi-stage build
│   └── server.xml                       # Liberty server config
├── .dockerignore
├── .github/workflows/
│   └── liberty-build.yml                # CI: build + push to GHCR
└── openshift/liberty-deployment/
    └── WebSphereLibertyApplication.yaml # Updated: points to GHCR image
```

## Step 1: Review the Application

The sample app is a Jakarta EE 10 / MicroProfile 6.1 application with two REST endpoints and MicroProfile Health beans.

**Endpoints:**
| Path | Source | Description |
|------|--------|-------------|
| `/app/` | `index.html` | Static landing page |
| `/app/api/health` | `HealthResource.java` | App health JSON |
| `/app/api/info` | `InfoResource.java` | App metadata JSON |
| `/health/ready` | `ReadinessCheck.java` | MicroProfile readiness (for K8s probes) |
| `/health/live` | `LivenessCheck.java` | MicroProfile liveness (for K8s probes) |

The MicroProfile Health endpoints (`/health/*`) are served at the server root by Liberty's `mpHealth` feature — they are separate from the app's own `/app/api/health` endpoint.

## Step 2: Build the Container Image Locally

From the repository root:

```bash
docker build -f docker/liberty-app/Dockerfile -t nexusliberty-app:latest .
```

The build context is the repo root (the Dockerfile references `app/pom.xml` and `app/src/`). The `.dockerignore` excludes non-build directories.

**First build takes ~5-10 minutes** (downloading Maven dependencies + Liberty features). Subsequent builds use Docker layer caching and are much faster.

Verify the image:
```bash
docker images | grep nexusliberty-app
```

## Step 3: Test Locally

```bash
docker run -d --name nexusliberty-test -p 9080:9080 nexusliberty-app:latest
```

Wait ~15-20 seconds for Liberty to start, then test:

```bash
# Landing page
curl http://localhost:9080/app/

# REST endpoints
curl http://localhost:9080/app/api/health
curl http://localhost:9080/app/api/info

# MicroProfile Health (what K8s probes hit)
curl http://localhost:9080/health/ready
curl http://localhost:9080/health/live
```

Expected responses:
```json
# /app/api/health
{"status":"UP","app":"NexusLiberty","version":"1.0.0"}

# /app/api/info
{"app":"NexusLiberty","description":"Enterprise Middleware Modernization Platform","version":"1.0.0","runtime":"IBM Semeru Runtime Open Edition","javaVersion":"17.0.x"}

# /health/ready
{"checks":[{"data":{},"name":"nexusliberty-readiness","status":"UP"}],"status":"UP"}
```

Clean up:
```bash
docker stop nexusliberty-test && docker rm nexusliberty-test
```

## Step 4: Push to GitHub Container Registry

### Authenticate to GHCR

```bash
# Create a PAT at https://github.com/settings/tokens with `write:packages` scope
echo $GITHUB_TOKEN | docker login ghcr.io -u jconover --password-stdin
```

### Tag and Push

```bash
docker tag nexusliberty-app:latest ghcr.io/jconover/nexusliberty-app:latest
docker push ghcr.io/jconover/nexusliberty-app:latest
```

### Make the Package Public (first time only)

1. Go to: https://github.com/users/jconover/packages/container/nexusliberty-app/settings
2. Under "Danger Zone" → Change visibility → **Public**

This is required so OKD can pull the image without an imagePullSecret. Alternatively, create a pull secret:
```bash
oc create secret docker-registry ghcr-pull-secret \
  --docker-server=ghcr.io \
  --docker-username=jconover \
  --docker-password=$GITHUB_TOKEN \
  -n liberty-apps

oc secrets link default ghcr-pull-secret --for=pull -n liberty-apps
```

## Step 5: Deploy to OKD

### Delete the Phase 1 Sample App (if still running)

```bash
oc delete WebSphereLibertyApplication nexusliberty-sample -n liberty-apps 2>/dev/null || true
```

### Apply the Updated CR

The `WebSphereLibertyApplication.yaml` now points to `ghcr.io/jconover/nexusliberty-app:latest` with resource limits for homelab sizing.

```bash
oc apply -f openshift/liberty-deployment/WebSphereLibertyApplication.yaml
```

Watch the pod start:
```bash
oc get pods -n liberty-apps -w
```

Wait for `1/1 Running`. First pull from GHCR may take 1-2 minutes.

**Troubleshooting image pull issues:**
```bash
# Check events for pull errors
oc get events -n liberty-apps --sort-by='.lastTimestamp' | grep -i pull

# If ErrImagePull — the package is likely still private
# Either make it public or add the pull secret (Step 4 above)
```

## Step 6: Verify the Route

```bash
oc get routes -n liberty-apps
```

Expected:
```
NAME               HOST/PORT                                                   SERVICES           PORT       TERMINATION
nexusliberty-app   nexusliberty-app-liberty-apps.apps.nexuslab.nexuslab.local   nexusliberty-app   9080-tcp   edge
```

**DNS:** Add to `/etc/hosts` if not using wildcard DNS:
```
192.168.68.101 nexusliberty-app-liberty-apps.apps.nexuslab.nexuslab.local
```

Test the deployed app:
```bash
# Landing page
curl -k https://nexusliberty-app-liberty-apps.apps.nexuslab.nexuslab.local/app/

# REST endpoints
curl -k https://nexusliberty-app-liberty-apps.apps.nexuslab.nexuslab.local/app/api/health
curl -k https://nexusliberty-app-liberty-apps.apps.nexuslab.nexuslab.local/app/api/info

# MicroProfile Health
curl -k https://nexusliberty-app-liberty-apps.apps.nexuslab.nexuslab.local/health/ready
curl -k https://nexusliberty-app-liberty-apps.apps.nexuslab.nexuslab.local/health/live
```

## Step 7: Validate Everything

```bash
echo "=== Liberty App CR ==="
oc get WebSphereLibertyApplication -n liberty-apps

echo ""
echo "=== Pods ==="
oc get pods -n liberty-apps

echo ""
echo "=== Pod Image ==="
oc get pods -n liberty-apps -o jsonpath='{.items[*].spec.containers[*].image}'
echo ""

echo ""
echo "=== Route ==="
oc get routes -n liberty-apps

echo ""
echo "=== Pod Logs (last 20 lines) ==="
oc logs deployment/nexusliberty-app -n liberty-apps --tail=20
```

Look for `CWWKF0011I: The nexusliberty-app server is ready to run a smarter planet` in the logs — that confirms Liberty started successfully.

## CI/CD: GitHub Actions

The workflow at `.github/workflows/liberty-build.yml` automatically builds and pushes to GHCR on every push to `main` that touches `docker/liberty-app/**` or `app/**`.

**What it does:**
1. Checks out the repo
2. Authenticates to GHCR via `GITHUB_TOKEN`
3. Generates image tags (git SHA, branch name, `latest`)
4. Builds using the multi-stage Dockerfile
5. Pushes to `ghcr.io/jconover/nexusliberty-app`

**To trigger a new build:** merge your feature branch to `main`.

**To update the running pod after CI pushes a new image:**
```bash
# Restart the deployment to pull the latest image
oc rollout restart deployment/nexusliberty-app -n liberty-apps
oc rollout status deployment/nexusliberty-app -n liberty-apps
```

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Open Liberty (not WebSphere Liberty) | No license required for portfolio work; functionally equivalent |
| `kernel-slim` base image | Only installs features declared in server.xml — smaller image |
| `webProfile-10.0` + `microProfile-6.1` | Umbrella features avoid conflicts; correct pairing for Jakarta EE 10 |
| Edge TLS termination | OKD Router handles TLS; pod serves plain HTTP on 9080 — simpler cert management |
| Multi-stage build | Build tools stay out of the runtime image; smaller attack surface |
| Resource limits (200m-500m CPU, 256-512Mi RAM) | Sized for 3-node homelab with 32GB per node |

## Cleanup (cloud users only)

If you're running on a paid cloud platform (ROSA, ARO, OSD) and want to avoid resource costs, tear down the deployment when not in use. On a homelab cluster, leave it running — there's no cost and it's useful for demos and building Phase 3.

```bash
oc delete -f openshift/liberty-deployment/WebSphereLibertyApplication.yaml
```

## What's Next (Phase 3)

Phase 3 adds Ansible automation for a simulated legacy WAS ND environment:
- Vagrant environment with WAS ND nodes
- Ansible playbooks for WAS install, cluster creation, app deployment
- IHS reverse proxy configuration
- wsadmin Jython scripts for admin tasks
