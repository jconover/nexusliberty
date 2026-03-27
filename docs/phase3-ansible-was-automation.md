# Phase 3: Ansible WAS ND Automation

Step-by-step guide to bring up the Vagrant WAS ND simulation environment and run the Ansible playbooks that automate the full WAS cell lifecycle.

## Prerequisites

- Phase 1 and 2 complete (Liberty Operator and containerized app working on OKD)
- Vagrant installed (`vagrant --version`) with VirtualBox or libvirt provider
- Ansible installed (`ansible --version` — 2.12+)
- `ansible.posix` collection installed (`ansible-galaxy collection install ansible.posix`)
- At least 6GB free RAM for all 4 VMs (or run them selectively)

## What We're Building

```
┌─────────────────────────────────────────────────────────────┐
│                   Vagrant Private Network                    │
│                     192.168.56.0/24                          │
│                                                             │
│  ┌──────────────────┐    ┌──────────────────┐               │
│  │  nexus-dmgr      │    │  nexus-ihs       │               │
│  │  .56.10           │    │  .56.13           │               │
│  │  Deployment Mgr   │    │  IBM HTTP Server  │               │
│  │  :9060 admin      │    │  :80/:443         │               │
│  │  :8879 SOAP       │    │  WebSphere Plugin │               │
│  └──────────────────┘    └────────┬─────────┘               │
│                                   │ Round Robin              │
│            ┌──────────────────────┼──────────────────┐       │
│            ▼                                         ▼       │
│  ┌──────────────────┐    ┌──────────────────┐               │
│  │  nexus-was1      │    │  nexus-was2      │               │
│  │  .56.11           │    │  .56.12           │               │
│  │  AppServer1      │    │  AppServer2      │               │
│  │  :9080/:9443     │    │  :9080/:9443     │               │
│  └──────────────────┘    └──────────────────┘               │
└─────────────────────────────────────────────────────────────┘
```

## Step 1 — Start the Vagrant VMs

```bash
cd vagrant/

# Bring up all 4 VMs (takes ~5-10 min first time — downloads CentOS box)
vagrant up

# Or bring them up one at a time if RAM is tight
vagrant up nexus-dmgr
vagrant up nexus-was1
vagrant up nexus-was2
vagrant up nexus-ihs

# Verify all VMs are running
vagrant status

# Expected output (provider may be virtualbox or libvirt):
# nexus-dmgr    running (libvirt)
# nexus-was1    running (libvirt)
# nexus-was2    running (libvirt)
# nexus-ihs     running (libvirt)
```

### Verify SSH access

```bash
# Test SSH to each VM
vagrant ssh nexus-dmgr -c "hostname && cat /etc/redhat-release"
vagrant ssh nexus-was1 -c "hostname && java -version 2>&1 | head -1"

# Generate SSH config for Ansible (if not using Vagrant's insecure key)
vagrant ssh-config > ~/.ssh/vagrant-config
```

### Verify the simulation structure

Each VM has the IBM directory tree pre-created by the provisioning scripts:

```bash
vagrant ssh nexus-dmgr -c "ls /opt/IBM/WebSphere/AppServer/"
# Expected: bin  java  profiles  properties

vagrant ssh nexus-ihs -c "ls /opt/IBM/HTTPServer/"
# Expected: bin  conf  htdocs  logs
```

## Step 2 — Verify Ansible Connectivity

```bash
cd ansible/

# Ping all hosts
ansible all -m ping

# Expected: all 4 hosts return SUCCESS

# If ping fails, check:
#   1. VMs are running (vagrant status)
#   2. SSH key path in inventory/group_vars/all.yml
#   3. Network: can you `ping 192.168.56.10` from your workstation?
```

### Troubleshooting SSH keys

```bash
# Option A: Use Vagrant's insecure key (default in group_vars/all.yml)
# Works out of the box for most setups

# Option B: Point to per-VM keys from vagrant ssh-config
export VAGRANT_SSH_KEY=$(vagrant ssh-config nexus-dmgr | grep IdentityFile | awk '{print $2}')
ansible all -m ping

# Option C: Copy your SSH key to all VMs
for vm in nexus-dmgr nexus-was1 nexus-was2 nexus-ihs; do
  vagrant ssh $vm -c "mkdir -p ~/.ssh"
  cat ~/.ssh/id_rsa.pub | vagrant ssh $vm -c "cat >> ~/.ssh/authorized_keys"
done
```

## Step 3 — Run Playbook 1: WAS Base Install

Installs prerequisites, Java 11, creates the `wasadmin` user, and sets up the IBM directory structure on all WAS nodes.

```bash
# Dry run first (shows what would change without changing anything)
ansible-playbook playbooks/was-install.yml --check

# Run for real
ansible-playbook playbooks/was-install.yml

# Run only specific tags
ansible-playbook playbooks/was-install.yml --tags prereqs
ansible-playbook playbooks/was-install.yml --tags java
ansible-playbook playbooks/was-install.yml --tags verify
```

### What to verify after

```bash
# Check versionInfo works on dmgr
vagrant ssh nexus-dmgr -c "sudo -u wasadmin /opt/IBM/WebSphere/AppServer/bin/versionInfo.sh"

# Should show:
# Product Name: IBM WebSphere Application Server
# Product Version: 9.0.5.15
```

## Step 4 — Run Playbook 2: WAS Cluster Creation

Creates the Deployment Manager profile, federates managed nodes, and creates the application cluster.

```bash
# Full run (all 3 plays in order)
ansible-playbook playbooks/was-cluster.yml

# Or run each stage independently:

# Stage 1: Dmgr profile only
ansible-playbook playbooks/was-cluster.yml --tags dmgr-profile

# Stage 2: Federate managed nodes
ansible-playbook playbooks/was-cluster.yml --tags federation

# Stage 3: Create cluster
ansible-playbook playbooks/was-cluster.yml --tags cluster-create
```

### What to verify after

```bash
# Check cell.xml has both managed nodes
vagrant ssh nexus-dmgr -c "cat /opt/IBM/WebSphere/AppServer/profiles/Dmgr01/config/cells/nexusliberty-cell/cell.xml"

# Check cluster.xml has both members
vagrant ssh nexus-dmgr -c "cat /opt/IBM/WebSphere/AppServer/profiles/Dmgr01/config/cells/nexusliberty-cell/clusters/nexusliberty_cluster/cluster.xml"

# Check federation records on managed nodes
vagrant ssh nexus-was1 -c "cat /opt/IBM/WebSphere/AppServer/profiles/AppSrv01/.federated"
vagrant ssh nexus-was2 -c "cat /opt/IBM/WebSphere/AppServer/profiles/AppSrv02/.federated"
```

## Step 5 — Run Playbook 3: Application Deployment

Deploys the nexus-app WAR to the cluster via wsadmin, then runs a health check.

```bash
ansible-playbook playbooks/was-deploy-app.yml
```

> **Note**: If you haven't built the WAR (`mvn package` in `app/`), the playbook
> creates a placeholder WAR and proceeds. This is fine for demonstrating the
> automation workflow.

### What to verify after

```bash
# Check the WAR is in installedApps
vagrant ssh nexus-dmgr -c "ls /opt/IBM/WebSphere/AppServer/profiles/Dmgr01/installedApps/nexusliberty-cell/"

# Run health check manually
vagrant ssh nexus-dmgr -c "sudo -u wasadmin python3 /opt/IBM/WebSphere/AppServer/profiles/Dmgr01/scripts/health-check.py"

# Should show: HEALTH CHECK: ALL COMPONENTS HEALTHY
```

## Step 6 — Run Playbook 4: IHS Installation

Installs IBM HTTP Server and configures the WebSphere plugin to load-balance across the cluster.

```bash
ansible-playbook playbooks/ihs-install.yml
```

### What to verify after

```bash
# Check httpd.conf
vagrant ssh nexus-ihs -c "cat /opt/IBM/HTTPServer/conf/httpd.conf"

# Check plugin-cfg.xml routes to both AppServers
vagrant ssh nexus-ihs -c "cat /opt/IBM/WebSphere/Plugins/config/webserver1/plugin-cfg.xml"

# Check IHS status (mock — prints simulated output, no real httpd process)
vagrant ssh nexus-ihs -c "sudo -u wasadmin /opt/IBM/HTTPServer/bin/apachectl status"

# Note: This is a simulated environment — there is no real HTTP server process.
# The curl test below would work on a real IHS install but not in this simulation.
# Verify the config files above to confirm the automation is correct.
```

## Step 7 — Run All Playbooks End-to-End

To provision the entire cell from scratch:

```bash
cd ansible/

ansible-playbook playbooks/was-install.yml
ansible-playbook playbooks/was-cluster.yml
ansible-playbook playbooks/was-deploy-app.yml
ansible-playbook playbooks/ihs-install.yml
```

Or create a site playbook that imports them all:

```bash
# Quick one-liner to run all in sequence
for pb in was-install was-cluster was-deploy-app ihs-install; do
  ansible-playbook playbooks/${pb}.yml || { echo "FAILED: ${pb}"; exit 1; }
done
```

## Vagrant Management Commands

```bash
cd vagrant/

# Check VM status
vagrant status

# SSH into a VM
vagrant ssh nexus-dmgr

# Halt (stop) all VMs (preserves state)
vagrant halt

# Destroy all VMs (delete completely — re-run vagrant up to recreate)
vagrant destroy -f

# Re-provision without destroying (re-runs shell scripts)
vagrant provision

# Re-provision a single VM
vagrant provision nexus-was1

# Snapshot before making changes (easy rollback)
vagrant snapshot save nexus-dmgr clean-state
vagrant snapshot restore nexus-dmgr clean-state
```

## Port Forwards (Host Access)

When VMs are running, these ports are forwarded to your workstation:

| Service | VM | Guest Port | Host Port |
|---|---|---|---|
| WAS Admin Console | nexus-dmgr | 9060 | 9060 |
| WAS Admin (HTTPS) | nexus-dmgr | 9043 | 9043 |
| SOAP Connector | nexus-dmgr | 8879 | 8879 |
| AppServer1 HTTP | nexus-was1 | 9080 | 19080 |
| AppServer1 HTTPS | nexus-was1 | 9443 | 19443 |
| AppServer2 HTTP | nexus-was2 | 9080 | 29080 |
| AppServer2 HTTPS | nexus-was2 | 9443 | 29443 |
| IHS HTTP | nexus-ihs | 80 | 8080 |
| IHS HTTPS | nexus-ihs | 443 | 8443 |

## Ansible Role Reference

| Role | Target | Purpose |
|---|---|---|
| `was-base` | `was` (dmgr + nodes) | OS prereqs, Java 11, wasadmin user, IBM dirs, firewall |
| `was-dmgr` | `dmgr` | Dmgr profile, cell.xml, security.xml, start/stop scripts |
| `was-nodeagent` | `was_nodes` | AppSrv profiles, federation, node agent, start/stop scripts |
| `was-cluster` | `dmgr` | Cluster definition, member registration, JDBC resources |
| `was-deploy` | `dmgr` | App deployment via wsadmin, post-deploy health check |
| `ihs-proxy` | `ihs` | httpd.conf, plugin-cfg.xml, apachectl, landing page |

## wsadmin Scripts

Located in `scripts/wsadmin/`. Can be run standalone with Python 3 or via the mock `wsadmin.sh`:

```bash
# Standalone
python3 scripts/wsadmin/health-check.py

# Via mock wsadmin (as it would run on a real WAS server)
/opt/IBM/WebSphere/AppServer/bin/wsadmin.sh -lang jython -f scripts/wsadmin/health-check.py
```

| Script | Purpose |
|---|---|
| `create-cluster.py` | Create cluster, add members, configure session management |
| `deploy-app.py` | Install/update WAR, configure classloader, start app |
| `health-check.py` | Verify all cell components: dmgr, agents, servers, cluster, apps |

## Troubleshooting

**Vagrant up fails with "VBoxManage not found"**
- Install VirtualBox: `sudo apt install virtualbox` (Ubuntu/WSL2)
- Or use libvirt provider: `vagrant up --provider=libvirt`

**Ansible ping fails**
- Check VMs are running: `vagrant status`
- Check network: `ping 192.168.56.10`
- Check SSH key: `vagrant ssh nexus-dmgr` (if this works, SSH is fine)
- Try explicit key: `ansible all -m ping --private-key=.vagrant/machines/nexus-dmgr/virtualbox/private_key`

**Playbook fails on firewalld**
- Ensure `ansible.posix` collection is installed:
  ```bash
  ansible-galaxy collection install ansible.posix
  ```

**Running on WSL2?**
- VirtualBox VMs may need Hyper-V disabled or use WSL2-compatible VirtualBox 7+
- Alternative: run Vagrant on the Windows host and Ansible from WSL2 targeting the VMs
