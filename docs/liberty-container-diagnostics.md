# Liberty Container Diagnostics on OpenShift

How to get inside Liberty pods and diagnose JVM, application, and configuration issues. This replaces the SSH + wsadmin workflow from WAS ND.

---

## Key Difference from WAS ND

| WAS ND (legacy) | Liberty on OpenShift |
|---|---|
| SSH to the server, fix it in place | `oc exec` into the pod, diagnose, fix in source code |
| wsadmin to manage server config | No wsadmin — everything is in `server.xml` |
| Fixes persist on the server | Pods are disposable — fixes must go through CI/CD |
| One server, one identity | Multiple pod replicas, any can be replaced |

**Liberty does not use wsadmin.** There is no Deployment Manager, no admin console, no admin service. Configuration is declarative via `server.xml` and environment variables.

The diagnostic workflow is:
1. `oc exec` into the pod to **diagnose**
2. Fix the root cause in source (`server.xml`, app code, Dockerfile, CR)
3. Push to Git → CI/CD rebuilds the image → new pods roll out with the fix

---

## Getting Into a Pod

```bash
# List Liberty pods
oc get pods -n liberty-apps -l app.kubernetes.io/name=nexusliberty-app

# Interactive shell into a running pod
oc exec -it <pod-name> -n liberty-apps -- bash

# If bash isn't available (minimal image), try sh
oc exec -it <pod-name> -n liberty-apps -- sh

# Run a single command without an interactive shell
oc exec <pod-name> -n liberty-apps -- cat /opt/ol/wlp/usr/servers/defaultServer/server.xml
```

---

## Liberty File Locations Inside the Pod

| What | Path |
|---|---|
| Liberty install | `/opt/ol/wlp/` |
| Server config | `/opt/ol/wlp/usr/servers/defaultServer/server.xml` |
| Server env vars | `/opt/ol/wlp/usr/servers/defaultServer/server.env` |
| JVM options | `/opt/ol/wlp/usr/servers/defaultServer/jvm.options` |
| Message log | `/opt/ol/wlp/output/defaultServer/logs/messages.log` |
| FFDC (first failure) | `/opt/ol/wlp/output/defaultServer/logs/ffdc/` |
| Trace log | `/opt/ol/wlp/output/defaultServer/logs/trace.log` |
| App dropins | `/opt/ol/wlp/usr/servers/defaultServer/dropins/` |
| App installed | `/opt/ol/wlp/usr/servers/defaultServer/apps/` |
| Shared libraries | `/opt/ol/wlp/usr/shared/resources/` |
| Hazelcast JARs | `/opt/ol/wlp/usr/shared/resources/hazelcast/` |

---

## Viewing Logs

```bash
# Stream logs from all Liberty pods (best for watching live)
oc logs -f -l app.kubernetes.io/name=nexusliberty-app -n liberty-apps --all-containers

# Logs from a specific pod
oc logs <pod-name> -n liberty-apps

# Previous container logs (after a crash/restart)
oc logs <pod-name> -n liberty-apps --previous

# Filter JSON logs with jq
oc logs <pod-name> -n liberty-apps | jq '.message'

# Search for errors
oc logs <pod-name> -n liberty-apps | grep -iE "error|exception|FFDC"

# From inside the pod — raw message log (not JSON)
cat /opt/ol/wlp/output/defaultServer/logs/messages.log

# FFDC reports (detailed first-failure dumps)
ls /opt/ol/wlp/output/defaultServer/logs/ffdc/
cat /opt/ol/wlp/output/defaultServer/logs/ffdc/*.log
```

---

## JVM Diagnostics

These commands run **inside** the pod (after `oc exec -it <pod> -- bash`). The JVM process is always PID 1 in a container.

### Thread Dumps — Find Deadlocks and Stuck Threads

```bash
# Using jstack (if JDK tools are in the image)
jstack 1

# Look for deadlocks specifically
jstack 1 | grep -A 20 "Found one Java-level deadlock"

# Look for blocked/waiting threads
jstack 1 | grep -E "BLOCKED|WAITING" | sort | uniq -c | sort -rn

# Without JDK tools — send SIGQUIT to trigger a thread dump
# Liberty writes it to messages.log or stdout
kill -3 1

# Take multiple thread dumps to spot stuck patterns (3 dumps, 10 seconds apart)
for i in 1 2 3; do jstack 1 > /tmp/threads_$i.txt; sleep 10; done
diff /tmp/threads_1.txt /tmp/threads_2.txt
```

### Heap Analysis — Memory Issues

```bash
# Heap summary (quick check)
jmap -heap 1

# Object histogram — what's eating memory (top 20)
jmap -histo 1 | head -25

# Live objects only (forces a GC first)
jmap -histo:live 1 | head -25

# Full heap dump (WARNING: can be large, may pause the JVM)
# Only do this if you have enough disk space in the container
jmap -dump:format=b,file=/tmp/heapdump.hprof 1

# Copy heap dump out of the pod for analysis
# (run this from your workstation, not inside the pod)
oc cp liberty-apps/<pod-name>:/tmp/heapdump.hprof ./heapdump.hprof
# Then open with Eclipse MAT, VisualVM, or jhat
```

### GC Stats — Garbage Collection Performance

```bash
# Live GC stats (updates every 2 seconds, 10 samples)
jstat -gc 1 2000 10

# Key columns:
#   S0U/S1U  = Survivor space used (bytes)
#   EU       = Eden used
#   OU       = Old gen used
#   GCT      = Total GC time (seconds)
#   YGCT     = Young gen GC time
#   FGCT     = Full GC time (if this is high, you have a problem)

# GC capacity (max sizes)
jstat -gccapacity 1

# GC cause (what triggered the last GC)
jstat -gccause 1 2000 5
```

### CPU and Process Info

```bash
# JVM system properties
jinfo 1

# Specific property
jinfo -sysprops 1 | grep "java.version"

# JVM flags (heap size, GC algorithm, etc.)
jinfo -flags 1

# CPU per thread (find hot threads)
top -H -p 1 -bn1 | head -20

# Convert thread TID (decimal) to hex for matching with jstack output
printf "0x%x\n" <tid-from-top>
# Then search jstack output: jstack 1 | grep -A 30 "nid=0x<hex>"
```

---

## Common Diagnostic Scenarios

### Pod Keeps Restarting (OOMKilled)

```bash
# 1. Check the exit code — 137 means OOMKilled
oc describe pod <pod> -n liberty-apps | grep -A 5 "Last State"

# 2. Check current memory limits
oc get pod <pod> -n liberty-apps -o jsonpath='{.spec.containers[0].resources}'

# 3. Exec in (if the pod is running) and check heap
oc exec <pod> -n liberty-apps -- jmap -heap 1

# 4. Check if heap max is close to container memory limit
#    JVM heap + metaspace + native memory must fit within the container limit
#    Rule of thumb: set -Xmx to ~75% of container memory limit

# Fix: increase memory limits in WebSphereLibertyApplication CR
#   spec.resources.limits.memory: "1Gi"  (was 768Mi)
# Or tune JVM: add -Xmx512m to jvm.options
```

### Application Returning 500 Errors

```bash
# 1. Check logs for stack traces
oc logs <pod> -n liberty-apps | grep -B 2 -A 20 "Exception"

# 2. Check FFDC reports (Liberty's automatic first-failure capture)
oc exec <pod> -n liberty-apps -- ls -la /opt/ol/wlp/output/defaultServer/logs/ffdc/
oc exec <pod> -n liberty-apps -- cat /opt/ol/wlp/output/defaultServer/logs/ffdc/*.log

# 3. Check if the app actually deployed
oc exec <pod> -n liberty-apps -- ls /opt/ol/wlp/usr/servers/defaultServer/apps/

# 4. Check server.xml for config errors
oc exec <pod> -n liberty-apps -- cat /opt/ol/wlp/usr/servers/defaultServer/server.xml
```

### Slow Response Times

```bash
# 1. Take thread dumps to find blocked threads
oc exec <pod> -n liberty-apps -- jstack 1 | grep -E "BLOCKED|WAITING" | sort | uniq -c | sort -rn

# 2. Check GC pauses (high FGCT = full GC stalls)
oc exec <pod> -n liberty-apps -- jstat -gc 1 2000 5

# 3. Check connection pools — are threads waiting for DB connections?
oc logs <pod> -n liberty-apps | grep -i "connection.*wait\|pool.*full\|timeout"

# 4. Check metrics endpoint for request latency
oc exec <pod> -n liberty-apps -- curl -s http://localhost:9080/metrics | grep "request"
```

### Hazelcast Session Clustering Not Working

```bash
# 1. Check if Hazelcast JARs are present
oc exec <pod> -n liberty-apps -- ls /opt/ol/wlp/usr/shared/resources/hazelcast/

# 2. Check logs for cluster formation
oc logs <pod> -n liberty-apps | grep -i hazelcast | grep -iE "Members|cluster"
# Should see: Members {size:2, [member1, member2]}

# 3. Check for discovery errors
oc logs <pod> -n liberty-apps | grep -i hazelcast | grep -iE "error|warn|exception"

# 4. Verify RBAC — SA must be able to list pods for K8s discovery
oc auth can-i list pods --as=system:serviceaccount:liberty-apps:nexusliberty-sa -n liberty-apps
# Must return: yes

# 5. Check the Hazelcast config
oc exec <pod> -n liberty-apps -- cat /opt/ol/wlp/usr/shared/resources/hazelcast/hazelcast.xml
```

### Liberty Won't Start

```bash
# 1. Check events for scheduling/image issues
oc get events -n liberty-apps --sort-by=.metadata.creationTimestamp | tail -20

# 2. Check SCC (Security Context Constraints) — OpenShift specific
oc get pod <pod> -n liberty-apps -o yaml | grep scc

# 3. Check image pull status
oc describe pod <pod> -n liberty-apps | grep -A 5 "Events"

# 4. Check Liberty server status from inside (if container is running)
oc exec <pod> -n liberty-apps -- /opt/ol/wlp/bin/server status defaultServer

# 5. Check messages.log for startup errors
oc exec <pod> -n liberty-apps -- cat /opt/ol/wlp/output/defaultServer/logs/messages.log | head -50

# Common causes:
#   ImagePullBackOff → GHCR credentials or image tag wrong
#   CrashLoopBackOff → server.xml config error, check messages.log
#   SCC denied → oc adm policy add-scc-to-serviceaccount restricted-v2 -z nexusliberty-sa -n liberty-apps
#   OOMKilled → increase memory limits in CR
```

### Config Change Without Rebuilding the Image

```bash
# For quick testing only — changes are lost when the pod restarts!

# Edit server.xml inside the pod
oc exec -it <pod> -n liberty-apps -- vi /opt/ol/wlp/usr/servers/defaultServer/server.xml

# Liberty has dynamic config reload — most changes take effect within 5 seconds
# Watch for the config update message:
oc logs -f <pod> -n liberty-apps | grep "CWWKG0017I"
# CWWKG0017I = "The server configuration was successfully updated"

# Once you've confirmed the fix, make the same change in your source files
# and push through CI/CD so it persists
```

---

## Enabling Tracing (Temporary)

Liberty supports dynamic trace control without restarting the server.

```bash
# From inside the pod — enable detailed tracing for a specific package
# This writes to /opt/ol/wlp/output/defaultServer/logs/trace.log

# Example: trace all JAX-RS requests
oc exec <pod> -n liberty-apps -- /opt/ol/wlp/bin/server dump defaultServer --include=thread

# Or edit server.xml to add a trace spec temporarily:
#   <logging traceSpecification="*=info:com.ibm.ws.webcontainer*=all" />

# Check the trace log
oc exec <pod> -n liberty-apps -- tail -100 /opt/ol/wlp/output/defaultServer/logs/trace.log
```

---

## Copying Files Out of a Pod

```bash
# Copy a file from pod to your workstation
oc cp liberty-apps/<pod-name>:/opt/ol/wlp/output/defaultServer/logs/messages.log ./messages.log

# Copy a heap dump
oc cp liberty-apps/<pod-name>:/tmp/heapdump.hprof ./heapdump.hprof

# Copy FFDC files
oc cp liberty-apps/<pod-name>:/opt/ol/wlp/output/defaultServer/logs/ffdc/ ./ffdc/
```

---

## MicroProfile Endpoints (No SSH Needed)

These are REST endpoints built into Liberty — check them before exec'ing into the pod.

```bash
# Health checks (via OpenShift Route)
curl -k https://nexusliberty-app-liberty-apps.apps.nexuslab.nexuslab.local/health
curl -k https://nexusliberty-app-liberty-apps.apps.nexuslab.nexuslab.local/health/ready
curl -k https://nexusliberty-app-liberty-apps.apps.nexuslab.nexuslab.local/health/live

# Metrics (Prometheus format)
curl -k https://nexusliberty-app-liberty-apps.apps.nexuslab.nexuslab.local/metrics

# From inside the cluster (no TLS)
oc exec <pod> -n liberty-apps -- curl -s http://localhost:9080/metrics
oc exec <pod> -n liberty-apps -- curl -s http://localhost:9080/health
```

---

## Quick Reference: WAS ND Command → Liberty/OKD Equivalent

| WAS ND task | WAS ND command | Liberty on OKD equivalent |
|---|---|---|
| Check server status | `serverStatus.sh -all` via SSH | `oc get pods -n liberty-apps` |
| Thread dump | `wsadmin` → `AdminControl.invoke(jvm, 'dumpThreads')` | `oc exec <pod> -- jstack 1` |
| Heap dump | `wsadmin` → `AdminControl.invoke(jvm, 'generateHeapDump')` | `oc exec <pod> -- jmap -dump:format=b,file=/tmp/heap.hprof 1` |
| View logs | SSH + `tail -f SystemOut.log` | `oc logs -f <pod>` |
| Check config | Admin console or `wsadmin` | `oc exec <pod> -- cat .../server.xml` |
| Deploy app | `wsadmin` → `AdminApp.install()` | Git push → CI/CD → Argo CD sync |
| Restart server | SSH + `stopServer`/`startServer` | `oc rollout restart deployment/nexusliberty-app` |
| Restart node agent | SSH + `stopNode`/`startNode` | N/A — no node agents in Liberty |
| GC tuning | `wsadmin` → JVM custom properties | `jvm.options` file in container image |
| Change log level | Admin console or `wsadmin` | Edit `server.xml` `<logging>` element |
