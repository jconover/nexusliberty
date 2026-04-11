# NexusLiberty — Operations Runbooks

Operational procedures for the NexusLiberty application running on OKD. Written for a mid-level middleware engineer who knows Liberty but is new to this environment.

---

## Environment Quick Reference

| Item | Value |
|------|-------|
| Namespace | `liberty-apps` |
| Application CR | `OpenLibertyApplication/nexusliberty-app` |
| Replicas | 2 (PDB: minAvailable 1) |
| Route | `oc get route nexusliberty-app -n liberty-apps -o jsonpath='{.spec.host}'` |
| Image | `ghcr.io/jconover/nexusliberty-app:<sha-tag>` |
| Service Account | `nexusliberty-sa` |
| Grafana Dashboard | `<GRAFANA_URL>/d/nexusliberty-liberty-metrics` |
| Argo CD Application | `nexusliberty-app` (namespace: `openshift-gitops`) |
| GitHub Repository | `github.com/jconover/nexusliberty` |
| Liberty Server Config | `docker/liberty-app/server.xml` |

---

## On-Call Quick Reference

When paged, run these five commands first:

```bash
# 1. Am I connected to the right cluster?
oc whoami && oc cluster-info | head -1

# 2. Are the nodes healthy?
oc get nodes

# 3. Are the Liberty pods running?
oc get pods -n liberty-apps -l app.kubernetes.io/name=nexusliberty-app -o wide

# 4. Is the application responding?
ROUTE=$(oc get route nexusliberty-app -n liberty-apps -o jsonpath='{.spec.host}')
curl -sk "https://${ROUTE}/health/ready"

# 5. Any errors in the last 30 minutes?
POD=$(oc get pods -n liberty-apps -l app.kubernetes.io/name=nexusliberty-app -o jsonpath='{.items[0].metadata.name}')
oc logs -n liberty-apps ${POD} --since=30m | grep -cE '"loglevel":"(ERROR|WARNING)"'
```

Then go to [Runbook 01 — Health Check](01-health-check.md) for the full procedure.

---

## Runbook Index

| # | Runbook | When to Use | Time |
|---|---------|-------------|------|
| [01](01-health-check.md) | **Liberty Application Health Check** | First response to any alert. Produces a Healthy / Degraded / Down verdict and routes to the correct follow-up. | 5-10 min |
| [02](02-deploy-and-rollback.md) | **Deploy, Verify, and Rollback** | During or after a deployment. Also when you need to undo a bad deploy. | 5-15 min |
| [03](03-pod-failure-and-recovery.md) | **Pod Failure Triage and Recovery** | Liberty pod is CrashLoopBackOff, OOMKilled, ImagePullBackOff, Pending, or not Ready. | 10-30 min |
| [04](04-scaling-and-performance.md) | **Scaling and Performance Tuning** | Application is slow, thread pool saturated, heap under pressure, or traffic spike incoming. | 10-30 min |

---

## Triage Flowchart

```
Alert fires or user reports issue
  │
  ├─ Run Runbook 01 (Health Check)
  │    │
  │    ├─ Healthy → Close alert
  │    │
  │    ├─ Degraded (pod issue) → Runbook 03
  │    │
  │    ├─ Degraded (performance) → Runbook 04
  │    │
  │    ├─ Down → Was there a recent deploy?
  │    │    ├─ Yes → Runbook 02 (rollback), then Runbook 01
  │    │    └─ No  → Runbook 03 (pod recovery)
  │    │
  │    └─ Unknown / cluster-level issue → Escalate to platform team
  │
  └─ Deploy in progress → Runbook 02 (verify)
```

---

## Liberty Log Code Quick Reference

Common `CWWK` message codes encountered during operations. Full reference: [IBM Liberty Message Reference](https://www.ibm.com/docs/en/was-liberty/nd?topic=liberty-702x-702x-702x-702x-702x-702x).

### Informational (normal operation)

| Code | Message | Meaning |
|------|---------|---------|
| `CWWKF0011I` | The server is ready to run a smarter planet | Server startup complete — all features resolved |
| `CWWKF0012I` | The server stopped | Clean shutdown |
| `CWWKT0016I` | Web application available | Application deployed and bound to context root |
| `CWWKZ0001I` | Application started | Application lifecycle event |
| `CWWKE0001I` | Server launched | JVM started, features loading |
| `CWWKF0008I` | Feature update completed | Feature set changed at runtime |

### Warnings (investigate if recurring)

| Code | Message | Runbook |
|------|---------|---------|
| `CWWKF0014W` | Feature not found in repository | [03](03-pod-failure-and-recovery.md) — feature name typo or missing feature |
| `CWWKE0701W` | Bundle exception (warning level) | [03](03-pod-failure-and-recovery.md) — feature conflict |
| `CWWKG0011W` | Configuration merge conflict | [03](03-pod-failure-and-recovery.md) — duplicate config elements |

### Errors (action required)

| Code | Message | Runbook |
|------|---------|---------|
| `CWWKF0001E` | Feature not found | [03](03-pod-failure-and-recovery.md) — server.xml misconfiguration |
| `CWWKE0701E` | Bundle exception (error level) | [03](03-pod-failure-and-recovery.md) — feature conflict preventing startup |
| `CWWKO0221E` | Port already in use | [03](03-pod-failure-and-recovery.md) — port conflict |
| `CWWKZ0002E` | Application exception during startup | [03](03-pod-failure-and-recovery.md) — WAR deployment failure |
| `CWWKZ0013E` | Application start failed | [03](03-pod-failure-and-recovery.md) — application-level error |
| `CWNEN0030E` | Resource injection / JNDI lookup failed | [03](03-pod-failure-and-recovery.md) — missing resource definition |
| `DSRA0080E` | Connection pool exhausted | [04](04-scaling-and-performance.md) — datasource connection limit |
| `J2CA0045E` | Connection wait timeout | [04](04-scaling-and-performance.md) — datasource backpressure |

---

## Prometheus Alert Reference

These alerts are defined in `openshift/monitoring/prometheusrule.yaml`:

| Alert | Condition | Severity | Runbook |
|-------|-----------|----------|---------|
| `LibertyHeapUsageHigh` | JVM heap >85% for 5 min | Warning | [04](04-scaling-and-performance.md) |
| `LibertyHighErrorRate` | 5xx rate >5% for 5 min | Critical | [01](01-health-check.md) → [03](03-pod-failure-and-recovery.md) |
| `LibertyPodsUnavailable` | <2 pods available for 2 min | Critical | [03](03-pod-failure-and-recovery.md) |
| `LibertyHighLatency` | Avg response >2s for 5 min | Warning | [04](04-scaling-and-performance.md) |

---

## External References

- [IBM Open Liberty Documentation](https://openliberty.io/docs/)
- [IBM Liberty Knowledge Center](https://www.ibm.com/docs/en/was-liberty)
- [Liberty Message Reference](https://www.ibm.com/docs/en/was-liberty/nd?topic=702x-702x-702x-702x-702x-702x)
- [MicroProfile Health Specification](https://microprofile.io/specifications/microprofile-health/)
- [MicroProfile Metrics Specification](https://microprofile.io/specifications/microprofile-metrics/)
- [OpenJ9 JVM Tuning Guide](https://eclipse.dev/openj9/docs/)
- [Hazelcast Kubernetes Discovery](https://docs.hazelcast.com/hazelcast/latest/kubernetes/kubernetes-auto-discovery)
- [OKD Documentation](https://docs.okd.io/)
