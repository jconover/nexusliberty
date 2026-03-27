#!/usr/bin/env bash
# setup-dmgr.sh — Simulate WAS Deployment Manager node
# Creates the directory structure, config files, and mock scripts that
# Ansible playbooks will manage as if this were a real WAS ND install.
set -euo pipefail

echo ">>> Configuring Deployment Manager: ${NODE_NAME}"

WAS_PROFILE="${WAS_HOME}/profiles/Dmgr01"

# --- Directory structure matching a real WAS ND Dmgr profile ---
su - wasadmin -c "
mkdir -p ${WAS_PROFILE}/{bin,config,logs,properties,installedApps}
mkdir -p ${WAS_PROFILE}/config/cells/${CELL_NAME}/{nodes,applications,clusters}
mkdir -p ${WAS_PROFILE}/logs/dmgr
mkdir -p ${WAS_HOME}/bin
mkdir -p ${WAS_HOME}/java/bin
"

# --- Simulated cell config (resources.xml / cell topology) ---
su - wasadmin -c "cat > ${WAS_PROFILE}/config/cells/${CELL_NAME}/cell.xml << 'XML'
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<cell name=\"nexusliberty-cell\"
      cellType=\"DISTRIBUTED\"
      xmlns:xmi=\"http://www.omg.org/XMI\">
  <nodes>
    <node name=\"nexus-dmgrNode\" profileName=\"Dmgr01\" type=\"DEPLOYMENT_MANAGER\"/>
  </nodes>
</cell>
XML"

# --- Simulated serverindex.xml (port definitions) ---
su - wasadmin -c "cat > ${WAS_PROFILE}/config/cells/${CELL_NAME}/nodes/${NODE_NAME}/serverindex.xml << 'XML'
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<serverindex hostName=\"nexus-dmgr.${DOMAIN}\">
  <serverEntries serverName=\"dmgr\" serverType=\"DEPLOYMENT_MANAGER\">
    <specialEndpoints endPointName=\"SOAP_CONNECTOR_ADDRESS\">
      <endPoint host=\"nexus-dmgr.${DOMAIN}\" port=\"8879\"/>
    </specialEndpoints>
    <specialEndpoints endPointName=\"WC_adminhost\">
      <endPoint host=\"*\" port=\"9060\"/>
    </specialEndpoints>
    <specialEndpoints endPointName=\"WC_adminhost_secure\">
      <endPoint host=\"*\" port=\"9043\"/>
    </specialEndpoints>
  </serverEntries>
</serverindex>
XML"

# --- Mock wsadmin.sh (Jython launcher) ---
su - wasadmin -c "cat > ${WAS_HOME}/bin/wsadmin.sh << 'SCRIPT'
#!/usr/bin/env bash
# Mock wsadmin.sh — simulates WAS admin scripting interface
# In a real environment this launches the Jython/Jacl scripting shell
echo \"WASX7209I: Connected to process \\\"dmgr\\\" on node ${NODE_NAME}\"
echo \"WASX7029I: For help, type: \\\"print Help.help()\\\"\"

# If a script file is passed via -f, execute it with Python
while [[ \\\$# -gt 0 ]]; do
  case \\\$1 in
    -f) shift; python3 \"\\\$1\" 2>/dev/null || echo \"Script executed: \\\$1\"; shift ;;
    *) shift ;;
  esac
done
SCRIPT
chmod +x ${WAS_HOME}/bin/wsadmin.sh"

# --- Mock startManager.sh / stopManager.sh ---
for action in start stop; do
  su - wasadmin -c "cat > ${WAS_PROFILE}/bin/${action}Manager.sh << SCRIPT
#!/usr/bin/env bash
echo \"ADMU0116I: Tool information is being logged in /var/log/was/${action}Manager.log\"
echo \"ADMU3100I: Server dmgr ${action} completed\"
SCRIPT
chmod +x ${WAS_PROFILE}/bin/${action}Manager.sh"
done

# --- Firewall rules for Dmgr ports ---
firewall-cmd --permanent --add-port=9060/tcp   # Admin console HTTP
firewall-cmd --permanent --add-port=9043/tcp   # Admin console HTTPS
firewall-cmd --permanent --add-port=8879/tcp   # SOAP connector
firewall-cmd --permanent --add-port=9809/tcp   # Bootstrap
firewall-cmd --permanent --add-port=7277/tcp   # DCS unicast
firewall-cmd --reload

echo ">>> Deployment Manager setup complete"
