# Technical Research & Decisions: Vaultwarden Public Access via Tailscale Funnel

**Feature Branch**: `008-vaultwarden-tailscale-funnel`  
**Date**: 2026-11-03  
**Status**: Completed  

## 1. Dynamic Tailscale FQDN Discovery (FR-004, FR-010, Principle IV)

### Unknown / Context
Vaultwarden requires its canonical `DOMAIN` environment variable (e.g. `DOMAIN=https://<node-name>.<tailnet>.ts.net`) for correct WebCrypto cryptographic context, password reset links, invitations, and mobile/extension syncing. However, Constitution Principle IV and FR-010 strictly forbid committing private domain names, machine hostnames, or tailnet identifiers to version control.

### Decision
Extract the fully qualified domain name dynamically at deployment runtime from the local Tailscale daemon using `tailscale status --json`.

### Technical Implementation
1. Execute `tailscale status --json`.
2. Inspect the JSON structure:
   - Primary: `.CertDomains[0]` (contains the canonical TLS certificate domain without trailing dot, e.g. `<node>.<tailnet>.ts.net`).
   - Fallback: `.Self.DNSName | regex_replace('\\.$', '')` (strips trailing FQDN dot).
3. If Tailscale is running and logged in, set `vaultwarden_domain: "https://{{ tailscale_node_fqdn }}"`.
4. If Tailscale is not yet authenticated or running in check/lint mode, safely fallback to a generic placeholder `https://<node-name>.<tailnet>.ts.net` or `https://127.0.0.1:8088` to prevent fatal templating errors during offline verification.
5. In Ansible:
   ```yaml
   - name: Query Tailscale status for dynamic FQDN resolution
     ansible.builtin.command:
       cmd: tailscale status --json
     register: tailscale_status_raw
     changed_when: false
     failed_when: false

   - name: Parse Tailscale FQDN
     ansible.builtin.set_fact:
       tailscale_discovered_fqdn: >-
         {{
           (tailscale_status_raw.stdout | from_json).CertDomains[0]
           if (tailscale_status_raw.rc == 0 and (tailscale_status_raw.stdout | from_json).CertDomains is defined and (tailscale_status_raw.stdout | from_json).CertDomains | length > 0)
           else ((tailscale_status_raw.stdout | from_json).Self.DNSName | regex_replace('\\.$', ''))
           if (tailscale_status_raw.rc == 0 and (tailscale_status_raw.stdout | from_json).Self.DNSName is defined)
           else 'vaultwarden.local'
         }}
   ```

### Alternatives Considered
- **Statically defining domain in `host_vars` or `vault.yml`**: Rejected because committing it violates Principle IV / FR-010, and storing it in `vault.yml` introduces manual coordination toil whenever nodes or tailnets change.
- **Querying external DNS APIs**: Rejected due to unnecessary external network dependencies and failure risk during network bootstrap.

---

## 2. Declarative Tailscale Funnel Orchestration & Persistence (FR-001, FR-002, FR-003, FR-007)

### Unknown / Context
Tailscale Funnel exposes a local backend port to the public internet using Tailscale's edge relays and automated Let's Encrypt certificates. How should this configuration be applied idempotently and persisted across node reboots?

### Decision
1. Tailscale's daemon (`tailscaled`) natively persists active `--bg` (background) Serve and Funnel configurations in its persistent state file (`/var/lib/tailscale/tailscaled.state`).
2. To ensure strict idempotency (Principle II) and declarative management (Principle I), Ansible will query `tailscale funnel status --json`.
3. If the backend target `127.0.0.1:8088` (or `8088`) is not active under port 443 with Funnel enabled:
   - Run `tailscale funnel --bg --yes 8088` (or `tailscale funnel --bg --https=443 --yes 8088`).
   - Mark task changed.
4. If already configured and active, skip command execution (`changed_when: false`).

### CLI Command & Flags
```bash
tailscale funnel --bg --yes 8088
```
- `--bg`: Keeps funnel persistent in background via `tailscaled`.
- `--yes`: Bypasses interactive confirmation prompts in automation scripts.
- `8088`: Target port on localhost where the Vaultwarden container is listening.

### Alternatives Considered
- **Foreground systemd unit running `tailscale funnel 8088`**: Rejected because `tailscale funnel --bg` delegates lifecycle to `tailscaled`, which already starts on boot and natively restores state. A redundant wrapper service adds process supervision overhead.
- **Using Caddy as a front-end for Funnel**: Rejected by FR-003 and User Story 3; Tailscale Funnel terminates TLS directly and reverse-proxies directly to Vaultwarden's container port 8088.

---

## 3. Resolving Port 443 Contention & Decommissioning Caddy Route (FR-008, User Story 3)

### Unknown / Context
`tailscaled` binds to port 443 on the local host to accept traffic when Funnel/Serve is enabled. Previously, Caddy had `:443` in `00-health.caddy` and `vaultwarden.lan` in `20-vaultwarden.caddy`. If Caddy binds to `0.0.0.0:443`, `tailscaled` encounters an `address already in use` error.

### Decision
1. **Decommission Vaultwarden in Caddy**: Remove `/etc/caddy/conf.d/20-vaultwarden.caddy` (`state: absent`) and delete `20-vaultwarden.caddy.j2` from deployment.
2. **Eliminate Caddy Wildcard Port 443 Contention**:
   - In `ansible/roles/caddy/templates/00-health.caddy.j2`, adjust Caddy so it does not hold a wildcard `:443` binding that conflicts with Tailscale.
   - Caddy retains port 80 for internal health checks (`http://127.0.0.1:80/health`) and redirecting plain HTTP.
   - Alternatively, bind Caddy's internal health check to an internal management port (e.g., `:8443` or `127.0.0.1:80`) if needed, allowing `tailscaled` unobstructed ownership of port 443.
3. Reload Caddy after removing `20-vaultwarden.caddy`.

### Alternatives Considered
- **Running Tailscale Funnel on an alternate public port (e.g. 8443 or 10000)**: Rejected because FR-001 mandates standard HTTPS (port 443) so users on restricted devices do not have connections blocked by egress firewalls filtering non-standard ports.

---

## 4. WebSocket & Real-Time Client Synchronization (FR-006, SC-003)

### Unknown / Context
Bitwarden desktop, browser, and mobile clients rely on real-time WebSocket notifications at `/notifications/hub` to push vault changes across devices without requiring manual sync.

### Findings
- Vaultwarden includes built-in WebSocket support via Rocket and its notification hub on port 8088 when `WEBSOCKET_ENABLED=true` is set.
- Tailscale Funnel supports HTTP/1.1 and HTTP/2 WebSocket upgrades natively. Requests to `wss://<node-name>.<tailnet>.ts.net/notifications/hub` with `Upgrade: websocket` headers are streamed transparently to backend port 8088.
- Verification tests can assert WebSocket handshake completion using `curl` with `Upgrade: websocket` headers.

---

## 5. Security Hardening & Zero Secrets (FR-005, FR-009, FR-010, Principle IV)

### Unknown / Context
Exposing the vault to the public internet increases attack surface.

### Hardening Guardrails
1. **Disabled Public Registrations**: `SIGNUPS_ALLOWED=false` remains strictly enforced in `.env`. Only existing accounts or administrative invitations (`INVITATIONS_ALLOWED=true`) can access the vault.
2. **Isolated Secrets**: `.env` file containing `ADMIN_TOKEN` hash has mode `0600` owned by `root:root`.
3. **Non-Root Execution**: Vaultwarden container runs with UID/GID 1000:1000 and drops Linux capabilities.
4. **WebCrypto HTTPS Context**: Because Tailscale Funnel provisions valid Let's Encrypt certificates for `*.ts.net`, browsers recognize the connection as a Secure Context (`isSecureContext === true`), allowing WebCrypto `crypto.subtle` APIs to function without exception.
5. **Sanitization**: Spec files, verification logs, and documentation must only reference placeholder domain `https://<node-name>.<tailnet>.ts.net`.
