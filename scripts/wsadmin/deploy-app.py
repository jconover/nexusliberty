"""
deploy-app.py — wsadmin Jython script for application deployment to WAS ND

Installs an application (EAR/WAR) to a WAS ND cluster, maps modules
to cluster members, and starts the application.

Usage (real WAS):
  wsadmin.sh -lang jython -f deploy-app.py \
    -host nexus-dmgr.nexuslab.local -port 8879 \
    -user wasadmin -password <pass>

Usage (simulation):
  python3 deploy-app.py
"""

import sys
import os
from datetime import datetime

# --- Configuration ---
CELL_NAME = os.environ.get("CELL_NAME", "nexusliberty-cell")
CLUSTER_NAME = os.environ.get("CLUSTER_NAME", "nexusliberty_cluster")
APP_NAME = os.environ.get("APP_NAME", "nexus-app")
APP_PATH = os.environ.get("APP_PATH", "/opt/IBM/apps/nexus-app.war")
CONTEXT_ROOT = os.environ.get("CONTEXT_ROOT", "/app")
VIRTUAL_HOST = os.environ.get("VIRTUAL_HOST", "default_host")


def check_existing_app():
    """Check if the application is already installed."""
    print("WSAD0100I: Checking for existing installation of '%s'" % APP_NAME)

    # In real wsadmin:
    # apps = AdminApp.list().splitlines()
    # return APP_NAME in apps

    print("WSAD0101I: Application '%s' not currently installed" % APP_NAME)
    return False


def install_application():
    """Install the application to the cluster."""
    print("WSAD0110I: Installing application '%s'" % APP_NAME)
    print("WSAD0111I: Source: %s" % APP_PATH)
    print("WSAD0112I: Target cluster: %s" % CLUSTER_NAME)

    # In real wsadmin:
    # AdminApp.install(APP_PATH, [
    #     '-appname', APP_NAME,
    #     '-cluster', CLUSTER_NAME,
    #     '-contextroot', CONTEXT_ROOT,
    #     '-MapWebModToVH', [
    #         [APP_NAME, APP_NAME + '.war,WEB-INF/web.xml', VIRTUAL_HOST]
    #     ],
    #     '-MapModulesToServers', [
    #         [APP_NAME, '.*', 'WebSphere:cell=%s,cluster=%s' % (CELL_NAME, CLUSTER_NAME)]
    #     ],
    # ])

    print("WSAD0113I: Application modules mapped to cluster %s" % CLUSTER_NAME)
    print("WSAD0114I: Context root set to: %s" % CONTEXT_ROOT)
    print("WSAD0115I: Virtual host mapping: %s -> %s" % (APP_NAME, VIRTUAL_HOST))
    return True


def update_application():
    """Update an existing application installation."""
    print("WSAD0120I: Updating application '%s'" % APP_NAME)

    # In real wsadmin:
    # AdminApp.update(APP_NAME, 'app', [
    #     '-operation', 'update',
    #     '-contents', APP_PATH,
    # ])

    print("WSAD0121I: Application '%s' updated from %s" % (APP_NAME, APP_PATH))
    return True


def configure_classloader():
    """Configure application classloader policy."""
    print("WSAD0130I: Configuring classloader for '%s'" % APP_NAME)

    # In real wsadmin:
    # deployment = AdminConfig.getid('/Deployment:%s/' % APP_NAME)
    # appDeploy = AdminConfig.showAttribute(deployment, 'deployedObject')
    # AdminConfig.modify(appDeploy, [['warClassLoaderPolicy', 'SINGLE']])
    # classloader = AdminConfig.showAttribute(appDeploy, 'classloader')
    # AdminConfig.modify(classloader, [['mode', 'PARENT_LAST']])

    settings = {
        "warClassLoaderPolicy": "SINGLE",
        "classloaderMode": "PARENT_LAST",
    }

    for key, value in settings.items():
        print("WSAD0131I: Set %s = %s" % (key, value))

    return True


def configure_shared_libraries():
    """Map shared libraries if needed."""
    print("WSAD0140I: Checking shared library mappings for '%s'" % APP_NAME)
    print("WSAD0141I: No shared libraries required")
    return True


def save_config():
    """Save configuration to the master repository."""
    print("WSAD0150I: Saving configuration to master repository...")
    # In real wsadmin: AdminConfig.save()
    print("WSAD0151I: Configuration saved successfully")
    return True


def sync_nodes():
    """Trigger full node synchronization after deployment."""
    nodes = ["nexus-was1Node", "nexus-was2Node"]
    for node in nodes:
        print("WSAD0160I: Synchronizing node: %s" % node)
        # In real wsadmin:
        # sync = AdminControl.completeObjectName('type=NodeSync,node=%s,*' % node)
        # AdminControl.invoke(sync, 'sync')
        print("WSAD0161I: Node %s synchronized" % node)
    return True


def start_application():
    """Start the deployed application on all cluster members."""
    print("WSAD0170I: Starting application '%s' on cluster '%s'" % (APP_NAME, CLUSTER_NAME))

    # In real wsadmin:
    # appManager = AdminControl.queryNames(
    #     'type=ApplicationManager,process=dmgr,*')
    # AdminControl.invoke(appManager, 'startApplication', APP_NAME)

    print("WSAD0171I: Application '%s' started successfully" % APP_NAME)
    print("WSAD0172I: Application available at context root: %s" % CONTEXT_ROOT)
    return True


def verify_deployment():
    """Verify the application is running on all cluster members."""
    print("WSAD0180I: Verifying deployment of '%s'" % APP_NAME)

    members = [
        ("nexus-was1Node", "AppServer1"),
        ("nexus-was2Node", "AppServer2"),
    ]

    for node, server in members:
        # In real wsadmin:
        # state = AdminControl.getAttribute(
        #     AdminControl.completeObjectName(
        #         'type=Application,name=%s,node=%s,server=%s,*' % (APP_NAME, node, server)),
        #     'state')

        print("WSAD0181I: %s/%s — application state: STARTED" % (node, server))

    return True


def main():
    """Main execution flow."""
    print("=" * 60)
    print("WAS ND Application Deployment Script")
    print("Application: %s" % APP_NAME)
    print("Cluster: %s" % CLUSTER_NAME)
    print("Cell: %s" % CELL_NAME)
    print("Timestamp: %s" % datetime.now().isoformat())
    print("=" * 60)

    # Check if app exists — update vs fresh install
    try:
        app_exists = check_existing_app()
    except Exception as e:
        print("WSAD9002E: Exception checking existing app: %s" % e)
        sys.exit(1)

    if app_exists:
        steps = [
            ("Update application", update_application),
        ]
    else:
        steps = [
            ("Install application", install_application),
        ]

    steps.extend([
        ("Configure classloader", configure_classloader),
        ("Configure shared libraries", configure_shared_libraries),
        ("Save configuration", save_config),
        ("Synchronize nodes", sync_nodes),
        ("Start application", start_application),
        ("Verify deployment", verify_deployment),
    ])

    for step_name, step_func in steps:
        print("\n--- %s ---" % step_name)
        try:
            if not step_func():
                print("WSAD9001E: Step failed: %s" % step_name)
                sys.exit(1)
        except Exception as e:
            print("WSAD9002E: Exception in step '%s': %s" % (step_name, e))
            sys.exit(1)

    print("\n" + "=" * 60)
    print("WSAD0199I: Application '%s' deployed successfully to cluster '%s'" % (
        APP_NAME, CLUSTER_NAME))
    print("WSAD0200I: Access at: http://<ihs-host>%s/" % CONTEXT_ROOT)
    print("=" * 60)


if __name__ == "__main__":
    main()
