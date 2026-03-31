# NexusLiberty — Enterprise Middleware Modernization Platform
## CLAUDE.md — Claude Code Project Instructions

---

## Table of Contents

- [Project Overview](#project-overview)
- [Infrastructure](#infrastructure-homelab-cluster-3-node)
- [Project Architecture](#project-architecture)
- [Tech Stack](#tech-stack)
- [Repository Structure](#repository-structure)
- [Project Phases](#project-phases-and-milestones)
- [Key Commands Reference](#key-commands-reference)
- [Key Configuration Files](#key-configuration-files)
- [Security Context Constraints](#security-context-constraints-scc-notes)
- [Notes for Claude Code Sessions](#notes-for-claude-code-sessions)

---

## Project Overview

**NexusLiberty** is a portfolio project demonstrating enterprise middleware modernization
from traditional IBM WebSphere Application Server deployments to containerized WebSphere
Liberty running on Red Hat OpenShift (OKD). It showcases the full modernization lifecycle:
legacy WAS provisioning, Liberty migration, container packaging, OpenShift deployment, and
automated operations — all tied together with Ansible, GitHub Actions CI/CD, and
infrastructure-as-code.

**Focus Area**: Enterprise Middleware Modernization (IBM WebSphere / Liberty / OpenShift)
**Portfolio Site**: devopsnexus.io
**GitHub**: github.com/jconover/nexusliberty

### Business Narrative

A simulated enterprise has a legacy WAS ND (Network Deployment) environment running
business-critical Java applications. The modernization mandate is to:

1. Automate the existing WAS ND environment (Ansible)
2. Migrate applications to WebSphere Liberty
3. Containerize Liberty workloads (Docker)
4. Deploy and operate containerized Liberty on OpenShift (OKD)
5. Establish a CI/CD pipeline for middleware deployments

---

## Infrastructure: Homelab Cluster (3-node)

- **3x Mini PC nodes**: AMD Ryzen 7 (8C/16T), 32GB LPDDR5, 1TB NVMe each
- **Network**: Home lab network with static DHCP reservations
- **Role**: Full OKD 4.x cluster — converged control plane + worker nodes

### IP Allocation (example — adjust to your subnet)
```
okd-node1.<cluster>.<domain>   192.168.68.93    (control plane + worker)
okd-node2.<cluster>.<domain>   192.168.68.84    (control plane + worker)
okd-node3.<cluster>.<domain>   192.168.68.88    (control plane + worker)
api.<cluster>.<domain>         192.168.68.100   (API VIP)
*.apps.<cluster>.<domain>      192.168.68.101   (Ingress VIP / wildcard DNS)
```

> For OKD cluster installation steps, see `docs/phase1-liberty-operator-install.md`.

---

## Project Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    GitHub Repository                            │
│                   NexusLiberty                                  │
└──────────────────────────┬──────────────────────────────────────┘
                           │ GitHub Actions CI/CD
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
   ┌─────────────┐  ┌───────────┐  ┌──────────────┐
   │  Ansible    │  │  Docker   │  │  OpenShift   │
   │  Playbooks  │  │  Build    │  │  Deploy      │
   │  (WAS/IHS)  │  │  Liberty  │  │  Liberty     │
   └──────┬──────┘  └─────┬─────┘  └──────┬───────┘
          │               │                │
          ▼               ▼                ▼
   ┌─────────────┐  ┌───────────┐  ┌──────────────┐
   │  Vagrant    │  │  Docker   │  │  OKD Cluster │
   │  WAS VMs    │  │  Registry │  │  (3-node     │
   │  (on-prem   │  │  (GHCR)   │  │   homelab)   │
   │  simulate)  │  └───────────┘  │              │
   └─────────────┘                 │  Liberty     │
                                   │  Operator    │
                                   │  + Argo CD   │
                                   │  + IHS LB    │
                                   │  + Monitoring│
                                   └──────────────┘
```

---

## Tech Stack

| Layer | Technology |
|---|---|
| Container Platform | Red Hat OKD 4.x (OpenShift upstream) |
| Middleware Runtime | Open Liberty (WebSphere Liberty upstream) |
| Legacy Middleware | IBM WAS ND (simulated via Vagrant — not licensed) |
| Automation | Ansible 2.x |
| CI/CD | GitHub Actions + Tekton/OpenShift Pipelines |
| GitOps | OpenShift GitOps (Argo CD) |
| Containers | Docker / Podman |
| Load Balancing | Apache HTTPD (simulating IHS pattern with mod_proxy) |
| Monitoring | Prometheus + Grafana (ServiceMonitor + custom dashboards) |
| Session Clustering | Hazelcast JCache (embedded, Kubernetes discovery) |
| SCM | Git / GitHub |
| Scripting | Bash, Python (wsadmin Jython scripts) |
| App | Jakarta EE 10 / MicroProfile 6.1 (JAX-RS, mpHealth, mpMetrics) |

---

## Repository Structure

```
nexusliberty/
├── CLAUDE.md                          # This file — Claude Code project context
├── README.md                          # Project overview and architecture
│
├── app/                               # Jakarta EE application
│   ├── pom.xml                        # Maven build (Open Liberty runtime)
│   └── src/main/
│       ├── java/io/devopsnexus/nexusapp/
│       │   ├── NexusApplication.java  # JAX-RS application root
│       │   ├── HealthResource.java    # /api/health endpoint
│       │   ├── InfoResource.java      # /api/info endpoint
│       │   ├── LivenessCheck.java     # MicroProfile liveness probe
│       │   └── ReadinessCheck.java    # MicroProfile readiness probe
│       └── webapp/index.html          # Landing page
│
├── docker/                            # Container builds
│   ├── liberty-app/
│   │   ├── Dockerfile                 # Multi-stage: Maven build → Open Liberty runtime
│   │   ├── server.xml                 # Liberty server config (webProfile + microProfile + sessionCache)
│   │   └── hazelcast-client.xml       # Hazelcast embedded member config (K8s discovery)
│   └── ihs/
│       ├── Dockerfile                 # Apache HTTPD 2.4 (IHS stand-in)
│       └── httpd.conf                 # Reverse proxy + load balancing config
│
├── openshift/                         # OpenShift deployment manifests
│   ├── liberty-deployment/
│   │   ├── WebSphereLibertyApplication.yaml  # Liberty Operator CR
│   │   ├── headless-service.yaml      # Hazelcast cluster discovery
│   │   └── rbac.yaml                  # ServiceAccount + Hazelcast RBAC
│   ├── ihs-deployment/
│   │   ├── deployment.yaml            # IHS (Apache) load balancer
│   │   ├── service.yaml
│   │   └── route.yaml
│   ├── monitoring/
│   │   ├── servicemonitor.yaml        # Prometheus scraping for Liberty
│   │   ├── prometheusrule.yaml        # Alert rules (pod down, high latency, errors)
│   │   ├── grafana-dashboard.yaml     # JVM + request metrics dashboard
│   │   └── cluster-monitoring-config.yaml  # Enable user workload monitoring
│   └── pipelines/                     # Tekton CI pipeline
│       ├── 01-rbac.yaml               # ServiceAccount + permissions
│       ├── 02-pvc.yaml                # Shared workspace PVC
│       ├── 03-secrets.yaml.example    # GHCR + Git credentials (template)
│       ├── 04-task-git-update-manifest.yaml  # Custom task: commit image tag
│       ├── 05-pipeline.yaml           # Liberty build pipeline
│       └── 06-pipelinerun-template.yaml
│
├── cluster/                           # OKD cluster-level configuration
│   ├── namespace/
│   │   └── liberty-apps.yaml
│   ├── operators/
│   │   ├── websphere-liberty-operator.yaml
│   │   ├── ibm-operator-catalog.yaml
│   │   ├── openshift-pipelines-subscription.yaml
│   │   └── builds-for-openshift-subscription.yaml
│   ├── gitops/
│   │   ├── argocd-nexusliberty-app.yaml    # Argo CD Application CR
│   │   ├── argocd-rbac.yaml                # Argo CD RBAC for Liberty CRDs
│   │   └── openshift-gitops-subscription.yaml
│   └── oauth/
│       └── htpasswd-oauth.yaml
│
├── ansible/                           # Ansible automation (WAS ND simulation)
│   ├── ansible.cfg
│   ├── inventory/
│   │   ├── hosts.ini                  # WAS/IHS node inventory
│   │   └── group_vars/
│   │       ├── all.yml                # Shared variables
│   │       ├── dmgr.yml               # Deployment Manager vars
│   │       ├── was_nodes.yml          # Managed node vars
│   │       └── ihs.yml               # IHS vars
│   ├── playbooks/
│   │   ├── was-install.yml            # WAS ND base install
│   │   ├── was-cluster.yml            # WAS cluster creation
│   │   ├── ihs-install.yml            # IHS + WebSphere plugin
│   │   └── was-deploy-app.yml         # Application deployment
│   └── roles/
│       ├── was-base/                  # OS prereqs, Java, WAS product simulation
│       ├── was-dmgr/                  # Deployment Manager profile
│       ├── was-nodeagent/             # Node agent + app server profiles
│       ├── was-cluster/               # Cluster creation + resources
│       ├── was-deploy/                # App deployment + health check
│       └── ihs-proxy/                 # IHS reverse proxy (supports liberty_mode toggle)
│
├── scripts/wsadmin/                   # wsadmin Jython scripts (simulation)
│   ├── create-cluster.py             # WAS cluster creation
│   ├── deploy-app.py                 # Application deployment
│   └── health-check.py              # Cell health verification
│
├── vagrant/                           # WAS on-prem simulation environment
│   ├── Vagrantfile                    # 4-node topology: dmgr, was1, was2, ihs
│   └── provision/
│       ├── bootstrap.sh               # Common OS setup for all nodes
│       ├── setup-dmgr.sh             # Deployment Manager provisioning
│       ├── setup-was1.sh             # Managed node 1
│       ├── setup-was2.sh             # Managed node 2
│       └── setup-ihs.sh             # IHS provisioning
│
├── docs/                              # Phase walkthrough guides
│   ├── phase1-liberty-operator-install.md
│   ├── phase2-liberty-containerization.md
│   ├── phase3-ansible-was-automation.md
│   ├── phase4-cicd-argocd.md
│   ├── phase5-ha-operations.md
│   ├── was-runbook.md                 # WAS operational procedures
│   ├── prerequisites.md               # Environment setup prerequisites
│   └── project-review-findings.md     # Architecture review findings
│
└── .github/workflows/
    ├── liberty-build.yml              # Build Liberty image, update manifest, push to GHCR
    ├── ihs-build.yml                  # Build IHS image, push to GHCR
    └── ansible-lint.yml               # Ansible linting on PR + push
```

---

## Project Phases and Milestones

### Phase 1 — OKD Cluster Up ✅
- [x] Install OKD 4.x via Assisted Installer on bare metal homelab
- [x] Validate all cluster operators healthy
- [x] Install WebSphere Liberty Operator
- [x] Deploy sample Liberty app via Operator (prove end-to-end)
- [x] Document cluster install process in docs/

### Phase 2 — Liberty Containerization ✅
- [x] Write Dockerfile for Liberty + sample Java app
- [x] Configure server.xml with features, datasources, endpoints
- [x] Push image to GitHub Container Registry (GHCR)
- [x] Deploy via WebSphereLibertyApplication CR on OKD
- [x] Expose via OpenShift Route
- [x] Validate app accessible via Route URL

### Phase 3 — Ansible WAS Automation ✅
- [x] Vagrant environment simulating WAS ND nodes
- [x] Ansible playbook: WAS base install and configuration
- [x] Ansible playbook: cluster creation (DM + managed nodes)
- [x] Ansible playbook: application deployment via wsadmin
- [x] Ansible playbook: IHS install + WebSphere plugin config
- [x] wsadmin Jython scripts for common admin tasks

### Phase 4 — CI/CD Pipeline ✅
- [x] GitHub Actions: pre-merge quality gates (Maven build, Dockerfile lint)
- [x] GitHub Actions: Ansible lint on playbook changes
- [x] Tekton/OpenShift Pipelines: on-cluster container build, push to GHCR, manifest update
- [x] OpenShift GitOps (Argo CD): deploy to OKD via GitOps sync
- [x] Health check via Argo CD self-heal + Liberty readiness/liveness probes
- [x] README badges (build status, Ansible lint status)

### Phase 5 — HA and Operations ✅
- [x] Liberty clustering config (Hazelcast JCache session replication)
- [x] IHS load balancing across Liberty instances
- [x] Prometheus metrics from Liberty via mpMetrics feature
- [x] Grafana dashboard for Liberty JVM/request metrics
- [x] Runbook documentation (WAS operational procedures)

---

## Key Commands Reference

### OKD / OpenShift
```bash
# Cluster status
oc get nodes
oc get clusteroperators
oc get clusterversion

# Liberty workloads
oc get pods -n liberty-apps
oc get WebSphereLibertyApplication -n liberty-apps
oc get routes -n liberty-apps

# Logs
oc logs -f deployment/liberty-app -n liberty-apps

# Debug
oc describe pod <pod-name> -n liberty-apps
oc adm must-gather
```

### Ansible (run from ansible/ directory)
```bash
ansible-playbook -i inventory/hosts.ini playbooks/was-install.yml --check   # dry run
ansible-playbook -i inventory/hosts.ini playbooks/was-install.yml           # execute
ansible-lint playbooks/
```

---

## Key Configuration Files

Rather than embedding stale copies, refer to the actual files:

| Purpose | File |
|---|---|
| Liberty server config | `docker/liberty-app/server.xml` |
| Hazelcast session clustering | `docker/liberty-app/hazelcast-client.xml` |
| Liberty Operator CR | `openshift/liberty-deployment/WebSphereLibertyApplication.yaml` |
| IHS load balancer config | `docker/ihs/httpd.conf` |
| Prometheus monitoring | `openshift/monitoring/servicemonitor.yaml` |
| Alert rules | `openshift/monitoring/prometheusrule.yaml` |
| Grafana dashboard | `openshift/monitoring/grafana-dashboard.yaml` |
| Argo CD Application | `cluster/gitops/argocd-nexusliberty-app.yaml` |
| Tekton pipeline | `openshift/pipelines/05-pipeline.yaml` |
| CI build workflow | `.github/workflows/liberty-build.yml` |

---

## Security Context Constraints (SCC) Notes

OpenShift SCCs are the key difference from vanilla Kubernetes PodSecurityAdmission.
Liberty pods typically need `restricted` SCC but may need `anyuid` if the base
image uses a specific UID. Always try restricted first:

```bash
# Check what SCC a pod is using
oc get pod <pod> -o yaml | grep scc

# If Liberty pod fails to start due to SCC
oc adm policy add-scc-to-serviceaccount restricted-v2 \
  -z nexusliberty-sa -n liberty-apps

# IBM's official Liberty operator handles SCC automatically
# Manual deployments may need explicit SCC assignment
```

---

## Git Workflow

Always create a feature branch before committing changes. Never commit directly to main.
Use the pattern: create branch → commit → push → create PR → merge.

---

## Debugging

When debugging deployment issues, verify the actual deployed environment URLs and
endpoints rather than assuming localhost or default paths. Always confirm the deployment
target (cloud vs local) before suggesting URLs.

When debugging Kubernetes/OpenShift issues, check the API version compatibility first
(e.g., v1 vs v1beta1) and trace the full request path (client → router → service → pod)
before suggesting fixes.

---

## Notes for Claude Code Sessions

### Project-specific gotchas
- Always check `oc get clusteroperators` before assuming cluster is healthy
- Liberty Operator CRDs may take 5-10 min to register after install
- OKD image pulls may be slow first time — use `oc get events -n liberty-apps` to monitor
- IHS plugin configuration requires matching WAS version — check fix pack levels
- When writing wsadmin scripts, use Jython (not Jacl) — industry standard now
- Vagrant WAS simulation is for config/automation demo only — not a licensed WAS install
- Use Open Liberty (open-source upstream) for container builds — no license required
- The IHS container is Apache HTTPD (not actual IBM IHS) — simulates the IHS pattern
- Hazelcast discovery requires the headless service and RBAC in `openshift/liberty-deployment/`

### Environment details
- Real infrastructure values (IPs, hostnames, domains) are in `CLAUDE.private.md` (local only, never commit)
- Target namespace for Liberty workloads: `liberty-apps`
- GHCR image base: `ghcr.io/jconover/nexusliberty-app`
- Argo CD watches `openshift/liberty-deployment/` for GitOps sync
- CI workflow updates image tag in `WebSphereLibertyApplication.yaml` via sed + commit to main

### Languages and tools
Primary: YAML (Ansible playbooks, K8s/OpenShift manifests), Python (wsadmin Jython),
Shell (Bash), Java (Liberty app), Dockerfiles. Prefer these unless otherwise specified.
