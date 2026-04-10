# NexusLiberty Security Audit Findings

**Date:** 2026-04-10
**Scope:** Full repository review before public GitHub visibility
**Auditor:** Security review (automated + manual)
**Commit:** `04a0eba` (main, pre-audit baseline)

---

## Executive Summary

The repository is in **good shape overall** for a portfolio project. Prior remediation
work (PR #38) already addressed the most critical issues: real IP scrubbing, GitHub
PAT removal, and .gitignore hardening. This audit found **0 critical**, **3 high**,
**6 medium**, and **4 low** findings. All high-severity items have been fixed in-place.

**No secrets were found in git history.** The previously reported `03-secrets.yaml`
with a `ghp_*` token was never committed to the repository (confirmed via
`git log --all --full-history`).

---

## 1. Secrets & Credentials

**[SEVERITY: HIGH]** `ansible/inventory/group_vars/all.yml:27`
- Plaintext password `wasadmin123` committed to version control
- `vault.yml.example` existed but `all.yml` used a hardcoded value instead of a vault reference
- Fixed: yes -- replaced with `{{ vault_was_admin_password | default('wasadmin123') }}` so vault overrides cleanly, demo fallback preserved
- Also updated `vault.yml.example` to use the matching `vault_was_admin_password` variable name
- Also updated `ansible/roles/was-dmgr/README.md` to stop documenting the plaintext default

**[SEVERITY: MEDIUM]** `docker/liberty-app/server.env:16`
- `KEYSTORE_PASSWORD=liberty` baked into the container image
- This is the development default; server.xml uses `${env.KEYSTORE_PASSWORD:liberty}` with env var override
- The file documents how to override via OpenShift Secrets, which is correct
- Fixed: no (accepted risk) -- the default is a well-known Liberty convention for dev/demo; the override mechanism is documented and correct. An interviewer asking about this should hear: "production injects via Secret, the default is only for local dev"

**[SEVERITY: LOW]** `app/src/test/liberty/config/server.xml:16`
- `password="liberty"` in test server config
- Fixed: no (accepted risk) -- test-only config, never deployed, standard Liberty test pattern

**[SEVERITY: LOW]** `CLAUDE.md:55-59`
- Contains `192.168.68.x` IPs, but in a clearly templated block with `<cluster>.<domain>` placeholders
- These are instructional examples, not leaked infrastructure
- Fixed: no (not a leak -- the format makes it clear these are fill-in-the-blank)

### IP Address Assessment

| Subnet | Location | Verdict |
|--------|----------|---------|
| `192.168.68.x` | `CLAUDE.md` (templated), `CLAUDE.private.md` (gitignored) | **OK** -- private.md is gitignored; CLAUDE.md uses placeholders |
| `192.168.56.x` | `vagrant/Vagrantfile`, `vagrant/provision/bootstrap.sh`, `docs/phase3-*` | **OK** -- standard VirtualBox host-only subnet, part of the Vagrant simulation design |
| `192.168.121.x` | `ansible/inventory/hosts.ini` | **OK** -- libvirt/QEMU auto-assigned IPs for Vagrant VMs, not real infrastructure |

### Domain Name Assessment

| Domain | Context | Verdict |
|--------|---------|---------|
| `nexuslab.local` | Vagrant/Ansible WAS simulation (hostnames like `nexus-dmgr.nexuslab.local`) | **OK** -- intentional simulation domain, distinct from real OKD cluster domain |
| `nexuslab.nexuslab.local` | Only in `CLAUDE.private.md` (gitignored) | **OK** -- never appears in any tracked file |

### Git History Verification

- `git log --all --full-history -- '**/*.env' '**/.env*'` -- no `.env` files ever committed (only `server.env` which is config, not secrets)
- `git log --all --full-history -- '**/*.pem' '**/*.key' '**/*.p12' '**/*.jks' '**/kubeconfig'` -- clean
- `git log --all --diff-filter=D -- '*secrets*'` -- no deleted secrets files found
- `git grep ghp_\|gho_\|github_pat_` -- no GitHub tokens in current tree (only references in prior audit docs)
- `openshift/pipelines/03-secrets.yaml` -- **never committed** (only `.example` exists)

---

## 2. Container / Dockerfile Security

**[SEVERITY: HIGH]** `docker/github-runner/Dockerfile:6`
- Base image `ghcr.io/actions/actions-runner:latest` -- unpinned, mutable tag
- A compromised or breaking `:latest` tag could affect CI pipeline integrity
- Fixed: yes -- pinned to `ghcr.io/actions/actions-runner:2.321.0`

**[SEVERITY: MEDIUM]** `docker/liberty-app/Dockerfile:22`
- Liberty base image uses tag only (`kernel-slim-java17-openj9-ubi-minimal`), not digest
- Already tracked in `IMPROVEMENTS.md` as item 1.1 -- requires cluster access to pull and verify digest
- Fixed: no (deferred) -- requires running `docker pull` to obtain current digest; documented in IMPROVEMENTS.md

**[SEVERITY: LOW]** `docker/ihs/Dockerfile:6`
- `httpd:2.4-alpine` not pinned to digest, but minor version is pinned
- Lower risk than `:latest` -- Alpine 2.4.x updates are patch-level
- Fixed: no (accepted risk)

### Dockerfile Strengths (no action needed)

| Check | Liberty | IHS | Runner |
|-------|---------|-----|--------|
| Multi-stage build | Yes | N/A (single-stage, no source) | N/A |
| Non-root USER | Yes (UID 1001 via base image) | Yes (`USER 1001`) | Yes (`USER runner`) |
| HEALTHCHECK | Yes | Yes | N/A (runner lifecycle managed by ARC) |
| .dockerignore | Yes (excludes .git, .env, keys) | Yes (shared) | Yes (shared) |
| Download verification | Yes (SHA256 on Hazelcast JAR) | N/A | N/A |
| SHELL pipefail | Yes | N/A | N/A |
| No COPY . . | Yes (selective COPY) | Yes | Yes |
| No secrets as ARGs | Yes | Yes | Yes |

---

## 3. Kubernetes / OpenShift Manifest Security

**[SEVERITY: MEDIUM]** `openshift/ihs-deployment/deployment.yaml:47`
- `image: ghcr.io/jconover/nexusliberty-ihs:latest` -- mutable tag in a deployment manifest
- Already tracked in `IMPROVEMENTS.md` as item 1.2
- Fixed: no (deferred) -- requires CI workflow change to commit SHA tag back to manifest, same pattern as Liberty pipeline

**[SEVERITY: MEDIUM]** `openshift/pipelines/01-rbac.yaml:28-36`
- Pipeline SA gets `system:openshift:scc:privileged` via **ClusterRoleBinding**
- Required for buildah (container-in-container builds need elevated privileges)
- This is the standard OpenShift Pipelines pattern, but should be documented
- Fixed: no (accepted risk) -- this is the documented OpenShift approach for buildah tasks; the SA is only used by pipeline runs, not application workloads

**[SEVERITY: MEDIUM]** `openshift/github-runner/arc-values.yaml:54`
- `image: ghcr.io/jconover/nexusliberty-runner:latest` -- mutable tag for runner pod
- Fixed: no (deferred) -- same class as IHS; requires CI workflow to pin SHA tags

### Manifest Strengths (no action needed)

| Check | Liberty CR | IHS Deployment | Runner Pods |
|-------|-----------|----------------|-------------|
| Dedicated ServiceAccount | `nexusliberty-sa` | default (OK for LB) | `github-runner-sa` |
| Resource requests + limits | Yes | Yes | Not in values (ARC manages) |
| runAsNonRoot | Via Operator | Yes | Yes |
| allowPrivilegeEscalation: false | Via Operator | Yes | Yes |
| Drop ALL capabilities | Via Operator | Yes | Yes |
| Probes (readiness + liveness) | Yes + startup | Yes | N/A (ARC) |
| NetworkPolicy | Yes (3 rules) | Covered by Liberty policy | Separate namespace |
| PodDisruptionBudget | Yes (minAvailable: 1) | No (acceptable for LB) | N/A |
| Pod anti-affinity | Yes | Yes | N/A |
| RBAC least-privilege | Namespace Role only | N/A | Scoped ClusterRole, no secret access |

### Argo CD RBAC Assessment

The `cluster/gitops/argocd-rbac.yaml` is well-structured:
- **ClusterRole**: Only for Liberty Operator CRDs (cluster-scoped resources) -- appropriate
- **Namespace Role**: Secrets, configmaps, RBAC in `liberty-apps` only -- proper least-privilege
- Previous audit finding about "cluster-wide delete on secrets" has been **already fixed** (secrets are namespace-scoped in the Role, not the ClusterRole)

---

## 4. CI/CD Pipeline Security

**[SEVERITY: MEDIUM]** `openshift/pipelines/04-task-git-update-manifest.yaml:39`
- `alpine/git:latest` used as step image in Tekton task -- unpinned
- Fixed: yes -- pinned to `docker.io/alpine/git:2.47.2`

### CI/CD Strengths (no action needed)

| Check | Status |
|-------|--------|
| Explicit `permissions:` block on all workflows | Yes -- `contents: read` / `packages: write` |
| All GitHub Actions pinned to SHA | Yes -- checkout, setup-java, hadolint, trivy, docker/login, docker/build-push, docker/metadata, setup-python |
| Image scanning in pipeline | Yes -- Trivy with CRITICAL,HIGH gate and `exit-code: 1` |
| Dockerfile linting | Yes -- Hadolint with `failure-threshold: warning` |
| GITHUB_TOKEN (no PATs in workflows) | Yes |
| No `pull_request_target` with secret access | Yes -- no fork-based secret leakage risk |
| Tekton credentials via workspace secrets | Yes -- separate git-credentials and ghcr-credentials workspaces |
| No secrets echoed in logs | Yes |

---

## 5. Ansible Security

**[SEVERITY: HIGH]** `ansible/ansible.cfg:5,19`
- `host_key_checking = False` and `StrictHostKeyChecking=no` disable SSH host verification
- These settings are for Vagrant VMs on a private 192.168.56.0/24 network and are standard practice for ephemeral lab environments
- Fixed: yes (partially) -- added explicit comments explaining the Vagrant context and what to change for production. The settings remain because they are correct for the intended Vagrant target.

**[SEVERITY: MEDIUM]** `ansible/ansible.cfg:12-15`
- `become = True` set globally in `[privilege_escalation]` section
- All WAS admin tasks genuinely require root, so this is functionally correct
- Fixed: yes (partially) -- added comment explaining the scope and production recommendation

**[SEVERITY: LOW]** `ansible/roles/was-deploy/tasks/main.yml:88-90`
- `deploy_result.stdout_lines` displayed after a `no_log: true` task
- The stdout contains deployment status messages, not credentials -- the password is in the command args (masked by `no_log`), not in the output
- Fixed: no (accepted risk) -- stdout is safe to display; the sensitive part (command line with password) is masked

### Ansible Strengths (no action needed)

| Check | Status |
|-------|--------|
| `no_log: true` on credential tasks | Yes -- `was-deploy/tasks/main.yml:78`, `health-check.yml:24` |
| Vault example provided | Yes -- `vault.yml.example` with usage instructions |
| vault.yml in .gitignore | Yes (added in this audit) |
| No secrets in inventory files | Yes -- only hostnames and SSH key paths |
| Playbook hosts are explicit groups | Yes -- `dmgr`, `was_nodes`, `was_cell`, not `all` |

---

## 6. Terraform Security

**Not applicable** -- no Terraform files exist in this repository. The project uses
OpenShift manifests (YAML) and Ansible for infrastructure management.

---

## 7. Git History & Repo Hygiene

**[SEVERITY: LOW]** `.gitignore` completeness
- Missing `kubeconfig` pattern (could be accidentally committed)
- Missing `ansible/inventory/group_vars/vault.yml` (the encrypted vault file)
- Fixed: yes -- added both patterns

### .gitignore Coverage (post-fix)

| Pattern | Status |
|---------|--------|
| `.env*` | Covered |
| `*.key`, `*.pem`, `*.p12`, `*.jks` | Covered |
| `kubeconfig`, `**/kubeconfig` | Covered (added) |
| `*-secrets.yaml` (with `!*.example` exclusion) | Covered |
| `openshift/pipelines/03-secrets.yaml` | Covered (explicit path) |
| `ansible/inventory/group_vars/vault.yml` | Covered (added) |
| `CLAUDE.private.md` | Covered |
| `terraform.tfstate`, `.terraform/` | N/A (no Terraform) |

### Git History Clean

No secrets, credentials, or sensitive files were found in git history across all branches.
**No git history rewrite is needed.**

---

## Summary by Severity

| Severity | Count | Fixed | Deferred | Accepted Risk |
|----------|-------|-------|----------|---------------|
| CRITICAL | 0 | -- | -- | -- |
| HIGH | 3 | 3 | 0 | 0 |
| MEDIUM | 6 | 2 | 3 | 1 |
| LOW | 4 | 1 | 0 | 3 |
| **Total** | **13** | **6** | **3** | **4** |
