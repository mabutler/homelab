# Feature Specification: Vaultwarden Application Deployment & Resiliency

**Feature Branch**: `005-vaultwarden-app`

**Created**: 2026-11-01

**Status**: Draft

**Input**: User description: "Let's start phase 5 using Vaultwarden as the first app" (Phase 5 of repository Roadmap: Application Platform)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Secure Credential Management & Cross-Device Synchronization (Priority: P1)

As a household member and homelab user, I want a private, central password and secret management service accessible from desktop browsers, mobile devices, and CLI tools, so that I can securely generate, store, autofill, and share passwords, two-factor authentication tokens (TOTP), secure notes, and file attachments without relying on third-party commercial cloud providers.

**Why this priority**: Password management is a foundational personal security utility. Vaultwarden serves as the primary password store for the homelab and household, enabling zero-trust secret storage with standard Bitwarden client compatibility.

**Independent Test**: Can be tested independently by deploying the service, registering or logging into an account, creating various secret items (logins, secure notes, TOTP seeds, attachments), and verifying that clients (web vault, browser extensions, mobile apps) can reliably retrieve, decrypt, and update these credentials.

**Acceptance Scenarios**:

1. **Given** an operational Vaultwarden service, **When** a user accesses the web vault interface, **Then** they can log in using their master credentials and access their encrypted vault.
2. **Given** an authenticated user session, **When** the user creates or edits a vault item (login credentials, note, card, or identity), **Then** the encrypted data is persistently stored and retrievable on subsequent sessions.
3. **Given** two active client sessions on different devices, **When** an item is created or updated on one device, **Then** real-time notification push over WebSockets prompts the second device to synchronize immediately without manual page refresh.
4. **Given** a user attempting to authenticate with invalid credentials, **When** authentication fails repeatedly, **Then** rate-limiting protections mitigate brute-force attempts and error events are recorded in service audit logs.

---

### User Story 2 - Reverse Proxy Ingress & End-to-End Encrypted Transport (Priority: P1)

As a security-conscious homelab operator, I want the password manager service integrated behind the reverse proxy with automated TLS encryption and WebSocket routing, so that modern client WebCrypto APIs function seamlessly and data in transit is protected across both local network and remote VPN overlays.

**Why this priority**: Modern Bitwarden client applications (browser extensions, mobile apps, and WebCrypto APIs) strictly reject unencrypted HTTP connections. Secure HTTPS with valid TLS certificates is an absolute prerequisite for operational password management.

**Independent Test**: Can be tested independently by dispatching HTTPS requests to the Vaultwarden domain via the reverse proxy, verifying automated TLS certificate validity, and establishing a persistent WebSocket connection to `/notifications/hub` confirming bidirectional communication.

**Acceptance Scenarios**:

1. **Given** the reverse proxy routing rules, **When** an HTTP request is made to the Vaultwarden host URL, **Then** it is automatically redirected to HTTPS with HTTP Strict Transport Security (HSTS) headers.
2. **Given** a client establishing a real-time event listener, **When** connecting to `/notifications/hub`, **Then** the reverse proxy upgrades the connection to WebSockets and routes communication directly to the backend service.
3. **Given** an incoming request from an authorized network overlay (Tailscale or trusted local subnet), **When** reaching the reverse proxy, **Then** traffic is forwarded to the backend container over internal isolated networking without exposing raw service ports to untrusted interfaces.

---

### User Story 3 - Non-Disruptive Transactional Backups & Restoration Verification (Priority: P1)

As a homelab administrator, I want automated, consistent transactional backups of the password vault database and attachments with automated retention rotation and a verified restore procedure, so that catastrophic hardware failure or accidental data corruption does not cause irrecoverable secret loss.

**Why this priority**: In accordance with Constitution Principle V (Disaster Recovery & Backup by Design), every stateful service must define an automated backup schedule and verified restoration procedure before completion. Because password vaults contain mission-critical credentials, backups must be transactional (consistent snapshots without stopping the service).

**Independent Test**: Can be tested independently by triggering the backup process while the service is actively running, verifying that a valid SQLite `.backup` / vacuum dump and attachment bundle are generated, inspecting the integrity of the backup file, and simulating a clean restore to an isolated target verifying data completeness.

**Acceptance Scenarios**:

1. **Given** a live Vaultwarden service with active transactions, **When** the scheduled backup routine executes, **Then** an online transactional database backup is created without locking out clients or corrupting in-flight writes.
2. **Given** the generated backup artifact, **When** tested with an automated SQLite integrity check (`PRAGMA integrity_check`), **Then** the check reports 100% data consistency.
3. **Given** persistent attachments and encryption keys, **When** the backup routine runs, **Then** attachments, icon caches, and cryptographic configuration are packaged alongside the database snapshot.
4. **Given** existing backups exceeding the retention policy (e.g., daily snapshots kept for 30 days), **When** the maintenance job runs, **Then** aged backups are pruned automatically to preserve storage space.
5. **Given** an emergency recovery drill or disaster recovery scenario, **When** executing the documented restoration procedure, **Then** the entire vault state can be restored to a clean instance within 5 minutes.

---

### User Story 4 - Observability, Telemetry & Acceptance Health Checks (Priority: P2)

As a systems operator, I want automated health assertions, uptime probes, and structured journal telemetry integrated into the service deployment, so that service disruptions, degraded database states, or proxy disconnects are immediately detectable by automated monitoring.

**Why this priority**: In accordance with Constitution Principle III (Automated Verification & Acceptance Gates), Phase 5 applications require explicit verification gates, health check assertions, and telemetry integration before deployment sign-off.

**Independent Test**: Can be tested independently by querying the service health endpoint (`/alive`), checking container lifecycle status, validating WebSocket ping response, and confirming that security/audit logs stream into the system journal.

**Acceptance Scenarios**:

1. **Given** a healthy running Vaultwarden container, **When** an automated health probe queries the `/alive` endpoint, **Then** the service returns an HTTP 200 OK status within 500ms.
2. **Given** a failed container process or blocked backend port, **When** the verification suite runs, **Then** the test fails immediately with an actionable diagnostic message indicating container down status.
3. **Given** user authentication attempts and administrative actions, **When** these events occur, **Then** structured operational log records are dispatched to standard system log facilities (journald) for centralized triaging.

---

### User Story 5 - Least-Privilege Execution & Secret Isolation (Priority: P2)

As a security-conscious administrator, I want the Vaultwarden container executed under dedicated non-root credentials with secrets (admin tokens, database encryption keys) decoupled from version-controlled files, so that host compromise or credential leakage is prevented.

**Why this priority**: In accordance with Constitution Principles IV (Zero Cleartext Secrets) and VI (Modular & Decoupled Architecture), service credentials must never exist in cleartext version control, and containerized workloads must run with minimal privileges.

**Independent Test**: Can be tested independently by inspecting the running container processes to ensure they run under a non-root UID/GID, validating filesystem permissions on `/opt/services/vaultwarden/data`, and ensuring configuration secrets are injected securely via SOPS/age encrypted files or environment variables without cleartext in git.

**Acceptance Scenarios**:

1. **Given** the deployed container runtime, **When** inspecting process ownership, **Then** no Vaultwarden process runs as root (`UID 0`).
2. **Given** persistent storage directories at `/opt/services/vaultwarden`, **When** permissions are audited, **Then** access is restricted strictly to the designated service user and group (`0700` / `0750`).
3. **Given** repository source files and configuration templates, **When** searched for sensitive tokens (such as the admin token or database keys), **Then** zero plaintext credentials are present.
4. **Given** a fresh system bootstrap, **When** secrets are decrypted using the host's age key, **Then** the required environment variables are rendered securely for container consumption.

---

### Edge Cases

- **Container Abrupt Termination**: What happens if the host reboots or loses power while a write transaction is occurring in SQLite?
  *Requirement: SQLite Write-Ahead Logging (WAL) mode must be enabled to ensure crash recovery and prevent database corruption upon restart.*
- **Attachment Storage Exhaustion**: What happens when a user attempts to upload a file attachment that exceeds quota or available NVMe space?
  *Requirement: The service must cleanly reject uploads exceeding the configured maximum attachment size (e.g., 25MB) with an informative client error, preventing disk exhaustion.*
- **Signups After Initial Admin Creation**: What happens if an external actor discovers the Vaultwarden ingress before signups are restricted?
  *Requirement: Public open registration must be disabled by default (`SIGNUPS_ALLOWED=false`) after initial setup or restricted to administrator invitations, preventing unauthorized registrations.*
- **Reverse Proxy Drop-In Failure**: What happens if the Caddy reverse proxy fails to reload after adding the Vaultwarden ingress configuration?
  *Requirement: Ingress drop-ins must be validated using `caddy validate` prior to service reload, failing safely without taking down existing reverse proxy routes.*

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST deploy Vaultwarden as an isolated, containerized application under `/opt/services/vaultwarden`.
- **FR-002**: System MUST run the Vaultwarden application process under a non-root system account (least privilege principle).
- **FR-003**: System MUST store persistent application state, including the SQLite database, cryptographic salts, and attachments, on high-performance NVMe storage (`/opt/services/vaultwarden/data`).
- **FR-004**: System MUST enable SQLite Write-Ahead Logging (WAL) and synchronous durability modes to ensure ACID compliance and safe concurrent access.
- **FR-005**: System MUST route ingress traffic through the existing reverse proxy (Caddy) using a modular configuration drop-in.
- **FR-006**: System MUST enforce valid TLS encryption for all client connections to comply with browser and mobile WebCrypto requirements.
- **FR-007**: System MUST proxy WebSocket traffic for path `/notifications/hub` to enable real-time vault synchronization across connected clients.
- **FR-008**: System MUST provide an automated transactional database backup routine (using SQLite `.backup` / vacuum dump) that executes without stopping or interrupting service availability.
- **FR-009**: System MUST package persistent attachments alongside the transactional database snapshot into a dated backup bundle.
- **FR-010**: System MUST enforce an automated backup retention policy (e.g., retain daily backups for 30 days) and automatically prune expired archives.
- **FR-011**: System MUST verify the integrity of newly created database backups using automated integrity validation (`PRAGMA integrity_check;`) before marking the backup successful.
- **FR-012**: System MUST expose an automated health check endpoint (`/alive`) capable of verifying that the web server and database backend are responding normally.
- **FR-013**: System MUST direct structured audit and diagnostic logs to standard system logging sinks (systemd journald / stdout) without logging sensitive master passwords or decryption keys.
- **FR-014**: System MUST encrypt sensitive service credentials (such as `ADMIN_TOKEN`) at rest using SOPS with age, preventing cleartext secret leakage in version control.
- **FR-015**: System MUST disable public unauthenticated signups by default (`SIGNUPS_ALLOWED=false`), permitting only invitation-based registration or explicit administrative authorization.
- **FR-016**: System MUST provide an automated verification script (e.g., `verify-phase5-vaultwarden.sh` / `.ps1`) that programmatically validates container health, reverse proxy routing, WebSocket handshake, and backup snapshot creation.

### Key Entities

- **Vault Database (`vaultwarden.sqlite3`)**: The core relational database containing encrypted user vaults, ciphers, organizations, collections, folders, and metadata.
- **Encrypted Cipher**: An encrypted credential entry containing usernames, passwords, URIs, notes, custom fields, or TOTP secrets, encrypted client-side using user-derived keys.
- **Attachments**: Encrypted binary assets associated with individual vault ciphers, stored within the persistent filesystem path.
- **Backup Archive**: A timestamped, self-contained archive containing the consistent transactional SQLite snapshot, cryptographic metadata, and attachments.
- **Reverse Proxy Ingress Drop-In**: A modular configuration snippet integrated into the Caddy configuration managing HTTPS routing, TLS termination, header sanitization, and WebSocket upgrading.
- **Administrative Token**: A securely hashed administrative authentication secret protecting the `/admin` interface for system diagnostics and invitation management.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Vaultwarden web interface and health check endpoint (`/alive`) respond with HTTP 200 within 500ms of request dispatch.
- **SC-002**: Reverse proxy upgrades `/notifications/hub` connections to WebSockets with a 101 Switching Protocols status, achieving cross-device vault sync propagation within 2 seconds of an item change.
- **SC-003**: 100% of Bitwarden standard clients (official browser extension, mobile application, CLI, and web vault) successfully authenticate and synchronize against the deployed service.
- **SC-004**: Automated transactional backup executes in under 30 seconds with zero service downtime, produces a verified clean SQLite integrity check, and enforces the 30-day retention pruning rule.
- **SC-005**: Full disaster recovery restoration from a raw backup snapshot to an operational state completes in under 5 minutes with zero data corruption.
- **SC-006**: Automated test script validates all Phase 5 Vaultwarden completion gates (container health, ingress TLS, WebSocket upgrade, backup verification, and secret decoupling) with a clean zero exit status.

## Assumptions

- **Container Runtime**: Container services in Phase 5 utilize Docker or Podman Compose managed via systemd unit files or declarative compose definitions under `/opt/services/<app>/compose.yml`.
- **Storage Tier Allocation**: Vaultwarden persistent data lives in the Tier 0 Fast NVMe App Data tier (`/opt/services/vaultwarden`), as defined in Roadmap section 5.1, while backup archives are staged locally prior to Phase 7 centralized offsite synchronization.
- **Network Ingress & Domain**: Vaultwarden ingress is accessed via internal domain resolution over the Tailscale mesh or local homelab DNS (e.g., `vaultwarden.lan` or `vaultwarden.<tailnet-host>`), terminating at the Caddy reverse proxy provisioned in Phase 3.
- **User Scale**: Sized for household and homelab use (1-10 users), making SQLite with WAL mode an optimal, lightweight, zero-maintenance database engine requiring no dedicated database daemon overhead.
- **Secrets Management**: Host has SOPS/age initialized from Phase 2; secrets for Vaultwarden (such as the admin token) are stored in an encrypted Ansible vault or SOPS file and injected into the container environment.
