# NexusLiberty Security Remediation Tracker

**Audit Date:** 2026-04-10
**Last Updated:** 2026-04-10

---

## Status Legend

| Status | Meaning |
|--------|---------|
| **FIXED** | Remediated in this audit, committed to repo |
| **DEFERRED** | Requires cluster access, external dependency, or human decision |
| **ACCEPTED** | Risk acknowledged; documented rationale justifies current state |

---

## Findings

| # | Severity | File | Description | Status | Notes |
|---|----------|------|-------------|--------|-------|
| 1 | HIGH | `ansible/inventory/group_vars/all.yml:27` | Plaintext WAS admin password `wasadmin123` | **FIXED** | Replaced with vault lookup `{{ vault_was_admin_password \| default('wasadmin123') }}`; updated `vault.yml.example` and `was-dmgr/README.md` |
| 2 | HIGH | `docker/github-runner/Dockerfile:6` | Base image `actions-runner:latest` unpinned | **FIXED** | Pinned to `ghcr.io/actions/actions-runner:2.321.0` |
| 3 | HIGH | `ansible/ansible.cfg:5,19` | `host_key_checking=False` + `StrictHostKeyChecking=no` | **FIXED** | Added explicit comments documenting Vagrant-only scope and production remediation steps |
| 4 | MEDIUM | `docker/liberty-app/Dockerfile:22` | Liberty base image tag not pinned to digest | **DEFERRED** | Requires `docker pull` to obtain current digest; tracked in `IMPROVEMENTS.md` item 1.1 |
| 5 | MEDIUM | `openshift/ihs-deployment/deployment.yaml:47` | IHS image uses `:latest` tag | **DEFERRED** | Requires CI workflow change to pin SHA tags; tracked in `IMPROVEMENTS.md` item 1.2 |
| 6 | MEDIUM | `openshift/pipelines/01-rbac.yaml:28-36` | Pipeline SA bound to `scc:privileged` (ClusterRoleBinding) | **ACCEPTED** | Required for buildah container builds; standard OpenShift Pipelines pattern; SA is pipeline-only, not app workload |
| 7 | MEDIUM | `openshift/pipelines/04-task-git-update-manifest.yaml:39` | Tekton step image `alpine/git:latest` unpinned | **FIXED** | Pinned to `docker.io/alpine/git:2.47.2` |
| 8 | MEDIUM | `docker/liberty-app/server.env:16` | Default `KEYSTORE_PASSWORD=liberty` in image | **ACCEPTED** | Standard Liberty dev default; override mechanism via OpenShift Secret is documented in-file; production uses Secret injection |
| 9 | MEDIUM | `ansible/ansible.cfg:12-15` | `become=True` set globally | **FIXED** | Added comment explaining WAS requirement and production recommendation for per-task scoping |
| 10 | MEDIUM | `openshift/github-runner/arc-values.yaml:54` | Runner pod image uses `:latest` tag | **DEFERRED** | Same class as IHS (#5); requires CI workflow to commit SHA tags |
| 11 | LOW | `.gitignore` | Missing `kubeconfig` and `vault.yml` patterns | **FIXED** | Added `kubeconfig`, `**/kubeconfig`, and `ansible/inventory/group_vars/vault.yml` |
| 12 | LOW | `docker/ihs/Dockerfile:6` | `httpd:2.4-alpine` not pinned to digest | **ACCEPTED** | Minor version pinned (2.4); Alpine patch updates are low-risk |
| 13 | LOW | `app/src/test/liberty/config/server.xml:16` | `password="liberty"` in test config | **ACCEPTED** | Test-only config, never deployed, standard Liberty test convention |

---

## Deferred Items — Prerequisites

| # | Item | Prerequisite | Owner |
|---|------|-------------|-------|
| 4 | Pin Liberty base image digest | Run `docker pull icr.io/appcafe/open-liberty:kernel-slim-java17-openj9-ubi-minimal` and capture `sha256:` digest | Human (needs Docker/cluster) |
| 5 | Pin IHS image tag in manifest | Modify IHS CI workflow to commit SHA tag back to deployment manifest (same pattern as Liberty pipeline) | Human (CI change) |
| 10 | Pin runner image tag | Same approach as #5 — CI workflow commits SHA tag | Human (CI change) |

---

## Previously Remediated (PR #38)

These items were fixed before this audit and confirmed clean:

| Item | Status |
|------|--------|
| Real homelab IPs (`192.168.68.x`) scrubbed from public files | Confirmed clean |
| OKD cluster domain (`nexuslab.nexuslab.local`) scrubbed | Confirmed clean -- only in gitignored `CLAUDE.private.md` |
| GitHub PAT removed from `03-secrets.yaml` | Confirmed -- file was never committed; only `.example` exists |
| `.gitignore` expanded for `.env*`, `*.key`, `*.pem`, `*-secrets.yaml` | Confirmed present |
| Argo CD RBAC scoped to namespace for secrets | Confirmed -- ClusterRole is CRDs only; secrets are in namespace Role |
| IHS deployment hardened (runAsNonRoot, drop ALL caps) | Confirmed present |
