# Session Replication — Hazelcast Verification

Procedures for verifying Hazelcast JCache session clustering is working correctly across Liberty pods.

---

## Verify Hazelcast Cluster Formation

```bash
# Check Hazelcast cluster membership in Liberty logs
oc logs nexusliberty-app-<hash> -n liberty-apps | grep -i hazelcast | grep -i "Members"
# Expected output: Members {size:2, [member1, member2]}
```

---

## Test Session Failover

1. Set a session value via the application
2. Note which pod served the request (check response headers or logs)
3. Delete that pod:

```bash
oc delete pod nexusliberty-app-<hash> -n liberty-apps
```

4. Hit the application again — the session should persist on the remaining pod

---

## Troubleshoot Session Replication

```bash
# 1. Verify Hazelcast JARs exist in the pod
oc exec nexusliberty-app-<hash> -n liberty-apps -- ls /opt/ol/wlp/usr/shared/resources/hazelcast/

# 2. Check RBAC — ServiceAccount must be able to list pods
oc auth can-i list pods --as=system:serviceaccount:liberty-apps:nexusliberty-sa -n liberty-apps
# Should return: yes

# 3. Check Hazelcast logs for discovery errors
oc logs nexusliberty-app-<hash> -n liberty-apps | grep -i "hazelcast" | grep -iE "error|warn|exception"

# 4. Verify operator-managed service resolves
oc get svc nexusliberty-app -n liberty-apps
oc get endpoints nexusliberty-app -n liberty-apps
```
