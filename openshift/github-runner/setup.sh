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
# Step 6 — Bind SCC to both service accounts
# ---------------------------------------------------------------------------
# ARC creates its own listener SA named arc-nexusliberty-gha-rs-no-permission
# in addition to the github-runner-sa we manage. Both need the custom SCC so
# pods can start under the restricted-compatible securityContext in arc-values.yaml.
# ---------------------------------------------------------------------------
log "Binding SCC to ARC listener SA and github-runner-sa..."

ARC_LISTENER_SA="system:serviceaccount:github-runner:arc-nexusliberty-gha-rs-no-permission"
RUNNER_SA="system:serviceaccount:github-runner:github-runner-sa"

if oc get clusterrolebinding arc-runner-scc-binding &>/dev/null; then
  info "SCC ClusterRoleBinding already exists — patching subjects..."
  oc patch clusterrolebinding arc-runner-scc-binding \
    --type=json \
    -p="[
      {\"op\":\"replace\",\"path\":\"/subjects\",\"value\":[
        {\"kind\":\"ServiceAccount\",\"name\":\"arc-nexusliberty-gha-rs-no-permission\",\"namespace\":\"github-runner\"},
        {\"kind\":\"ServiceAccount\",\"name\":\"github-runner-sa\",\"namespace\":\"github-runner\"}
      ]}
    ]"
else
  info "Creating SCC ClusterRoleBinding..."
  oc create clusterrolebinding arc-runner-scc-binding \
    --clusterrole=github-runner-scc \
    --user="${ARC_LISTENER_SA}" \
    --user="${RUNNER_SA}"
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
