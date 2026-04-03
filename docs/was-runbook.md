# WAS Operational Runbook — NexusLiberty

Standard operating procedures for the WebSphere Application Server ND environment and the modernized Liberty deployment on OKD.

---

## 1. WAS ND Cell — Daily Operations

### 1.1 Check Cell Health

```bash
# SSH to Deployment Manager
ssh wasadmin@nexus-dmgr.nexuslab.local

# Verify DMGR is running
/opt/IBM/WebSphere/AppServer/bin/serverStatus.sh dmgr

# Check all node agents and app servers
/opt/IBM/WebSphere/AppServer/bin/serverStatus.sh -all

# Or via wsadmin
wsadmin.sh -lang jython -host nexus-dmgr.nexuslab.local -port 8879 \
  -user wasadmin -password <pass> \
  -f /path/to/scripts/wsadmin/health-check.py
```

### 1.2 Start / Stop Application Servers

```bash
# Start a managed server
wsadmin.sh -lang jython -c "AdminControl.startServer('AppServer1', 'nexus-was1')"

# Stop a managed server (graceful)
wsadmin.sh -lang jython -c "AdminControl.stopServer('AppServer1', 'nexus-was1')"

# Restart node agent on a managed node
ssh wasadmin@nexus-was1.nexuslab.local
/opt/IBM/WebSphere/AppServer/bin/stopNode.sh
/opt/IBM/WebSphere/AppServer/bin/startNode.sh
```

### 1.3 Deploy / Update Application

```bash
# Deploy via wsadmin script
wsadmin.sh -lang jython -host nexus-dmgr.nexuslab.local -port 8879 \
  -user wasadmin -password <pass> \
  -f scripts/wsadmin/deploy-app.py

# Or via Ansible
ansible-playbook -i ansible/inventory/hosts.ini \
  ansible/playbooks/was-deploy-app.yml
```

### 1.4 Log Locations

| Component | Log Path |
|---|---|
| DMGR | `/opt/IBM/WebSphere/AppServer/profiles/Dmgr01/logs/dmgr/SystemOut.log` |
| Node Agent | `/opt/IBM/WebSphere/AppServer/profiles/AppSrv01/logs/nodeagent/SystemOut.log` |
| App Server | `/opt/IBM/WebSphere/AppServer/profiles/AppSrv01/logs/AppServer1/SystemOut.log` |
| FFDC | `/opt/IBM/WebSphere/AppServer/profiles/AppSrv01/logs/ffdc/` |
| IHS Access | `/opt/IBM/HTTPServer/logs/access_log` |
| IHS Error | `/opt/IBM/HTTPServer/logs/error_log` |
| WAS Plugin | `/opt/IBM/WebSphere/Plugins/logs/webserver1/http_plugin.log` |

---

## 2. Liberty on OKD — Daily Operations

### 2.1 Check Liberty Pod Health

```bash
# Pod status
oc get pods -n liberty-apps -l app.kubernetes.io/name=nexusliberty-app

# Detailed pod info
oc describe pod -l app.kubernetes.io/name=nexusliberty-app -n liberty-apps

# Health endpoints (from within cluster or via Route)
curl -k https://nexusliberty-app-liberty-apps.apps.nexuslab.nexuslab.local/health
curl -k https://nexusliberty-app-liberty-apps.apps.nexuslab.nexuslab.local/health/ready
curl -k https://nexusliberty-app-liberty-apps.apps.nexuslab.nexuslab.local/health/live
```

### 2.2 View Liberty Logs

```bash
# Stream logs from all Liberty pods
oc logs -f -l app.kubernetes.io/name=nexusliberty-app -n liberty-apps --all-containers

# Logs from a specific pod
oc logs nexusliberty-app-<hash> -n liberty-apps

# Previous container logs (after a crash)
oc logs nexusliberty-app-<hash> -n liberty-apps --previous

# JSON logs — parse with jq
oc logs nexusliberty-app-<hash> -n liberty-apps | jq '.message'
```

### 2.3 Scale Liberty Pods

```bash
# Scale up (e.g., for high traffic)
oc scale deployment nexusliberty-app --replicas=4 -n liberty-apps

# Scale back to normal
oc scale deployment nexusliberty-app --replicas=2 -n liberty-apps

# Or edit the CR directly (preferred — operator manages lifecycle)
oc edit WebSphereLibertyApplication nexusliberty-app -n liberty-apps
# Change spec.replicas to desired count
```

### 2.4 Rolling Restart

```bash
# Trigger a rolling restart without changing the image
oc rollout restart deployment/nexusliberty-app -n liberty-apps

# Watch rollout progress
oc rollout status deployment/nexusliberty-app -n liberty-apps
```

### 2.5 Check Metrics

```bash
# Prometheus metrics from a Liberty pod
oc exec nexusliberty-app-<hash> -n liberty-apps -- curl -s http://localhost:9080/metrics

# Key metrics to check
# base:memory_used_heap_bytes  — JVM heap usage
# base:cpu_process_cpu_load    — CPU utilization
# base:thread_count            — active thread count
# base:gc_time_total           — GC pause time
```

---

## 3. IHS Load Balancer Operations

### 3.1 Legacy IHS (Vagrant / On-Prem)

```bash
# Check IHS status
ssh wasadmin@nexus-ihs.nexuslab.local
/opt/IBM/HTTPServer/bin/apachectl status

# Restart IHS
/opt/IBM/HTTPServer/bin/apachectl restart

# Test plugin routing
curl -I http://nexus-ihs.nexuslab.local/app/
# Should return 200 with response from WAS backend

# Regenerate plugin-cfg.xml via Ansible
ansible-playbook -i ansible/inventory/hosts.ini \
  ansible/playbooks/ihs-install.yml --tags plugin
```

### 3.2 Containerized IHS (OKD)

```bash
# IHS pod status
oc get pods -l app.kubernetes.io/name=nexusliberty-ihs -n liberty-apps

# IHS logs
oc logs -f -l app.kubernetes.io/name=nexusliberty-ihs -n liberty-apps

# Test via Route
curl -I https://nexusliberty-ihs.apps.nexuslab.nexuslab.local/app/

# Health check
curl http://nexusliberty-ihs.apps.nexuslab.nexuslab.local/ihs-health
```

---

## 4. Session Replication — Hazelcast Verification

```bash
# Check Hazelcast cluster formation in Liberty logs
oc logs nexusliberty-app-<hash> -n liberty-apps | grep -i hazelcast | grep -i "Members"
# Should show: Members {size:2, [member1, member2]}

# Verify session failover:
# 1. Set a session value via the app
# 2. Note which pod served the request (check response headers or logs)
# 3. Delete that pod:
oc delete pod nexusliberty-app-<hash> -n liberty-apps
# 4. Hit the app again — session should persist on the remaining pod
```

---

## 5. Monitoring and Alerting

### 5.1 Verify Prometheus Scraping

```bash
# Confirm user workload monitoring is enabled
oc get pods -n openshift-user-workload-monitoring
# Should see prometheus-user-workload and thanos-ruler pods

# Check ServiceMonitor is picked up
oc get servicemonitor -n liberty-apps
# nexusliberty-app should be listed

# Check targets in Prometheus UI
# Navigate to: Observe → Targets in OKD console
# Filter by namespace: liberty-apps
# Status should show "UP" for Liberty endpoints
```

### 5.2 Verify Alert Rules

```bash
# List active PrometheusRules
oc get prometheusrule -n liberty-apps

# Check firing alerts
# OKD Console → Observe → Alerting
# Or via API:
oc exec -n openshift-user-workload-monitoring prometheus-user-workload-0 \
  -- curl -s http://localhost:9090/api/v1/alerts | jq '.data.alerts[] | select(.labels.app=="nexusliberty")'
```

### 5.3 Grafana Dashboard

```
# Access Grafana (if deployed via Grafana Operator)
# OKD Console → Networking → Routes → grafana (openshift-monitoring or custom namespace)

# Import dashboard manually:
# 1. Open Grafana → Dashboards → Import
# 2. Paste contents of openshift/monitoring/grafana-dashboard.yaml (the JSON in data field)
# 3. Select Prometheus datasource
# 4. Dashboard: "NexusLiberty — Liberty Application Metrics"
```

---

## 6. Troubleshooting

### 6.1 Liberty Pod Won't Start

```bash
# Check events
oc get events -n liberty-apps --sort-by=.metadata.creationTimestamp | tail -20

# Check SCC issues
oc get pod nexusliberty-app-<hash> -o yaml -n liberty-apps | grep scc

# Check image pull
oc describe pod nexusliberty-app-<hash> -n liberty-apps | grep -A5 "Events"

# Common fixes:
# Image pull error → verify GHCR credentials / image exists
# SCC denied → oc adm policy add-scc-to-serviceaccount restricted-v2 -z nexusliberty-sa -n liberty-apps
# OOMKilled → increase memory limits in WebSphereLibertyApplication CR
```

### 6.2 Session Replication Not Working

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

### 6.3 Metrics Not Appearing in Prometheus

```bash
# 1. Verify /metrics endpoint responds
oc exec nexusliberty-app-<hash> -n liberty-apps -- curl -s http://localhost:9080/metrics | head -20

# 2. Check ServiceMonitor selector matches the service labels
oc get svc -n liberty-apps --show-labels
oc get servicemonitor nexusliberty-app -n liberty-apps -o yaml | grep -A5 selector

# 3. Check Prometheus targets
# OKD Console → Observe → Targets → filter by liberty-apps

# 4. If targets show "down", check network policies
oc get networkpolicy -n liberty-apps
```

### 6.4 IHS Returning 503

```bash
# Containerized IHS — check Liberty backend is reachable
oc exec <ihs-pod> -n liberty-apps -- curl -s http://nexusliberty-app.liberty-apps.svc.cluster.local:9080/health

# Legacy IHS — check plugin-cfg.xml is current
cat /opt/IBM/WebSphere/Plugins/config/webserver1/plugin-cfg.xml
# Verify Server hostnames/ports match running WAS nodes

# Check IHS error log for upstream connection failures
oc logs <ihs-pod> -n liberty-apps | grep -i "proxy" | grep -iE "error|refused"
```

---

## 7. Disaster Recovery Procedures

### 7.1 Full Cluster Restore

```bash
# OKD etcd backup (run on a control plane node)
ssh core@okd-node1.nexuslab.nexuslab.local
sudo /usr/local/bin/cluster-backup.sh /home/core/backup/

# Restore from backup (emergency only — follow OKD docs)
# https://docs.okd.io/latest/backup_and_restore/
```

### 7.2 Liberty Application Rollback

```bash
# Check deployment history
oc rollout history deployment/nexusliberty-app -n liberty-apps

# Rollback to previous revision
oc rollout undo deployment/nexusliberty-app -n liberty-apps

# Rollback to specific revision
oc rollout undo deployment/nexusliberty-app --to-revision=3 -n liberty-apps

# If using Argo CD — revert the Git commit and let Argo sync
git revert HEAD
git push origin main
# Argo CD will detect the manifest change and sync
```

### 7.3 WAS Cell Recovery

```bash
# Restore DMGR config from backup
/opt/IBM/WebSphere/AppServer/bin/restoreConfig.sh /backup/was-config-backup.zip

# Resync nodes after DMGR restore
wsadmin.sh -lang jython -c "
nodeList = AdminConfig.list('Node').splitlines()
for node in nodeList:
    nodeName = AdminConfig.showAttribute(node, 'name')
    if nodeName != 'dmgr':
        AdminControl.invoke(AdminControl.queryNames('type=NodeSync,node=' + nodeName + ',*'), 'sync')
        print('Synced: ' + nodeName)
"
```
