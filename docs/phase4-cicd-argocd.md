# Phase 4: CI/CD Pipeline with GitHub Actions and Argo CD

Step-by-step guide to set up the CI/CD pipeline: GitHub Actions for building Liberty container images (CI) and OpenShift GitOps / Argo CD for automated deployment to OKD (CD).

## Prerequisites

- Phase 1-3 complete (OKD cluster running, Liberty app deployed, Ansible automation working)
- `oc` CLI installed and authenticated to the OKD cluster
- GitHub repository with push access (`github.com/jconover/nexusliberty`)
- GHCR (GitHub Container Registry) accessible from OKD nodes

## What We're Building

```
┌──────────────────────────────────────────────────────────────────┐
│                        CI (GitHub Actions)                       │
│                                                                  │
│  Push to main ──→ Build Liberty image ──→ Push to GHCR           │
│  (app/ or docker/)   (Dockerfile)          (sha-<commit> tag)    │
│                                                                  │
│                  ──→ Commit updated image tag to manifest         │
└─────────────────────────────┬────────────────────────────────────┘
                              │ git push (updated YAML)
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│                     CD (Argo CD on OKD)                          │
│                                                                  │
│  Watches repo ──→ Detects manifest change ──→ Syncs to cluster   │
│  (openshift/)     (new image tag)             (liberty-apps ns)  │
│                                                                  │
│  Self-heal: if someone manually changes a resource, Argo CD      │
│  reverts it to match Git (single source of truth)                │
└──────────────────────────────────────────────────────────────────┘
```

## Step 1 — Verify the Build Workflow

The build workflow (`.github/workflows/liberty-build.yml`) already exists and triggers on pushes to `main` that touch `docker/liberty-app/` or `app/`.

```bash
# Check the workflow file exists
cat .github/workflows/liberty-build.yml

# Check recent workflow runs on GitHub
gh run list --workflow=liberty-build.yml --limit 5
```

### What the build workflow does

1. Checks out the repo
2. Logs into GHCR
3. Builds the Liberty Docker image (multi-stage: Maven build + Open Liberty runtime)
4. Pushes to `ghcr.io/jconover/nexusliberty-app` with tags: `sha-<commit>`, `main`, `latest`
5. Updates `openshift/liberty-deployment/WebSphereLibertyApplication.yaml` with the new `sha-<commit>` tag
6. Commits and pushes the manifest change back to the repo

This commit is what triggers Argo CD to sync the new image to the cluster.

## Step 2 — Verify the Ansible Lint Workflow

The Ansible lint workflow (`.github/workflows/ansible-lint.yml`) triggers on pushes or PRs that touch `ansible/`.

```bash
# Check the workflow
cat .github/workflows/ansible-lint.yml

# Trigger a test run (make a trivial change to an ansible file)
# Or check runs:
gh run list --workflow=ansible-lint.yml --limit 5
```

## Step 3 — Install OpenShift GitOps Operator

This installs Argo CD on your OKD cluster via the OperatorHub.

```bash
# Apply the operator subscription
oc apply -f cluster/gitops/openshift-gitops-subscription.yaml

# Watch the operator install (takes ~2-3 minutes)
oc get csv -n openshift-operators -w

# Expected: openshift-gitops-operator.v1.x.x   Succeeded
# Press Ctrl+C once you see Succeeded
```

### Verify the operator is running

```bash
# Check the GitOps namespace was created
oc get namespace openshift-gitops

# Check Argo CD pods are running
oc get pods -n openshift-gitops

# Expected pods (all Running):
#   openshift-gitops-application-controller-...
#   openshift-gitops-applicationset-controller-...
#   openshift-gitops-dex-server-...
#   openshift-gitops-redis-...
#   openshift-gitops-repo-server-...
#   openshift-gitops-server-...
```

### Get the Argo CD admin password

```bash
# The initial admin password is stored in a secret
oc extract secret/openshift-gitops-cluster -n openshift-gitops --to=-

# Save it somewhere safe — you'll need it for the Argo CD UI
```

### Access the Argo CD UI

```bash
# Get the Route URL
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'

# Expected: openshift-gitops-server-openshift-gitops.apps.nexuslab.nexuslab.local
```

Open in browser: `https://openshift-gitops-server-openshift-gitops.apps.nexuslab.nexuslab.local`
- Username: `admin`
- Password: (from the secret above)

## Step 4 — Apply RBAC for Liberty CRDs

Argo CD needs permission to manage WebSphereLibertyApplication resources. The default ClusterRole doesn't include IBM's CRDs.

```bash
# Apply the ClusterRole and ClusterRoleBinding
oc apply -f cluster/gitops/argocd-rbac.yaml

# Verify the role was created
oc get clusterrole argocd-liberty-operator-manager
oc get clusterrolebinding argocd-liberty-operator-manager-binding
```

## Step 5 — Create the Argo CD Application

This tells Argo CD to watch the `openshift/liberty-deployment/` directory in the GitHub repo and sync it to the `liberty-apps` namespace.

```bash
# Apply the Application CR
oc apply -f cluster/gitops/argocd-nexusliberty-app.yaml

# Check the application was created
oc get application -n openshift-gitops

# Expected:
# NAME               SYNC STATUS   HEALTH STATUS
# nexusliberty-app   Synced        Healthy
```

### Verify in the Argo CD UI

1. Open the Argo CD UI (URL from Step 3)
2. You should see `nexusliberty-app` in the application list
3. Click it — you'll see the resource tree:
   - `WebSphereLibertyApplication/nexusliberty-app`
   - Any child resources (Deployment, Service, Route) created by the Liberty Operator
4. Status should show **Synced** and **Healthy**

### Verify the app is running

```bash
# Check the Liberty pods
oc get pods -n liberty-apps

# Check the Route
oc get route -n liberty-apps

# Hit the health endpoint
ROUTE=$(oc get route nexusliberty-app -n liberty-apps -o jsonpath='{.spec.host}')
curl -k https://${ROUTE}/health/ready
```

## Step 6 — Test the Full CI/CD Flow

Make a change to the app or Docker config and watch it flow through the entire pipeline.

```bash
# 1. Make a trivial change (e.g., bump a comment in server.xml)
echo "<!-- CI/CD test $(date) -->" >> docker/liberty-app/server.xml

# 2. Commit and push to main
git add docker/liberty-app/server.xml
git commit -m "test: trigger CI/CD pipeline"
git push origin main

# 3. Watch the GitHub Actions build
gh run watch

# 4. After the build completes, check the manifest was updated
git pull
grep applicationImage openshift/liberty-deployment/WebSphereLibertyApplication.yaml
# Should show: applicationImage: ghcr.io/jconover/nexusliberty-app:sha-<new-commit>

# 5. Watch Argo CD sync (in the UI or via CLI)
# Argo CD polls every 3 minutes by default, or you can force a sync:
oc get application nexusliberty-app -n openshift-gitops -o jsonpath='{.status.sync.status}'
# Expected: Synced

# 6. Verify the new pod rolled out
oc get pods -n liberty-apps
oc rollout status deployment/nexusliberty-app -n liberty-apps
```

## Step 7 — Verify README Badges

After the workflows have run at least once, check that badges render on GitHub:

1. Go to `https://github.com/jconover/nexusliberty`
2. You should see two badges at the top of the README:
   - **Build and Push Liberty Image** — green if the last build passed
   - **Ansible Lint** — green if linting passed

## Architecture Summary

| Component | Where it runs | What it does |
|---|---|---|
| `liberty-build.yml` | GitHub Actions (cloud) | Builds Liberty image, pushes to GHCR, updates manifest |
| `ansible-lint.yml` | GitHub Actions (cloud) | Lints Ansible playbooks on changes |
| OpenShift GitOps Operator | OKD cluster (`openshift-gitops` ns) | Manages Argo CD lifecycle |
| Argo CD Application CR | OKD cluster | Watches GitHub repo, syncs manifests to `liberty-apps` |
| RBAC (ClusterRole) | OKD cluster | Grants Argo CD permission for Liberty CRDs |

## Troubleshooting

**Argo CD Application shows "OutOfSync"**
- Check if the manifest in Git matches what's deployed:
  ```bash
  oc get application nexusliberty-app -n openshift-gitops -o yaml | grep -A5 status
  ```
- Force a sync: click **Sync** in the Argo CD UI, or:
  ```bash
  # Install argocd CLI (optional)
  # Or just delete and re-apply the Application CR
  oc delete application nexusliberty-app -n openshift-gitops
  oc apply -f cluster/gitops/argocd-nexusliberty-app.yaml
  ```

**Argo CD can't reach the GitHub repo**
- The repo is public, so no auth is needed
- If you made it private, add a repo secret in Argo CD:
  Settings → Repositories → Connect Repo → HTTPS → add a GitHub PAT

**Build workflow doesn't commit the manifest update**
- Check the workflow has `contents: write` permission
- Check the `GITHUB_TOKEN` has push access (default for same-repo workflows)
- Review the workflow run logs: `gh run view --log`

**Liberty pod fails to pull the new image**
- Check GHCR image visibility: `gh api user/packages/container/nexusliberty-app/versions --jq '.[0].metadata.container.tags'`
- If GHCR package is private, create an image pull secret:
  ```bash
  oc create secret docker-registry ghcr-pull \
    --docker-server=ghcr.io \
    --docker-username=jconover \
    --docker-password=<GITHUB_PAT> \
    -n liberty-apps
  oc secrets link default ghcr-pull --for=pull -n liberty-apps
  ```

**Argo CD UI not accessible**
- Check the Route: `oc get route -n openshift-gitops`
- Check DNS resolves: `nslookup openshift-gitops-server-openshift-gitops.apps.nexuslab.nexuslab.local`
- Try port-forward as a fallback:
  ```bash
  oc port-forward svc/openshift-gitops-server -n openshift-gitops 8443:443
  # Then open https://localhost:8443
  ```

**Operator install fails (no redhat-operators catalog)**
- OKD uses `community-operators` instead of `redhat-operators`. If on OKD (not OpenShift):
  ```bash
  # Install vanilla Argo CD instead:
  oc new-project argocd
  oc apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  ```
  Then update the Application CR namespace from `openshift-gitops` to `argocd`.
