# WAS ND Daily Operations

Standard operating procedures for the simulated WebSphere Application Server Network Deployment cell.

---

## Check Cell Health

```bash
# SSH to Deployment Manager
ssh wasadmin@nexus-dmgr.nexuslab.local

# Verify DMGR is running
/opt/IBM/WebSphere/AppServer/bin/serverStatus.sh dmgr

# Check all node agents and app servers
/opt/IBM/WebSphere/AppServer/bin/serverStatus.sh -all

# Or via wsadmin
wsadmin.sh -lang jython -host nexus-dmgr.nexuslab.local -port 8879 \
  -user wasadmin -password <pass> \
  -f /path/to/scripts/wsadmin/health-check.py
```

---

## Start / Stop Application Servers

```bash
# Start a managed server
wsadmin.sh -lang jython -c "AdminControl.startServer('AppServer1', 'nexus-was1')"

# Stop a managed server (graceful)
wsadmin.sh -lang jython -c "AdminControl.stopServer('AppServer1', 'nexus-was1')"

# Restart node agent on a managed node
ssh wasadmin@nexus-was1.nexuslab.local
/opt/IBM/WebSphere/AppServer/bin/stopNode.sh
/opt/IBM/WebSphere/AppServer/bin/startNode.sh
```

---

## Deploy / Update Application

```bash
# Deploy via wsadmin script
wsadmin.sh -lang jython -host nexus-dmgr.nexuslab.local -port 8879 \
  -user wasadmin -password <pass> \
  -f scripts/wsadmin/deploy-app.py

# Or via Ansible
ansible-playbook -i ansible/inventory/hosts.ini \
  ansible/playbooks/was-deploy-app.yml
```

---

## Log Locations

| Component | Log Path |
|---|---|
| DMGR | `/opt/IBM/WebSphere/AppServer/profiles/Dmgr01/logs/dmgr/SystemOut.log` |
| Node Agent | `/opt/IBM/WebSphere/AppServer/profiles/AppSrv01/logs/nodeagent/SystemOut.log` |
| App Server | `/opt/IBM/WebSphere/AppServer/profiles/AppSrv01/logs/AppServer1/SystemOut.log` |
| FFDC | `/opt/IBM/WebSphere/AppServer/profiles/AppSrv01/logs/ffdc/` |
| IHS Access | `/opt/IBM/HTTPServer/logs/access_log` |
| IHS Error | `/opt/IBM/HTTPServer/logs/error_log` |
| WAS Plugin | `/opt/IBM/WebSphere/Plugins/logs/webserver1/http_plugin.log` |
