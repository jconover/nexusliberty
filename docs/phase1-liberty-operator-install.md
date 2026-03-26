# Phase 1: WebSphere Liberty Operator Install + Sample App

Step-by-step guide to install the IBM WebSphere Liberty Operator on OKD and deploy a sample app.

## Prerequisites

- OKD cluster healthy (`oc get clusteroperators` — all AVAILABLE=True)
- `oc` CLI installed and logged in:
  ```bash
  oc login https://api.nexuslab.nexuslab.local:6443 --username kubeadmin --password <password>
  ```

## Step 1: Create the liberty-apps namespace

```bash
oc apply -f cluster/namespace/liberty-apps.yaml
```

Verify:
```bash
oc get namespace liberty-apps
```

## Step 2: Add IBM Operator Catalog

OKD doesn't include IBM's certified operator catalog by default (commercial OpenShift does). This adds it to OLM.

```bash
oc apply -f cluster/operators/ibm-operator-catalog.yaml
```

Wait for the catalog pod to be running (~2-3 minutes):
```bash
oc get pods -n openshift-marketplace | grep ibm
```

You should see something like:
```
ibm-operator-catalog-xxxxx   1/1   Running   0   2m
```

**Troubleshooting:** If the pod is stuck in `ImagePullBackOff`:
```bash
oc get events -n openshift-marketplace --sort-by='.lastTimestamp' | grep ibm
```
This usually means a network/DNS issue pulling `icr.io/cpopen/ibm-operator-catalog`. Verify your nodes can reach `icr.io`.

## Step 3: Install the Liberty Operator

This creates an OperatorGroup (scopes to liberty-apps) and a Subscription (triggers OLM to install the operator).

```bash
oc apply -f cluster/operators/websphere-liberty-operator.yaml
```

Watch the ClusterServiceVersion (CSV) until it shows `Succeeded` (~3-5 minutes):
```bash
oc get csv -n liberty-apps -w
```

Expected output:
```
NAME                          DISPLAY                    VERSION   PHASE
ibm-websphere-liberty.v1.3.x  IBM WebSphere Liberty      1.3.x     Succeeded
```

Verify the operator pod is running:
```bash
oc get pods -n liberty-apps
```

**Troubleshooting:** If CSV stays in `Pending` or `InstallReady`:
```bash
# Check if the channel exists in the catalog
oc get packagemanifest ibm-websphere-liberty -n openshift-marketplace -o jsonpath='{.status.channels[*].name}'
```
If `v1.3` isn't listed, update the `channel` field in `cluster/operators/websphere-liberty-operator.yaml` to match what's available, then re-apply.

## Step 4: Deploy the Sample App

This uses IBM's official Open Liberty getting-started sample image — no container build needed.

```bash
oc apply -f openshift/liberty-deployment/WebSphereLibertyApplication.yaml
```

Watch the pod start:
```bash
oc get pods -n liberty-apps -w
```

Wait for `1/1 Running` status. First pull may take a few minutes.

## Step 5: Verify the Route

The Liberty Operator automatically creates a Route when `expose: true` is set.

> **Important:** The operator defaults to `reencrypt` TLS termination, which requires the pod to serve HTTPS. Since the sample app only serves HTTP on port 9080, the CR sets `route.termination: edge` — TLS terminates at the OKD router and plain HTTP is forwarded to the pod. Without this, the Route will show "Application is not available".

```bash
oc get routes -n liberty-apps
```

Expected output:
```
NAME                  HOST/PORT                                                      PATH   SERVICES              PORT       TERMINATION
nexusliberty-sample   nexusliberty-sample-liberty-apps.apps.nexuslab.nexuslab.local          nexusliberty-sample   9080-tcp   edge
```

**DNS:** Your workstation needs to resolve `*.apps.nexuslab.nexuslab.local` to the ingress VIP (`192.168.68.101`). Add to `/etc/hosts` (Linux/Mac) or `C:\Windows\System32\drivers\etc\hosts` (Windows):
```
192.168.68.101 nexusliberty-sample-liberty-apps.apps.nexuslab.nexuslab.local
```

Test the app (note: `edge` route requires HTTPS on the client side, use `-k` to skip cert validation):
```bash
curl -k https://nexusliberty-sample-liberty-apps.apps.nexuslab.nexuslab.local/
```

Test health endpoints:
```bash
curl -k https://nexusliberty-sample-liberty-apps.apps.nexuslab.nexuslab.local/health/ready
curl -k https://nexusliberty-sample-liberty-apps.apps.nexuslab.nexuslab.local/health/live
```

Both should return `{"status":"UP",...}`.

## Step 6: Validate Everything

Run this checklist to confirm Phase 1 completion:

```bash
echo "=== Cluster Operators ==="
oc get clusteroperators | grep -v "True.*False.*False" || echo "All healthy"

echo ""
echo "=== IBM Catalog ==="
oc get catalogsource ibm-operator-catalog -n openshift-marketplace

echo ""
echo "=== Liberty Operator CSV ==="
oc get csv -n liberty-apps

echo ""
echo "=== Liberty App ==="
oc get WebSphereLibertyApplication -n liberty-apps

echo ""
echo "=== Pods ==="
oc get pods -n liberty-apps

echo ""
echo "=== Route ==="
oc get routes -n liberty-apps
```

## Cleanup (if needed)

To tear down and start over:
```bash
oc delete -f openshift/liberty-deployment/WebSphereLibertyApplication.yaml
oc delete -f cluster/operators/websphere-liberty-operator.yaml
oc delete -f cluster/operators/ibm-operator-catalog.yaml
oc delete -f cluster/namespace/liberty-apps.yaml
```

## What's Next (Phase 2)

Once this works end-to-end, Phase 2 replaces the sample image with our own:
- Write a Dockerfile for Liberty + custom Java app
- Configure server.xml
- Push to GHCR (`ghcr.io/jconover/nexusliberty-app`)
- Update the WebSphereLibertyApplication CR to point to our image
