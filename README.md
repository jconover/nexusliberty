# NexusLiberty

[![Build and Push Liberty Image](https://github.com/jconover/nexusliberty/actions/workflows/liberty-build.yml/badge.svg)](https://github.com/jconover/nexusliberty/actions/workflows/liberty-build.yml)
[![Ansible Lint](https://github.com/jconover/nexusliberty/actions/workflows/ansible-lint.yml/badge.svg)](https://github.com/jconover/nexusliberty/actions/workflows/ansible-lint.yml)

Enterprise middleware modernization platform demonstrating automated WAS ND management, WebSphere Liberty containerization, and OpenShift deployment using Ansible, GitHub Actions, Argo CD, and the WebSphere Liberty Operator.

## Architecture

```
Push code → GitHub Actions (CI) → Build Liberty image → Push to GHCR
                                                            ↓
            Argo CD (on OKD) ← watches repo ← detects manifest change → deploys to cluster
```

- **CI**: GitHub Actions builds and pushes the Liberty container image to GHCR on changes to `docker/liberty-app/` or `app/`
- **CD**: OpenShift GitOps (Argo CD) runs on the OKD cluster, watches the `openshift/` manifests in this repo, and auto-syncs deployments

## Tech Stack

| Layer | Technology |
|---|---|
| Container Platform | Red Hat OKD 4.x (OpenShift) |
| Middleware Runtime | IBM WebSphere Liberty (Open Liberty) |
| Legacy Middleware | IBM WAS ND (simulated via Vagrant) |
| CI | GitHub Actions |
| CD | OpenShift GitOps (Argo CD) |
| Automation | Ansible |
| Containers | Docker / Podman |
| Monitoring | Prometheus + Grafana |

## Project Phases

1. **OKD Cluster Setup** — 3-node bare metal OKD 4.x cluster (Beelink SER5 Max homelab)
2. **Liberty Containerization** — Dockerfile, server.xml, GHCR, OpenShift Route
3. **Ansible WAS Automation** — Vagrant WAS ND simulation, Ansible playbooks, wsadmin scripts
4. **CI/CD Pipeline** — GitHub Actions CI + Argo CD GitOps delivery
5. **HA & Operations** — Clustering, IHS load balancing, Prometheus metrics, Grafana dashboards

## Quick Start

```bash
# Build Liberty image locally
docker build -t nexusliberty-app:latest ./docker/liberty-app/

# Test locally
docker run -p 9080:9080 -p 9443:9443 nexusliberty-app:latest

# Deploy to OKD (via Argo CD - auto-syncs from this repo)
# Or manually:
oc apply -f openshift/liberty-deployment/WebSphereLibertyApplication.yaml
```

## Repository Structure

```
nexusliberty/
├── app/                    # Sample Java EE application (Maven)
├── ansible/                # Ansible playbooks and roles for WAS automation
├── cluster/                # OKD cluster config (operators, namespaces, GitOps)
├── docker/liberty-app/     # Liberty container image (Dockerfile + server.xml)
├── openshift/              # OpenShift deployment manifests (Argo CD watches this)
├── scripts/                # wsadmin Jython scripts and bash utilities
├── vagrant/                # WAS ND on-prem simulation
├── docs/                   # Architecture docs, runbooks, migration guides
└── .github/workflows/      # GitHub Actions CI pipelines
```

## License

Portfolio project — see [devopsnexus.io](https://devopsnexus.io) for more.
