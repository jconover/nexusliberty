# Runbook 03 — Pod Failure Triage and Recovery

Diagnose and recover Liberty pods that are not Running/Ready. Covers every common failure mode: crash loops, OOM kills, image pull failures, scheduling failures, SCC issues, and Liberty-specific startup errors.

---

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NAMESPACE` | `liberty-apps` | OKD namespace |
| `APP_NAME` | `nexusliberty-app` | OpenLibertyApplication CR name |
| `SA_NAME` | `nexusliberty-sa` | ServiceAccount used by Liberty pods |

---

## Prerequisites

- `oc` CLI authenticated with `edit` role (or higher) on `liberty-apps`
- Ability to delete pods (for recovery)
- Familiarity with Liberty `CWWK` log code format

---

## Procedure

### Step 1 — Identify the Failure Mode

```bash
oc get pods -n liberty-apps -l app.kubernetes.io/name=nexusliberty-app -o wide
```

```bash
# Get detailed status for failing pod
oc describe pod <POD_NAME> -n liberty-apps | tail -30
```

Identify which failure mode matches, then jump to the corresponding section below.

---

## Failure Mode: CrashLoopBackOff

The container starts, crashes, restarts, crashes again. The backoff delay increases with each cycle (10s, 20s, 40s... up to 5m).

### Diagnose

```bash
# Check the exit code
oc get pod <POD_NAME> -n liberty-apps -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode}'
```

| Exit Code | Meaning |
|-----------|---------|
| `1` | Application error — JVM exited with error |
| `137` | SIGKILL (128+9) — OOMKilled or liveness probe killed it |
| `143` | SIGTERM (128+15) — graceful shutdown, normal during rollout |

```bash
# Get logs from the PREVIOUS crashed container (critical — current container may have no logs yet)
oc logs -n liberty-apps <POD_NAME> --previous
```

### Common Causes and Fixes

**Feature conflict in server.xml:**

Look for `CWWKE0701E` or `CWWKF0001E` in the previous logs.

```bash
oc logs -n liberty-apps <POD_NAME> --previous | grep -E "CWWKE0701E|CWWKF0001E|CWWKF0032E"
```

This means a feature listed in `server.xml` is either not installed in the Liberty runtime or conflicts with another feature. Common causes:
- Typo in feature name (e.g., `webprofile-10.0` instead of `webProfile-10.0`)
- Feature version mismatch with the Liberty kernel version in the Docker image
- Two features that cannot coexist (e.g., `jaxrs-2.1` with `restfulWS-3.1`)

Fix: Correct the feature name in `docker/liberty-app/server.xml` and rebuild the image.

**Port conflict (`CWWKO0221E`):**

```bash
oc logs -n liberty-apps <POD_NAME> --previous | grep "CWWKO0221E"
```

Another process in the container is already bound to port 9080 or 9443. This should not happen with standard Liberty images — if it does, the image may have been built with a conflicting base layer. Rebuild from a clean `icr.io/appcafe/open-liberty` base.

**Application deployment failure (`CWWKZ0002E` or `CWWKZ0013E`):**

```bash
oc logs -n liberty-apps <POD_NAME> --previous | grep -E "CWWKZ0002E|CWWKZ0013E"
```

The WAR file failed to deploy. Causes:
- Missing classes (check Maven dependencies in `app/pom.xml`)
- Servlet initialization exception (look for `Caused by:` stack traces after the CWWKZ message)
- Context root conflict

**JNDI / Resource binding failure (`CWNEN0030E`):**

```bash
oc logs -n liberty-apps <POD_NAME> --previous | grep "CWNEN0030E"
```

A `@Resource` injection in the application code references a JNDI name that is not configured in `server.xml`. Either add the resource definition or fix the application's JNDI lookup name.

### Recovery

If the fix requires a code or config change, push the fix through the normal pipeline (Runbook 02). If you need immediate recovery to the previous known-good state:

```bash
oc rollout undo deployment/nexusliberty-app -n liberty-apps
```

---

## Failure Mode: OOMKilled

The container exceeded its memory limit and was killed by the kernel.

### Diagnose

```bash
oc get pod <POD_NAME> -n liberty-apps -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}'
```

**Expected output:** `OOMKilled`

```bash
# Check the container memory limit vs JVM heap
oc get pod <POD_NAME> -n liberty-apps -o jsonpath='{.spec.containers[0].resources.limits.memory}'
```

Current limits: `768Mi`. The JVM heap is a subset of this — OpenJ9 also needs metaspace, thread stacks, JIT code cache, and Hazelcast native memory.

### Fix

**Option 1 — Reduce JVM heap** (if application can tolerate it):

Create or update `docker/liberty-app/jvm.options`:

```
-Xmx256m
-Xms128m
```

Rebuild and redeploy.

**Option 2 — Increase container memory limit** (if cluster has capacity):

Edit `openshift/liberty-deployment/WebSphereLibertyApplication.yaml`:

```yaml
resources:
  requests:
    memory: 512Mi
  limits:
    memory: 1Gi
```

Commit, push, let Argo CD sync.

### Rule of Thumb

Container memory limit should be at least 1.5x the JVM max heap to accommodate native memory, Hazelcast, and GC overhead. If max heap is 256Mi, the container limit should be at least 384Mi. The current 768Mi limit supports approximately 400-450Mi max heap safely.

---

## Failure Mode: ImagePullBackOff

OKD cannot pull the container image from the registry.

### Diagnose

```bash
oc describe pod <POD_NAME> -n liberty-apps | grep -A5 "Events:"
```

Look for:
- `Failed to pull image` — the image tag does not exist in GHCR
- `401 Unauthorized` — pull secret is missing or expired
- `connection refused` / `timeout` — network issue reaching GHCR

### Fix

**Image tag does not exist:**

```bash
# Check what image the pod is trying to pull
oc get pod <POD_NAME> -n liberty-apps -o jsonpath='{.spec.containers[0].image}'
```

Verify the tag exists in GHCR. If the Tekton pipeline pushed a bad tag reference, fix the tag in `openshift/liberty-deployment/WebSphereLibertyApplication.yaml` and commit.

**Pull secret missing or expired:**

```bash
# Check if the pull secret exists
oc get secrets -n liberty-apps | grep -i pull

# Verify it's linked to the service account
oc get sa nexusliberty-sa -n liberty-apps -o jsonpath='{.imagePullSecrets}'
```

If the GHCR pull secret is missing, recreate it:

```bash
oc create secret docker-registry ghcr-pull-secret \
  -n liberty-apps \
  --docker-server=ghcr.io \
  --docker-username=<GITHUB_USERNAME> \
  --docker-password=<GITHUB_PAT>

oc secrets link nexusliberty-sa ghcr-pull-secret --for=pull -n liberty-apps
```

After fixing the pull secret, delete the failing pod to force a re-pull:

```bash
oc delete pod <POD_NAME> -n liberty-apps
```

---

## Failure Mode: Pending

The pod cannot be scheduled to any node.

### Diagnose

```bash
oc describe pod <POD_NAME> -n liberty-apps | grep -A10 "Events:"
```

| Event Message | Cause | Fix |
|---------------|-------|-----|
| `Insufficient cpu` | No node has 200m CPU available | Scale down other workloads or reduce CPU request |
| `Insufficient memory` | No node has 384Mi memory available | Scale down other workloads or reduce memory request |
| `0/3 nodes are available: 3 node(s) didn't match pod anti-affinity` | Anti-affinity conflict with maxSurge during rollout | Wait for the rollout to complete — transient during rolling updates |
| `no persistent volumes available` | PVC binding failure | Not expected for this app (no PVCs) — investigate |
| `didn't match Pod's node affinity/selector` | Node label mismatch | Check node labels with `oc get nodes --show-labels` |

### Check Node Resources

```bash
oc adm top nodes
```

If all nodes are near capacity, the cluster needs capacity management. This is outside the scope of application operations.

---

## Failure Mode: Security Context Constraint (SCC) Rejection

OpenShift-specific. The pod is rejected because the container's security context does not satisfy the assigned SCC. This commonly trips engineers coming from vanilla Kubernetes.

### Diagnose

```bash
oc get events -n liberty-apps --sort-by=.lastTimestamp | grep -i "scc\|forbidden\|security"
```

```bash
# Check which SCC the pod is using
oc get pod <POD_NAME> -n liberty-apps -o jsonpath='{.metadata.annotations.openshift\.io/scc}'
```

The Liberty image runs as non-root (UID 1001, GID 0). It should work with `restricted-v2` SCC. If it does not:

### Fix

```bash
# Verify the service account can use restricted-v2
oc adm policy who-can use scc restricted-v2 -n liberty-apps | grep nexusliberty-sa

# If needed, explicitly grant (rarely required — restricted-v2 is the default)
oc adm policy add-scc-to-user restricted-v2 -z nexusliberty-sa -n liberty-apps
```

If the issue is that a custom or third-party Liberty image requires a specific UID:

```bash
# Check what UID the container is trying to run as
oc describe pod <POD_NAME> -n liberty-apps | grep -A5 "Security Context"
```

Do not grant `anyuid` or `privileged` unless there is no alternative. The Open Liberty base image (`icr.io/appcafe/open-liberty`) is designed to run as non-root.

---

## Live Triage of a Running Pod

If a pod is Running but not Ready (readiness probe failing), exec in for live investigation.

### Get a Shell

```bash
oc exec -it <POD_NAME> -n liberty-apps -- /bin/bash
```

### Check Liberty Server Status

```bash
# Inside the pod
/opt/ibm/wlp/bin/server status defaultServer
```

**Expected output:** `Server defaultServer is running with process ID <PID>.`

### Read the Messages Log Directly

```bash
# Inside the pod
cat /logs/messages.log | tail -50
```

Or from outside the pod:

```bash
oc exec -n liberty-apps <POD_NAME> -- tail -50 /logs/messages.log
```

### Capture a Thread Dump

Useful for diagnosing deadlocks, hung threads, or thread pool exhaustion.

```bash
oc exec -n liberty-apps <POD_NAME> -- /opt/ibm/wlp/bin/server javadump defaultServer
```

The dump is written to `/logs/` inside the container. Copy it out:

```bash
# Find the dump file
oc exec -n liberty-apps <POD_NAME> -- ls -lt /logs/ | head -5

# Copy it to your local machine
oc cp liberty-apps/<POD_NAME>:/logs/nexusliberty-app_javacore.<TIMESTAMP>.txt ./javacore.txt
```

### Capture a Heap Dump

Use when investigating OOMKilled or suspected memory leaks. The heap dump can be large (hundreds of MB).

```bash
oc exec -n liberty-apps <POD_NAME> -- /opt/ibm/wlp/bin/server javadump defaultServer --include=heap
```

```bash
# Copy the heap dump out
oc exec -n liberty-apps <POD_NAME> -- ls -lt /logs/ | grep heapdump
oc cp liberty-apps/<POD_NAME>:/logs/<HEAPDUMP_FILE> ./heapdump.phd
```

Analyze with IBM Eclipse Memory Analyzer (MAT) or the IBM Interactive Diagnostic Data Explorer (IDDE).

---

## When to Delete vs. Investigate

| Situation | Action |
|-----------|--------|
| Pod is CrashLoopBackOff with clear error in `--previous` logs | Fix the root cause, then delete the pod |
| Pod is Running but not Ready, no obvious errors | Exec in and investigate before deleting |
| Pod is OOMKilled repeatedly | Increase memory limits or reduce heap, then delete |
| Pod is Pending | Fix the scheduling constraint, pod will auto-schedule |
| Pod is ImagePullBackOff | Fix the image reference or pull secret, then delete |
| Pod is old (from a failed rollout) and a new pod is healthy | Delete the old pod — it's leftover |

To delete a pod (the Deployment controller will create a replacement):

```bash
oc delete pod <POD_NAME> -n liberty-apps
```

Do not delete all pods simultaneously. Delete one at a time and wait for the replacement to become Ready before deleting the next. The PodDisruptionBudget (`minAvailable: 1`) enforces this during voluntary disruptions, but direct pod deletes bypass the PDB.

---

## Troubleshooting

**`oc exec` fails with "error: unable to upgrade connection":**
The node running the pod may have kubelet issues. Check node status:
```bash
oc get node $(oc get pod <POD_NAME> -n liberty-apps -o jsonpath='{.spec.nodeName}') -o wide
```

**`oc logs` returns "container not found":**
The pod has been rescheduled. Get the new pod name:
```bash
oc get pods -n liberty-apps -l app.kubernetes.io/name=nexusliberty-app
```

**Hazelcast cluster formation failure:**
If logs show `com.hazelcast.cluster` errors about member discovery, verify:
1. RBAC is in place: `oc get role nexusliberty-pod-reader -n liberty-apps`
2. The service account is bound: `oc get rolebinding nexusliberty-pod-reader-binding -n liberty-apps`
3. Peer pods exist and have the label `app.kubernetes.io/name=nexusliberty-app`
4. NetworkPolicy allows Hazelcast traffic on port 5701 between Liberty pods

```bash
# Verify Hazelcast port connectivity between pods
POD1=$(oc get pods -n liberty-apps -l app.kubernetes.io/name=nexusliberty-app -o jsonpath='{.items[0].metadata.name}')
POD2_IP=$(oc get pods -n liberty-apps -l app.kubernetes.io/name=nexusliberty-app -o jsonpath='{.items[1].status.podIP}')
oc exec -n liberty-apps ${POD1} -- curl -s --connect-timeout 3 ${POD2_IP}:5701 || echo "Port 5701 unreachable"
```

---

## Escalation

Stop and escalate if:
- The pod fails with an exit code you do not recognize and there are no `CWWK` messages in logs — possible JVM-level crash, engage IBM support with the javacore dump
- SCC issues persist after applying the correct policy — contact the cluster security admin
- The node itself is unresponsive (`NotReady` status) — this is a platform issue, not an application issue
- A pod is stuck in `Terminating` state for more than 5 minutes — may need `--force --grace-period=0` deletion, but check for finalizers first

---

## Related Runbooks

- [01 — Health Check](01-health-check.md) — verify recovery after fixing a failed pod
- [02 — Deploy and Rollback](02-deploy-and-rollback.md) — if the failure was caused by a bad deploy
- [04 — Scaling and Performance](04-scaling-and-performance.md) — if OOMKilled or resource pressure is recurring
