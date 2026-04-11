# NexusLiberty -- Remaining Improvements

Items identified during the portfolio audit that require human action
(credentials, environment access, or judgment calls).

---

## Low Priority (Polish)

### 1. Vagrant IPs in Ansible inventory
**File:** `ansible/inventory/hosts.ini`
**Issue:** Contains hardcoded `192.168.121.x` IPs from libvirt/Vagrant.
**Risk:** Low -- these are ephemeral VM IPs, not real infrastructure.
**Action:** Optionally replace with Ansible variables or add a comment block
explaining these are auto-assigned Vagrant IPs for the WAS ND simulation.

### 2. Default simulation passwords in tracked files
**Files:**
- `ansible/inventory/group_vars/all.yml` -- `wasadmin123` default
- `docker/liberty-app/server.env` -- `KEYSTORE_PASSWORD=liberty`

**Risk:** Low -- both serve the Vagrant simulation / local dev context and
are documented as "override in production via Vault / Secrets."
**Action:** No change needed. Both files already document the production
override path. A reviewer may flag them; the existing comments address it.

---

## Already Fixed (This Audit)

- [x] ArgoCD OutOfSync -- probes moved to `spec.probes.*` per CRD schema (PR #43)
- [x] `spec.license` removed -- not part of Open Liberty Operator CRD (PR #43)
- [x] Rolling update strategy added -- `maxUnavailable: 0, maxSurge: 1` (this PR)
- [x] Screenshot guide created -- `docs/SCREENSHOT_GUIDE.md`
