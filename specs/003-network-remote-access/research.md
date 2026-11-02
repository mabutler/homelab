# Research: Network & Remote Access Overlay (Phase 3)

**Feature**: `003-network-remote-access`  
**Date**: 2026-11-01  
**Status**: Completed  

---

## 1. Mesh VPN Architecture: Tailscale on Arch Linux

### Decision
Deploy the official `tailscale` package on Arch Linux, managed as a native systemd unit (`tailscaled.service`), authenticated non-interactively via a reusable or pre-authenticated auth key stored in the SOPS encrypted vault (`vault.sops.yml`).

### Rationale
- **Zero Firewall Punching**: Tailscale utilizes WireGuard under the hood with NAT traversal (DERP relays and STUN), eliminating the need for port-forwarding on upstream home routers.
- **Stable Headless Addressing**: Assigns a predictable 100.x.y.z IP and MagicDNS domain name (`homelab2.<tailnet>.ts.net`), ensuring persistent access from operator workstations, mobile devices, and laptops regardless of physical location.
- **Native Arch Integration**: The `tailscale` package is in Arch Linux official repositories (`extra`), cleanly managed by `systemd`.
- **SOPS Secret Pipeline**: The authentication key is kept encrypted at rest in `ansible/inventory/group_vars/all/vault.sops.yml` and injected via Ansible tasks without ever being written to cleartext logs.

### Alternatives Considered
- **Standard WireGuard**: Requires public IPv4 / dynamic DNS, port forwarding on WAN router (UDP 51820), and manual peer key exchanges. Rejected due to operational complexity and failure when behind CGNAT or hotel/cellular networks.
- **ZeroTier**: Similar mesh concept, but Tailscale offers superior integration with MagicDNS, automatic TLS certificate integration, and seamless WireGuard kernel support.
- **OpenVPN**: Heavyweight, TCP/UDP port overhead, higher latency, complex PKI certificate maintenance.

---

## 2. Host-Level Packet Filtering: nftables

### Decision
Implement host firewall rules using native Linux `nftables` via `/etc/nftables.conf`, enforcing an `inet` address family table with a default-drop policy on inbound packets, explicitly whitelisting local management subnets (`192.168.4.0/24`), the mesh VPN interface (`tailscale0`), loopback (`lo`), WireGuard/Tailscale UDP encapsulation (`41641`), and HTTP/HTTPS (`80`, `443`).

### Rationale
- **Modern Linux Standard**: `nftables` replaces legacy `iptables`, `ip6tables`, and `ebtables` with a single, unified kernel framework offering atomic rule updates and cleaner syntax.
- **Single Dual-Stack Table**: The `inet` family handles IPv4 and IPv6 concurrently in a single table, eliminating duplicate rule maintenance and IPv6 leakage risks.
- **Ansible Native Configuration**: Managed as a single template `/etc/nftables.conf` evaluated atomically via `nft -c -f /etc/nftables.conf` before service reload, preventing syntax errors from causing accidental operator lockout.
- **Fail-Safe Structure**: Drop-ins or main configuration explicitly allow established/related traffic and loopback first, ensuring existing SSH connections and local daemon communications are never severed during rule convergence.

### Alternatives Considered
- **ufw (Uncomplicated Firewall)**: Adds Python runtime wrapper and legacy iptables translation layers, which is less transparent on bare-metal Arch Linux and conflicts with container network engines.
- **firewalld**: Dynamic daemon with heavy D-Bus dependencies, unneeded complexity for a dedicated headless server where declarative file-based rules are preferred.
- **iptables-nft**: Compatibility layer; native `nft` syntax is cleaner, faster, and more auditable.

---

## 3. Reverse Proxy & Automated TLS: Caddy

### Decision
Deploy **Caddy** (native package `caddy` from Arch Linux `extra`) as a systemd service listening on ports 80 and 443. Configure `/etc/caddy/Caddyfile` with an extensible `/etc/caddy/conf.d/*.caddy` drop-in import pattern, supporting automatic HTTPS redirection, WebSocket upgrades, and automated ACME certificate management (via DNS-01 challenge for public/private domains or native Tailscale TLS).

### Rationale
- **Automated ACME by Default**: Caddy automatically provisions and renews TLS certificates via Let's Encrypt / ZeroSSL, handling OCSP stapling and TLS 1.3 negotiation with zero configuration toil.
- **Modular Ingress Drop-Ins**: Using `import /etc/caddy/conf.d/*.caddy` allows future Phase 5 container services (Home Assistant, Vaultwarden, Immich, etc.) to define their own routing rules and proxy stanzas without modifying the core `Caddyfile`.
- **Built-in WebSocket Upgrades**: Caddy's `reverse_proxy` directive automatically handles HTTP/1.1 `Upgrade: websocket` and `Connection: Upgrade` headers without requiring custom boilerplate.
- **HTTP/3 & HTTP/2 Support**: Built-in support for HTTP/2 multiplexing and HTTP/3 (QUIC) over UDP 443.
- **Phase 3 Placeholder & Health Endpoint**: Exposes a dedicated health check endpoint (`/health` returning HTTP 200 `OK`) and default placeholder page for undefined virtual hosts.

### Alternatives Considered
- **Traefik**: Excellent for dynamic Docker container label discovery, but heavier configuration overhead, complex static vs dynamic configuration separation, and more verbose YAML syntax for simple host-level reverse proxying.
- **NGINX**: Requires manual ACME scripting (certbot timers, certbot nginx plugin), manual HTTP->HTTPS redirect blocks, and manual WebSocket upgrade map definitions. Higher operational toil violating Constitution Principle I.
- **Envoy**: Overly complex service-mesh proxy designed for large distributed microservices; excessive resource overhead for homelab ingress.

---

## 4. Automated Verification & Acceptance Testing (Phase 3 Gate)

### Decision
Create a dedicated verification playbook (`ansible/playbooks/verify-phase3.yml`) and orchestrator script (`scripts/verify-phase3.sh` and Windows PowerShell companion `scripts/apply-phase3.ps1`) executing 8 deterministic health assertions:
1. `systemd` unit active: `nftables.service`
2. `systemd` unit active: `tailscaled.service`
3. `systemd` unit active: `caddy.service`
4. Tailscale status check: node online and authenticated on mesh network
5. Firewall verification: default-drop verified on closed ports; port 22/80/443 open
6. Ingress HTTP port 80 check: redirect to HTTPS with 301/308 status
7. Ingress HTTPS port 443 check: valid TLS handshake and HTTP 200 on `/health` endpoint
8. Ingress WebSocket proxying check: connection upgrade test verification

### Rationale
- Satisfies Constitution Principle III (Automated Verification & Acceptance Gates), which mandates that Phase 3 onward confirms operational telemetry and automated health assertions.
- Provides immediate regression detection when subsequent application containers or storage layers are deployed.

---

## 5. Backup & Disaster Recovery Posture (Phase 3 Gate)

### Decision
Confirm Phase 3 backup readiness by:
1. Version-controlling `/etc/nftables.conf` template, `/etc/caddy/Caddyfile`, and modular drop-in architecture in the `homelab2` git repository.
2. Storing all Tailscale authentication tokens and DNS API credentials in encrypted SOPS format (`vault.sops.yml`).
3. Backing up Caddy's persistent data directory (`/var/lib/caddy`) containing ACME account keys and certificates in the planned Phase 7 Restic backup matrix, while documenting that ACME certificates are completely disposable and automatically re-issuable upon clean disaster restore.

### Rationale
- Satisfies Constitution Principle V (Disaster Recovery & Backup by Design).
- Eliminates brittle state; a total host wipe can be restored in under 5 minutes purely from the git repository and master age private key.
