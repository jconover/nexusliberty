# Runbook 02 — Deploy, Verify, and Rollback

Covers the full deploy lifecycle for the NexusLiberty application: how deploys are triggered, how to verify success, and how to roll back when something goes wrong. Use this when a deploy is in progress, has just completed, or needs to be undone.

---

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NAMESPACE` | `liberty-apps` | OKD namespace |
| `APP_NAME` | `nexusliberty-app` | OpenLibertyApplication CR name |
| `GHCR_IMAGE` | `ghcr.io/jconover/nexusliberty-app` | Container image repository |
| `ARGOCD_APP` | `nexusliberty-app` | Argo CD Application name |
| `GITHUB_REPO` | `jconover/nexusliberty` | GitHub repository |

---

## Prerequisites

- `oc` CLI authenticated with `edit` role (or higher) on `liberty-apps`
- Access to the GitHub repository (for pipeline triggers and git reverts)
- Access to the Argo CD UI or `argocd` CLI (optional, `oc` commands cover most operations)

---

## How Deploys Work

The deploy pipeline is fully automated via GitOps:

```
git push (app/ or docker/liberty-app/) 
  → GitHub Actions: maven build, hadolint, trivy scan
    → GitHub Actions (self-hosted runner on OKD): trigger Tekton PipelineRun
      → Tekton: clone → maven build → docker build → push to GHCR → update image tag in YAML
        → git commit updated WebSphereLibertyApplication.yaml to main
          → Argo CD detects manifest change → syncs to OKD
            → Liberty Operator performs rolling update (maxUnavailable=0, maxSurge=1)
```

**Key point:** The actual image tag update happens via Tekton's `git-update-manifest` task, which commits the new SHA-pinned image tag into `openshift/liberty-deployment/WebSphereLibertyApplication.yaml`. Argo CD watches that directory.

---

## Procedure

### Deploy Verification (after a deploy has been triggered)

#### Step 1 — Confirm the Pipeline Ran

```bash
# Check the latest PipelineRun
oc get pipelinerun -n liberty-apps --sort-by=.metadata.creationTimestamp -o wide | tail -3
```

**Expected output:** The most recent PipelineRun shows `Succeeded` under the `STATUS` column.

```
NAME                              SUCCEEDED   REASON      STARTTIME   COMPLETIONTIME
liberty-build-run-20260411-1234   True        Succeeded   10m         5m
```

If the PipelineRun shows `Failed`, inspect the failed task:

```bash
PIPELINE_RUN=$(oc get pipelinerun -n liberty-apps --sort-by=.metadata.creationTimestamp -o name | tail -1)
oc describe ${PIPELINE_RUN} -n liberty-apps
```

#### Step 2 — Confirm Argo CD Sync

```bash
# Check Argo CD Application health and sync status
oc get application nexusliberty-app -n openshift-gitops -o jsonpath='{.status.sync.status}{"\n"}{.status.health.status}{"\n"}'
```

**Expected output:**

```
Synced
Healthy
```

If it shows `OutOfSync`, Argo CD has not yet picked up the manifest change. It polls every 3 minutes by default. Force a sync:

```bash
oc annotate application nexusliberty-app -n openshift-gitops argocd.argoproj.io/refresh=hard --overwrite
```

#### Step 3 — Confirm Rolling Update Progress

```bash
oc rollout status deployment/nexusliberty-app -n liberty-apps --timeout=300s
```

**Expected output:**

```
deployment "nexusliberty-app" successfully rolled out
```

If the rollout is stuck, check what is happening:

```bash
oc get pods -n liberty-apps -l app.kubernetes.io/name=nexusliberty-app -o wide
oc get events -n liberty-apps --sort-by=.lastTimestamp | tail -20
```

With `maxUnavailable=0` and `maxSurge=1`, the rolling update creates one new pod, waits for it to pass readiness, then terminates one old pod. If the new pod never becomes ready, the rollout stalls and old pods continue serving.

#### Step 4 — Verify the Deployed Image

```bash
oc get pods -n liberty-apps -l app.kubernetes.io/name=nexusliberty-app \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'
```

**Expected output:** Both pods show the same image with the new SHA tag.

```
nexusliberty-app-6d8f4b7c9-abc12   ghcr.io/jconover/nexusliberty-app:sha-<NEW_SHA>
nexusliberty-app-6d8f4b7c9-def34   ghcr.io/jconover/nexusliberty-app:sha-<NEW_SHA>
```

If pods show different image tags, the rolling update is still in progress.

#### Step 5 — Verify Liberty Startup Markers

Every Liberty server logs specific message codes on successful startup. Confirm both pods have them:

```bash
for POD in $(oc get pods -n liberty-apps -l app.kubernetes.io/name=nexusliberty-app -o jsonpath='{.items[*].metadata.name}'); do
  echo "=== ${POD} ==="
  oc logs -n liberty-apps ${POD} | grep -E "CWWKF0011I|CWWKT0016I" | tail -2
done
```

**Expected output per pod:**

```
[INFO] CWWKT0016I: Web application available (default_host): http://0.0.0.0:9080/app/
[INFO] CWWKF0011I: The nexusliberty-app server is ready to run a smarter planet. ...
```

- `CWWKT0016I` — web application bound and available at context root
- `CWWKF0011I` — server startup complete, all features resolved, ready for traffic

If these messages are missing, the server did not fully start. Check for error codes:

```bash
oc logs -n liberty-apps ${POD} | grep -E "CWWK[A-Z][0-9]{4}E"
```

#### Step 6 — Verify Application Endpoint

```bash
ROUTE_HOST=$(oc get route -n liberty-apps nexusliberty-app -o jsonpath='{.spec.host}')

# Hit the health endpoints
curl -sk "https://${ROUTE_HOST}/health/ready"
curl -sk "https://${ROUTE_HOST}/health/live"

# Hit the application endpoints
curl -sk "https://${ROUTE_HOST}/app/api/health"
curl -sk "https://${ROUTE_HOST}/app/api/info"
```

**Expected output:** HTTP 200 with JSON response bodies. If you get 503, the pods may not have registered with the router yet — wait 30 seconds and retry.

#### Step 7 — Check for Errors Post-Deploy

```bash
for POD in $(oc get pods -n liberty-apps -l app.kubernetes.io/name=nexusliberty-app -o jsonpath='{.items[*].metadata.name}'); do
  echo "=== ${POD} ==="
  oc logs -n liberty-apps ${POD} --since=10m | grep -cE '"loglevel":"(ERROR|WARNING)"'
done
```

**Expected output:** `0` for each pod. A non-zero count warrants reviewing the actual messages.

---

## Triggering a Manual Deploy

### Re-run the GitHub Actions Pipeline

Go to `https://github.com/<GITHUB_REPO>/actions` → select "Liberty CI" → click "Re-run all jobs" on the latest main-branch run.

### Trigger Tekton Directly (skip GitHub Actions)

If the image is already in GHCR and you just need to redeploy:

```bash
oc create -f openshift/pipelines/06-pipelinerun-template.yaml -n liberty-apps
```

### Force Argo CD to Re-sync

If the manifest is already updated but Argo CD has not synced:

```bash
# Hard refresh — forces Argo CD to re-read the repo and re-apply
oc annotate application nexusliberty-app -n openshift-gitops argocd.argoproj.io/refresh=hard --overwrite
```

---

## Rollback Procedures

### Option A — Rollback via `oc rollout undo` (fastest, 30 seconds)

Use when: The bad deploy just happened and you need to revert immediately. This rolls back the Deployment to the previous ReplicaSet.

```bash
# Undo the last rollout
oc rollout undo deployment/nexusliberty-app -n liberty-apps

# Watch it complete
oc rollout status deployment/nexusliberty-app -n liberty-apps --timeout=300s

# Verify pods are running the previous image
oc get pods -n liberty-apps -l app.kubernetes.io/name=nexusliberty-app \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'
```

**Important:** This is a temporary fix. Argo CD will detect the drift and re-sync the bad image within 3 minutes. You must also fix the source of truth (the YAML in git). Pause Argo CD auto-sync to buy time:

```bash
oc patch application nexusliberty-app -n openshift-gitops \
  --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
```

Re-enable auto-sync after fixing the manifest in git:

```bash
oc patch application nexusliberty-app -n openshift-gitops \
  --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
```

### Option B — Rollback via Git Revert (correct, 5 minutes)

Use when: You have time and want the rollback to flow through the normal GitOps pipeline. This is the cleanest approach.

```bash
# Find the commit that updated the image tag
git log --oneline -5 openshift/liberty-deployment/WebSphereLibertyApplication.yaml

# Revert the bad commit
git revert <BAD_COMMIT_SHA> --no-edit

# Push to main — this triggers the normal Argo CD sync
git push origin main
```

Argo CD detects the reverted manifest and rolls the deployment back to the previous image.

### Option C — Rollback via Direct Manifest Edit (when git access is unavailable)

Use when: Git is down or inaccessible and you need to act now.

```bash
# Get the previous image tag from the old ReplicaSet
oc get replicasets -n liberty-apps -l app.kubernetes.io/name=nexusliberty-app \
  --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-2].spec.template.spec.containers[0].image}'
```

```bash
# Patch the CR directly with the old image
oc patch OpenLibertyApplication nexusliberty-app -n liberty-apps \
  --type merge -p '{"spec":{"applicationImage":"ghcr.io/jconover/nexusliberty-app:<PREVIOUS_TAG>"}}'
```

**Important:** Same Argo CD drift caveat as Option A. Pause auto-sync first if you do not want Argo CD to overwrite your manual fix.

### When to Use Which Rollback

| Scenario | Method | Time to Restore |
|----------|--------|-----------------|
| App is down, need immediate recovery | Option A (`oc rollout undo`) + pause Argo CD | ~30 seconds |
| Bad deploy, app is degraded but serving | Option B (git revert) | ~5 minutes |
| Git is down, need to act now | Option C (direct patch) + pause Argo CD | ~1 minute |

---

## Post-Rollback Verification

After any rollback, run through these steps:

1. Confirm pods are Running and Ready:
   ```bash
   oc get pods -n liberty-apps -l app.kubernetes.io/name=nexusliberty-app
   ```

2. Confirm Liberty startup markers are present (Step 5 above).

3. Hit the health and application endpoints (Step 6 above).

4. Check Grafana for error rate returning to zero.

5. Verify Argo CD is back in sync (if you used Option B):
   ```bash
   oc get application nexusliberty-app -n openshift-gitops \
     -o jsonpath='{.status.sync.status}'
   ```
   Expected: `Synced`

6. If you paused Argo CD auto-sync (Options A/C), re-enable it after fixing the source manifest in git.

---

## Troubleshooting

**Rollout is stuck — new pod never becomes Ready:**
The startup probe gives Liberty up to 5 minutes (30 failures x 10s interval) before killing it. If the pod sits in `0/1 Running` for more than 5 minutes, the startup probe will fail and the pod will restart. Check logs:
```bash
POD=$(oc get pods -n liberty-apps --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
oc logs -n liberty-apps ${POD}
```

**Argo CD shows `OutOfSync` after rollback:**
Expected if you used Option A or C. The live state no longer matches git. Either revert git (Option B) or pause auto-sync and fix the manifest.

**Image pull fails (ImagePullBackOff):**
The GHCR image tag does not exist. Verify the tag:
```bash
oc get pods -n liberty-apps -l app.kubernetes.io/name=nexusliberty-app \
  -o jsonpath='{.items[0].spec.containers[0].image}'
```
Check if the image exists in GHCR. If the tag was never pushed, the pipeline failed during the push step — check the PipelineRun or GitHub Actions logs.

**Old ReplicaSet not available for undo:**
OKD keeps a limited revision history (default 10). If the good revision has been garbage collected:
```bash
oc get replicasets -n liberty-apps -l app.kubernetes.io/name=nexusliberty-app \
  --sort-by=.metadata.creationTimestamp
```
If the old ReplicaSet is gone, use Option B (git revert) or Option C with a known-good image tag from GHCR.

---

## Escalation

Stop and escalate if:
- The rollback itself fails (new pod crash-loops on the old image too) — the problem may not be the deploy, engage the platform team
- Argo CD is in a sync loop (syncing, drifting, re-syncing) — check `ignoreDifferences` in the Argo CD Application CR, contact the GitOps admin
- The pipeline is producing images that fail security scans but auto-deploying anyway — disable the pipeline and investigate

---

## Related Runbooks

- [01 — Health Check](01-health-check.md) — verify application health after deploy or rollback
- [03 — Pod Failure and Recovery](03-pod-failure-and-recovery.md) — if the new pod fails to start
- [04 — Scaling and Performance](04-scaling-and-performance.md) — if the new deploy introduced a performance regression
