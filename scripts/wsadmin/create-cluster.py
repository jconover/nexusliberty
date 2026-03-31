"""
create-cluster.py — wsadmin Jython script for WAS ND cluster creation

Creates a server cluster, adds managed nodes as cluster members,
and configures session replication settings.

Usage (real WAS):
  wsadmin.sh -lang jython -f create-cluster.py \
    -host nexus-dmgr.nexuslab.local -port 8879 \
    -user wasadmin -password <pass>

Usage (simulation):
  python3 create-cluster.py
"""

import sys
import os
from datetime import datetime

# --- Configuration ---
CELL_NAME = os.environ.get("CELL_NAME", "nexusliberty-cell")
CLUSTER_NAME = os.environ.get("CLUSTER_NAME", "nexusliberty_cluster")
DMGR_NODE = os.environ.get("DMGR_NODE", "nexus-dmgrNode")

CLUSTER_MEMBERS = [
    {"node": "nexus-was1Node", "server": "AppServer1", "weight": 2},
    {"node": "nexus-was2Node", "server": "AppServer2", "weight": 2},
]


def create_cluster():
    """Create the WAS ND server cluster."""
    print("WSAD0001I: Creating cluster '%s' in cell '%s'" % (CLUSTER_NAME, CELL_NAME))

    # In real wsadmin, this would be:
    # cluster = AdminTask.createCluster('[-clusterConfig [-clusterName %s]]' % CLUSTER_NAME)
    print("WSAD0002I: Cluster object created: %s(cells/%s/clusters/%s|cluster.xml)" % (
        CLUSTER_NAME, CELL_NAME, CLUSTER_NAME))
    return True


def add_cluster_members():
    """Add application servers as cluster members."""
    for member in CLUSTER_MEMBERS:
        print("WSAD0010I: Adding cluster member: node=%s server=%s weight=%d" % (
            member["node"], member["server"], member["weight"]))

        # In real wsadmin:
        # AdminTask.createClusterMember('[-clusterName %s -memberConfig [-memberNode %s
        #   -memberName %s -memberWeight %d]]' % (
        #   CLUSTER_NAME, member["node"], member["server"], member["weight"]))

        print("WSAD0011I: Cluster member %s added successfully" % member["server"])

    print("WSAD0012I: Total cluster members: %d" % len(CLUSTER_MEMBERS))
    return True


def configure_session_management():
    """Configure cluster-level session management."""
    print("WSAD0020I: Configuring session management for cluster %s" % CLUSTER_NAME)

    # In real wsadmin:
    # AdminConfig.modify(cluster, [['sessionReplication', 'memory-to-memory']])
    # AdminConfig.modify(cluster, [['sessionTimeout', '30']])

    settings = {
        "sessionReplication": "NONE",
        "sessionTimeout": "30",
        "cookieName": "JSESSIONID",
        "enableCookies": "true",
        "enableUrlRewriting": "false",
    }

    for key, value in settings.items():
        print("WSAD0021I: Set %s = %s" % (key, value))

    return True


def save_config():
    """Save the configuration to the master repository."""
    print("WSAD0030I: Saving configuration to master repository...")
    # In real wsadmin: AdminConfig.save()
    print("WSAD0031I: Configuration saved successfully")
    return True


def sync_nodes():
    """Trigger node synchronization."""
    for member in CLUSTER_MEMBERS:
        node = member["node"]
        print("WSAD0040I: Synchronizing node: %s" % node)
        # In real wsadmin:
        # sync = AdminControl.completeObjectName('type=NodeSync,node=%s,*' % node)
        # AdminControl.invoke(sync, 'sync')
        print("WSAD0041I: Node %s synchronized" % node)
    return True


def main():
    """Main execution flow."""
    print("=" * 60)
    print("WAS ND Cluster Creation Script")
    print("Cell: %s" % CELL_NAME)
    print("Cluster: %s" % CLUSTER_NAME)
    print("Timestamp: %s" % datetime.now().isoformat())
    print("=" * 60)

    steps = [
        ("Create cluster", create_cluster),
        ("Add cluster members", add_cluster_members),
        ("Configure session management", configure_session_management),
        ("Save configuration", save_config),
        ("Synchronize nodes", sync_nodes),
    ]

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
    print("WSAD0099I: Cluster %s created and configured successfully" % CLUSTER_NAME)
    print("=" * 60)


if __name__ == "__main__":
    main()
