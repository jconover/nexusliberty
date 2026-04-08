# ihs-proxy

IHS (IBM HTTP Server) reverse proxy configuration.

## Purpose

Configures Apache HTTPD as a reverse proxy to WAS application servers or Liberty pods. Supports a `liberty_mode` toggle to switch between traditional WAS plugin routing and modern Liberty/Kubernetes service routing.

## Required Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ihs_home` | `/opt/IBM/HTTPServer` | IHS install directory |
| `liberty_mode` | `false` | Use Liberty backend instead of WAS |
| `domain` | `nexuslab.local` | Domain for server names |

## Example

```yaml
- hosts: ihs
  roles:
    - ihs-proxy
  vars:
    liberty_mode: true
```

## Dependencies

- `was-base` (for OS prereqs)
- WAS cluster or Liberty pods running (for backend targets)
