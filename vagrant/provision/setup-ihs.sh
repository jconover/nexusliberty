#!/usr/bin/env bash
# setup-ihs.sh — Simulate IBM HTTP Server + WebSphere Plugin
set -euo pipefail

echo ">>> Configuring IBM HTTP Server: nexus-ihs"

# --- Directory structure matching a real IHS + WAS plugin install ---
su - wasadmin -c "
mkdir -p ${IHS_HOME}/{bin,conf,logs,htdocs}
mkdir -p ${PLUGIN_HOME}/config/webserver1
mkdir -p ${PLUGIN_HOME}/logs/webserver1
"

# --- Simulated httpd.conf (IHS main config) ---
su - wasadmin -c "cat > ${IHS_HOME}/conf/httpd.conf << 'CONF'
# IBM HTTP Server Configuration — NexusLiberty WAS ND Simulation
ServerRoot \"/opt/IBM/HTTPServer\"
Listen 80
Listen 443

ServerName nexus-ihs.nexuslab.local:80
ServerAdmin wasadmin@nexuslab.local

DocumentRoot \"/opt/IBM/HTTPServer/htdocs\"

# Load WebSphere Plugin module
LoadModule was_ap24_module /opt/IBM/WebSphere/Plugins/bin/mod_was_ap24_http.so
WebSpherePluginConfig /opt/IBM/WebSphere/Plugins/config/webserver1/plugin-cfg.xml

# Logging
ErrorLog \"/opt/IBM/HTTPServer/logs/error_log\"
CustomLog \"/opt/IBM/HTTPServer/logs/access_log\" combined
LogLevel warn

# SSL/TLS (placeholder — Ansible will configure real certs)
# SSLEngine on
# SSLCertificateFile /opt/IBM/HTTPServer/conf/ihs-cert.pem
# SSLCertificateKeyFile /opt/IBM/HTTPServer/conf/ihs-key.pem

<Directory \"/opt/IBM/HTTPServer/htdocs\">
    Options Indexes FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>
CONF"

# --- Simulated plugin-cfg.xml (routes requests to WAS cluster) ---
su - wasadmin -c "cat > ${PLUGIN_HOME}/config/webserver1/plugin-cfg.xml << 'XML'
<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>
<Config ASDisableNagle=\"false\" AcceptAllContent=\"false\"
        IISDisableNagle=\"false\" IgnoreDNSFailures=\"false\"
        RefreshInterval=\"60\" ResponseChunkSize=\"64\"
        VHostMatchingCompat=\"false\">

  <Log LogLevel=\"Error\"
       Name=\"/opt/IBM/WebSphere/Plugins/logs/webserver1/http_plugin.log\"/>

  <ServerCluster CloneSeparatorChange=\"false\"
                 LoadBalance=\"Round Robin\"
                 Name=\"nexusliberty_cluster\"
                 PostSizeLimit=\"-1\"
                 RemoveSpecialHeaders=\"true\"
                 RetryInterval=\"60\">

    <Server ConnectTimeout=\"5\"
            ExtendedHandshake=\"false\"
            MaxConnections=\"-1\"
            Name=\"nexus-was1_AppServer1\"
            WaitForContinue=\"false\">
      <Transport Hostname=\"nexus-was1.nexuslab.local\" Port=\"9080\" Protocol=\"http\"/>
      <Transport Hostname=\"nexus-was1.nexuslab.local\" Port=\"9443\" Protocol=\"https\"/>
    </Server>

    <Server ConnectTimeout=\"5\"
            ExtendedHandshake=\"false\"
            MaxConnections=\"-1\"
            Name=\"nexus-was2_AppServer2\"
            WaitForContinue=\"false\">
      <Transport Hostname=\"nexus-was2.nexuslab.local\" Port=\"9080\" Protocol=\"http\"/>
      <Transport Hostname=\"nexus-was2.nexuslab.local\" Port=\"9443\" Protocol=\"https\"/>
    </Server>

    <PrimaryServers>
      <Server Name=\"nexus-was1_AppServer1\"/>
      <Server Name=\"nexus-was2_AppServer2\"/>
    </PrimaryServers>

  </ServerCluster>

  <VirtualHostGroup Name=\"default_host\">
    <VirtualHost Name=\"*:80\"/>
    <VirtualHost Name=\"*:443\"/>
    <VirtualHost Name=\"*:9080\"/>
    <VirtualHost Name=\"*:9443\"/>
  </VirtualHostGroup>

  <UriGroup Name=\"default_host_URIs\">
    <Uri AffinityCookie=\"JSESSIONID\" Name=\"/app/*\"/>
    <Uri AffinityCookie=\"JSESSIONID\" Name=\"/nexus-app/*\"/>
  </UriGroup>

  <Route ServerCluster=\"nexusliberty_cluster\"
         UriGroup=\"default_host_URIs\"
         VirtualHostGroup=\"default_host\"/>

</Config>
XML"

# --- Mock apachectl / IHS control scripts ---
su - wasadmin -c "cat > ${IHS_HOME}/bin/apachectl << 'SCRIPT'
#!/usr/bin/env bash
ACTION=\${1:-status}
case \$ACTION in
  start)   echo \"IHS: Starting IBM HTTP Server\" ;;
  stop)    echo \"IHS: Stopping IBM HTTP Server\" ;;
  restart) echo \"IHS: Restarting IBM HTTP Server\" ;;
  status)  echo \"IHS: IBM HTTP Server is running (pid 1234)\" ;;
  *)       echo \"Usage: apachectl {start|stop|restart|status}\" ;;
esac
SCRIPT
chmod +x ${IHS_HOME}/bin/apachectl"

# --- Default landing page ---
su - wasadmin -c "cat > ${IHS_HOME}/htdocs/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head><title>NexusLiberty — IBM HTTP Server</title></head>
<body>
  <h1>NexusLiberty WAS ND Environment</h1>
  <p>IBM HTTP Server is routing traffic to the WebSphere cluster.</p>
  <ul>
    <li><a href=\"/app/\">Application</a></li>
  </ul>
</body>
</html>
HTML"

# --- Firewall rules for IHS ---
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --permanent --add-port=8008/tcp   # IHS admin port
firewall-cmd --reload

echo ">>> IBM HTTP Server setup complete"
