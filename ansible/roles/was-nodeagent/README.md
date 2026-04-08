# was-nodeagent

Node agent and application server profile creation.

## Purpose

Creates AppSrv profiles on managed nodes, federates them to the Deployment Manager, and starts the node agent. Each node gets a unique profile name based on its index.

## Required Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `was_home` | `/opt/IBM/WebSphere/AppServer` | WAS install directory |
| `cell_name` | `nexusliberty-cell` | WAS cell name |
| `dmgr_host` | `nexus-dmgr.nexuslab.local` | Dmgr hostname for federation |

## Node Index

Nodes are indexed via `hostvars[host].node_index` (preferred) or by position in the `was_nodes` inventory group (fallback).

## Example

```yaml
- hosts: was_nodes
  roles:
    - was-base
    - was-nodeagent
```

## Dependencies

- `was-base`
- `was-dmgr` (Dmgr must be running for federation)
