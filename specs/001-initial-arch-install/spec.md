# Feature Specification: Initial Arch Linux Installation Bootstrap

**Feature Branch**: `001-initial-arch-install`

**Created**: 2026-10-11

**Status**: Draft

**Input**: User description: "Build out the initial scripts/configs for installation. I will boot an Arch live USB and SSH into it and run an install script. I can do a few manual steps to initiate that (like cloning the github repo and pulling down secrets archives). End result of this script should be a working Arch installation that can reboot and allow installation to continu"

## Clarifications

### Session 2026-10-11
- Q: How should the newly installed base operating system confirm its telemetry and observability readiness before Phase 1 is declared complete? (FR-011) → A: Phase 1 is an exception to external telemetry and backup rules because it holds no user data or application services yet; verification is satisfied entirely by local bootstrap assertions (UEFI boot, local DHCP acquisition, and responsive SSH daemon ready for Phase 2).
- Q: Should the roadmap phases be reorganized so that Network and Remote Access (Tailscale, reverse proxy, TLS, firewall) is completed before Storage and Applications, or should the current sequence be maintained with staged configurations reviewed later? → A: Option A — Reorganize roadmap phases to promote Network & Ingress (Tailscale, nftables firewall, Caddy reverse proxy with automated ACME TLS) to Phase 3, placing Storage Pooling into Phase 4 and Applications into Phase 5. This ensures all network, remote management, and TLS ingress prerequisites are active before storage workloads and applications are provisioned.
- Q: Should FR-004 support both Ext4 and Btrfs for the base OS root filesystem, or standardize strictly on Ext4? → A: Standardize strictly on Ext4 for the Phase 1 base OS root partition to align with plan.md, data-model.md, and implementation tasks (T011). Btrfs is explicitly out of scope for the Phase 1 base OS root and reserved as an alternative for storage pooling in Phase 4.

### Session 2026-10-12
- Q: Which specific packages constitute the mandatory "essential administration tools" in FR-006 versus optional operator utilities? → A: The mandatory baseline administration packages required by FR-006 are explicitly enumerated as `sudo`, `openssh`, `python`, and `git`. Additional operator tools and conveniences (such as `tmux` and `vim`, or `htop` and `jq`) are explicitly non-mandatory and MUST NOT be hardcoded into the base installer; they must be decoupled and provisioned optionally via the `EXTRA_PACKAGES` configuration setting in `install.conf`.
- Q: What constitutes the Installation Secrets Bundle and are private keys staged or copied during bootstrap? (Principle IV) → A: Only public SSH keys and non-secret installation parameters are consumed by the bootstrap installer; private keys are never staged or copied to the host.
- Q: How does FR-013 function relative to discrete functional requirements FR-005, FR-007, FR-008, FR-009, and FR-010? → A: FR-013 is clarified as an overarching post-reboot integration verification gate (composite acceptance milestone) rather than an independent component requirement. While FR-005, FR-007, FR-008, FR-009, and FR-010 define discrete subsystem provisioning, and FR-011 defines internal in-chroot pre-reboot assertions, FR-013 establishes the end-to-end integration acceptance milestone (operator smoke tests documented in quickstart.md) confirming full post-boot system convergence (native UEFI boot, DHCP lease, authorized-key SSH access, passwordless sudo, and Python runtime availability) before handing off to Phase 2 automation.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Safe and Automated Base OS Installation from Live Environment (Priority: P1)

An operator booted into an Arch Linux live environment (with SSH access, the cloned homelab repository, and decrypted secrets available) runs an installation script. The installer identifies candidate storage drives, enforces an explicit confirmation safety guard before modifying disks, partitions the target storage, installs the base operating system and boot infrastructure, configures the base system, and executes automated verification checks before declaring completion.

**Why this priority**: Without a functional, safe, verified base OS installation, no homelab infrastructure can exist. This is the foundational prerequisite for the entire system lifecycle. In accordance with Constitution Principle II (Strict Idempotency & Safe Convergence), destructive disk formatting must never run unconfirmed.

**Independent Test**: Can be tested on a bare-metal host or test virtual machine booted to an Arch Linux live environment. The operator runs the installer, confirms the target disk, and observes that the installer partitions, formats, installs base packages, and passes pre-reboot verification checks without errors.

**Acceptance Scenarios**:

1. **Given** an operator running the installer in an active live environment, **When** prompted with the detected candidate storage drive, **Then** the installer requires explicit confirmation before any destructive disk modifications take place.
2. **Given** the operator confirms the target disk, **When** the installation executes, **Then** the system partitions the disk, creates the required filesystems, installs core OS packages, configures bootloader infrastructure, and executes pre-reboot validation checks.
3. **Given** the operator declines confirmation or specifies an invalid drive, **When** the confirmation guard runs, **Then** the installer aborts immediately with zero modifications to disk partition tables or data.
4. **Given** a network failure or package download error occurs during installation, **When** the failure is detected, **Then** the installer halts immediately with an actionable error message on stderr and unmounts target filesystems cleanly.

---

### User Story 2 - Headless First Boot with Verified Remote Access (Priority: P2)

Upon completion of the installation, the system is safely rebooted. The newly installed target operating system boots directly via UEFI into a working state, initializes the network interface, and starts the SSH service with the operator's authorized SSH keys and administrative user already configured. The operator connects to the new installation over the network without attaching a physical monitor or keyboard.

**Why this priority**: Homelab servers frequently operate headless in racks or remote locations. If the target system fails to boot or cannot be reached via SSH after reboot, the operator must intervene physically, breaking the automation workflow.

**Independent Test**: Can be tested by issuing a reboot on the newly installed system, observing that it boots without interactive console prompts, and establishing an SSH connection from an administrative workstation using the pre-configured SSH key.

**Acceptance Scenarios**:

1. **Given** a cleanly installed machine rebooting from the target drive, **When** the boot sequence completes, **Then** the host obtains network connectivity and starts the SSH service automatically.
2. **Given** the operator attempts to connect via SSH using their authorized key, **When** authenticating as the provisioned administrative user, **Then** the session is established successfully without password prompts.
3. **Given** direct root login or password authentication over SSH, **When** an authentication attempt is made, **Then** password-based SSH access is denied by default in accordance with security standards.

---

### User Story 3 - Execution Continuation Readiness (Priority: P3)

Once connected to the rebooted target machine, the base environment contains necessary runtime dependencies, privilege escalation configurations, and repository state so subsequent installation and configuration management workflows (such as Ansible playbooks or post-install scripts) can proceed immediately without manual system patching.

**Why this priority**: The installation script is a bootstrap phase; its objective is to hand off seamlessly to the next stage of homelab automation. If baseline dependencies or sudo permissions are missing, automated convergence cannot continue.

**Independent Test**: Can be tested by logging into the newly booted host, verifying sudo privileges without password friction, and confirming that standard configuration management dependencies (e.g., Python runtime, basic system tools) are operational.

**Acceptance Scenarios**:

1. **Given** an authenticated administrative session on the rebooted host, **When** the user executes commands via privilege escalation (sudo), **Then** commands execute successfully according to configured privilege policies.
2. **Given** downstream automation tools require standard runtime interpreters, **When** invoked on the fresh system, **Then** baseline dependencies (such as Python) are present and functional.

---

### Edge Cases

- **Target Drive Identification Ambiguity**: When multiple storage drives (such as USB installation media, NVMe drives, and existing storage disks) are attached, the installer must clearly present drive model, size, and device node, preventing accidental selection of the installer drive or unintended data drives.
- **Existing Partition Signatures**: When the target drive contains prior GPT/MBR partition tables, filesystem signatures, or volume metadata, the installer must safely wipe existing signatures only after explicit confirmation.
- **Network Interruption During Package Installation**: If internet connectivity drops while pacstrap or package downloading is in progress, the installation must fail fast, provide descriptive diagnostics, and avoid leaving partially mounted, inconsistent states.
- **Firmware / Boot Environment Mismatch**: If the live environment was booted under Legacy BIOS instead of modern UEFI, the installer must detect this before modifying disks and abort with instructions to boot via UEFI.
- **Missing or Incomplete Secrets Bundle**: If the required secrets archive or SSH keys are absent or corrupt in the live session, the installer must abort during pre-flight checks before modifying the target disk.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The installer MUST perform pre-flight checks validating that the system was booted in UEFI mode, has active internet connectivity, and has the required repository and secrets artifacts available before touching storage.
- **FR-002**: The installer MUST identify available storage block devices and require explicit confirmation from the operator identifying the target drive before executing any partitioning or formatting operations.
- **FR-003**: The installer MUST immediately abort and exit with a non-zero exit code if the target drive confirmation is rejected, unverified, or cancelled.
- **FR-004**: The installer MUST configure the target disk storage layout with a dedicated EFI System Partition (ESP) and a plain, unencrypted Ext4 root filesystem to guarantee unattended headless reboot without pre-boot passphrase prompts or early-boot networking dependencies (Btrfs root is explicitly out of scope for Phase 1 and reserved as an alternative for storage pooling in Phase 4).
- **FR-005**: The installer MUST configure dynamic host network addressing (DHCP) and set the system hostname based on the installation profile or secrets bundle, enabling predictable discovery via router MAC reservation while minimizing local configuration drift.
- **FR-006**: The installer MUST install the minimal Arch Linux base operating system, Linux kernel, system firmware, and mandatory baseline administration packages (specifically `sudo`, `openssh`, `python`, and `git`). Any additional administrative tools or user utilities (such as `tmux` and `vim`) MUST be decoupled from the mandatory baseline and provisioned optionally via the `EXTRA_PACKAGES` configuration setting.
- **FR-007**: The installer MUST configure and install a UEFI-compatible bootloader configured to boot the installed operating system by default.
- **FR-008**: The installer MUST create a designated administrative user account with elevated privileges (sudo/wheel group) and provision authorized SSH public keys.
- **FR-009**: The installer MUST install and enable an SSH daemon configured for secure public-key authentication, disabling cleartext password authentication.
- **FR-010**: The installer MUST install baseline runtime dependencies (including Python) required for subsequent configuration management phases.
- **FR-011**: The installer MUST execute in-chroot pre-reboot verification assertions (validating fstab entries, bootloader configuration, administrative user setup, SSH key presence, and enabled systemd services); post-boot verification is executed post-reboot as operator smoke tests (documented in quickstart.md); external telemetry agents and offsite backups are explicitly out-of-scope for Phase 1 as no user data or services are hosted yet.
- **FR-012**: The installer MUST safely unmount all filesystems and cleanly terminate before prompting or initiating system reboot.
- **FR-013**: The installer and bootstrap procedure MUST satisfy an overarching post-reboot integration verification gate (composite acceptance milestone and operator smoke tests documented in quickstart.md) confirming that upon first reboot, all provisioned subsystems converge into an operational headless state: native UEFI boot succeeds (FR-007), network connectivity is acquired via DHCP (FR-005), sshd is reachable with authorized public keys without password authentication (FR-008, FR-009), sudo privilege escalation succeeds without password prompts (FR-008), and the Python runtime is operational (FR-010) for downstream configuration management handoff.

### Key Entities *(include if feature involves data)*

- **Target Node Definition**: Represents the target physical machine, its designated storage device node, firmware parameters (UEFI), and assigned network identity.
- **Administrative Identity**: Represents the initial administrative user, privilege group mapping, and authorized public SSH credentials.
- **Storage Profile**: Represents the disk partition table, partition sizes, filesystem types (FAT32 for ESP and Ext4 for root), mount points, and volume identifiers.
- **Installation Secrets Bundle**: The configuration inputs prepared in the live session containing public key material and non-secret installation parameters (e.g., authorized public SSH keys and system configuration). In accordance with Principle IV, only public SSH keys and non-secret installation parameters are consumed by the bootstrap installer; private keys are never staged or copied to the host.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of installation runs require explicit confirmation before performing any non-reversible disk partitioning or formatting operations.
- **SC-002**: Complete installation from script invocation to completion completes in under 15 minutes on a standard broadband connection (100 Mbps+).
- **SC-003**: Rebooted system successfully brings up its network interface and SSH service within 90 seconds of reboot.
- **SC-004**: 100% of post-reboot SSH connection attempts using the provisioned administrative key succeed on the first attempt without requiring physical keyboard or monitor access.
- **SC-005**: Zero cleartext secrets or sensitive credentials are committed to version control or left world-readable in temporary locations during installation.
- **SC-006**: 100% of pre-reboot automated verification checks pass before the installer declares installation success.

## Assumptions

- The target homelab machine supports 64-bit UEFI firmware and is booted in native UEFI mode.
- The target machine is connected via an Ethernet cable or supported network adapter to a local network with active internet access.
- The operator boots an official Arch Linux live USB environment and establishes an interactive SSH session to it.
- The operator performs initial manual prep within the live environment (cloning the git repository and unpacking the secrets archive into a specified local directory).
- The target machine has at least one dedicated physical storage device intended for the operating system that can be completely allocated to this installation.
- DNS resolution and standard package repositories are reachable over the internet during the installation run.
- Phase 1 hosts no persistent user application data or services; disaster recovery for this phase is satisfied by deterministic re-installation from the version-controlled repository and secrets archive.
- The base root filesystem is strictly formatted as plain, unencrypted Ext4; advanced copy-on-write filesystems such as Btrfs (including subvolume layouts and snapshot management) are out of scope for the Phase 1 base OS root partition and reserved for storage pooling evaluation in Phase 4.
