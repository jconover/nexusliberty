# Prerequisites

Tools and dependencies needed to work with the NexusLiberty project. Instructions are for Ubuntu/Debian — adjust package managers for other distros.

---

## Required Tools

### OpenShift CLI (`oc`)

The `oc` CLI is required for all cluster operations. Download from the OKD mirror:

```bash
# Download latest stable oc client
curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz

# Extract and install
tar -xzf openshift-client-linux.tar.gz
sudo mv oc kubectl /usr/local/bin/

# Verify
oc version --client

# Login to your cluster
oc login https://api.<cluster>.<domain>:6443 --username kubeadmin --password <password>
```

### Ansible

Used for WAS ND automation playbooks (Phase 3).

```bash
# Install via pip (recommended for latest version)
pip install ansible ansible-lint

# Or via apt
sudo apt update && sudo apt install -y ansible ansible-lint

# Verify
ansible --version
```

### Terraform

Used for infrastructure-as-code (DNS, registry config).

```bash
# Add HashiCorp repo
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt update && sudo apt install -y terraform

# Verify
terraform version
```

### Docker

Used for building Liberty container images (Phase 2).

```bash
# Install Docker Engine (official method)
# See: https://docs.docker.com/engine/install/ubuntu/

# Quick setup
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io

# Add your user to docker group (avoids sudo)
sudo usermod -aG docker $USER
newgrp docker

# Verify
docker --version
```

### Vagrant + VirtualBox

Used for simulating the WAS ND on-prem environment (Phase 3).

```bash
# Install VirtualBox
sudo apt update && sudo apt install -y virtualbox

# Install Vagrant
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
sudo apt update && sudo apt install -y vagrant

# Verify
vagrant --version
```

### Java (OpenJDK 21) + Maven

Used for building the sample Java EE application.

```bash
# Install OpenJDK and Maven
sudo apt update && sudo apt install -y openjdk-21-jdk maven

# Verify
java --version
mvn --version
```

### Git

```bash
sudo apt install -y git
git --version
```

---

## DNS / Host Resolution

OKD requires DNS resolution for the API and wildcard app routes. Choose one approach:

### Option A: `/etc/hosts` (simplest)

Add entries for the cluster endpoints. Wildcard (`*.apps`) is not supported in `/etc/hosts`, so add each app route individually:

```
# OKD Cluster
192.168.68.93   okd-node1.<cluster>.<domain>
192.168.68.84   okd-node2.<cluster>.<domain>
192.168.68.88   okd-node3.<cluster>.<domain>
192.168.68.100  api.<cluster>.<domain>
192.168.68.101  console-openshift-console.apps.<cluster>.<domain>
192.168.68.101  oauth-openshift.apps.<cluster>.<domain>
```

### Option B: dnsmasq (supports wildcard)

```bash
sudo apt install -y dnsmasq

# Create config
echo "address=/apps.<cluster>.<domain>/192.168.68.101" | sudo tee /etc/dnsmasq.d/okd.conf
echo "address=/api.<cluster>.<domain>/192.168.68.100" | sudo tee -a /etc/dnsmasq.d/okd.conf

sudo systemctl restart dnsmasq
```

Then point `/etc/resolv.conf` (or systemd-resolved) to `127.0.0.1` for local resolution.

---

## Verify Everything

Quick check that all tools are available:

```bash
oc version --client
ansible --version | head -1
terraform version | head -1
vagrant --version
docker --version
java --version 2>&1 | head -1
mvn --version | head -1
git --version
```
