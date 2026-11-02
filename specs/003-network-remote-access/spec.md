# Feature Specification: Network & Remote Access Overlay

**Feature Branch**: `003-network-remote-access`

**Created**: 2026-11-01

**Status**: Draft

**Input**: User description: "Phase 3"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Secure Mesh Networking & Remote Administration (Priority: P1)

As a homelab administrator, I want the host integrated into a secure, encrypted mesh virtual private network (Tailscale), so that I can remotely administer the server and access homelab workloads from anywhere without exposing administrative ports to the public internet or configuring fragile router port forwarding rules.

**Why this priority**: Remote access is the operational bridge between base system hardening (Phase 2) and service deployment (Phases 4-6). It enables headless management across geographic boundaries while keeping network attack surfaces minimized.

**Independent Test**: Can be tested independently by authenticating the host into the overlay network, verifying that the node appears active and reachable on the private mesh network, and executing remote administrative commands over the encrypted mesh connection from an external client without local LAN routing.

**Acceptance Scenarios**:

1. **Given** a hardened host with network connectivity, **When** the mesh network daemon is configured and started, **Then** the host authenticates to the mesh control plane and obtains a stable private mesh IP and node name.
2. **Given** an authorized remote client connected to the mesh network, **When** the client initiates an SSH connection to the host's mesh IP or name, **Then** the connection succeeds securely without requiring router port-forwarding.
3. **Given** an unauthenticated client or a client outside the mesh network, **When** attempting to reach the host's mesh IP address, **Then** traffic is unreachable and dropped.
4. **Given** a reboot of the host, **When** the operating system finishes starting up, **Then** the mesh daemon automatically reconnects and re-establishes remote accessibility without manual administrative intervention.

---

### User Story 2 - Host-Level Firewall & Boundary Protection (Priority: P1)

As a homelab administrator, I want host-level packet filtering (`nftables`) enforced across all network interfaces, so that unsolicited incoming traffic on physical network boundaries is dropped by default while explicitly allowing required local LAN management, mesh VPN encapsulation, and reverse proxy traffic.

**Why this priority**: A robust, declarative host firewall protects the server against unauthorized internal network scans, rogue devices on the local subnet, and port leakage before multi-service container stacks are introduced.

**Independent Test**: Can be tested independently by applying the firewall rules and running port scans from both local subnet devices and external networks, confirming that only explicitly whitelisted ports (such as SSH, HTTP/S, and mesh tunnel UDP ports) accept packets, while all unapproved ports drop packets silently.

**Acceptance Scenarios**:

1. **Given** the firewall service is active, **When** unsolicited inbound packets arrive on the physical network interface for non-whitelisted ports, **Then** the firewall drops the packets by default without responding.
2. **Given** an established outbound connection originating from the host (e.g., package manager updates, DNS lookups, or mesh coordination), **When** return traffic arrives, **Then** the firewall matches established/related connection state and permits the packets.
3. **Given** administrative traffic originating from an approved local management subnet or mesh VPN interface, **When** targeting the configured management port (SSH), **Then** the connection is accepted.
4. **Given** mesh VPN coordination traffic (UDP port 41641), **When** packets arrive on the public/physical interface, **Then** the firewall permits the encapsulation traffic to sustain peer-to-peer tunnels.
5. **Given** an invalid or syntactically malformed firewall rule set, **When** the firewall configuration is evaluated, **Then** existing active rules are preserved and the system rejects the erroneous change rather than dropping all traffic or locking out administration.

---

### User Story 3 - Automated Ingress Reverse Proxy & ACME TLS Termination (Priority: P2)

As a homelab user and administrator, I want a declarative reverse proxy (such as Caddy or Traefik) handling incoming web traffic with automated, zero-touch ACME TLS certificate lifecycle management and WebSocket support, so that household web applications can be accessed securely over HTTPS via clean domain names with valid certificates and real-time bidirectional synchronization.

**Why this priority**: Secure HTTPS ingress and WebSocket transport are required preconditions for deploying user-facing applications (such as Home Assistant, Vaultwarden, Immich, and FileBrowser in Phase 5). Manual TLS certificate renewals create operational toil and risk unexpected service outages.

**Independent Test**: Can be tested independently by launching the reverse proxy service, pointing test domain/subdomain requests to the host over HTTP and HTTPS, and verifying that HTTP requests automatically redirect to HTTPS, TLS certificates are issued and trusted, and WebSocket connections remain connected.

**Acceptance Scenarios**:

1. **Given** an HTTP request arriving on port 80 for any configured domain, **When** received by the reverse proxy, **Then** the client is automatically redirected to the corresponding HTTPS endpoint (port 443) with an HTTP 301/308 redirect.
2. **Given** a newly configured application domain or subdomain, **When** the reverse proxy starts or reloads, **Then** it automatically negotiates with the ACME certificate authority (via DNS-01 or mesh TLS challenge), stores the issued certificate, and serves valid TLS without operator intervention.
3. **Given** an impending TLS certificate expiration within renewal thresholds, **When** the proxy daemon runs its background renewal loop, **Then** certificates are renewed automatically and reloaded without dropping active client connections.
4. **Given** an application requiring real-time updates (e.g., WebSocket upgrade headers for Home Assistant state changes or Vaultwarden push notifications), **When** a client initiates a WebSocket handshake, **Then** the reverse proxy upgrades the connection and transparently tunnels bidirectional traffic without timeout drops.
5. **Given** an ingress request targeting an upstream backend service that is temporarily stopped or not yet deployed, **When** the proxy receives the request, **Then** it returns an appropriate standard HTTP gateway response (e.g., HTTP 502 Bad Gateway) without crashing the proxy process or breaking TLS negotiation for other domains.

---

### User Story 4 - Verification, Telemetry & Configuration Recovery (Priority: P2)

As a homelab administrator, I want automated verification tests, structured telemetry, and verified backup procedures for the network and ingress stack, so that system health is observable, certificate expiry warnings are logged, and networking configurations can be recovered in disaster scenarios in compliance with Constitution Principles III and V.

**Why this priority**: Phase 3 establishes network connectivity, marking the boundary where Constitution Principles III and V strictly mandate active telemetry and verified backup postures before phase sign-off.

**Independent Test**: Can be tested independently by executing the Phase 3 automated verification suite; it executes health checks against the firewall, mesh VPN, and reverse proxy, verifies structured journal logging, and confirms that all configuration files and secret credentials are safely backed up in version control or designated recovery stores.

**Acceptance Scenarios**:

1. **Given** the network overlay stack is running, **When** the automated verification script is executed, **Then** it confirms active firewall filtering, mesh VPN node connectivity, reverse proxy port listening (80/443), and certificate validity, exiting with code 0 on success.
2. **Given** network status events or reverse proxy access and error events, **When** generated by the host, **Then** structured entries are written to the system journal with appropriate log levels for alerting and auditability.
3. **Given** all declarative firewall configurations, reverse proxy definitions, and encrypted DNS/mesh secrets, **When** inspected in the repository, **Then** all files are tracked in version control with zero plaintext secrets exposed.
4. **Given** an emergency disaster recovery scenario where the host must be restored from scratch, **When** running the declarative playbooks with the encryption keys present, **Then** the complete network and remote access configuration is reconstituted to an identical operational state in under 5 minutes.

---

### Edge Cases

- **Mesh Control Plane Outage or Packet Loss**: If the remote mesh coordination server is temporarily unreachable, local LAN connectivity and local SSH administrative access must remain fully functional.
- **Upstream Internet Uplink Down**: The host firewall and local reverse proxy must continue serving local LAN clients and routing traffic locally without hanging on external DNS or ACME timeouts.
- **ACME DNS API Rate Limiting or Provider Authentication Failure**: If the DNS provider API is unreachable or rate-limited during initial certificate request, the proxy must log structured failure details and retry with exponential backoff rather than terminating the proxy process.
- **Port Conflict on 80/443**: If an unmanaged service attempts to bind ports 80 or 443, the reverse proxy configuration must fail fast and report an unambiguous port binding conflict in journal logs.
- **Dynamic WAN IP Changes**: The mesh network must adapt to changing external IP addresses and network topology shifts dynamically without requiring a service restart.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST integrate an encrypted mesh virtual private network (Tailscale) daemon that starts automatically on system boot.
- **FR-002**: System MUST authenticate the host to the mesh network using non-interactive credentials (auth key managed via SOPS encrypted secrets).
- **FR-003**: System MUST enforce a declarative host-level firewall (`nftables`) with a default-drop policy for all unsolicited inbound traffic on external physical interfaces.
- **FR-004**: System MUST allow established and related inbound connections through the firewall.
- **FR-005**: System MUST explicitly whitelist SSH administrative access on physical management subnets and the mesh VPN interface.
- **FR-006**: System MUST permit necessary mesh VPN encapsulation traffic (UDP port 41641) on physical interfaces.
- **FR-007**: System MUST deploy an ingress reverse proxy (Caddy or Traefik) managed as a declarative systemd service or container service.
- **FR-008**: System MUST configure the reverse proxy to listen on standard HTTP (80) and HTTPS (443) ports.
- **FR-009**: System MUST automatically redirect all insecure HTTP requests on port 80 to HTTPS on port 443.
- **FR-010**: System MUST automate TLS certificate acquisition and renewal via ACME protocols (using DNS-01 challenges or mesh-native TLS) with zero manual intervention required.
- **FR-011**: Reverse proxy MUST support protocol upgrading for WebSockets and HTTP/2 multiplexing across all proxy routes.
- **FR-012**: System MUST provide a modular configuration structure allowing subsequent service phases (Phase 5) to declare new proxy routes and virtual hosts without altering core proxy defaults.
- **FR-013**: Reverse proxy MUST log access requests and error events in structured format to the system journal or dedicated rotated log files.
- **FR-014**: System MUST provide an automated verification runner (test script or playbook) that validates firewall rules, mesh connectivity, reverse proxy HTTP/HTTPS listeners, and TLS certificate validity.
- **FR-015**: All network overlay configurations, firewall definitions, proxy routes, and encrypted secrets MUST be version-controlled in the repository, satisfying Constitution Principle V (Backup by Design).

### Key Entities

- **Mesh Node State**: Represents the host's identity on the overlay network, including mesh IP address, authorized node tags, and connection status to peers.
- **Firewall Policy**: Declarative nftables ruleset defining input/forward/output chains, interface bindings, allowed port matrices, and rate limiting thresholds.
- **Proxy Ingress Route**: Virtual host definition mapping inbound hostnames to internal upstream service targets, TLS configurations, and header forwarding policies.
- **TLS Certificate Record**: Cryptographic certificate, private key, and metadata tracking validity duration, issuing authority, and automated renewal triggers.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Remote administration via the encrypted mesh network is established and functional within 15 seconds from any authorized external client without router port forwarding.
- **SC-002**: Unsolicited network packets to closed ports on physical interfaces are dropped by default, achieving 100% compliance with default-deny inbound firewall policy.
- **SC-003**: HTTPS web endpoints negotiate valid TLS handshakes with modern cipher suites and achieve automated certificate renewals with 0 hours of manual administration per year.
- **SC-004**: Insecure HTTP requests are redirected to HTTPS with standard redirection status codes in under 100 milliseconds.
- **SC-005**: Real-time WebSocket connections through the reverse proxy maintain continuous streaming sessions with zero connection drops under normal network conditions.
- **SC-006**: Complete network overlay and ingress stack recovers and converges to full operational status in under 60 seconds following a host reboot.
- **SC-007**: Automated acceptance verification suite executes and confirms firewall, mesh network, and reverse proxy health in under 60 seconds.

## Assumptions

- **DNS Provider Access**: The operator possesses domain names managed via an ACME DNS-01 compatible DNS provider (e.g., Cloudflare) with API credentials stored securely in SOPS, or utilizes mesh-provided domain names (`.ts.net`) for automated TLS.
- **Local Network Environment**: The host receives a stable local IP address (via static assignment or router DHCP reservation) on the home LAN.
- **Application Availability**: Application workloads (Home Assistant, Immich, Vaultwarden, etc.) will be deployed in Phase 5; Phase 3 provides placeholder routes or health check endpoints to verify proxy forwarding, TLS termination, and WebSocket capabilities.
- **Secrets Management**: Credentials (mesh auth keys and DNS API tokens) are provisioned via the SOPS/age secrets pipeline established in Phase 2.
