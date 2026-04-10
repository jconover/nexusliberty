# NexusLiberty — Improvement Backlog

Prioritized list of improvements that require human decisions, external dependencies,
or real cluster connectivity. Items are grouped by priority.

---

## Priority 1 — High Impact, Low Effort

### 1.1 Pin Liberty base image to digest
**File:** `docker/liberty-app/Dockerfile`
**Current:** `icr.io/appcafe/open-liberty:kernel-slim-java17-openj9-ubi-minimal`
**Action:** Pin to a specific digest for reproducible builds:
```dockerfile
FROM icr.io/appcafe/open-liberty:kernel-slim-java17-openj9-ubi-minimal@sha256:<digest>
```
**Why:** Prevents silent base image drift between builds. Run `docker pull` and note the digest.
**Requires:** Cluster or Docker access to pull and verify the current digest.

### 1.2 Pin IHS image tag in deployment manifest
**File:** `openshift/ihs-deployment/deployment.yaml`
**Current:** Uses `:latest` tag.
**Action:** Either update IHS CI workflow to commit the SHA tag back to the deployment manifest
(like the Liberty pipeline does), or pin to a known good SHA tag.
**Why:** `:latest` in a production manifest is a red flag in any enterprise review.

### 1.3 Add Tekton smoke test task
**File:** `openshift/pipelines/05-pipeline.yaml`
**Action:** Add a final pipeline task after `update-manifest` that curls the health endpoint
and verifies the new deployment is healthy:
```yaml
- name: smoke-test
  runAfter:
    - update-manifest
  taskSpec:
    steps:
      - name: wait-and-check
        image: curlimages/curl:latest
        script: |
          sleep 60  # wait for ArgoCD sync
          curl -f http://nexusliberty-app.liberty-apps.svc:9080/health/ready
```
**Why:** Closes the feedback loop — a pipeline that builds and pushes but never validates
is only half a pipeline.
**Requires:** Cluster access to test.

---

## Priority 2 — Enterprise Depth (Interview Talking Points)

### 2.1 cert-manager or OpenShift service serving certificates
**Action:** Add a stub manifest or documentation showing how TLS certificates would be
managed in production. Options:
- cert-manager with a ClusterIssuer (Let's Encrypt or internal CA)
- OpenShift service serving certificates (annotation-based, auto-rotated)
**Files:** New `openshift/liberty-deployment/certificate.yaml` or documented in Phase 5 guide.
**Why:** "How do you handle certificates?" is a common interview question. The current setup
uses edge-terminated Routes (good), but doesn't show certificate lifecycle management.

### 2.2 Network segmentation documentation
**Action:** Add a brief section to the Phase 5 doc or README explaining the NetworkPolicy
strategy: default-deny ingress, explicit allow for IHS → Liberty, Liberty ↔ Liberty
(Hazelcast), and Prometheus → Liberty.
**Why:** NetworkPolicy is already implemented (`openshift/liberty-deployment/networkpolicy.yaml`)
but not called out prominently. This is a strong enterprise security talking point.

### 2.3 Real database connectivity
**Action:** Deploy a PostgreSQL or DB2 instance (Helm chart or Operator) and uncomment
the JNDI datasource stub in `server.xml`. Add a `/api/db-check` endpoint.
**Why:** Demonstrates real connection pooling, JNDI lookup, and Secret management for
database credentials — the bread and butter of enterprise middleware.
**Requires:** Cluster access, database deployment.

### 2.4 ImageStream for internal image references
**Action:** Create an ImageStream in `liberty-apps` namespace that mirrors the GHCR image.
Update the Liberty Operator CR to reference the ImageStream tag instead of the raw GHCR URL.
**Why:** ImageStreams are the OpenShift-native way to manage container images. Demonstrates
familiarity with OpenShift-specific patterns vs. plain Kubernetes.
**Requires:** Cluster access.

---

## Priority 3 — Production Hardening

### 3.1 Pod topology spread constraints
**File:** `openshift/liberty-deployment/WebSphereLibertyApplication.yaml`
**Action:** Add `topologySpreadConstraints` in addition to pod anti-affinity for more
predictable pod distribution. The current `preferredDuringScheduling` anti-affinity is
best-effort — topology spread constraints provide harder guarantees.

### 3.2 Resource quota alignment with HPA
**Files:** `openshift/monitoring/resourcequota.yaml`, `openshift/liberty-deployment/hpa.yaml`
**Action:** Verify the ResourceQuota (`limits.cpu: 4`, `limits.memory: 4Gi`) can accommodate
max HPA replicas (4 pods × 500m CPU = 2 CPU, 4 pods × 768Mi = 3Gi). Current quota is
sufficient, but document the relationship.

### 3.3 Backup and disaster recovery documentation
**Action:** Document the recovery procedure: what to do if the cluster goes down, how to
rebuild from the Git repo (the whole point of GitOps). Include:
- ArgoCD re-bootstrap steps
- Secret re-creation commands
- Validation checklist
**Why:** "What's your DR plan?" is a standard enterprise operations question.

### 3.4 OPA/Gatekeeper policy constraints
**Action:** Add ConstraintTemplate examples for common enterprise policies:
- Require resource limits on all pods
- Require non-root security context
- Block `latest` image tags
**Why:** Policy-as-code is increasingly expected in enterprise OpenShift environments.
**Requires:** Gatekeeper or OPA installed on the cluster.

---

## Priority 4 — Nice to Have

### 4.1 Kustomize overlays for multi-environment
**Action:** Restructure `openshift/liberty-deployment/` into Kustomize base + overlays
(dev, staging, prod) with environment-specific replicas, resource limits, and image tags.
**Why:** Shows environment promotion patterns. Currently single-environment.

### 4.2 OpenTelemetry tracing integration
**Action:** Liberty's `mpTelemetry-1.1` feature (included in `microProfile-6.1`) can export
traces. Add an OpenTelemetry Collector sidecar or Operator and configure trace export.
**Why:** Distributed tracing is a strong observability talking point.

### 4.3 Canary/blue-green deployment strategy
**Action:** Document or implement a canary deployment using OpenShift Route weights or
Argo Rollouts.
**Why:** Shows deployment strategy sophistication beyond basic rolling update.

### 4.4 Ansible Vault for WAS credentials
**Action:** Use `ansible-vault` to encrypt the WAS admin credentials in `group_vars/`
instead of plaintext defaults. Add a vault password file to `.gitignore`.
**Why:** Shows security awareness even in the simulation environment.

---

## Already Addressed (This Review)

- [x] server.xml: Added JNDI datasource stub, LDAP/SSO stub, executor tuning, graceful shutdown docs
- [x] server.env: Created with env var substitution for keystore password and JVM tuning
- [x] IHS deployment: Added securityContext (runAsNonRoot, drop ALL caps), rolling update strategy
- [x] IHS route: Removed hardcoded hostname (OKD auto-generates)
- [x] HPA: Created `openshift/liberty-deployment/hpa.yaml` with CPU/memory scaling
- [x] README: Added tech badges, CI/CD pipeline architecture section, Known Issues, Liberty Operator callout
- [x] Validation workflow: Created `.github/workflows/validate.yml` (YAML lint, Dockerfile lint, kube-score)
- [x] IP scrub: Replaced real IPs and `nexuslab.nexuslab.local` with placeholders in docs and manifests
- [x] httpd.conf: Replaced real email with placeholder
- [x] GitOps subscription: Replaced hardcoded hostname in comment
