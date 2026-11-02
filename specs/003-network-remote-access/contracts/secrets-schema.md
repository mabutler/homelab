# Contract: Secrets Schema & Variable Additions (Phase 3)

**Feature**: `003-network-remote-access`  
**Contract ID**: `CNTR-NET-003`  
**Status**: Ratified  

---

## 1. Encrypted Secrets Storage (`vault.sops.yml`)

All secret parameters for Phase 3 must reside encrypted at rest in `ansible/inventory/group_vars/all/vault.sops.yml`, managed via SOPS with the project's age master key.

### Variable Definitions

| Variable Name | Type | Sensitivity | Purpose | Format / Validation |
|---|---|---|---|---|
| `tailscale_auth_key` | String | Secret | Non-interactive registration key for Tailscale | Begins with `tskey-auth-` |
| `cloudflare_api_token` | String | Secret | Optional token for ACME DNS-01 certificate challenges | 40-character alphanumeric token |

### Example Schema (Decrypted representation)

```yaml
# In ansible/inventory/group_vars/all/vault.sops.yml
vault_tailscale_auth_key: "tskey-auth-kxxxxxxxxxxxxxxxxxxxxxxx"
vault_cloudflare_api_token: "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

---

## 2. Non-Sensitive Variable Declarations (`vars.yml`)

Non-sensitive default variables added to `ansible/inventory/group_vars/all/vars.yml`:

```yaml
# Network & Remote Access (Phase 3)
tailscale_enabled: true
tailscale_accept_routes: true
tailscale_advertise_exit_node: false

firewall_enabled: true
firewall_allowed_subnets:
  - "192.168.4.0/24"
firewall_allowed_tcp_ports:
  - 22
  - 80
  - 443
firewall_allowed_udp_ports:
  - 41641

caddy_enabled: true
caddy_conf_dir: "/etc/caddy/conf.d"
```

---

## 3. Security Invariants

- Cleartext secret tokens MUST NEVER be committed to Git.
- Playbook tasks handling the Tailscale registration command MUST use `no_log: true` to prevent secrets leaking to Ansible stdout or journal logs.
