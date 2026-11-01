# Feature Specification: Core Hardening & Configuration Management Foundation

**Feature Branch**: `002-core-hardening-iac`

**Created**: 2026-11-01

**Status**: Draft

**Input**: User description: "Let's start phase 2"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Declarative Configuration Management & Secrets Pipeline (Priority: P1)

As a homelab administrator, I want to declare, apply, and maintain all base system configurations through an idempotent, automated configuration management framework with encrypted secrets at rest, so that system state is reproducible, auditable in version control, and free of cleartext credentials.

**Why this priority**: Declarative configuration management and encrypted secret handling form the foundation for all subsequent infrastructure layers (networking, storage, container workloads, game streaming). Without this foundation, host configurations drift and secrets risk accidental exposure.

**Independent Test**: Can be tested independently by running the configuration management playbooks against the bootstrap target host; it succeeds cleanly, applies all base host declarations, and leaves all secrets encrypted on disk and in version control. A second consecutive execution reports zero changes (clean no-op convergence).

**Acceptance Scenarios**:

1. **Given** a cleanly bootstrapped host reachable via network, **When** the administrator runs the configuration management convergence command with the decryption key available, **Then** all base system roles and configurations are applied successfully with zero failures.
2. **Given** an already converged host, **When** the administrator re-runs the configuration management convergence command, **Then** the process completes with zero changes applied (strict idempotency).
3. **Given** encrypted configuration vaults containing sensitive parameters, **When** inspected in the repository working tree or committed to version control, **Then** sensitive values are fully ciphertext and inaccessible without the master decryption key.
4. **Given** an invalid or missing decryption key, **When** configuration management convergence is attempted, **Then** execution terminates immediately with a clear diagnostic message and makes no unverified changes to the target host.

---

### User Story 2 - Host Hardening & Secure Remote Access Control (Priority: P1)

As a homelab administrator, I want remote access to the host hardened against unauthorized access while preserving seamless administrative privilege escalation, so that the server is protected against credential brute-forcing and network attacks without impeding automated maintenance.

**Why this priority**: Once a host is connected to the local network or internet-adjacent networks, securing remote entry points and administrative privileges is critical to prevent compromise before higher-level services are deployed.

**Independent Test**: Can be tested independently by verifying SSH daemon configuration rejects password authentication, accepts valid administrative public keys, and enforces connection rate limiting, while the administrative user executes privileged commands without password prompts.

**Acceptance Scenarios**:

1. **Given** a remote client attempting SSH access with a password, **When** authentication is requested, **Then** the host unconditionally rejects the password attempt and requires cryptographic public key authentication.
2. **Given** repeated failed connection attempts or anomalous connection bursts, **When** rate limits or intrusion detection thresholds are exceeded, **Then** the offending client IP is temporarily blocked and the security event is logged to the system journal.
3. **Given** an authenticated administrative user session, **When** a privileged command or configuration automation script executes via `sudo`, **Then** privileges are granted without an interactive password prompt.
4. **Given** an unprivileged user not in the designated administrative group, **When** privilege escalation is attempted, **Then** access is denied and an audit log entry is recorded in the system journal.

---

### User Story 3 - Core Diagnostics, Health Daemons & Device Symlinks (Priority: P2)

As a homelab administrator, I want core system daemons (time synchronization, disk health diagnostics, memory pressure safeguards) and persistent hardware device mappings configured automatically, so that the host maintains system health, prevents out-of-memory kernel panics, logs hardware telemetry, and reliably addresses attached smart home and AI peripherals across reboots.

**Why this priority**: Hardware reliability and peripheral stability are vital before configuring storage pools and container stacks. Persistent udev mappings ensure smart home controllers and accelerator devices do not change paths upon reboot or USB re-enumeration.

**Independent Test**: Can be tested independently by verifying `chrony` tracks reliable time sources, `smartd` monitors disk health attributes and logs diagnostic status to the journal, `systemd-oomd` monitors memory pressure, and udev rules create predictable symlinks for attached peripherals (such as Z-Wave dongles and Coral TPUs).

**Acceptance Scenarios**:

1. **Given** the host is running, **When** system time status is queried, **Then** the time synchronization daemon reports active synchronization with configured upstream network time sources.
2. **Given** connected storage drives supporting diagnostic reporting, **When** the drive diagnostic daemon runs, **Then** SMART health attributes are actively tracked, recorded in system logs, and failure threshold monitoring is active.
3. **Given** heavy memory pressure approaching exhaustion thresholds, **When** configured swap or memory pressure limits are breached, **Then** the user-space out-of-memory daemon intervenes gracefully according to configured cgroup policies rather than triggering uncoordinated kernel hangs.
4. **Given** supported physical peripherals (such as a USB Z-Wave stick or Coral TPU) connected to the host, **When** the device is enumerated by the kernel, **Then** persistent, stable device symlinks (e.g. `/dev/zwave` or persistent `/dev/serial/by-id/*` mappings) with appropriate group ownership are created.

---

### User Story 4 - Phase 2 Quality, Backup & Telemetry Gates (Priority: P2)

As a homelab administrator, I want the Phase 2 baseline verified against Constitution quality gates—including out-of-band secret backup verification and local health telemetry assertions—so that the platform is guaranteed stable and recoverable before proceeding to Phase 3 (Network & Remote Access Overlay).

**Why this priority**: In accordance with Constitution Principles III (Acceptance Gates) and V (Disaster Recovery), each phase must verify its backup posture and health telemetry before sign-off.

**Independent Test**: Can be tested independently by running automated verification checks that validate linting, verify encrypted vault commits, confirm out-of-band master key backup documentation, and assert active status across all Phase 2 systemd units.

**Acceptance Scenarios**:

1. **Given** the configuration management codebase and playbooks, **When** automated linting and syntax validation are executed, **Then** all playbooks, role definitions, and inventory files pass with zero syntax or style errors.
2. **Given** the encrypted configuration vault and age master key, **When** backup posture is validated, **Then** the encrypted vault is committed to version control and the out-of-band master key recovery procedure is documented and verified.
3. **Given** the deployed host, **When** automated health assertions run, **Then** `chronyd`, `smartd`, `systemd-oomd`, and hardened SSH services report active/healthy status, and persistent journal logging is verified functional.

---

### Edge Cases

- **Missing or Corrupted Secret Key**: If the master decryption key is missing or corrupted, configuration runs must abort early with a non-zero exit code and descriptive error message before applying partial state changes.
- **SSH Lockout Prevention**: Configuration updates to SSH settings must validate syntax and preserve existing administrative access before reloading the daemon, preventing headless lockout.
- **Disconnected Peripherals**: If optional hardware devices (e.g., Coral TPU or Z-Wave controller) are not physically plugged into the host when configuration runs, udev rules must still install cleanly without causing playbook failures.
- **Unsynchronized Upstream Clock**: If upstream NTP servers are temporarily unreachable, the time daemon must maintain local monotonic time without step disruptions and log an actionable warning.
- **Non-SMART Compliant Drives**: If a storage device does not support standard SMART reporting (e.g., certain USB enclosures or virtual disks in testing), the diagnostic daemon must log an informational notice rather than failing system startup.
- **Repeated Playbook Runs**: Re-running configuration management on an already converged host must produce zero changed tasks and zero restarts of stable services.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide an Infrastructure-as-Code configuration repository structured with standardized roles, playbooks, inventories, and linting rules.
- **FR-002**: All configuration secrets, credentials, and sensitive variables MUST be encrypted at rest using strong asymmetric cryptography (SOPS with age keys) prior to being committed to version control.
- **FR-003**: The configuration framework MUST execute idempotently, producing zero state changes and zero service interruptions when executed against an already converged host.
- **FR-004**: The host MUST enforce SSH daemon hardening by restricting remote authentication exclusively to cryptographic public keys and unconditionally disabling password-based logins and direct root logins.
- **FR-005**: The host MUST enforce connection rate limiting and brute-force protection on incoming SSH connections, logging offending source addresses to the system journal.
- **FR-006**: The host MUST configure administrative user privileges such that authorized administrative users in the designated wheel group execute privileged administrative commands via `sudo` without interactive password prompts.
- **FR-007**: The host MUST deploy and enable an active time synchronization service (`chrony`) configured to maintain sub-second clock accuracy against resilient upstream time sources.
- **FR-008**: The host MUST deploy and enable a continuous drive health monitoring daemon (`smartd`) configured to monitor drive self-test attributes, track wear indicators, and log alerts to the system journal.
- **FR-009**: The host MUST configure user-space memory pressure safeguards (`systemd-oomd`) with appropriate system slice policies to protect core system stability under heavy load.
- **FR-010**: The host MUST deploy udev hardware rules providing persistent, human-readable symlinks and group access permissions for attached peripherals including home automation radio sticks and hardware accelerators.
- **FR-011**: The host MUST configure persistent, structured system journal logging (`journald`) with bounded storage quotas to prevent disk space exhaustion while preserving diagnostic history.
- **FR-012**: The system MUST provide an automated verification suite that validates linting compliance, service unit health, and telemetry logging before declaring Phase 2 complete.

### Key Entities

- **Host Inventory**: Represents managed infrastructure targets, host variables, group memberships, and connection parameters.
- **Encrypted Secret Vault**: Represents sensitive operational parameters (tokens, credentials, private keys) encrypted at rest using asymmetric public key cryptography.
- **Administrative Identity**: Represents authorized operator accounts configured with public key authentication, wheel group membership, and non-interactive sudo escalation.
- **System Diagnostic Service**: Represents background operational daemons (`chronyd`, `smartd`, `systemd-oomd`) responsible for host timekeeping, drive health, and resource safety.
- **Peripheral Hardware Rule**: Represents udev rules mapping kernel device paths (vendor/product IDs, serial numbers) to persistent device symlinks and group permissions.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of base host configuration is declared in version control; clean-slate convergence against a freshly bootstrapped host completes in under 10 minutes.
- **SC-002**: Re-running configuration management on a converged host produces 0 changed tasks, confirming strict idempotency.
- **SC-003**: 0 cleartext passwords or secret keys exist in the repository tree; all secrets pass automated git pre-commit scanning.
- **SC-004**: 100% of password-based SSH connection attempts are rejected; key-based administrative login succeeds in under 3 seconds.
- **SC-005**: System time synchronization maintains clock offset within 50 milliseconds of reference time sources.
- **SC-006**: 100% of monitored storage drives have active SMART tracking enabled and reported in system health telemetry.
- **SC-007**: Automated linting (`ansible-lint`, syntax checks) passes with 0 errors and 0 warnings.
- **SC-008**: Phase 2 completion verification assertions pass 100% of checks across service health, log sinks, and secret backup readiness.

## Assumptions

- The target host has completed Phase 1 (Base OS Bootstrap) and is booted into Arch Linux with network connectivity and an initial SSH-reachable administrative user.
- The operator possesses the age private key corresponding to the public key used for vault encryption.
- Storage devices connected to the host adhere to standard ATA/NVMe specifications for diagnostic query support via `smartd`.
- Full remote access overlay (Tailscale) and public reverse proxy (Caddy) are explicitly deferred to Phase 3.
- Storage drive pooling (MergerFS) and parity protection (SnapRAID) are explicitly deferred to Phase 4.
- Application container workloads (Docker/Podman) are explicitly deferred to Phase 5.
