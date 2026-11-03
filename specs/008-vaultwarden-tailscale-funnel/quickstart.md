# Quickstart & Verification Guide: Vaultwarden via Tailscale Funnel

**Feature Branch**: `008-vaultwarden-tailscale-funnel`  
**Date**: 2026-11-03  

## 1. Overview
This guide provides runnable scenarios to validate public accessibility, Let's Encrypt TLS certificate validity, WebSocket synchronization, and security hardening for Vaultwarden exposed through Tailscale Funnel.

---

## 2. Prerequisites
1. Homelab node is connected to Tailscale (`tailscale status` returns `BackendState: Running`).
2. Tailnet policy / ACL grants the node permission to use Tailscale Funnel.
3. Ansible inventory and variables are configured (`ansible/inventory/hosts.yml`).

---

## 3. Deployment Verification Scenarios

### Scenario 1: Deploy Funnel & Vaultwarden via Ansible
Run the updated Vaultwarden playbook:
```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/vaultwarden.yml
```
**Expected Outcome**:
- `tailscale status --json` dynamically resolves the node's FQDN.
- `20-vaultwarden.caddy` is removed from `/etc/caddy/conf.d/`.
- Caddy reloads without holding wildcard `:443`.
- `tailscale funnel --bg --yes 8088` is activated idempotently.
- `/opt/services/vaultwarden/.env` is deployed with `DOMAIN=https://<node-name>.<tailnet>.ts.net` and `SIGNUPS_ALLOWED=false`.
- Vaultwarden container restarts and listens on `127.0.0.1:8088`.

---

### Scenario 2: Verify Ingress & TLS from External Device
On an external laptop or phone **without Tailscale installed**:
1. Open any web browser.
2. Navigate to `https://<node-name>.<tailnet>.ts.net/alive`.
3. Check the browser security padlock icon.

**Expected Outcome**:
- HTTP 200 response received.
- Certificate issuer is Let's Encrypt / Tailscale.
- Zero certificate warnings or security errors.
- `window.isSecureContext === true` in the browser console.

---

### Scenario 3: Verify WebSocket Live Synchronization
From the terminal or external client:
```bash
curl --http1.1 -i -N \
  -H "Connection: Upgrade" \
  -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Key: SGVsbG8sIHdvcmxkIQ==" \
  -H "Sec-WebSocket-Version: 13" \
  --max-time 5 \
  https://<node-name>.<tailnet>.ts.net/notifications/hub
```

**Expected Outcome**:
- Response includes `HTTP/1.1 101 Switching Protocols` (or `401 Unauthorized` with WebSocket upgrade acknowledgement from Vaultwarden).

---

### Scenario 4: Automated Verification Playbook Execution
Run the automated verification suite:
```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/verify-phase5.yml
```

**Expected Outcome**:
- `VW-01`: Docker Engine operational
- `VW-02`: Vaultwarden systemd service active
- `VW-03`: Non-root process & data permissions
- `VW-04`: Secret isolation (`.env` mode 0600)
- `VW-05`: Backend loopback probe HTTP 200 (`http://127.0.0.1:8088/alive`)
- `VW-06`: Tailscale Funnel ingress HTTPS probe HTTP 200
- `VW-07`: WebSocket handshake on `/notifications/hub`
- `VW-08`: Transactional backup execution and integrity
- `VW-09`: Vaultwarden backup timer active
- All assertions pass with exit code 0.
