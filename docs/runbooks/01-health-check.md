# Runbook 01 — Liberty Application Health Check

Systematic health verification for the NexusLiberty application running on OKD. Run this first when paged, before investigating specific symptoms. Produces a health status of **Healthy**, **Degraded**, or **Down** and routes you to the correct follow-up runbook.

---

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NAMESPACE` | `liberty-apps` | OKD namespace for Liberty workloads |
| `APP_NAME` | `nexusliberty-app` | OpenLibertyApplication CR name |
| `ROUTE_HOST` | `oc get route -n liberty-apps -o jsonpath='{.items[0].spec.host}'` | External Route hostname |
| `GRAFANA_URL` | `https://grafana-openshift-monitoring.apps.<CLUSTER_DOMAIN>/d/nexusliberty-liberty-metrics` | Grafana dashboard |
| `REPLICAS` | `2` | Expected replica count |

---

## Prerequisites

- `oc` CLI authenticated to the OKD cluster (`oc whoami` returns a valid user)
- `cluster-reader` or `namespace-admin` role on `liberty-apps`
- Network access to the cluster API and Route endpoints
- Access to Grafana (OpenShift monitoring stack)

---

## Procedure

### Step 1 — Cluster Health (30 seconds)

Verify the cluster itself is healthy before investigating the application.

```bash
oc get nodes
```

**Expected output:** All 3 nodes show `Ready`. If any node shows `NotReady`, the problem may be infrastructure — check node events before continuing.

```
NAME         STATUS   ROLES                         AGE    VERSION
okd-node1    Ready    control-plane,master,worker    30d    v1.28.x
okd-node2    Ready    control-plane,master,worker    30d    v1.28.x
okd-node3    Ready    control-plane,master,worker    30d    v1.28.x
```

```bash
oc get clusteroperators | grep -v "True.*False.*False"
```

**Expected output:** No output. Every operator should show `AVAILABLE=True`, `PROGRESSING=False`, `DEGRADED=False`. Any lines returned here are degraded operators — note them but continue with the app check.

### Step 2 — Pod Status (30 seconds)

```bash
oc get pods -n liberty-apps -l app.kubernetes.io/name=nexusliberty-app -o wide
```

**Expected output:** 2 pods in `Running` state with `1/1` containers ready, distributed across different nodes.

```
NAME                                READY   STATUS    RESTARTS   AGE   IP            NODE
nexusliberty-app-6d8f4b7c9-abc12   1/1     Running   0          2h    10.128.2.15   okd-node1
nexusliberty-app-6d8f4b7c9-def34   1/1     Running   0          2h    10.129.0.22   okd-node2
```

**Check for problems:**

| Status | Meaning | Go to |
|--------|---------|-------|
| `Running` + `1/1` | Healthy | Continue |
| `Running` + `0/1` | Readiness probe failing | Step 4, then Runbook 03 |
| `CrashLoopBackOff` | Application crash | Runbook 03 |
| `OOMKilled` | Memory limit exceeded | Runbook 03 |
| `ImagePullBackOff` | Image pull failure | Runbook 03 |
| `Pending` | Scheduling failure | Runbook 03 |
| Fewer than 2 pods | Partial outage | Step 3, then Runbook 03 |

```bash
oc get pods -n liberty-apps -l app.kubernetes.io/name=nexusliberty-app --field-selector=status.phase!=Running
```

**Expected output:** No resources found. Any output here means at least one pod is unhealthy.

### Step 3 — OpenLibertyApplication CR Status

```bash
oc get OpenLibertyApplication nexusliberty-app -n liberty-apps -o jsonpath='{.status.conditions}' | python3 -m json.tool
```

**Expected output:** Conditions array with `Reconciled` type showing `True` status.

```bash
oc get deployment nexusliberty-app -n liberty-apps -o jsonpath='{.status.availableReplicas}'
```

**Expected output:** `2`. If less than 2, the deployment is degraded.

### Step 4 — MicroProfile Health Endpoints

**Via Route (external, tests full path through OpenShift router):**

```bash
ROUTE_HOST=$(oc get route -n liberty-apps nexusliberty-app -o jsonpath='{.spec.host}')

# Liveness — is the JVM alive and not deadlocked?
curl -sk "https://${ROUTE_HOST}/health/live" | python3 -m json.tool

# Readiness — can the app serve traffic?
curl -sk "https://${ROUTE_HOST}/health/ready" | python3 -m json.tool
```

**Expected output (healthy):**

```json
{
    "status": "UP",
    "checks": [
        {
            "name": "LivenessCheck",
            "status": "UP",
            "data": {}
        }
    ]
}
```

**Via pod exec (bypasses Route — use when Route is down or suspected):**

```bash
POD=$(oc get pods -n liberty-apps -l app.kubernetes.io/name=nexusliberty-app -o jsonpath='{.items[0].metadata.name}')

oc exec -n liberty-apps ${POD} -- curl -s http://localhost:9080/health/live
oc exec -n liberty-apps ${POD} -- curl -s http://localhost:9080/health/ready
```

If the Route curl fails but the exec curl succeeds, the problem is in the Route or OpenShift router — not the application.

### Step 5 — Liberty Logs

```bash
POD=$(oc get pods -n liberty-apps -l app.kubernetes.io/name=nexusliberty-app -o jsonpath='{.items[0].metadata.name}')

# Check for ERROR or WARNING messages in the last 30 minutes
oc logs -n liberty-apps ${POD} --since=30m | grep -E '"loglevel":"(ERROR|WARNING)"'
```

**Expected output:** No output. Any ERROR or WARNING lines need investigation.

**Key Liberty log codes to look for:**

| Code | Meaning | Severity |
|------|---------|----------|
| `CWWKF0011I` | Server ready | Info — this is good |
| `CWWKT0016I` | Web application available | Info — this is good |
| `CWWKF0012I` | Server stopped | Info — expected during shutdown |
| `CWWKF0001E` | Feature not found | Error — server.xml misconfiguration |
| `CWWKO0221E` | Port already in use | Error — port conflict |
| `CWWKE0701E` | Bundle exception | Error — feature conflict in server.xml |
| `CWWKZ0002E` | Application failed to start | Error — app deployment issue |
| `CWNEN0030E` | JNDI lookup failure | Error — datasource or resource misconfigured |

```bash
# Confirm the server started successfully (look for the ready message)
oc logs -n liberty-apps ${POD} | grep -E "CWWKF0011I|CWWKT0016I" | tail -5
```

**Expected output:** Lines containing `CWWKF0011I` (server is ready to run a smarter planet) and `CWWKT0016I` (web application available).

### Step 6 — Prometheus Metrics Spot Check

Verify that the `/metrics` endpoint is accessible and returning data.

```bash
POD=$(oc get pods -n liberty-apps -l app.kubernetes.io/name=nexusliberty-app -o jsonpath='{.items[0].metadata.name}')

# Check heap usage — value in bytes
oc exec -n liberty-apps ${POD} -- curl -s http://localhost:9080/metrics | grep base_memory_usedHeap_bytes

# Check thread count
oc exec -n liberty-apps ${POD} -- curl -s http://localhost:9080/metrics | grep base_thread_count

# Check HTTP request counters
oc exec -n liberty-apps ${POD} -- curl -s http://localhost:9080/metrics | grep base_REST_request_total
```

**Expected output:** Numeric values for each metric. If `/metrics` returns empty or 404, the `mpMetrics` feature may not be loaded — check `CWWKF` messages in logs.

**Quick math on heap pressure:**

```bash
# Calculate heap usage percentage
oc exec -n liberty-apps ${POD} -- curl -s http://localhost:9080/metrics | \
  grep -E "^base_memory_(usedHeap|maxHeap)_bytes " | awk '{print $1, $2}'
```

If `usedHeap / maxHeap > 0.85`, the pod is under heap pressure. See Runbook 04.

### Step 7 — Grafana Dashboard Review

Open the Grafana dashboard: `<GRAFANA_URL>`

Check these panels in order:

1. **Pod Status** — should show `2` in green. Yellow (1) = degraded. Red (0) = down.
2. **Error Rate (5xx)** — should be `0%`. Any non-zero value needs investigation.
3. **Avg Response Time** — baseline is <500ms. Above 2s triggers the `LibertyHighLatency` alert.
4. **JVM Heap Usage** — look for a sawtooth pattern (normal GC). A steadily rising line without drops indicates a memory leak.
5. **GC Pause Time** — occasional short pauses are normal. Frequent long pauses (>500ms) correlate with heap pressure.
6. **HTTP Request Rate** — compare to baseline. A sudden spike or drop is worth noting.

### Step 8 — Active Alerts

```bash
# Check if any PrometheusRule alerts are firing
oc get prometheusrules -n liberty-apps
```

Check the Alertmanager UI or Prometheus targets page for active alerts:
- `LibertyHeapUsageHigh` — JVM heap >85% for 5m (warning)
- `LibertyHighErrorRate` — 5xx rate >5% for 5m (critical)
- `LibertyPodsUnavailable` — fewer than 2 pods available for 2m (critical)
- `LibertyHighLatency` — avg response time >2s for 5m (warning)

---

## Health Status Decision

| Condition | Status | Action |
|-----------|--------|--------|
| All pods Running + Ready, health endpoints UP, no errors in logs, metrics normal | **Healthy** | Done. Close the alert. |
| 1 pod unhealthy, other pod serving traffic, elevated but functional metrics | **Degraded** | Go to Runbook 03 to recover the failed pod. |
| All pods down, health endpoints unreachable, or >5% error rate sustained | **Down** | Go to Runbook 03 for immediate recovery. If deploy-related, go to Runbook 02 for rollback. |
| Pods healthy but response time elevated, heap pressure, high GC | **Degraded (Performance)** | Go to Runbook 04 for scaling and tuning. |

---

## Troubleshooting

**`oc` commands hang or timeout:**
The cluster API server may be overloaded or unreachable. Verify network connectivity to the API endpoint. Try `oc whoami` — if that hangs, the problem is cluster access, not the application.

**Route returns 503 but pods are Running:**
The OpenShift router may not have endpoints. Check:
```bash
oc get endpoints nexusliberty-app -n liberty-apps
```
If the endpoints list is empty, the service selector does not match the pod labels. Compare `oc get svc nexusliberty-app -n liberty-apps -o yaml` label selectors against the pod labels.

**Health endpoint returns DOWN but pod is Running:**
The readiness check includes application-level validations (servlet engine, JCache). The JVM is alive but the application is not ready. Check logs for the specific check that failed:
```bash
oc logs -n liberty-apps ${POD} --since=10m | grep -i "readiness\|health"
```

**Metrics endpoint returns 404:**
The `mpMetrics` feature failed to load. Check for feature resolution errors:
```bash
oc logs -n liberty-apps ${POD} | grep "CWWKF"
```

---

## Escalation

Stop and escalate if:
- All 3 cluster nodes are `NotReady` — this is an infrastructure issue, not an application issue
- Multiple cluster operators are degraded — contact the platform team
- Liberty pods are running but returning persistent 500 errors with no `CWWK` error codes in logs — possible application-level bug, engage the development team
- You have followed Runbook 03 and the application will not recover after 2 restart cycles

---

## Related Runbooks

- [02 — Deploy and Rollback](02-deploy-and-rollback.md) — if the issue started after a recent deploy
- [03 — Pod Failure and Recovery](03-pod-failure-and-recovery.md) — if pods are not Running/Ready
- [04 — Scaling and Performance](04-scaling-and-performance.md) — if pods are healthy but slow
