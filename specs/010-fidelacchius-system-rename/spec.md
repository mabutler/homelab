# Feature Specification: System Identity & Backup Bucket Naming (Fidelacchius)

**Feature Branch**: `010-fidelacchius-system-rename`

**Created**: 2026-11-04

**Status**: Draft

**Input**: User description: "There's some naming I need to fix. The server name has a generic name, but I want it named Fidelacchius (the sword of faith). I named the backblaze bucket a test name, but want it named something official as well. Anything else along those lines should be fixed too"

## Clarifications

### Session 2026-11-04
- **Q1: Official Backblaze B2 Bucket Name & Snapshot Strategy** → **A**: Option A — Use official Backblaze B2 bucket **`fidelacchius-backups`** (repository target `b2:fidelacchius-backups:fidelacchius`). Initialize a clean Restic repository, run a fresh full encrypted backup of all host secrets and application databases, verify restore capability, and retire the legacy test bucket (`homelab2-fidelachius`).
- **Q2: Tailscale Node Collision with Legacy Offline `fidelacchius` Device** → **A**: Option A — Decommission/delete the legacy offline `fidelacchius` device (`100.109.1.87`, last seen 27 days ago) from the Tailscale Admin Console so this machine claims the clean `fidelacchius` hostname and `fidelacchius.fable-mackarel.ts.net` MagicDNS and Funnel domain without numeric suffixes (e.g., `-1`).
- **Q3: Scope of "Anything Else Along Those Lines" (Internal Paths vs Host Identity)** → **A**: Option A — Focus on Host Identity, Network Ingress, and IaC Inventory: rename OS hostname (`fidelacchius`), `/etc/hosts`, Tailscale node, Funnel URL, Vaultwarden `DOMAIN`, Ansible inventory host (`homelab2` -> `fidelacchius`), and `host_vars/fidelacchius/`. Keep internal platform configuration paths (`/etc/homelab`, `/opt/services`, `/etc/udev/rules.d/99-homelab-peripherals.rules`, `homelab-backup.service`) unchanged to avoid unnecessary systemd service migrations.
- **Q4: Backblaze B2 Application Key Rotation & Renaming** → **A**: The operator is provisioning a new Backblaze B2 Application Key (replacing the legacy key previously named `homelab` in the B2 portal). The new Key ID and Key Secret will be placed directly into the gitignored secret files (`ansible/inventory/group_vars/all/vault.yml` and `/etc/homelab/backup.env`), preserving Constitution Principle IV (zero secrets in version control).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - System Hostname & Network Identity as Fidelacchius (Priority: P1)

As a server owner and operator, I want the server's operating system hostname, terminal prompts, and network overlay identity changed from generic names ("homelab"/"homelab2") to "Fidelacchius" (the sword of faith), so that the machine reflects its official personal identity consistently across local logins, network discovery, and remote access.

**Why this priority**: The primary motivation is establishing the server's canonical identity. Every subsequent network-aware service, dashboard, and management tool inherits this identity.

**Independent Test**: Can be tested independently by logging into the system, running hostname diagnostic checks to verify `fidelacchius`, confirming local resolution via `/etc/hosts`, and verifying that the network mesh overlay identifies the device as `fidelacchius` with functional connectivity.

**Acceptance Scenarios**:

1. **Given** the server operating system, **When** queried via standard hostname utilities, **Then** the system reports `fidelacchius` as its static and transient hostname.
2. **Given** an operator opening a new terminal or SSH session, **When** the shell prompt or message of the day displays, **Then** the prompt displays `fidelacchius` instead of generic `homelab` placeholders.
3. **Given** the network overlay agent (Tailscale) following decommissioning of the legacy offline node, **When** checking device connectivity, **Then** the node is registered and reachable under the official node identity `fidelacchius` (without numeric suffixes) and responds on `fidelacchius.fable-mackarel.ts.net`.
4. **Given** publicly exposed services utilizing the network overlay funnel (e.g., Vaultwarden), **When** accessing the service endpoint, **Then** the public domain reflects `fidelacchius.fable-mackarel.ts.net` without breaking TLS termination or WebCrypto functionality.

---

### User Story 2 - Official Backblaze B2 Backup Bucket & Repository Migration (Priority: P1)

As a backup administrator governed by disaster recovery standards, I want the offsite backup storage renamed from the temporary test bucket to an official, canonically named Backblaze B2 bucket (`fidelacchius-backups`), so that automated offsite backups and recovery operations target a permanent, properly titled cloud repository.

**Why this priority**: Backups are mission-critical. Running production backups to a test-named or misspelled bucket creates operational debt and confusion during disaster recovery.

**Independent Test**: Can be tested independently by initializing the new repository in `b2:fidelacchius-backups:fidelacchius`, running an automated backup, confirming the snapshot appears in the repository catalog, and running a test restore of a critical file (such as configuration secrets) to verify end-to-end data integrity.

**Acceptance Scenarios**:

1. **Given** the configured offsite backup environment, **When** the backup client connects to cloud storage, **Then** it authenticates against the official Backblaze B2 bucket `fidelacchius-backups` with repository URI `b2:fidelacchius-backups:fidelacchius`.
2. **Given** scheduled backup timers, **When** the automated backup service triggers, **Then** a client-side encrypted snapshot is successfully committed to `fidelacchius-backups` and passes integrity verification.
3. **Given** disaster recovery tooling, **When** executing a targeted restore drill, **Then** the restore script reads from `b2:fidelacchius-backups:fidelacchius` and restores authentic configuration files without error.

---

### User Story 3 - Declarative Infrastructure & Inventory Identity Alignment (Priority: P2)

As an Infrastructure-as-Code operator, I want the Ansible inventory, host variable definitions, and platform deployment scripts updated to reflect `fidelacchius` instead of `homelab2`, so that configuration playbooks can be converged cleanly against the official hostname without legacy alias drift.

**Why this priority**: The repository enforces declarative-first automation (Constitution Principle I). If the codebase inventory still targets `homelab2` while the machine is `fidelacchius`, running automation playbooks will fail or require brittle override flags.

**Independent Test**: Can be tested independently by running the central Ansible convergence playbook with `-i inventory/hosts.yml` targeting `fidelacchius` and confirming zero unreachable host errors or missing host-variable lookups.

**Acceptance Scenarios**:

1. **Given** the Ansible inventory (`hosts.yml`), **When** inspecting managed hosts, **Then** the primary node is declared as `fidelacchius` under the target host groups.
2. **Given** host-specific configuration files (`host_vars/`), **When** Ansible evaluates disk storage layouts and hardware variables, **Then** variable files reside in `host_vars/fidelacchius/` and resolve identically.
3. **Given** platform verification playbooks and operator helper scripts, **When** executed, **Then** they reference `fidelacchius` as the default target host.

---

### Edge Cases

- **Tailscale Name Collision Resolution**: The legacy offline device (`100.109.1.87`) must be removed from the Tailscale Admin Console before or during the node rename so Tailscale assigns the exact name `fidelacchius` rather than `fidelacchius-1`.
- **Public Domain Transition & Client Re-authentication**: Active Bitwarden clients configured for `homelab.fable-mackarel.ts.net` must update their server URL to `https://fidelacchius.fable-mackarel.ts.net` and log in again once the Funnel route is updated.
- **Preservation of Platform Configuration Namespaces**: Standard internal platform paths (such as `/etc/homelab/`, `/opt/services/`, and systemd service names like `homelab-backup.service`) are preserved unchanged, maintaining stability and avoiding unnecessary service unit renaming risks.
- **Case Sensitivity in Network Standards**: Hostnames and cloud bucket names require strict lowercase alphanumeric and hyphen formatting per RFC 1123 and S3/B2 naming standards (`fidelacchius`, `fidelacchius-backups`), while display branding uses capitalized "Fidelacchius".

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST set the static and transient Linux operating system hostname to `fidelacchius` in `/etc/hostname` and map it to localhost loopback in `/etc/hosts`.
- **FR-002**: System MUST register and advertise the node name on the Tailscale network mesh as `fidelacchius` (claiming `fidelacchius.fable-mackarel.ts.net` upon legacy device decommissioning).
- **FR-003**: System MUST update public-facing service domain configurations (including Vaultwarden `DOMAIN` environment variable and Tailscale Funnel route) to reflect `fidelacchius.fable-mackarel.ts.net`.
- **FR-004**: System MUST configure the offsite backup pipeline with the official Backblaze B2 bucket `fidelacchius-backups` (`b2:fidelacchius-backups:fidelacchius`) and initialize a verified Restic repository.
- **FR-005**: System MUST update committed example templates (`vault.yml.example`, `env.example`) to reference the official naming convention rather than generic placeholders.
- **FR-006**: System MUST update the Ansible inventory file (`ansible/inventory/hosts.yml`) and host variables directory (`ansible/inventory/host_vars/`) from `homelab2` to `fidelacchius`.
- **FR-007**: System MUST update operator orchestration scripts (`scripts/apply-*.sh`, `scripts/apply-*.ps1`, `scripts/verify-*.sh`) to default to target host `fidelacchius`.
- **FR-008**: System MUST maintain Constitution Principle IV (zero secrets in version control) ensuring no real credentials or encryption keys are leaked during bucket or inventory updates.
- **FR-009**: System MUST verify disaster recovery restore readiness from the official bucket `fidelacchius-backups` in accordance with Constitution Principle V.

### Key Entities *(include if feature involves data)*

- **Host Identity**: The canonical hostname (`fidelacchius`), display name ("Fidelacchius (the sword of faith)"), and local/network address resolutions.
- **Network Overlay Identity**: The Tailscale node name (`fidelacchius`) and associated MagicDNS/Funnel Fully Qualified Domain Name (`fidelacchius.fable-mackarel.ts.net`).
- **Backup Repository Target**: The Backblaze B2 bucket URI and Restic repository configuration (`b2:fidelacchius-backups:fidelacchius`) housing client-side encrypted backup snapshots.
- **Infrastructure Inventory Target**: The Ansible host definition and associated host variable tree (`host_vars/fidelacchius/`) governing hardware topology.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: System hostname query (`hostnamectl` / `uname -n`) returns `fidelacchius` in 100% of checks.
- **SC-002**: Tailscale MagicDNS and Funnel endpoints successfully resolve and route to `fidelacchius.fable-mackarel.ts.net` with valid TLS certificates.
- **SC-003**: An automated backup snapshot completes successfully to the official Backblaze B2 bucket `fidelacchius-backups`, and a subsequent restore test recovers 100% of tested verification files with matching SHA256 checksums.
- **SC-004**: Running `ansible-playbook -i inventory/hosts.yml playbooks/site.yml --check` against host `fidelacchius` succeeds with zero inventory lookup or host connection errors.
- **SC-005**: System rename and backup cutover completes with zero data loss and under 15 minutes of service downtime.

## Assumptions

- The operator will remove the legacy offline `fidelacchius` node (`100.109.1.87`) from the Tailscale Admin Console before or during the rename procedure.
- The operator possesses Backblaze B2 account credentials capable of creating or writing to the newly designated bucket `fidelacchius-backups`.
- The underlying project repository name (`homelab2`) and Git remote URL remain as-is as the project workspace umbrella, while the running server host identity is named `fidelacchius`.
- Standard internal platform paths (`/etc/homelab`, `/opt/services`, and systemd service names like `homelab-backup.service`) remain stable and unchanged.
