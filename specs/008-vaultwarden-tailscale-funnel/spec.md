# Feature Specification: Vaultwarden Public Access via Tailscale Funnel

**Feature Branch**: `008-vaultwarden-tailscale-funnel`

**Created**: 2026-11-03

**Status**: Draft

**Input**: User description: "Expose Vaultwarden password manager via Tailscale Funnel on the node's public URL (*.<tailnet>.ts.net) so it is truly publicly accessible over HTTPS from any device (including work computers without Tailscale installed). Tailscale handles the public Let's Encrypt TLS termination and reverse proxying directly to the Vaultwarden container port (8088), bypassing Caddy. Update Vaultwarden DOMAIN configuration accordingly."

## Clarifications

### Session 2026-11-02
- Q: How should the system resolve and supply the Tailscale Funnel public URL without committing the real hostname or domain to version control? (FR-004) → A: Dynamic discovery at runtime (via `tailscale status --json`) to configure Vaultwarden `DOMAIN` and Tailscale Funnel; sanitize all committed specs, code, and documentation to generic placeholders (`https://<node-name>.<tailnet>.ts.net`).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Frictionless Credential Access from Any Device and Network (Priority: P1)

As a homelab and household member using a managed work laptop, school workstation, or guest computer without VPN software or administrative permissions, I want to access my password vault via a publicly resolvable, validly certified HTTPS domain (`<node-name>.<tailnet>.ts.net`), so that I can securely log in, retrieve stored credentials, and autofill passwords without needing Tailscale installed on the client machine.

**Why this priority**: Universal client availability is the core motivation for this feature. Users frequently need access to saved credentials on employer-provided or restricted devices where third-party VPN clients cannot be installed or are blocked by network firewalls.

**Independent Test**: Can be tested independently on an isolated device connected to an external cellular or guest network with zero VPN client installed. Navigating to the public URL in any standard browser must load the web vault securely with a valid TLS certificate and permit logging in and accessing vault items.

**Acceptance Scenarios**:

1. **Given** a standard web browser on a device outside the local network without Tailscale installed, **When** the user navigates to the public HTTPS URL (`https://<node-name>.<tailnet>.ts.net`), **Then** the password manager interface loads over secure HTTPS with a trusted certificate and zero browser security warnings.
2. **Given** the web interface loaded on an untrusted external network, **When** the user authenticates with their master credentials, **Then** the encrypted vault is decrypted client-side and full credential management features are functional.
3. **Given** the publicly accessible endpoint, **When** an unauthenticated visitor attempts to register a new account, **Then** registration is refused or disabled, ensuring the public URL cannot be abused for unauthorized account creation.

---

### User Story 2 - Bitwarden Client Integration & Real-Time Sync (Priority: P1)

As a password manager user with official Bitwarden mobile apps and browser extensions installed across multiple personal devices, I want the applications to connect seamlessly to the public domain with live synchronization enabled, so that credential updates on one device propagate immediately to other devices regardless of what network they are currently connected to.

**Why this priority**: A password vault must keep all active client sessions consistent in real time. If a user creates or rotates a password on a mobile phone, that password must appear immediately on their desktop browser extension without requiring manual vault synchronization or VPN activation.

**Independent Test**: Can be tested independently by configuring a browser extension and a mobile device against the public Funnel URL, adding a new credential item on one device, and confirming that the second device receives the update over real-time notification push without manual interaction.

**Acceptance Scenarios**:

1. **Given** official Bitwarden client software (mobile app or browser extension) configured with the public server URL, **When** the client logs in or synchronizes, **Then** all vault data, notes, and authenticator seeds synchronize securely over HTTPS.
2. **Given** two active client sessions connected via the public endpoint, **When** a vault item is created, edited, or deleted on one client, **Then** a real-time event notification is delivered over the persistent connection and the second client immediately refreshes its local vault view.

---

### User Story 3 - Automated Ingress Routing & Direct TLS Termination (Priority: P2)

As a homelab administrator, I want inbound public HTTPS traffic to be terminated and forwarded directly to the backend password vault service port without intermediary proxy layers, so that public TLS certificate lifecycle management is completely automated and local reverse proxy (Caddy) configuration is simplified and bypassed for this service.

**Why this priority**: Direct ingress via Tailscale Funnel eliminates redundant hops, removes internal certificate conflicts, and centralizes public TLS termination within Tailscale's edge infrastructure, reducing operational complexity and maintenance overhead.

**Independent Test**: Can be tested independently by querying the public HTTPS endpoint and verifying that the connection terminates with Tailscale's automated publicly trusted TLS certificate, while checking that Caddy no longer handles or proxies traffic for the Vaultwarden service.

**Acceptance Scenarios**:

1. **Given** an incoming HTTPS request on port 443 addressed to the node's public domain, **When** Tailscale Funnel receives the request, **Then** it terminates TLS using its automated publicly trusted certificate and forwards the unencrypted HTTP traffic directly to the backend container listening on port 8088.
2. **Given** the local reverse proxy (Caddy) configuration, **When** inspecting active routes, **Then** Vaultwarden ingress through Caddy is retired or bypassed, avoiding dual-proxy forwarding and port contention.
3. **Given** a host reboot or network interface reset, **When** the system returns online, **Then** the public Funnel ingress and backend service restore automatically without manual administrative commands.

---

### User Story 4 - Public Ingress Hardening & Domain Configuration Alignment (Priority: P2)

As a security-conscious administrator, I want the password manager's canonical domain setting and environment configuration to align with the public URL, so that invitations, security tokens, WebCrypto origins, and vault links generated by the service match the public HTTPS endpoint and reject origin mismatches.

**Why this priority**: Modern password vault clients and WebCrypto APIs enforce strict origin validation. If the internal domain configuration does not match the external public hostname, password reset emails, organization invitations, and browser security contexts will fail or produce security errors.

**Independent Test**: Can be tested independently by checking generated vault links, invitation invitations, and inspecting the HTTP response headers and origin validation responses dispatched by the backend service.

**Acceptance Scenarios**:

1. **Given** an administrative or user-initiated action generating a service link (such as an invitation or email verification), **When** the link URL is inspected, **Then** the URL base matches the canonical public HTTPS domain (`https://<node-name>.<tailnet>.ts.net`).
2. **Given** client WebCrypto cryptographic requests sent from a browser running on the public domain, **When** processed by the server, **Then** origin checks succeed without security policy or mixed-content violations.

---

### Edge Cases

- **Node Reboot or Network Reconnect**: What happens if the homelab host reboots or temporarily loses internet connectivity?
  *Requirement: Tailscale Funnel ingress configuration must be persistent across reboots so public accessibility is restored automatically once network and daemon connectivity resume.*
- **Tailscale Edge Connectivity Disruption**: What happens if the external Tailscale relay network or control plane experiences an outage?
  *Requirement: Existing client applications retain their local decrypted vault cache for offline reading; once the connection recovers, synchronization resumes seamlessly without data corruption.*
- **Plain HTTP Request on Public Hostname**: What happens if an external client attempts to connect to port 80 (HTTP)?
  *Requirement: Tailscale Funnel automatically redirects plain HTTP traffic to secure HTTPS (port 443).*
- **Malicious Public Ingress Probing**: How is the publicly exposed instance protected against brute-force attacks and unsolicited registrations?
  *Requirement: Signups must remain strictly disabled (`SIGNUPS_ALLOWED=false`), invitations restricted, and built-in rate-limiting mechanisms active to protect against credential stuffing.*

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST expose the Vaultwarden password manager on the node's public Tailscale Funnel endpoint (`<node-name>.<tailnet>.ts.net`) over standard HTTPS (port 443).
- **FR-002**: Tailscale Funnel MUST handle public TLS certificate provisioning, automated renewal, and TLS termination using publicly trusted certificates (Let's Encrypt).
- **FR-003**: System MUST route incoming public traffic directly from Tailscale Funnel to the Vaultwarden container port (8088), bypassing the Caddy reverse proxy.
- **FR-004**: System MUST dynamically resolve the node's Tailscale FQDN at deployment time (via `tailscale status --json`) and configure Vaultwarden's canonical `DOMAIN` environment variable to match the discovered public HTTPS URL (`https://<node-name>.<tailnet>.ts.net`).
- **FR-005**: System MUST enforce strict signup restrictions (signups disabled, invitations controlled) to prevent unauthorized public registrations on the publicly accessible instance.
- **FR-006**: System MUST maintain full WebSocket bidirectional communication support over the public Funnel endpoint to provide real-time push synchronization to connected clients.
- **FR-007**: Tailscale Funnel ingress configuration MUST be declaratively managed and persistent across host reboots, daemon restarts, and system updates.
- **FR-008**: System MUST decommission or retire any conflicting Vaultwarden ingress definitions in Caddy to eliminate redundant proxy hops and conflicting domain bindings.
- **FR-009**: System MUST ensure WebCrypto API compliance and secure context validation for all client browsers accessing the public HTTPS endpoint.
- **FR-010**: All version-controlled files, automation scripts, and templates MUST NOT contain committed real public Funnel URLs or tailnet domain names; only generic placeholders (`<node-name>.<tailnet>.ts.net`) or runtime-discovered variables may appear in git, in strict adherence to Constitution Principle IV (Zero Secrets in Version Control & Isolated Configuration).

### Key Entities

- **Vaultwarden Backend**: The containerized password management service listening internally on port 8088, responsible for serving the web vault, managing encrypted vault databases, and pushing real-time synchronization events.
- **Tailscale Funnel Ingress**: The edge ingress and TLS-terminating capability provided by the Tailscale daemon that exposes the node to the public internet on port 443 with a trusted certificate and proxies requests to `127.0.0.1:8088`.
- **Public Canonical Origin**: The authoritative public URL (`https://<node-name>.<tailnet>.ts.net`) dynamically resolved at runtime from the Tailscale daemon and configured for the service, establishing the secure origin for client WebCrypto, links, and API calls without committing private domain metadata to git.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users on external devices with zero VPN or Tailscale software installed can access and interact with the web vault over public HTTPS in under 3 seconds with valid TLS certificate verification and zero browser security warnings.
- **SC-002**: 100% of standard Bitwarden client interactions (browser extension logins, autofill, mobile app sync, item updates) complete successfully through the public endpoint.
- **SC-003**: Vault updates performed on one active client propagate to other connected client sessions within 5 seconds via real-time WebSocket notifications.
- **SC-004**: Ingress configuration is 100% resilient across reboots: upon host restart, public HTTPS access to the password vault is restored within 60 seconds of network initialization without manual operator intervention.
- **SC-005**: 0% of unauthorized public registration attempts succeed; account creation is restricted strictly to existing credentials or administrator-issued invitations.

## Assumptions

- The target node is already joined and authenticated to an active tailnet with HTTPS and Funnel permissions enabled in the tailnet policy/ACL.
- Tailscale Funnel serves public traffic directly over port 443 using Tailscale's edge infrastructure without requiring inbound port forwarding on the homelab's local router or firewall.
- Vaultwarden continues running in its hardened container listening on loopback port 8088.
- Caddy continues managing any other homelab internal services or health checks; only Vaultwarden ingress routing is transferred to Tailscale Funnel.
- Existing database persistence, SQLite WAL configuration, and backup routines established in Feature 005 remain unchanged and operational.
