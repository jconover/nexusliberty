#!/usr/bin/env bash
# setup-was1.sh — Simulate WAS Managed Node 1 (AppServer1)
set -euo pipefail

echo ">>> Configuring Managed Node: ${NODE_NAME} (AppServer1)"

WAS_PROFILE="${WAS_HOME}/profiles/AppSrv01"

# --- Directory structure matching a real WAS ND managed node ---
su - wasadmin -c "
mkdir -p ${WAS_PROFILE}/{bin,config,logs,properties,installedApps}
mkdir -p ${WAS_PROFILE}/config/cells/${CELL_NAME}/nodes/${NODE_NAME}/servers/AppServer1
mkdir -p ${WAS_PROFILE}/logs/AppServer1
mkdir -p ${WAS_PROFILE}/installedApps/${CELL_NAME}
mkdir -p ${WAS_HOME}/bin
"

# --- Simulated server.xml for AppServer1 ---
su - wasadmin -c "cat > ${WAS_PROFILE}/config/cells/${CELL_NAME}/nodes/${NODE_NAME}/servers/AppServer1/server.xml << 'XML'
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<server name=\"AppServer1\"
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
su - wasadmin -c "cat > ${WAS_PROFILE}/config/cells/${CELL_NAME}/nodes/${NODE_NAME}/serverindex.xml << 'XML'
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<serverindex hostName=\"nexus-was1.${DOMAIN}\">
  <serverEntries serverName=\"AppServer1\" serverType=\"APPLICATION_SERVER\">
    <specialEndpoints endPointName=\"WC_defaulthost\">
      <endPoint host=\"*\" port=\"9080\"/>
    </specialEndpoints>
    <specialEndpoints endPointName=\"WC_defaulthost_secure\">
      <endPoint host=\"*\" port=\"9443\"/>
    </specialEndpoints>
    <specialEndpoints endPointName=\"SOAP_CONNECTOR_ADDRESS\">
      <endPoint host=\"nexus-was1.${DOMAIN}\" port=\"8880\"/>
    </specialEndpoints>
    <specialEndpoints endPointName=\"BOOTSTRAP_ADDRESS\">
      <endPoint host=\"nexus-was1.${DOMAIN}\" port=\"9810\"/>
    </specialEndpoints>
  </serverEntries>
  <serverEntries serverName=\"nodeagent\" serverType=\"NODE_AGENT\">
    <specialEndpoints endPointName=\"SOAP_CONNECTOR_ADDRESS\">
      <endPoint host=\"nexus-was1.${DOMAIN}\" port=\"8878\"/>
    </specialEndpoints>
  </serverEntries>
</serverindex>
XML"

# --- Mock startServer.sh / stopServer.sh ---
for action in start stop; do
  su - wasadmin -c "cat > ${WAS_PROFILE}/bin/${action}Server.sh << SCRIPT
#!/usr/bin/env bash
SERVER=\\\${1:-AppServer1}
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
firewall-cmd --permanent --add-port=9810/tcp   # Bootstrap
firewall-cmd --permanent --add-port=8878/tcp   # Node agent SOAP
firewall-cmd --permanent --add-port=7272/tcp   # DCS unicast
firewall-cmd --reload

echo ">>> Managed Node 1 setup complete"
