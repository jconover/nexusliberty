# NexusLiberty Screenshot Guide

Screenshots for the portfolio README and docs. Each entry lists what to capture,
how to get there, and why it matters to a hiring manager reviewing the repo.

Save screenshots to `docs/screenshots/` with the filenames below.

---

## Phase 0 -- Cluster Foundation

### `cluster-nodes.png`
**What:** `oc get nodes -o wide` terminal output showing 3 Ready nodes
**Command:** `oc get nodes -o wide`
**Why:** Proves real hardware, not a cloud sandbox. Shows converged control-plane+worker topology.

### `cluster-operators.png`
**What:** `oc get clusteroperators` showing all Available=True
**Command:** `oc get clusteroperators`
**Why:** Demonstrates healthy OKD 4.21 cluster -- all operators green.

### `okd-console-overview.png`
**What:** OKD web console Home > Overview page
**URL:** `https://console-openshift-console.apps.nexuslab.nexuslab.local/`
**Why:** Visual proof of a running cluster with resource utilization graphs.

---

## Phase 1 -- Liberty Operator & Application

### `liberty-topology.png`
**What:** OKD console Developer > Topology view in `liberty-apps` namespace
**URL:** Console > Developer perspective > Topology (namespace: liberty-apps)
**Why:** Shows Liberty pods, IHS pods, services, and routes in a visual graph. Immediately conveys the deployment architecture.

### `liberty-app-browser.png`
**What:** The NexusLiberty app landing page loaded in a browser via the Route
**URL:** `https://nexusliberty-app-liberty-apps.apps.nexuslab.nexuslab.local/`
**Why:** End-to-end proof: code built, pushed, deployed, routable, serving traffic.

### `liberty-pods-running.png`
**What:** `oc get pods -n liberty-apps` showing 2 Running Liberty pods + IHS pods
**Command:** `oc get pods -n liberty-apps -l 'app.kubernetes.io/name in (nexusliberty-app,nexusliberty-ihs)'`
**Why:** Shows HA deployment with pods spread across nodes.

### `liberty-health-endpoints.png`
**What:** Browser or curl output of `/health/ready` and `/health/live` endpoints
**Command:** `curl -sk https://nexusliberty-app-liberty-apps.apps.nexuslab.nexuslab.local/health/ready | python3 -m json.tool`
**Why:** MicroProfile Health is a key Liberty modernization feature. Shows readiness checks passing.

---

## Phase 2 -- Ansible Automation (WAS ND Simulation)

### `ansible-playbook-run.png`
**What:** Terminal showing a successful `ansible-playbook --check` dry run
**Command:** `cd ansible && ansible-playbook -i inventory/hosts.ini playbooks/was-install.yml --check`
**Why:** Shows Ansible automation works. `--check` is safe without Vagrant VMs running.

### `ansible-lint-clean.png`
**What:** Terminal showing `ansible-lint` passing with 0 violations
**Command:** `cd ansible && ansible-lint playbooks/`
**Why:** Code quality -- linting passes on all playbooks.

---

## Phase 3 -- GitHub Actions CI

### `github-actions-green.png`
**What:** GitHub Actions tab showing green checkmarks on recent runs
**URL:** `https://github.com/jconover/nexusliberty/actions`
**Why:** CI pipeline is real and passing. Shows Liberty build, IHS build, and Ansible lint workflows.

### `github-badges-readme.png`
**What:** Top of README.md on GitHub showing status badges
**URL:** `https://github.com/jconover/nexusliberty`
**Why:** Badges give instant credibility -- green = everything works.

---

## Phase 4 -- CI/CD Pipeline (Tekton + ArgoCD)

### `argocd-synced.png`
**What:** ArgoCD UI showing nexusliberty-app as Synced + Healthy (all green)
**URL:** `https://openshift-gitops-server-openshift-gitops.apps.nexuslab.nexuslab.local/applications/nexusliberty-app`
**Why:** The money shot. GitOps pipeline working end-to-end. Every resource synced and healthy.

### `argocd-resource-tree.png`
**What:** ArgoCD app detail page showing the full resource tree (SA, CR, HPA, PDB, NetworkPolicy, RBAC)
**URL:** Same as above, click into the app
**Why:** Shows the breadth of managed resources -- not just a Deployment but full enterprise config.

### `tekton-pipeline-run.png`
**What:** OKD console Pipelines > PipelineRuns showing a completed run
**URL:** Console > Pipelines > PipelineRuns (namespace: liberty-apps)
**Why:** On-cluster CI via Tekton. Shows git-clone, maven-build, buildah, manifest-update stages.

---

## Phase 5 -- HA & Operations

### `grafana-dashboard.png`
**What:** Grafana dashboard showing live Liberty JVM metrics
**URL:** Grafana route in `openshift-monitoring` or `openshift-user-workload-monitoring` namespace
**Why:** Observability is table stakes for enterprise. Shows JVM heap, HTTP request rate, GC pauses, response times.

### `prometheus-targets.png`
**What:** Prometheus Targets page showing Liberty endpoints as UP
**URL:** Thanos Querier or Prometheus UI > Status > Targets
**Why:** Proves ServiceMonitor is correctly scraping Liberty metrics.

### `hpa-status.png`
**What:** `oc get hpa -n liberty-apps` showing the autoscaler config
**Command:** `oc get hpa -n liberty-apps`
**Why:** Enterprise-grade autoscaling configured with CPU and memory targets.

### `pdb-status.png`
**What:** `oc get pdb -n liberty-apps` showing disruption budget
**Command:** `oc get pdb -n liberty-apps`
**Why:** Shows operational maturity -- pod disruption budgets protect availability during maintenance.

---

## Recommended Screenshot Order for README

For maximum impact in the README, present screenshots in this order:

1. `argocd-synced.png` -- hero image, proves everything works
2. `liberty-topology.png` -- architecture at a glance
3. `github-actions-green.png` -- CI credibility
4. `tekton-pipeline-run.png` -- on-cluster pipeline
5. `grafana-dashboard.png` -- observability
6. `liberty-app-browser.png` -- the app itself running
