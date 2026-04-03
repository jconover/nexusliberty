# Phase 5: HA and Operations — Liberty Clustering, IHS Load Balancing, and Monitoring

Step-by-step guide to configuring high availability, load balancing, and observability for Liberty on OKD.

## Prerequisites

- Phase 1-4 complete (OKD cluster running, Liberty deployed, CI/CD pipeline active)
- `oc` CLI installed and authenticated to the OKD cluster
- Liberty app deployed via WebSphereLibertyApplication CR in `liberty-apps` namespace

## What We're Building

```
┌──────────────────────────────────────────────────────────────────┐
│                     OKD Cluster (3-node)                         │
│                                                                  │
│  ┌────────────┐     ┌──────────────────────────────────────┐     │
│  │  IHS LB    │────→│  Liberty Pod 1     Liberty Pod 2     │     │
│  │  (HTTPD +  │     │  ┌────────────┐   ┌────────────┐    │     │
│  │  mod_proxy)│     │  │ App + JVM  │   │ App + JVM  │    │     │
│  └─────┬──────┘     │  │ Hazelcast  │←─→│ Hazelcast  │    │     │
│        │            │  │ /metrics   │   │ /metrics   │    │     │
│        │            │  └────────────┘   └────────────┘    │     │
│  OKD Route          │       Headless Service               │     │
│                     └──────────────┬───────────────────────┘     │
│                                    │                             │
│  ┌─────────────────────────────────▼──────────────────────────┐  │
│  │              Prometheus → Grafana Dashboard                 │  │
│  │  ServiceMonitor scrapes /metrics every 30s                  │  │
│  │  Alerts: heap > 85%, 5xx > 5%, pods < 2, latency > 2s     │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

## Step 1 — Liberty Session Replication (Hazelcast JCache)

Session replication ensures HTTP sessions survive pod failures. We use the `sessionCache-1.0` Liberty feature backed by embedded Hazelcast with Kubernetes API discovery.

### 1.1 Apply RBAC for Hazelcast Pod Discovery

```bash
# Create ServiceAccount, Role, and RoleBinding
oc apply -f openshift/liberty-deployment/rbac.yaml

# Verify
oc get serviceaccount nexusliberty-sa -n liberty-apps
oc auth can-i list pods --as=system:serviceaccount:liberty-apps:nexusliberty-sa -n liberty-apps
# Should return: yes
```

### 1.2 Deploy Updated Liberty CR (2 Replicas)

```bash
# Apply the updated WebSphereLibertyApplication (replicas: 2, serviceAccountName added)
oc apply -f openshift/liberty-deployment/WebSphereLibertyApplication.yaml

# Watch pods come up
oc get pods -w -n liberty-apps -l app.kubernetes.io/name=nexusliberty-app
# Wait for 2/2 pods Running and Ready
```

### 1.3 Verify Hazelcast Cluster Formation

```bash
# Check logs for Hazelcast member discovery
oc logs -l app.kubernetes.io/name=nexusliberty-app -n liberty-apps | grep -i "Members"
# Should show: Members {size:2, [member1, member2]}

# Test session failover:
# 1. Create a session via the app
# 2. Delete one pod
oc delete pod $(oc get pods -n liberty-apps -l app.kubernetes.io/name=nexusliberty-app -o name | head -1) -n liberty-apps
# 3. Verify session persists on the remaining pod
```

## Step 2 — IHS Load Balancing

### 2.1 Verify the Operator-Managed Service

The Liberty Operator automatically creates a ClusterIP service for the application.
IHS proxies to this service, which Kubernetes load-balances across Liberty pods.

```bash
# Verify the operator-created service exists
oc get svc nexusliberty-app -n liberty-apps
```

### 2.2 Build and Push the IHS Image

```bash
# Build from repo root
docker build -t ghcr.io/jconover/nexusliberty-ihs:latest -f docker/ihs/Dockerfile .

# Push to GHCR
docker push ghcr.io/jconover/nexusliberty-ihs:latest
```

### 2.3 Deploy IHS on OKD

```bash
# Deploy IHS pod, service, and route
oc apply -f openshift/ihs-deployment/

# Verify
oc get pods -l app.kubernetes.io/name=nexusliberty-ihs -n liberty-apps
oc get route nexusliberty-ihs -n liberty-apps

# Test routing through IHS
curl -k https://nexusliberty-ihs.apps.nexuslab.nexuslab.local/app/
curl -k https://nexusliberty-ihs.apps.nexuslab.nexuslab.local/ihs-health
```

## Step 3 — Prometheus Monitoring

### 3.1 Enable User Workload Monitoring

```bash
# Enable Prometheus scraping of user namespaces (cluster-admin required)
oc apply -f openshift/monitoring/cluster-monitoring-config.yaml -n openshift-monitoring

# Wait for user workload monitoring pods to start
oc get pods -n openshift-user-workload-monitoring -w
# Wait for prometheus-user-workload and thanos-ruler pods
```

### 3.2 Deploy ServiceMonitor

```bash
# Tell Prometheus to scrape Liberty's /metrics endpoint
oc apply -f openshift/monitoring/servicemonitor.yaml

# Verify targets appear
# OKD Console → Observe → Targets → filter by liberty-apps
# Both Liberty pods should show status "UP"
```

### 3.3 Deploy Alert Rules

```bash
# Apply PrometheusRule with Liberty-specific alerts
oc apply -f openshift/monitoring/prometheusrule.yaml

# Verify rules loaded
oc get prometheusrule -n liberty-apps
# OKD Console → Observe → Alerting → filter by "Liberty"
```

### 3.4 Verify Metrics Flow

```bash
# Quick check — scrape metrics from a Liberty pod directly
oc exec $(oc get pods -n liberty-apps -l app.kubernetes.io/name=nexusliberty-app -o name | head -1) \
  -n liberty-apps -- curl -s http://localhost:9080/metrics | head -30

# Check via OKD Console → Observe → Metrics
# Try queries:
#   base_memory_usedHeap_bytes{namespace="liberty-apps"}
#   rate(base_REST_request_total{namespace="liberty-apps"}[5m])
```

## Step 4 — Grafana Dashboard

### 4.1 Deploy Dashboard ConfigMap

```bash
oc apply -f openshift/monitoring/grafana-dashboard.yaml
```

### 4.2 Import into Grafana

If using the Grafana Operator with dashboard discovery (`grafana_dashboard: "true"` label), the dashboard auto-imports.

For manual import:
1. Open Grafana UI
2. Dashboards → Import
3. Extract the JSON from the ConfigMap:
   ```bash
   oc get configmap nexusliberty-grafana-dashboard -n liberty-apps \
     -o jsonpath='{.data.nexusliberty-dashboard\.json}' > /tmp/dashboard.json
   ```
4. Paste the JSON into the Grafana import dialog
5. Select the Prometheus datasource
6. Dashboard title: "NexusLiberty — Liberty Application Metrics"

### 4.3 Dashboard Panels

| Row | Panels |
|---|---|
| Top | Pod status, request rate, error rate, avg response time |
| Middle | JVM heap usage, JVM CPU usage |
| Lower | HTTP request rate by pod, response time percentiles (p50/p95/p99) |
| Bottom | JVM thread count, GC pause time |

## Step 5 — Validation Checklist

```bash
# 1. Liberty pods running with 2 replicas
oc get pods -n liberty-apps -l app.kubernetes.io/name=nexusliberty-app
# Expected: 2 pods, Running, Ready

# 2. Hazelcast session replication active
oc logs -l app.kubernetes.io/name=nexusliberty-app -n liberty-apps | grep -c "Members"
# Expected: entries showing size:2

# 3. IHS pod running and proxying
curl -k https://nexusliberty-ihs.apps.nexuslab.nexuslab.local/app/
# Expected: 200 OK from Liberty app

# 4. Prometheus scraping Liberty metrics
# OKD Console → Observe → Targets → liberty-apps → all UP

# 5. Alert rules loaded
oc get prometheusrule nexusliberty-alerts -n liberty-apps
# Expected: resource exists

# 6. Grafana dashboard accessible
# Import and verify panels render with data
```

## Files Added / Modified

| File | Purpose |
|---|---|
| `docker/liberty-app/server.xml` | Added `sessionCache-1.0` + Hazelcast JCache config |
| `docker/liberty-app/Dockerfile` | Hazelcast JAR downloads + config copy |
| `docker/liberty-app/hazelcast.xml` | Hazelcast K8s discovery config |
| `openshift/liberty-deployment/WebSphereLibertyApplication.yaml` | 2 replicas + ServiceAccount |
| `openshift/liberty-deployment/rbac.yaml` | SA + Role + RoleBinding for pod discovery |
| `docker/ihs/Dockerfile` | Containerized IHS (Apache HTTPD + mod_proxy_balancer) |
| `docker/ihs/httpd.conf` | Reverse proxy config targeting Liberty ClusterIP service |
| `openshift/ihs-deployment/deployment.yaml` | IHS Deployment on OKD |
| `openshift/ihs-deployment/service.yaml` | IHS Service |
| `openshift/ihs-deployment/route.yaml` | IHS OKD Route |
| `.github/workflows/ihs-build.yml` | GitHub Actions build for IHS image |
| `ansible/roles/ihs-proxy/defaults/main.yml` | Added `liberty_mode` toggle |
| `ansible/roles/ihs-proxy/templates/plugin-cfg.xml.j2` | Dual WAS/Liberty target support |
| `openshift/monitoring/cluster-monitoring-config.yaml` | Enable user workload monitoring |
| `openshift/monitoring/servicemonitor.yaml` | Prometheus scrape config |
| `openshift/monitoring/prometheusrule.yaml` | Alert rules (heap, errors, availability, latency) |
| `openshift/monitoring/grafana-dashboard.yaml` | Grafana dashboard JSON |
| `docs/was-runbook.md` | WAS + Liberty operational runbook |

## What's Next

All five phases are complete. The NexusLiberty platform now demonstrates the full enterprise middleware modernization lifecycle: from legacy WAS ND automation through containerized Liberty on OpenShift with CI/CD, high availability, and observability.

For operational procedures, see the [WAS Operational Runbook](was-runbook.md).

Back to the [project README](../README.md) for the full project overview.
