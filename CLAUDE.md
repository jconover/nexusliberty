# NexusLiberty — Enterprise Middleware Modernization Platform
## CLAUDE.md — Claude Code Project Instructions

---

## Project Overview

**NexusLiberty** is a portfolio project demonstrating enterprise middleware modernization
from traditional IBM WebSphere Application Server deployments to containerized WebSphere
Liberty running on Red Hat OpenShift (OKD). It showcases the full modernization lifecycle:
legacy WAS provisioning, Liberty migration, container packaging, OpenShift deployment, and
automated operations — all tied together with Ansible, GitHub Actions CI/CD, and
infrastructure-as-code.

> This project is built with [Claude Code](https://claude.ai/code) as the primary AI
> development assistant. The CLAUDE.md file provides Claude Code with full project context,
> architecture decisions, and operational runbook so every session starts with complete
> awareness of the platform.

**Focus Area**: Enterprise Middleware Modernization (IBM WebSphere / Liberty / OpenShift)
**Portfolio Site**: devopsnexus.io
**GitHub**: github.com/jconover/nexusliberty

---

## Business Narrative

A simulated enterprise has a legacy WAS ND (Network Deployment) environment running
business-critical Java applications. The modernization mandate is to:

1. Automate the existing WAS ND environment (Ansible)
2. Migrate applications to WebSphere Liberty
3. Containerize Liberty workloads (Docker)
4. Deploy and operate containerized Liberty on OpenShift (OKD)
5. Establish a CI/CD pipeline for middleware deployments

This mirrors real-world enterprise modernization patterns happening across the financial
services, healthcare, and retail sectors where WAS environments are being containerized
and shifted to OpenShift.

---

## Infrastructure: Homelab Cluster (3-node)

### Hardware
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

---

## Phase 0: Cluster Wipe and OKD Installation

### Step 0.1 — Pre-flight Checklist

Before wiping anything:
- [ ] Note current kubeadm cluster state (kubectl get nodes, namespaces, pvs)
- [ ] Backup any manifests or configs you want to keep (~/k8s-backup/)
- [ ] Confirm static IPs or DHCP reservations set on your router for all 3 nodes
- [ ] Set up DNS entries (or /etc/hosts on your workstation as fallback):
  - api.\<cluster\>.\<domain\> → API VIP
  - *apps.\<cluster\>.\<domain\> → Ingress VIP
- [ ] Have a USB drive (8GB+) ready for bootstrap ISO
- [ ] Create free Red Hat Developer account at console.redhat.com if not already done

### Step 0.2 — Wipe Existing Nodes

SSH into each node and run:

```bash
# On each node — destroys kubeadm setup and clears disk for fresh install
sudo kubeadm reset -f
sudo rm -rf /etc/kubernetes /var/lib/etcd /var/lib/kubelet /etc/cni /opt/cni
sudo iptables -F && sudo iptables -X
sudo ipvsadm --clear 2>/dev/null || true

# Optional: full disk wipe if you want completely clean state
# WARNING: This destroys everything on the node
# sudo wipefs -a /dev/nvme0n1
```

> **Note**: OKD installs RHCOS (Red Hat CoreOS) automatically — Ubuntu/existing OS
> is wiped during install. You do not need to manually prepare the OS.

### Step 0.3 — OKD Installation via Assisted Installer (Recommended)

The Assisted Installer is the easiest path for bare metal OKD. It handles
bootstrap automatically — no separate bootstrap node required.

**Using OKD/OpenShift Assisted Installer:**

1. Go to: https://console.redhat.com/openshift/assisted-installer/clusters
2. Click **Create Cluster**
3. Select:
   - Cluster name: your choice
   - Base domain: your local domain
   - OpenShift version: Latest stable OKD 4.x
   - Installation type: **Full cluster** (not SNO)
   - Control plane nodes: **3 (highly available)**
   - Network config: **DHCP only** (if using DHCP reservations)
4. Operators screen: **skip all** — add post-install via OperatorHub
5. Download the **Minimal Discovery ISO**
6. Write to USB via Balena Etcher
7. Boot each node from USB — nodes appear in Assisted Installer UI
8. Assign all 3 nodes as **Control Plane** role (auto-becomes worker too)
9. Set **API IP** and **Ingress IP** (must be outside DHCP pool)
10. Click **Install** — ~45-90 minutes

**Alternative: Agent-Based Installer (offline/air-gapped)**
See: https://docs.okd.io/latest/installing/installing_with_agent_based_installer/

### Step 0.4 — Post-Install Validation

```bash
# Install oc CLI on your workstation
curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz
tar -xzf openshift-client-linux.tar.gz
sudo mv oc kubectl /usr/local/bin/

# Download kubeconfig from Assisted Installer completion screen
mkdir -p ~/.kube
mv ~/Downloads/kubeconfig ~/.kube/config

# Verify cluster
oc get nodes
oc get clusterversion
oc get clusteroperators
# All operators should show AVAILABLE=True
# Nodes should show Ready status

# Login via CLI
oc login https://api.<cluster>.<domain>:6443 \
  --username kubeadmin \
  --password <password-from-installer>
```

### Step 0.5 — Install WebSphere Liberty Operator

```bash
# Create namespace for Liberty workloads
oc new-project liberty-apps

# Install IBM WebSphere Liberty Operator from OperatorHub
# Via web console: Operators → OperatorHub → search "WebSphere Liberty"
# Or via CLI:
oc apply -f operators/websphere-liberty-operator.yaml
```

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
   │  (on-prem   │  │  (Quay or │  │   homelab)   │
   │  simulate)  │  │   GHCR)   │  │              │
   └─────────────┘  └───────────┘  │  Liberty     │
                                   │  Operator    │
                                   │  + Routes    │
                                   │  + IHS LB    │
                                   └──────────────┘
```

---

## Tech Stack

| Layer | Technology |
|---|---|
| Container Platform | Red Hat OKD 4.x (OpenShift upstream) |
| Middleware Runtime | IBM WebSphere Liberty (Open Liberty base) |
| Legacy Middleware | IBM WebSphere Application Server ND (simulated via Vagrant) |
| Automation | Ansible 2.x |
| CI/CD | GitHub Actions |
| IaC | Terraform (cluster infra config) |
| Containers | Docker / Podman |
| Load Balancing | IBM HTTP Server (IHS) with WebSphere plugin |
| Monitoring | Prometheus + Grafana (OKD built-in + custom dashboards) |
| SCM | Git / GitHub |
| Scripting | Bash, Python (wsadmin Jython scripts) |
| App | Sample Java EE app (Open Liberty getting-started or custom) |
| AI Dev Assistant | Claude Code (Anthropic) |

---

## Repository Structure

```
nexusliberty/
├── CLAUDE.md                          # This file — Claude Code project context
├── README.md                          # Project overview and architecture
│
├── cluster/                           # OKD cluster configuration
│   ├── install-config.yaml            # OKD installer config
│   ├── oauth/
│   │   └── htpasswd-oauth.yaml        # OAuth identity provider config
│   ├── operators/
│   │   ├── websphere-liberty-operator.yaml
│   │   ├── openshift-pipelines-subscription.yaml
│   │   └── builds-for-openshift-subscription.yaml
│   └── rbac/                          # OKD RBAC configs
│
├── ansible/                           # Ansible automation
│   ├── inventory/
│   │   ├── hosts.ini                  # WAS/IHS node inventory
│   │   └── group_vars/
│   ├── playbooks/
│   │   ├── was-install.yml            # WAS ND install and config
│   │   ├── was-cluster.yml            # WAS cluster creation
│   │   ├── liberty-install.yml        # Liberty server provisioning
│   │   ├── ihs-install.yml            # IBM HTTP Server + plugin
│   │   └── was-deploy-app.yml         # Application deployment
│   └── roles/
│       ├── was-base/                  # WAS base configuration role
│       ├── liberty-server/            # Liberty server role
│       └── ihs-proxy/                 # IHS reverse proxy role
│
├── docker/                            # Container builds
│   ├── liberty-app/
│   │   ├── Dockerfile                 # Liberty container image
│   │   └── server.xml                 # Liberty server configuration
│   └── ihs/
│       └── Dockerfile                 # IHS container (if containerizing)
│
├── openshift/                         # OpenShift manifests
│   ├── namespace/
│   ├── liberty-deployment/
│   │   ├── WebSphereLibertyApplication.yaml   # Liberty Operator CR
│   │   ├── service.yaml
│   │   └── route.yaml
│   ├── configmaps/
│   │   └── liberty-server-config.yaml
│   ├── secrets/
│   │   └── liberty-tls.yaml
│   ├── pipelines/                                     # Tekton CI pipeline
│   │   ├── 01-rbac.yaml                               # ServiceAccount + permissions
│   │   ├── 02-pvc.yaml                                # Shared workspace PVC
│   │   ├── 03-secrets.yaml                            # GHCR + Git credentials (template)
│   │   ├── 04-task-git-update-manifest.yaml           # Custom task: commit image tag
│   │   ├── 05-pipeline.yaml                           # Liberty build pipeline
│   │   └── 06-pipelinerun-template.yaml               # PipelineRun template
│   └── monitoring/
│       ├── servicemonitor.yaml
│       └── grafana-dashboard.yaml
│
├── terraform/                         # Infrastructure as code
│   ├── okd-dns/                       # DNS config for cluster
│   └── registry/                      # Container registry config
│
├── app/                               # Sample Java EE application
│   ├── src/
│   ├── pom.xml
│   └── README.md
│
├── scripts/                           # Utility scripts
│   ├── wsadmin/                       # wsadmin Jython scripts
│   │   ├── create-cluster.py
│   │   ├── deploy-app.py
│   │   └── health-check.py
│   └── bash/
│       ├── was-status.sh
│       └── liberty-logs.sh
│
├── vagrant/                           # WAS on-prem simulation
│   ├── Vagrantfile                    # WAS ND node definitions
│   └── provision/
│
├── docs/                              # Documentation
│   ├── architecture.md
│   ├── was-runbook.md                 # WAS operational runbook
│   ├── liberty-migration-guide.md     # WAS → Liberty migration guide
│   └── openshift-operations.md        # OKD day-2 operations
│
└── .github/
    └── workflows/
        ├── liberty-build.yml          # Build Liberty container image
        ├── liberty-deploy-okd.yml     # Deploy to OKD cluster
        └── ansible-lint.yml           # Ansible linting
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
- [x] GitHub Actions: pre-merge quality gates (Maven build, unit tests, Dockerfile lint)
- [x] GitHub Actions: Ansible lint on playbook changes
- [x] Tekton/OpenShift Pipelines: on-cluster container build, push to GHCR, manifest update
- [x] OpenShift GitOps (Argo CD): deploy to OKD via GitOps sync
- [x] Health check via Argo CD self-heal + Liberty readiness/liveness probes
- [x] README badges (build status, Ansible lint status)

### Phase 5 — HA and Operations (Stretch)
- [ ] Liberty clustering config (session replication)
- [ ] IHS load balancing across Liberty instances
- [ ] Prometheus metrics from Liberty via mpMetrics feature
- [ ] Grafana dashboard for Liberty JVM/request metrics
- [ ] Runbook documentation (WAS operational procedures)

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
oc adm must-gather                          # Full cluster diagnostic dump

# SCCs (Security Context Constraints — OpenShift specific)
oc get scc
oc adm policy add-scc-to-serviceaccount anyuid -z default -n liberty-apps
```

### Ansible
```bash
# Dry run
ansible-playbook -i inventory/hosts.ini playbooks/was-install.yml --check

# Run playbook
ansible-playbook -i inventory/hosts.ini playbooks/was-install.yml

# Run specific tags
ansible-playbook -i inventory/hosts.ini playbooks/was-cluster.yml --tags "cluster-create"

# Lint
ansible-lint playbooks/
```

### wsadmin (Jython)
```bash
# Connect to Deployment Manager
wsadmin.sh -lang jython -host <dmgr-host> -port 8879 \
  -user wasadmin -password <pass>

# Run script
wsadmin.sh -lang jython -f scripts/wsadmin/deploy-app.py \
  -host <dmgr-host> -port 8879
```

### Liberty (local/Vagrant)
```bash
# Start Liberty server
/opt/ibm/wlp/bin/server start defaultServer

# Status
/opt/ibm/wlp/bin/server status defaultServer

# Logs
tail -f /opt/ibm/wlp/usr/servers/defaultServer/logs/messages.log
```

### Docker / Container
```bash
# Build Liberty image
docker build -t nexusliberty-app:latest ./docker/liberty-app/

# Test locally
docker run -p 9080:9080 -p 9443:9443 nexusliberty-app:latest

# Push to GHCR
docker tag nexusliberty-app:latest ghcr.io/<your-username>/nexusliberty-app:latest
docker push ghcr.io/<your-username>/nexusliberty-app:latest
```

---

## Liberty server.xml Baseline

```xml
<?xml version="1.0" encoding="UTF-8"?>
<server description="NexusLiberty App Server">

    <!-- Enable features -->
    <featureManager>
        <feature>servlet-5.0</feature>
        <feature>jndi-1.0</feature>
        <feature>jdbc-4.2</feature>
        <feature>ssl-1.0</feature>
        <feature>mpHealth-3.1</feature>
        <feature>mpMetrics-4.0</feature>
        <feature>mpConfig-3.0</feature>
    </featureManager>

    <!-- HTTP endpoints -->
    <httpEndpoint id="defaultHttpEndpoint"
                  host="*"
                  httpPort="9080"
                  httpsPort="9443"/>

    <!-- TLS config -->
    <keyStore id="defaultKeyStore" password="${env.KEYSTORE_PASSWORD}"/>

    <!-- Health checks (for OKD liveness/readiness probes) -->
    <mpHealth/>

    <!-- Metrics (for Prometheus scraping) -->
    <mpMetrics authentication="false"/>

    <!-- Application -->
    <webApplication id="nexus-app"
                    location="nexus-app.war"
                    contextRoot="/app"/>

</server>
```

---

## OpenShift Liberty Operator CR Example

```yaml
apiVersion: liberty.websphere.ibm.com/v1
kind: WebSphereLibertyApplication
metadata:
  name: nexusliberty-app
  namespace: liberty-apps
spec:
  applicationImage: ghcr.io/<your-username>/nexusliberty-app:latest
  replicas: 2
  expose: true
  service:
    port: 9443
  readinessProbe:
    httpGet:
      path: /health/ready
      port: 9443
      scheme: HTTPS
    initialDelaySeconds: 30
    periodSeconds: 10
  livenessProbe:
    httpGet:
      path: /health/live
      port: 9443
      scheme: HTTPS
    initialDelaySeconds: 60
    periodSeconds: 30
  env:
    - name: WLP_LOGGING_CONSOLE_FORMAT
      value: json
    - name: WLP_LOGGING_CONSOLE_LOGLEVEL
      value: info
```

---

## GitHub Actions Pipeline Baseline

```yaml
# .github/workflows/liberty-deploy-okd.yml
name: Build and Deploy Liberty to OKD

on:
  push:
    branches: [main]
    paths:
      - 'docker/liberty-app/**'
      - 'app/**'

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push Liberty image
        uses: docker/build-push-action@v5
        with:
          context: ./docker/liberty-app
          push: true
          tags: ghcr.io/${{ github.repository_owner }}/nexusliberty-app:${{ github.sha }}

  deploy-to-okd:
    needs: build-and-push
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install oc CLI
        uses: redhat-actions/openshift-tools-installer@v1
        with:
          oc: latest

      - name: Login to OKD
        uses: redhat-actions/oc-login@v1
        with:
          openshift_server_url: ${{ secrets.OKD_SERVER_URL }}
          openshift_token: ${{ secrets.OKD_TOKEN }}

      - name: Update image and deploy
        run: |
          oc set image deployment/nexusliberty-app \
            nexusliberty-app=ghcr.io/${{ github.repository_owner }}/nexusliberty-app:${{ github.sha }} \
            -n liberty-apps
          oc rollout status deployment/nexusliberty-app -n liberty-apps
```

---

## WAS Cell Topology (Simulated via Vagrant)

```
┌─────────────────────────────────────────────┐
│              WAS ND Cell                    │
│           nexusliberty-cell                 │
│                                             │
│  ┌──────────────────────────────────────┐   │
│  │  Deployment Manager (dmgr)           │   │
│  │  nexus-dmgr.<domain>                 │   │
│  │  Admin Console: :9060                │   │
│  │  SOAP Port: :8879                    │   │
│  └──────────────────────────────────────┘   │
│                                             │
│  ┌────────────────┐  ┌────────────────┐     │
│  │  Managed Node 1│  │  Managed Node 2│     │
│  │  nexus-was1    │  │  nexus-was2    │     │
│  │  AppServer1    │  │  AppServer2    │     │
│  │  :9080/:9443   │  │  :9080/:9443   │     │
│  └────────────────┘  └────────────────┘     │
│                                             │
│  ┌──────────────────────────────────────┐   │
│  │  IBM HTTP Server (IHS)               │   │
│  │  nexus-ihs.<domain>                  │   │
│  │  :80/:443  → WAS cluster             │   │
│  └──────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

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

## About This CLAUDE.md

This file is the primary context document for [Claude Code](https://claude.ai/code)
AI-assisted development sessions. It provides:

- Full project architecture and technology decisions
- Infrastructure topology and IP allocation
- Phase-by-phase implementation plan with checkboxes
- Command reference for all tools in the stack
- Baseline configuration examples (server.xml, CR manifests, GitHub Actions)
- Operational runbook notes

Every Claude Code session in this repo starts by reading this file, giving the AI
assistant complete context without re-explaining the project from scratch. This
pattern significantly accelerates development velocity and keeps sessions focused.

---

## Notes for Claude Code Sessions

- Always check `oc get clusteroperators` before assuming cluster is healthy
- Liberty Operator CRDs may take 5-10 min to register after install
- OKD image pulls may be slow first time — use `oc get events -n liberty-apps` to monitor
- IHS plugin configuration requires matching WAS version — check fix pack levels
- When writing wsadmin scripts, use Jython (not Jacl) — industry standard now
- Vagrant WAS simulation is for config/automation demo only — not a licensed WAS install
- Use Open Liberty (open-source upstream) for container builds — functionally equivalent
  to WebSphere Liberty, no license required for portfolio work
- Update IP addresses and domain names in this file to match your actual environment
