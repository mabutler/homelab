# Interface Contract: Ansible Role Variables & Configuration

**Feature Branch**: `008-vaultwarden-tailscale-funnel`  
**Date**: 2026-11-03  

## 1. Vaultwarden Role Variables (`ansible/roles/vaultwarden`)

| Variable Name | Type | Default | Description |
|---|---|---|---|
| `vaultwarden_domain` | string | `""` (empty triggers dynamic discovery) | Canonical public domain. If empty, dynamically discovered from Tailscale. |
| `vaultwarden_domain_default` | string | `"https://<node-name>.<tailnet>.ts.net"` | Fallback placeholder used during offline dry-runs. |
| `vaultwarden_enable_funnel` | boolean | `true` | Whether to expose Vaultwarden via Tailscale Funnel. |
| `vaultwarden_funnel_port` | integer | `443` | Public HTTPS port for Tailscale Funnel. |
| `vaultwarden_internal_port`| integer | `8088` | Loopback port for Vaultwarden container. |
| `vaultwarden_signups_allowed` | boolean | `false` | Must remain `false` for public exposure. |
| `vaultwarden_invitations_allowed` | boolean | `true` | Allows controlled onboarding by administrator. |
| `vaultwarden_websocket_enabled` | boolean | `true` | Enables real-time synchronization. |

---

## 2. Caddy Role Variables (`ansible/roles/caddy`)

| Variable Name | Type | Default | Description |
|---|---|---|---|
| `caddy_manage_vaultwarden` | boolean | `false` | When false, ensures `20-vaultwarden.caddy` is removed from `/etc/caddy/conf.d/`. |
| `caddy_conf_dir` | string | `"/etc/caddy/conf.d"` | Drop-in directory for Caddy route configurations. |
| `caddy_enable_wildcard_443` | boolean | `false` | When false, suppresses wildcard `:443` binding in `00-health.caddy` to prevent port contention with Tailscale Funnel. |
