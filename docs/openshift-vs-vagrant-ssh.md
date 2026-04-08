# SSH Access: OpenShift vs Vagrant WAS VMs

There are **two separate environments** in this project, and the SSH story is different for each.

---

## 1. WAS Vagrant VMs (Simulated Legacy Environment)

The hostnames like `nexus-dmgr.nexuslab.local`, `nexus-was1.nexuslab.local`, `nexus-ihs.nexuslab.local` are **Vagrant virtual machines**, not OpenShift nodes. They only exist if you've run `vagrant up` from the `vagrant/` directory.

### Check if they exist

```bash
cd ~/projects/nexusliberty/vagrant
vagrant status
```

- If you see machines listed as `running`, you can SSH with `vagrant ssh dmgr`, `vagrant ssh was1`, etc.
- If you've never run `vagrant up`, they don't exist yet. The WAS ND cell is a simulation you spin up on demand.

---

## 2. OpenShift/OKD Nodes (Real Cluster)

Your real OKD cluster nodes (`okd-node1/2/3.nexuslab.nexuslab.local`) are **not meant for regular SSH access**. OKD runs on CoreOS, which is immutable — you don't install packages or manage services over SSH like traditional servers.

Instead, you interact with everything through `oc` commands:

| Traditional server | OpenShift equivalent |
|---|---|
| `ssh user@server` | `oc debug node/okd-node1.nexuslab.nexuslab.local` (emergency only) |
| `ssh` into app server | `oc exec -it <pod-name> -n liberty-apps -- bash` |
| Check logs via SSH | `oc logs <pod-name> -n liberty-apps` |
| Check process status | `oc get pods -n liberty-apps` |

### Check if your OKD cluster is up

```bash
export KUBECONFIG=~/.kube/config
oc get nodes                  # Are the 3 nodes Ready?
oc get clusterversion         # Is the cluster version healthy?
oc get pods -n liberty-apps   # Are your Liberty pods running?
```

---

## Key Takeaway

- **WAS stuff** (runbook Section 1, 3.1) = Vagrant VMs, created with `vagrant up`, SSH is normal
- **Liberty/OKD stuff** (runbook Section 2+) = Beelink cluster, use `oc` commands instead of SSH
- The one exception is `oc debug node/<node>` for emergency node-level troubleshooting (e.g., etcd backup in runbook Section 7.1), but that's rare

---

## tmux Scroll / Copy Mode

To scroll up in tmux:

1. **Enter copy mode**: `Ctrl+b` then `[`
2. **Scroll**: Use arrow keys, Page Up/Page Down, or mouse wheel
3. **Exit copy mode**: Press `q` or `Esc`

If mouse mode is enabled (`set -g mouse on` in `~/.tmux.conf`), you can also just scroll with your mouse wheel.
