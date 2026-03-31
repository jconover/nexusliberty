# Phase 4: CI/CD Pipeline — GitHub Actions + Tekton + Argo CD

Step-by-step guide to set up the enterprise CI/CD pipeline: GitHub Actions for pre-merge quality gates, Tekton (OpenShift Pipelines) for on-cluster container builds, and Argo CD for GitOps deployment to OKD.

## Prerequisites

- Phase 1-3 complete (OKD cluster running, Liberty app deployed, Ansible automation working)
- `oc` CLI installed and authenticated to the OKD cluster
- GitHub repository with push access (`github.com/jconover/nexusliberty`)
- GHCR (GitHub Container Registry) accessible from OKD nodes

## Architecture

```
GitHub Actions          Tekton/OpenShift Pipelines      ArgoCD
──────────────          ──────────────────────────      ──────
Code quality gates  →   Build Liberty container     →   Deploy to OKD
Ansible lint            Run tests                       GitOps sync
Unit tests              Push to GHCR                    Health checks
Dockerfile lint         Commit updated image tag        Self-heal / Rollback
```

### How It Flows

```
Developer pushes PR
  → GitHub Actions: lint, unit tests, Dockerfile lint (pre-merge gates)
  → PR approved + merged to main

Merge to main
  → GitHub Actions: quality gates pass
  → GitHub Actions: triggers Tekton PipelineRun via oc CLI
  → Tekton Pipeline (runs on OKD cluster):
      1. git-clone — checkout repo
      2. maven-build — compile + package the Java app
      3. buildah — build container image + push to GHCR
      4. git-update-manifest — commit new image tag to repo
  → ArgoCD detects manifest change in Git
  → ArgoCD syncs deployment to liberty-apps namespace
  → Health checks confirm rollout
```

This separation keeps:
- **Quality gates** in GitHub (fast, cloud-hosted, runs on every PR)
- **Container builds** inside the cluster security boundary (Tekton)
- **Deployments** driven by Git as single source of truth (ArgoCD)

---

## Step 1 — Install OpenShift Pipelines Operator

The OpenShift Pipelines operator provides Tekton on the cluster.

```bash
# Apply the subscription (you may have already done this via OperatorHub UI)
oc apply -f cluster/operators/openshift-pipelines-subscription.yaml

# Watch for the operator to install (~2-3 minutes)
oc get csv -n openshift-operators -w
# Expected: openshift-pipelines-operator-rh.v1.x.x   Succeeded

# Verify Tekton pipelines are available
oc get pods -n openshift-pipelines
tkn version  # If tkn CLI is installed
```

## Step 2 — Install Builds for Red Hat OpenShift Operator (Optional)

Provides the Shipwright Build API for declarative image builds. Useful alongside Tekton for additional build strategies.

```bash
oc apply -f cluster/operators/builds-for-openshift-subscription.yaml

# Watch for install
oc get csv -n openshift-operators -w
# Expected: builds-for-openshift-operator.v1.x.x   Succeeded
```

## Step 3 — Install OpenShift GitOps Operator (Argo CD)

```bash
# Apply the operator subscription
oc apply -f cluster/gitops/openshift-gitops-subscription.yaml

# Watch the operator install (~2-3 minutes)
oc get csv -n openshift-operators -w
# Expected: openshift-gitops-operator.v1.x.x   Succeeded

# Troubleshooting: If the CSV never appears, check OLM resolution status:
oc get subscription openshift-gitops-operator -n openshift-operators -o jsonpath='{.status.conditions}' | jq .
# A ResolutionFailed condition means another subscription is blocking OLM.
# Common cause: a subscription with an incorrect package name (e.g.,
# builds-for-openshift-operator vs the correct openshift-builds-operator).
# Fix: delete the broken subscription, correct the package name, and reapply.
```

### Verify Argo CD is running

```bash
# Check the GitOps namespace
oc get namespace openshift-gitops

# Check Argo CD pods
oc get pods -n openshift-gitops
# All pods should be Running
```

### Get the Argo CD admin password

```bash
oc extract secret/openshift-gitops-cluster -n openshift-gitops --to=-
```

### Access the Argo CD UI

```bash
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'
# Expected: openshift-gitops-server-openshift-gitops.apps.nexuslab.nexuslab.local
```

Open in browser with the admin credentials above.

## Step 4 — Set Up Tekton Pipeline Resources

Apply the Tekton resources in order. The numbered filenames ensure correct dependency ordering.

### 4a — RBAC (ServiceAccount + permissions)

```bash
oc apply -f openshift/pipelines/01-rbac.yaml

# Verify
oc get serviceaccount liberty-pipeline-sa -n liberty-apps
oc get rolebinding liberty-pipeline-edit -n liberty-apps
```

### 4b — Workspace PVC

```bash
oc apply -f openshift/pipelines/02-pvc.yaml

# Verify
oc get pvc liberty-pipeline-workspace -n liberty-apps
```

### 4c — Secrets (GHCR + Git credentials)

**Before applying**, copy the example file and add your real token:
```bash
cp openshift/pipelines/03-secrets.yaml.example openshift/pipelines/03-secrets.yaml
```

Edit `openshift/pipelines/03-secrets.yaml` and replace `<GITHUB_PAT>` with a personal access token:
- Token needs scopes: `write:packages` (GHCR push) and `repo` or `contents:write` (Git push)
- Generate at: Settings → Developer Settings → Personal Access Tokens → Fine-grained tokens
- The real secrets file is gitignored — only the `.example` template is committed

```bash
oc apply -f openshift/pipelines/03-secrets.yaml

# Link secrets to the pipeline ServiceAccount
oc secrets link liberty-pipeline-sa ghcr-credentials --for=pull,mount -n liberty-apps
oc secrets link liberty-pipeline-sa git-credentials -n liberty-apps

# Verify
oc get secrets -n liberty-apps | grep -E 'ghcr|git'
```

> **Important:** Do not commit the secrets file with real tokens. Either use `oc create secret` directly or use sealed-secrets/external-secrets in production.

### 4d — Custom Task (git-update-manifest)

```bash
oc apply -f openshift/pipelines/04-task-git-update-manifest.yaml

# Verify
oc get task git-update-manifest -n liberty-apps
```

### 4e — Pipeline

```bash
oc apply -f openshift/pipelines/05-pipeline.yaml

# Verify
oc get pipeline liberty-build-pipeline -n liberty-apps

# Check available Tasks (provided by OpenShift Pipelines operator in openshift-pipelines namespace)
# Note: ClusterTasks were removed in Pipelines v1.21+; tasks are now namespace-scoped
oc get task -n openshift-pipelines | grep -E 'git-clone|maven|buildah'
```

## Step 5 — Apply Argo CD RBAC and Application

### RBAC for Liberty CRDs

```bash
oc apply -f cluster/gitops/argocd-rbac.yaml

# Verify
oc get clusterrole argocd-liberty-operator-manager
```

### Create the Argo CD Application

```bash
oc apply -f cluster/gitops/argocd-nexusliberty-app.yaml

# Verify
oc get application -n openshift-gitops
# Expected: nexusliberty-app   Synced   Healthy
```

## Step 6 — Configure GitHub Secrets

The GitHub Actions workflow needs these secrets to trigger Tekton:

| Secret | Value |
|---|---|
| `OKD_SERVER_URL` | `https://api.nexuslab.nexuslab.local:6443` |
| `OKD_TOKEN` | Service account token with pipeline permissions |

To get a long-lived token:
```bash
# Create a token for the pipeline SA
oc create token liberty-pipeline-sa -n liberty-apps --duration=8760h
# Copy the output and set it as the OKD_TOKEN secret in GitHub
```

Set these at: GitHub repo → Settings → Secrets and variables → Actions

## Step 7 — Test the Full Pipeline

### Manual test (Tekton only)

```bash
# Trigger a PipelineRun directly
oc create -f openshift/pipelines/06-pipelinerun-template.yaml -n liberty-apps

# Watch it run
tkn pipelinerun logs -f -n liberty-apps
# Or via oc:
oc get pipelinerun -n liberty-apps -w

# Check each task's status
tkn pipelinerun describe $(tkn pipelinerun list -n liberty-apps --limit 1 -o name) -n liberty-apps
```

### End-to-end test (GitHub Actions → Tekton → ArgoCD)

```bash
# 1. Make a change to the app
echo "// CI/CD pipeline test" >> app/src/main/java/io/openliberty/sample/system/SystemResource.java

# 2. Commit and push
git add app/
git commit -m "test: trigger full CI/CD pipeline"
git push origin main

# 3. Watch GitHub Actions
gh run watch

# 4. After GHA triggers Tekton, watch the PipelineRun
tkn pipelinerun logs -f -n liberty-apps

# 5. After Tekton commits the image tag, watch ArgoCD sync
oc get application nexusliberty-app -n openshift-gitops -w

# 6. Verify the new pod rolled out
oc get pods -n liberty-apps
ROUTE=$(oc get route nexusliberty-app -n liberty-apps -o jsonpath='{.spec.host}')
curl -k https://${ROUTE}/health/ready
```

## Step 8 — Verify README Badges

After the workflows run, check badges at `https://github.com/jconover/nexusliberty`:
- **Liberty CI** — green if quality gates + Tekton trigger passed
- **Ansible Lint** — green if linting passed

## Architecture Summary

| Component | Where It Runs | What It Does |
|---|---|---|
| `liberty-build.yml` (quality-gates job) | GitHub Actions (cloud) | Maven build, unit tests, Dockerfile lint |
| `liberty-build.yml` (trigger-tekton job) | GitHub Actions (cloud) | Authenticates to OKD, creates PipelineRun |
| `ansible-lint.yml` | GitHub Actions (cloud) | Lints Ansible playbooks on changes |
| OpenShift Pipelines Operator | OKD cluster | Manages Tekton lifecycle |
| `liberty-build-pipeline` | OKD cluster (liberty-apps) | git-clone → maven → buildah → push → commit tag |
| OpenShift GitOps Operator | OKD cluster | Manages Argo CD lifecycle |
| Argo CD Application | OKD cluster | Watches GitHub repo, syncs manifests to liberty-apps |

## Troubleshooting

**PipelineRun fails at git-clone**
- Check git-credentials secret is correct: `oc get secret git-credentials -n liberty-apps -o yaml`
- Verify the repo URL is accessible from the cluster: `oc run test --rm -it --image=alpine/git -- git ls-remote https://github.com/jconover/nexusliberty.git`

**PipelineRun fails at buildah**
- Check the pipeline SA has privileged SCC: `oc get clusterrolebinding liberty-pipeline-privileged`
- Check GHCR credentials: `oc get secret ghcr-credentials -n liberty-apps`
- If permission denied on `/var/lib/containers`, the SCC binding may need reapply

**PipelineRun fails at maven-build**
- Check PVC has enough space: `oc get pvc liberty-pipeline-workspace -n liberty-apps`
- Check Maven image can resolve dependencies (network access to Maven Central)

**PipelineRun fails at git-update-manifest**
- Token needs `contents:write` or `repo` scope
- Check the git-credentials secret matches GitHub PAT

**GitHub Actions can't reach OKD API**
- Your cluster is behind NAT — GHA needs a route to `api.nexuslab.nexuslab.local:6443`
- Options: Cloudflare Tunnel, port forwarding on router, or self-hosted runner on your network

**GitHub Actions re-triggers itself after Tekton commits**
- The `git-update-manifest` task commits an updated image tag back to `main`. If your GitHub Actions workflow triggers on pushes to `main` without path filtering, this creates an infinite loop.
- Fix: ensure `liberty-build.yml` uses path filters (`paths: ['app/**', 'docker/liberty-app/**']`) so the manifest-only commit from Tekton does not re-trigger the workflow.

**ArgoCD shows OutOfSync after Tekton commits**
- ArgoCD polls every 3 minutes by default — wait or force sync in the UI
- Check Argo CD can reach the repo: Settings → Repositories in Argo CD UI

**ArgoCD can't manage Liberty CRDs**
- Verify RBAC: `oc get clusterrole argocd-liberty-operator-manager`
- Re-apply: `oc apply -f cluster/gitops/argocd-rbac.yaml`

## What's Next (Phase 5)

With the CI/CD pipeline complete, Phase 5 adds HA and observability:
- Liberty clustering with session replication
- IHS load balancing across Liberty instances
- Prometheus metrics from Liberty (mpMetrics)
- Grafana dashboard for JVM/request metrics

Next: [Phase 5 — HA and Operations](phase5-ha-operations.md)
