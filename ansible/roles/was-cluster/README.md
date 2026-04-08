# was-cluster

WAS ND cluster creation and resource configuration.

## Purpose

Creates a WAS cluster from federated application servers, configures cluster members, and sets up shared resources (data sources, JMS, etc.) via wsadmin scripts.

## Required Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `cluster_name` | `nexusliberty_cluster` | Cluster name |
| `cell_name` | `nexusliberty-cell` | WAS cell name |
| `dmgr_host` | `nexus-dmgr.nexuslab.local` | Dmgr hostname |
| `dmgr_soap_port` | `8879` | SOAP connector port |

## Example

```yaml
- hosts: dmgr
  roles:
    - was-cluster
```

## Dependencies

- `was-dmgr`
- `was-nodeagent` (nodes must be federated first)
