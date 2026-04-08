# was-base

OS prerequisites, Java, and WAS product directory simulation.

## Purpose

Prepares managed nodes with the directory structure, Java runtime, and environment that a real WAS ND installation would create. This is the foundation role that all other roles depend on.

## Required Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `was_home` | `/opt/IBM/WebSphere/AppServer` | WAS install directory |
| `java_home` | `/usr/lib/jvm/java-11-openjdk` | Java home path |
| `was_user` | `wasadmin` | OS user for WAS |
| `was_group` | `wasgrp` | OS group for WAS |

## Example

```yaml
- hosts: all
  roles:
    - was-base
```

## Dependencies

None — this is the base role.
