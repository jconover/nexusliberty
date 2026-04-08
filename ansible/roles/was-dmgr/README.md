# was-dmgr

Deployment Manager profile creation and configuration.

## Purpose

Creates the Dmgr01 profile with cell topology, server index, and wsadmin scripts. Simulates the WAS ND Deployment Manager that manages the cell.

## Required Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `was_home` | `/opt/IBM/WebSphere/AppServer` | WAS install directory |
| `cell_name` | `nexusliberty-cell` | WAS cell name |
| `dmgr_host` | `nexus-dmgr.nexuslab.local` | Dmgr hostname |
| `dmgr_soap_port` | `8879` | SOAP connector port |
| `was_admin_user` | `wasadmin` | Admin console user |
| `was_admin_password` | `wasadmin123` | Admin password (use vault) |

## Example

```yaml
- hosts: dmgr
  roles:
    - was-base
    - was-dmgr
```

## Dependencies

- `was-base`
