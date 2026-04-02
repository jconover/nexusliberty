#!/usr/bin/env bash
# GitHub Actions Runner Controller (ARC) setup for OKD
# Prerequisites: oc CLI authenticated as cluster-admin, helm installed
#
# Usage: bash openshift/github-runner/setup.sh
#
# This script is idempotent — safe to re-run after partial failures.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# WSL2 / Rancher Desktop workaround
# ---------------------------------------------------------------------------
# Rancher Desktop installs docker-credential-secretservice on the Windows side
# but it cannot load libsecret-1.so.0 inside WSL2, causing Helm OCI pulls to
# fail. If the broken binary is detected, create a shim that returns empty
# credentials so Helm can reach public registries (like ghcr.io).
if docker-credential-secretservice list >/dev/null 2>&1; then
  : # credential helper works — nothing to do
else
  if command -v docker-credential-secretservice >/dev/null 2>&1; then
    echo "==> WSL2 workaround: docker-credential-secretservice is broken, installing shim..."
    mkdir -p "$HOME/bin"
    cat > "$HOME/bin/docker-credential-secretservice" << 'SHIM'
#!/bin/bash
echo '{"ServerURL":"","Username":"","Secret":""}'
SHIM
    chmod +x "$HOME/bin/docker-credential-secretservice"
    export PATH="$HOME/bin:$PATH"
  fi
fi

# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------
log()  { echo ""; echo "==> $*"; }
info() { echo "    $*"; }

# ---------------------------------------------------------------------------
# Step 1 — Apply namespace, service account, RBAC, SCC manifests
# ---------------------------------------------------------------------------
log "Applying namespace, serviceaccount, RBAC, SCC, and SCC clusterrole manifests..."

for manifest in namespace.yaml serviceaccount.yaml rbac.yaml scc.yaml scc-clusterrole.yaml; do
  if [[ -f "${SCRIPT_DIR}/${manifest}" ]]; then
    info "Applying ${manifest}"
    oc apply -f "${SCRIPT_DIR}/${manifest}"
  else
    echo "    [WARN] ${manifest} not found — skipping"
  fi
done

# ---------------------------------------------------------------------------
# Step 1b — Copy GHCR pull secret from liberty-apps (if available)
# ---------------------------------------------------------------------------
# The runner image is hosted on GHCR (private by default). OKD needs pull
# credentials in the github-runner namespace. We copy the existing secret
# from liberty-apps if it exists, then link it to the service accounts.
# ---------------------------------------------------------------------------
if oc get secret ghcr-pull-secret -n liberty-apps &>/dev/null; then
  if oc get secret ghcr-pull-secret -n github-runner &>/dev/null; then
    info "GHCR pull secret already exists in github-runner namespace"
  else
    log "Copying GHCR pull secret from liberty-apps to github-runner..."
    oc get secret ghcr-pull-secret -n liberty-apps -o yaml | \
      sed 's/namespace: liberty-apps/namespace: github-runner/' | \
      grep -v -E '(resourceVersion|uid|creationTimestamp|selfLink)' | \
      oc apply -n github-runner -f -
  fi
  info "Linking pull secret to service accounts..."
  oc secrets link default ghcr-pull-secret --for=pull -n github-runner 2>/dev/null || true
  oc secrets link github-runner-sa ghcr-pull-secret --for=pull -n github-runner 2>/dev/null || true
else
  echo "    [WARN] ghcr-pull-secret not found in liberty-apps — runner image must be public or you must create the pull secret manually"
fi

# ---------------------------------------------------------------------------
# Step 2 — GitHub PAT secret
# ---------------------------------------------------------------------------
log "GitHub PAT secret setup"
echo ""
echo "  ARC requires a Kubernetes secret containing your GitHub Personal Access Token."
echo "  The token needs the 'repo' scope (for private repos) or just 'public_repo'."
echo ""
echo "  If the secret does not exist yet, create it now:"
echo ""
echo "    oc create secret generic github-arc-pat \\"
echo "      -n github-runner \\"
echo "      --from-literal=github_token=<YOUR_PAT>"
echo ""
echo "  To check if it already exists:"
echo "    oc get secret github-arc-pat -n github-runner"
echo ""
read -r -p "  Press ENTER once the secret is in place (or Ctrl+C to abort)..."

# ---------------------------------------------------------------------------
# Step 3 — Install ARC controller
# ---------------------------------------------------------------------------
log "Installing ARC controller into github-arc-system namespace..."

if helm status arc-system -n github-arc-system &>/dev/null; then
  info "ARC controller release 'arc-system' already exists — upgrading..."
  helm upgrade arc-system \
    oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
    -n github-arc-system \
    --create-namespace \
    --wait
else
  info "Installing ARC controller..."
  helm install arc-system \
    oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
    -n github-arc-system \
    --create-namespace \
    --wait
fi

# ---------------------------------------------------------------------------
# Step 4 — Wait for controller pods to be ready
# ---------------------------------------------------------------------------
log "Waiting for ARC controller pods to be ready..."
oc rollout status deployment \
  -l app.kubernetes.io/name=gha-runner-scale-set-controller \
  -n github-arc-system \
  --timeout=120s

info "ARC controller is ready."

# ---------------------------------------------------------------------------
# Step 5 — Install the runner scale set
# ---------------------------------------------------------------------------
log "Installing runner scale set (nexusliberty-runners) into github-runner namespace..."

if helm status nexusliberty-runners -n github-runner &>/dev/null; then
  info "Scale set release 'nexusliberty-runners' already exists — upgrading..."
  helm upgrade nexusliberty-runners \
    oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
    -n github-runner \
    --create-namespace \
    -f "${SCRIPT_DIR}/arc-values.yaml" \
    --wait
else
  info "Installing runner scale set..."
  helm install nexusliberty-runners \
    oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
    -n github-runner \
    --create-namespace \
    -f "${SCRIPT_DIR}/arc-values.yaml" \
    --wait
fi

# ---------------------------------------------------------------------------
# Step 6 — Bind SCC to service accounts used by ARC runner pods
# ---------------------------------------------------------------------------
# ARC ephemeral runner pods may use the 'default' SA in the namespace even when
# serviceAccountName is set in the pod template (ARC version-dependent behavior).
# We bind the custom SCC to 'default', 'github-runner-sa', and the ARC-created
# listener SA to cover all cases.
# ---------------------------------------------------------------------------
log "Binding github-arc SCC to service accounts in github-runner namespace..."

for SA_NAME in default github-runner-sa; do
  info "Binding SCC to ${SA_NAME}..."
  oc adm policy add-scc-to-user github-arc \
    -z "${SA_NAME}" \
    -n github-runner 2>/dev/null || true
done

# Also bind the ARC-created listener SA if it exists
ARC_LISTENER_SA="arc-nexusliberty-gha-rs-no-permission"
if oc get sa "${ARC_LISTENER_SA}" -n github-runner &>/dev/null; then
  info "Binding SCC to ${ARC_LISTENER_SA}..."
  oc adm policy add-scc-to-user github-arc \
    -z "${ARC_LISTENER_SA}" \
    -n github-runner 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Step 7 — Verification
# ---------------------------------------------------------------------------
log "Setup complete. Run these commands to verify:"

MIN_RUNNERS=$(grep 'minRunners:' "${SCRIPT_DIR}/arc-values.yaml" | awk '{print $2}' || echo "1")

echo ""
echo "  # ARC controller pods"
echo "  oc get pods -n github-arc-system"
echo ""
echo "  # Runner scale set pods (expect ${MIN_RUNNERS} warm runner)"
echo "  oc get pods -n github-runner"
echo ""
echo "  # AutoscalingRunnerSet CR"
echo "  oc get autoscalingrunnersets -n github-runner"
echo ""
echo "  # Runner registration in GitHub"
echo "  # Settings -> Actions -> Runners -> nexusliberty-runners"
echo "  # https://github.com/jconover/nexusliberty/settings/actions/runners"
echo ""
echo "  # Trigger a test workflow run:"
echo "  # gh workflow run liberty-build.yml --repo jconover/nexusliberty"
echo ""
