#!/usr/bin/env bash
# setup-was-node.sh — Shared provisioning for WAS ND managed nodes
#
# Required environment variables (set by Vagrantfile):
#   WAS_HOME, CELL_NAME, NODE_NAME, DOMAIN
#
# Required arguments:
#   $1 — Profile name    (e.g. AppSrv01)
#   $2 — Server name     (e.g. AppServer1)
#   $3 — Bootstrap port  (e.g. 9810)
#   $4 — DCS unicast port (e.g. 7272)
#   $5 — Node number     (e.g. 1)
set -euo pipefail

PROFILE_NAME="${1:?Usage: setup-was-node.sh <profile> <server> <bootstrap_port> <dcs_port> <node_num>}"
SERVER_NAME="${2:?}"
BOOTSTRAP_PORT="${3:?}"
DCS_PORT="${4:?}"
NODE_NUM="${5:?}"

# Derive hostname from node number
HOSTNAME="nexus-was${NODE_NUM}"

WAS_PROFILE="${WAS_HOME}/profiles/${PROFILE_NAME}"

echo ">>> Configuring Managed Node: ${NODE_NAME} (${SERVER_NAME})"

# --- Directory structure matching a real WAS ND managed node ---
su - wasadmin -c "
mkdir -p ${WAS_PROFILE}/{bin,config,logs,properties,installedApps}
mkdir -p ${WAS_PROFILE}/config/cells/${CELL_NAME}/nodes/${NODE_NAME}/servers/${SERVER_NAME}
mkdir -p ${WAS_PROFILE}/logs/${SERVER_NAME}
mkdir -p ${WAS_PROFILE}/installedApps/${CELL_NAME}
mkdir -p ${WAS_HOME}/bin
"

# --- Simulated server.xml ---
su - wasadmin -c "cat > ${WAS_PROFILE}/config/cells/${CELL_NAME}/nodes/${NODE_NAME}/servers/${SERVER_NAME}/server.xml << 'XML'
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<server name=\"${SERVER_NAME}\"
        serverType=\"APPLICATION_SERVER\"
        xmlns:xmi=\"http://www.omg.org/XMI\">
  <stateManagement initialState=\"START\"/>
  <processDefinition>
    <jvmEntries initialHeapSize=\"512\" maximumHeapSize=\"1024\"
                genericJvmArguments=\"-Xshareclasses:none\"/>
  </processDefinition>
</server>
XML"

# --- Simulated serverindex.xml (port definitions) ---
su - wasadmin -c "cat > ${WAS_PROFILE}/config/cells/${CELL_NAME}/nodes/${NODE_NAME}/serverindex.xml << XML
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<serverindex hostName=\"${HOSTNAME}.${DOMAIN}\">
  <serverEntries serverName=\"${SERVER_NAME}\" serverType=\"APPLICATION_SERVER\">
    <specialEndpoints endPointName=\"WC_defaulthost\">
      <endPoint host=\"*\" port=\"9080\"/>
    </specialEndpoints>
    <specialEndpoints endPointName=\"WC_defaulthost_secure\">
      <endPoint host=\"*\" port=\"9443\"/>
    </specialEndpoints>
    <specialEndpoints endPointName=\"SOAP_CONNECTOR_ADDRESS\">
      <endPoint host=\"${HOSTNAME}.${DOMAIN}\" port=\"8880\"/>
    </specialEndpoints>
    <specialEndpoints endPointName=\"BOOTSTRAP_ADDRESS\">
      <endPoint host=\"${HOSTNAME}.${DOMAIN}\" port=\"${BOOTSTRAP_PORT}\"/>
    </specialEndpoints>
  </serverEntries>
  <serverEntries serverName=\"nodeagent\" serverType=\"NODE_AGENT\">
    <specialEndpoints endPointName=\"SOAP_CONNECTOR_ADDRESS\">
      <endPoint host=\"${HOSTNAME}.${DOMAIN}\" port=\"8878\"/>
    </specialEndpoints>
  </serverEntries>
</serverindex>
XML"

# --- Mock startServer.sh / stopServer.sh ---
for action in start stop; do
  su - wasadmin -c "cat > ${WAS_PROFILE}/bin/${action}Server.sh << SCRIPT
#!/usr/bin/env bash
SERVER=\\\${1:-${SERVER_NAME}}
echo \"ADMU0116I: Tool information is being logged in /var/log/was/${action}Server.log\"
echo \"ADMU3000I: Server \\\${SERVER} ${action} completed\"
SCRIPT
chmod +x ${WAS_PROFILE}/bin/${action}Server.sh"
done

# --- Mock startNode.sh / stopNode.sh (node agent) ---
for action in start stop; do
  su - wasadmin -c "cat > ${WAS_PROFILE}/bin/${action}Node.sh << SCRIPT
#!/usr/bin/env bash
echo \"ADMU0116I: Tool information is being logged in /var/log/was/${action}Node.log\"
echo \"ADMU3100I: Node agent ${action} completed on ${NODE_NAME}\"
SCRIPT
chmod +x ${WAS_PROFILE}/bin/${action}Node.sh"
done

# --- Firewall rules for managed node ---
firewall-cmd --permanent --add-port=9080/tcp   # HTTP transport
firewall-cmd --permanent --add-port=9443/tcp   # HTTPS transport
firewall-cmd --permanent --add-port=8880/tcp   # SOAP connector
firewall-cmd --permanent --add-port=${BOOTSTRAP_PORT}/tcp  # Bootstrap
firewall-cmd --permanent --add-port=8878/tcp   # Node agent SOAP
firewall-cmd --permanent --add-port=${DCS_PORT}/tcp   # DCS unicast
firewall-cmd --reload

echo ">>> Managed Node ${NODE_NUM} (${SERVER_NAME}) setup complete"
