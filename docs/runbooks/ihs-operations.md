# IHS Load Balancer Operations

Procedures for managing the IBM HTTP Server (Apache HTTPD stand-in) in both legacy and containerized deployments.

---

## Legacy IHS (Vagrant / On-Prem)

```bash
# Check IHS status
ssh wasadmin@nexus-ihs.nexuslab.local
/opt/IBM/HTTPServer/bin/apachectl status

# Restart IHS
/opt/IBM/HTTPServer/bin/apachectl restart

# Test plugin routing
curl -I http://nexus-ihs.nexuslab.local/app/
# Should return 200 with response from WAS backend

# Regenerate plugin-cfg.xml via Ansible
ansible-playbook -i ansible/inventory/hosts.ini \
  ansible/playbooks/ihs-install.yml --tags plugin
```

---

## Containerized IHS (OKD)

```bash
# IHS pod status
oc get pods -l app.kubernetes.io/name=nexusliberty-ihs -n liberty-apps

# IHS logs
oc logs -f -l app.kubernetes.io/name=nexusliberty-ihs -n liberty-apps

# Test via Route
curl -I https://nexusliberty-ihs.apps.<cluster>.<domain>/app/

# Health check
curl http://nexusliberty-ihs.apps.<cluster>.<domain>/ihs-health
```
