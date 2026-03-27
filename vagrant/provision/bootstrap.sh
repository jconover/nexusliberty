#!/usr/bin/env bash
# bootstrap.sh — Common provisioning for all WAS ND simulation VMs
# Installs prerequisites that Ansible expects on managed nodes.
set -euo pipefail

echo ">>> NexusLiberty WAS ND Simulation — Bootstrap"

# Ensure Python 3 is available (Ansible requirement)
dnf install -y python3 python3-pip libselinux-python3 2>/dev/null || true

# Common packages used by WAS/IHS administration
dnf install -y \
  java-11-openjdk java-11-openjdk-devel \
  unzip tar wget curl \
  net-tools bind-utils \
  firewalld \
  2>/dev/null || true

# Enable and start firewalld (WAS environments use strict firewall rules)
systemctl enable --now firewalld

# Create the IBM installation user and group (simulates enterprise convention)
groupadd -f wasgrp
id wasadmin &>/dev/null || useradd -g wasgrp -m -s /bin/bash wasadmin

# Create standard IBM directory structure
mkdir -p /opt/IBM/WebSphere/AppServer
mkdir -p /opt/IBM/WebSphere/Plugins
mkdir -p /opt/IBM/HTTPServer
mkdir -p /opt/IBM/InstallationManager
mkdir -p /var/log/was

chown -R wasadmin:wasgrp /opt/IBM
chown -R wasadmin:wasgrp /var/log/was

# Set JAVA_HOME for WAS compatibility
cat > /etc/profile.d/was-env.sh << 'ENVEOF'
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
export WAS_HOME=/opt/IBM/WebSphere/AppServer
export PATH=$WAS_HOME/bin:$JAVA_HOME/bin:$PATH
ENVEOF

# Add /etc/hosts entries for all cell members
cat >> /etc/hosts << 'HOSTSEOF'
192.168.56.10  nexus-dmgr.nexuslab.local  nexus-dmgr
192.168.56.11  nexus-was1.nexuslab.local   nexus-was1
192.168.56.12  nexus-was2.nexuslab.local   nexus-was2
192.168.56.13  nexus-ihs.nexuslab.local    nexus-ihs
HOSTSEOF

echo ">>> Bootstrap complete"
