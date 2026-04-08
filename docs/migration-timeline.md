# WAS-to-Liberty Migration Timeline

How a legacy WAS ND environment transitions to containerized Liberty on OpenShift. This is the narrative NexusLiberty demonstrates end-to-end.

---

## The Two Environments

| Environment | What it is | How you manage it | Project location |
|---|---|---|---|
| WAS ND Cell (Vagrant) | Simulated legacy on-prem WAS | SSH, wsadmin, Ansible | `vagrant/`, `ansible/`, `scripts/wsadmin/` |
| Liberty on OKD (Beelink cluster) | Modernized cloud-native deployment | `oc` commands, GitOps, CI/CD | `docker/`, `openshift/`, `.github/workflows/` |

The Vagrant VMs do **not** migrate into OKD. The **application** migrates. The VMs represent the "before" state and eventually get decommissioned.

---

## Migration Phases

```
Phase 1: Legacy Ops (WAS only)
├── All traffic goes through IHS → WAS cluster
├── Managed via wsadmin, Ansible, SSH
└── This is where most enterprises start
         │
         ▼
Phase 2: Coexistence (WAS + Liberty side-by-side)
├── Application is refactored for Liberty (server.xml replaces WAS admin config)
├── Liberty container built and deployed to OKD
├── Both environments run simultaneously
├── WAS still handles production traffic
├── Liberty handles test/staging traffic via OpenShift Routes
├── Ops teams manage BOTH:
│   ├── WAS: wsadmin, Ansible, SSH (legacy runbook Section 1, 3.1)
│   └── Liberty: oc commands, CI/CD (runbook Section 2+)
└── This is the hardest phase — two worlds at once
         │
         ▼
Phase 3: Cutover
├── Traffic shifts from IHS/WAS → OpenShift Route/Liberty
├── Methods: DNS switch, load balancer repoint, or blue-green
├── Rollback plan: revert traffic to WAS if issues arise
└── Session state: Liberty uses Hazelcast for session replication,
    so no session loss between Liberty pods
         │
         ▼
Phase 4: Decommission (Liberty only)
├── WAS environment is shut down
├── Vagrant VMs destroyed (vagrant destroy)
├── Ansible playbooks archived (they proved you could automate legacy)
├── All operations are now via oc, GitOps, CI/CD
└── Runbook Section 2+ is your only ops guide going forward
```

---

## What Changes at Each Phase

### Application Config

| Aspect | WAS ND | Liberty |
|---|---|---|
| Server config | Admin console + `wsadmin` scripts | `server.xml` (declarative, version-controlled) |
| App deployment | EAR/WAR via wsadmin or admin console | Container image via CI/CD pipeline |
| Feature management | Fix packs + feature packs (monolithic) | Feature tags in `server.xml` (only load what you need) |
| Clustering | WAS ND cell with node agents | Kubernetes replicas + Hazelcast JCache |
| Health checks | Manual or custom scripts | MicroProfile Health (`/health/ready`, `/health/live`) |
| Metrics | PMI / custom JMX | MicroProfile Metrics (`/metrics`) → Prometheus |

### Operations

| Task | WAS ND | Liberty on OKD |
|---|---|---|
| Check status | `serverStatus.sh -all` via SSH | `oc get pods -n liberty-apps` |
| View logs | SSH + `tail -f SystemOut.log` | `oc logs -f <pod>` |
| Deploy app | wsadmin script or Ansible playbook | Git push → CI/CD → Argo CD sync |
| Scale | Add WAS node + run wsadmin | `oc scale` or edit CR replicas |
| Restart | SSH + `stopServer` / `startServer` | `oc rollout restart` |
| Rollback | Restore EAR from backup via wsadmin | `oc rollout undo` or git revert |

### Traffic Flow

```
BEFORE (WAS):
  Users → IHS (:80/:443) → WAS Plugin → WAS Cluster (AppServer1, AppServer2)

DURING (Coexistence):
  Production users → IHS → WAS Cluster
  Test users       → OpenShift Route → Liberty Pods

AFTER (Liberty):
  Users → OpenShift Route → IHS container (optional) → Liberty Pods
          (or directly to Liberty via Route, skipping IHS)
```

---

## Why Both Environments Exist in This Project

The point of NexusLiberty is to demonstrate the **complete modernization lifecycle**. An interviewer asking "How would you migrate WAS to Liberty?" expects you to understand both sides:

- **"I can automate the legacy environment"** — Ansible playbooks, wsadmin scripts, Vagrant simulation
- **"I can build the modern target"** — Liberty containers, OpenShift Operator, CI/CD, monitoring
- **"I can bridge them"** — understanding what changes in operations, where the risks are during cutover, and how to run both during coexistence

The two environments are not competing — they are chapters in the same story.
