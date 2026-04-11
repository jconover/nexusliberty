# Runbook 04 — Scaling and Performance Tuning

Diagnose and resolve performance issues with the NexusLiberty application. Covers manual scaling, key performance metrics, Liberty tuning parameters, JVM diagnostics, and the decision framework for horizontal vs. vertical scaling.

---

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NAMESPACE` | `liberty-apps` | OKD namespace |
| `APP_NAME` | `nexusliberty-app` | OpenLibertyApplication CR name |
| `GRAFANA_URL` | `https://grafana-openshift-monitoring.apps.<CLUSTER_DOMAIN>/d/nexusliberty-liberty-metrics` | Grafana dashboard |
| `CURRENT_REPLICAS` | `2` | Current replica count |
| `MAX_REPLICAS` | `3` | Max replicas (limited by 3-node cluster) |

---

## Prerequisites

- `oc` CLI authenticated with `edit` role on `liberty-apps`
- Access to Grafana dashboard
- Understanding of current baseline performance (normal request rate, latency, heap usage)

---

## Procedure

### Step 1 — Confirm the Problem is Performance (Not Failure)

Before tuning, verify pods are healthy. A "slow" application that is actually crash-looping is a Runbook 03 problem.

```bash
oc get pods -n liberty-apps -l app.kubernetes.io/name=nexusliberty-app
```

All pods should show `Running` with `1/1` Ready. If not, go to Runbook 03 first.

### Step 2 — Identify the Bottleneck

Check these metrics in order. The first one that is abnormal is usually the bottleneck.

#### 2a — Request Latency

```bash
POD=$(oc get pods -n liberty-apps -l app.kubernetes.io/name=nexusliberty-app -o jsonpath='{.items[0].metadata.name}')

# Average response time from mpMetrics
oc exec -n liberty-apps ${POD} -- curl -s http://localhost:9080/metrics | \
  grep -E "base_REST_request_elapsedTime_seconds_(sum|count)" | head -4
```

Compute average: `sum / count`. Baseline should be <500ms. Above 2s triggers the `LibertyHighLatency` alert.

On Grafana, check the **HTTP Response Time (p50 / p95 / p99)** panel. A high p99 with normal p50 means a subset of requests is slow (likely GC pauses or a specific slow endpoint).

#### 2b — JVM Heap

```bash
oc exec -n liberty-apps ${POD} -- curl -s http://localhost:9080/metrics | \
  grep -E "^base_memory_(usedHeap|maxHeap)_bytes "
```

Calculate `usedHeap / maxHeap`. Under 70% is normal. 70-85% is elevated. Above 85% fires the `LibertyHeapUsageHigh` alert.

On Grafana, check the **JVM Heap Usage** panel:
- **Healthy pattern:** Sawtooth — usage rises, GC drops it, repeats.
- **Unhealthy pattern:** Steadily rising with no drops — likely memory leak.
- **Saturated pattern:** Flat line near maxHeap — GC running constantly, application is thrashing.

#### 2c — Garbage Collection

```bash
oc exec -n liberty-apps ${POD} -- curl -s http://localhost:9080/metrics | \
  grep "base_gc_time_total"
```

On Grafana, check the **GC Pause Time** panel. Frequent pauses over 500ms indicate heap pressure. The application is spending time in GC instead of processing requests.

#### 2d — Thread Pool

```bash
oc exec -n liberty-apps ${POD} -- curl -s http://localhost:9080/metrics | \
  grep "base_thread_"
```

Key values:
- `base_thread_count` — active threads (current `maxThreads` is 20)
- `base_thread_daemon_count` — daemon threads (Liberty internals, Hazelcast)

If `thread_count` is consistently at or near `maxThreads` (20), the thread pool is saturated. Requests are queuing.

#### 2e — CPU and Memory at Node Level

```bash
oc adm top pods -n liberty-apps
oc adm top nodes
```

If a pod is consistently at its CPU limit (500m), it is being throttled. If a node is above 80% memory, scheduling new pods may fail.

---

## Manual Scaling

### Scale Up

```bash
# Scale from 2 to 3 replicas
oc scale deployment nexusliberty-app -n liberty-apps --replicas=3

# Watch the new pod come up
oc get pods -n liberty-apps -l app.kubernetes.io/name=nexusliberty-app -w
```

Wait for the new pod to show `1/1 Running` before declaring success. The startup probe allows up to 5 minutes for Liberty to initialize.

**Note:** With a 3-node cluster and pod anti-affinity (`preferredDuringScheduling`), 3 replicas will spread one pod per node. Scaling beyond 3 is possible but places multiple pods on the same node, reducing failure isolation.

### Scale Down

```bash
# Scale from 3 back to 2 replicas
oc scale deployment nexusliberty-app -n liberty-apps --replicas=2
```

The PodDisruptionBudget (`minAvailable: 1`) ensures at least one pod remains during scale-down. OKD will terminate pods one at a time.

**Important:** If you scale via `oc scale`, Argo CD will detect drift and may reset the replica count on the next sync (auto-sync is enabled with `selfHeal: true`). To persist the change, update `replicas` in `openshift/liberty-deployment/WebSphereLibertyApplication.yaml` and commit.

### Verify Scaling

```bash
# Confirm desired vs available
oc get deployment nexusliberty-app -n liberty-apps \
  -o jsonpath='desired={.spec.replicas} available={.status.availableReplicas}{"\n"}'
```

After scaling up, verify load distribution:

```bash
# Hit the route multiple times and check which pod responds
ROUTE_HOST=$(oc get route -n liberty-apps nexusliberty-app -o jsonpath='{.spec.host}')
for i in {1..6}; do
  curl -sk "https://${ROUTE_HOST}/app/api/info" | python3 -c "import sys,json; print(json.load(sys.stdin).get('hostname','?'))"
done
```

You should see responses from different pods, confirming the load balancer is distributing traffic.

---

## Liberty Performance Tuning

### Thread Pool (`server.xml`)

Current configuration in `docker/liberty-app/server.xml`:

```xml
<executor id="defaultExecutor"
          coreThreads="4"
          maxThreads="20"
          keepAlive="60s"/>
```

| Parameter | Current | Tuning Guidance |
|-----------|---------|-----------------|
| `coreThreads` | 4 | Set to 2x the CPU cores available to the container. At 500m (0.5 cores), 4 is generous. |
| `maxThreads` | 20 | Upper bound for burst. If thread_count consistently hits this, increase to 40. Above 50 per container is rarely beneficial. |
| `keepAlive` | 60s | How long idle threads survive. Lower to 30s if memory is tight. |

To change: edit `docker/liberty-app/server.xml`, rebuild the image, and deploy through the normal pipeline.

### JVM Heap (`jvm.options`)

Create or update `docker/liberty-app/jvm.options` and add `COPY --chown=1001:0 docker/liberty-app/jvm.options /config/jvm.options` to the Dockerfile.

**Conservative defaults for a 768Mi container limit:**

```
# Max heap — leave ~300Mi for metaspace, thread stacks, Hazelcast, native buffers
-Xmx384m
# Initial heap — reduces startup GC churn
-Xms256m
# OpenJ9 shared class cache — improves startup time and memory footprint
-Xshareclasses:cacheDir=/tmp/.classCache
```

**Aggressive defaults for a 1Gi container limit:**

```
-Xmx512m
-Xms384m
-Xshareclasses:cacheDir=/tmp/.classCache
```

**Rule of thumb:** `Xmx` should be no more than 50-60% of the container memory limit when running Hazelcast. Without Hazelcast, 65-70% is safe.

### Connection Pool (if datasource is configured)

The connection pool in `server.xml` (currently commented out) controls database connection allocation:

```xml
<connectionManager maxPoolSize="25"
                   minPoolSize="5"
                   connectionTimeout="30s"
                   maxIdleTime="10m"/>
```

If connections are exhausted, the application logs `DSRA0080E` or `J2CA0045E`. Increase `maxPoolSize` or investigate slow queries. Do not set `maxPoolSize` above 50 without also tuning the database's max connection limit.

---

## Capturing Diagnostic Data for IBM Support

### Server Dump (includes config, thread dump, memory info)

```bash
oc exec -n liberty-apps <POD_NAME> -- /opt/ibm/wlp/bin/server dump defaultServer --include=heap,thread
```

The dump is written as a ZIP file to `/logs/`:

```bash
# Find the dump file
oc exec -n liberty-apps <POD_NAME> -- ls -lt /logs/ | grep "\.zip"

# Copy it out
oc cp liberty-apps/<POD_NAME>:/logs/nexusliberty-app_dump_<TIMESTAMP>.zip ./liberty-dump.zip
```

This ZIP contains:
- `server.xml` (sanitized)
- `javacore` (thread dump)
- `heapdump.phd` (if `--include=heap` was specified)
- `server.env` and `jvm.options` (if present)

### Thread Dump Only (lightweight, no heap)

```bash
oc exec -n liberty-apps <POD_NAME> -- /opt/ibm/wlp/bin/server javadump defaultServer
```

Use the IBM Thread and Monitor Dump Analyzer (TMDA) to analyze the output.

---

## Horizontal vs. Vertical Scaling

| Signal | Scale Horizontally (more pods) | Scale Vertically (more resources per pod) |
|--------|-------------------------------|------------------------------------------|
| CPU throttling (pod at CPU limit) | Yes — if request processing is CPU-bound | Yes — increase CPU limit |
| Thread pool saturated | Yes — more pods = more thread pools | Partially — increase `maxThreads`, but diminishing returns |
| Heap pressure / frequent GC | No — more pods with the same heap won't help | Yes — increase memory limit + `Xmx` |
| High request volume, normal latency per request | Yes — distribute the load | No — each pod is handling requests fine |
| Single slow endpoint / query | No — the bottleneck is per-request, not per-pod | No — fix the endpoint or query |
| OOMKilled | No — the pod needs more memory, not more siblings | Yes — increase memory limit |

**For this deployment:**
- Start with horizontal scaling (2 → 3 replicas) since the 3-node cluster can absorb it
- If the bottleneck is heap or GC, scale vertically (increase memory limit and `Xmx`)
- If the bottleneck is a specific endpoint, scaling will not help — profile the code

---

## Hazelcast Session Replication Under Load

Hazelcast adds overhead to every HTTP session write (replication to backup member). Under high load with large sessions, this can contribute to latency.

Check Hazelcast member count:

```bash
oc logs -n liberty-apps <POD_NAME> | grep -i "Members \[" | tail -1
```

**Expected output:** `Members [2]` (or `Members [3]` if scaled to 3). If a pod shows `Members [1]`, it has lost cluster connectivity — check RBAC and NetworkPolicy (Runbook 03 troubleshooting section).

If Hazelcast replication is the bottleneck (visible as increased latency on session-writing endpoints), options:
- Reduce session payload size (store less data in HttpSession)
- Set `backup-count` to `0` in `docker/liberty-app/hazelcast.xml` (disables replication — faster but no session HA)
- Move to external session store (Redis, Infinispan) for higher throughput

---

## Troubleshooting

**Grafana shows no data for Liberty metrics:**
Verify the ServiceMonitor is targeting the correct label and port:
```bash
oc get servicemonitor nexusliberty-app -n liberty-apps -o yaml
```
Confirm Prometheus is scraping:
```bash
oc exec -n liberty-apps <POD_NAME> -- curl -s http://localhost:9080/metrics | head -5
```
If `/metrics` returns data but Grafana is empty, the issue is Prometheus target discovery — check the ServiceMonitor `selector.matchLabels` against the Service labels.

**`oc adm top pods` shows 0 CPU / 0 memory:**
Metrics server may not be running. Check:
```bash
oc get pods -n openshift-monitoring | grep metrics-server
```

**Scaling to 3 replicas but third pod stays Pending:**
Check node resources:
```bash
oc adm top nodes
oc describe node <NODE> | grep -A10 "Allocated resources"
```
The third node may not have enough allocatable CPU or memory. Consider reducing resource requests in the CR.

---

## Escalation

Stop and escalate if:
- JVM heap shows a steady memory leak pattern (rising without GC drops over hours) — this is an application bug, provide the heap dump to the development team
- GC pauses exceed 5 seconds consistently — may need JVM tuning beyond standard parameters, engage an OpenJ9 performance specialist
- Hazelcast split-brain detected (pods show different member counts and partitions are not converging) — restart all pods in a rolling fashion, escalate to the Hazelcast support channel if it recurs
- Application response time is degraded but all infrastructure metrics are normal — the bottleneck is in the application code or a downstream dependency, not the middleware

---

## Related Runbooks

- [01 — Health Check](01-health-check.md) — baseline health verification before and after tuning
- [02 — Deploy and Rollback](02-deploy-and-rollback.md) — deploying tuning changes via the normal pipeline
- [03 — Pod Failure and Recovery](03-pod-failure-and-recovery.md) — if OOMKilled recurs after tuning
