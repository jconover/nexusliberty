# was-deploy

Application deployment to WAS cluster with health verification.

## Purpose

Deploys the application WAR to the WAS cluster via wsadmin, starts the application, and verifies it is healthy by checking HTTP endpoints.

## Required Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `app_name` | `nexus-app` | Application name |
| `app_war` | `nexus-app.war` | WAR filename |
| `app_context_root` | `/app` | Context root for the app |
| `cluster_name` | `nexusliberty_cluster` | Target cluster |
| `dmgr_host` | `nexus-dmgr.nexuslab.local` | Dmgr hostname |

## Example

```yaml
- hosts: dmgr
  roles:
    - was-deploy
```

## Dependencies

- `was-cluster` (cluster must exist)
