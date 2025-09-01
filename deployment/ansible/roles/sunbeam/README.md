# Sunbeam Role

This Ansible role runs the `sunbeam cluster bootstrap` command with the specified roles.

## Role Variables

- `sunbeam_roles`: Comma-separated list of roles to bootstrap (default: "control,compute,storage")
- `sunbeam_accept_defaults`: Whether to accept defaults (default: true)

## Example Playbook

```yaml
- hosts: servers
  roles:
    - role: sunbeam
      sunbeam_roles: "control,compute,storage"
```

## License

MIT
