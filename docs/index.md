# NexusLiberty Documentation

Welcome to the NexusLiberty documentation. This project demonstrates enterprise middleware modernization from traditional IBM WebSphere Application Server deployments to containerized WebSphere Liberty running on Red Hat OpenShift (OKD).

---

## Phase Walkthroughs

Follow the phases in order for the full modernization journey:

| Phase | Guide | Summary |
|-------|-------|---------|
| 1 | [Liberty Operator Install](phase1-liberty-operator-install.md) | Install OKD, deploy the Liberty Operator, and run a sample app |
| 2 | [Liberty Containerization](phase2-liberty-containerization.md) | Build a custom Liberty container image, push to GHCR, deploy to OKD |
| 3 | [Ansible WAS Automation](phase3-ansible-was-automation.md) | Simulate a legacy WAS ND environment with Vagrant and automate it with Ansible |
| 4 | [CI/CD Pipeline](phase4-cicd-argocd.md) | GitHub Actions quality gates, Tekton on-cluster builds, Argo CD GitOps deployment |
| 5 | [HA and Operations](phase5-ha-operations.md) | Liberty clustering, IHS load balancing, Prometheus monitoring, Grafana dashboards |

## Reference

| Document | Description |
|----------|-------------|
| [WAS Operational Runbook](was-runbook.md) | Day-to-day operations for both WAS ND and Liberty on OKD |
| [Prerequisites](prerequisites.md) | Tools and dependencies needed to work with the project |
| [Project Review Findings](project-review-findings.md) | Architecture review findings and improvement roadmap |

## Quick Links

- [Back to README](../README.md)
- [GitHub Repository](https://github.com/jconover/nexusliberty)
- [Portfolio Site](https://devopsnexus.io)
