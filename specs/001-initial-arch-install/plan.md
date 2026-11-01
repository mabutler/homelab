# Implementation Plan: Initial Arch Linux Installation Bootstrap

**Branch**: `001-initial-arch-install` | **Date**: 2026-10-11 | **Spec**: [`specs/001-initial-arch-install/spec.md`](file:///C:/Users/micro/projects/homelab2/specs/001-initial-arch-install/spec.md)

**Input**: Feature specification from [`specs/001-initial-arch-install/spec.md`](file:///C:/Users/micro/projects/homelab2/specs/001-initial-arch-install/spec.md)

---

## Summary

Build a modular, automated, and safe installation bootstrap script set (`scripts/install/`) to be run from an active Arch Linux live USB environment. The installer validates host firmware (UEFI) and connectivity, prompts the operator with an explicit destructive confirmation safety guard before modifying storage, partitions the selected disk (1 GiB ESP + Ext4 root), installs the minimal base operating system (`pacstrap`), configures the target system (networking, administrative user, authorized SSH public key, `systemd-boot`), and executes 10 automated pre-reboot verification assertions before cleanly unmounting. The final outcome is a headless, SSH-ready Arch Linux installation prepared for Phase 2 Ansible configuration management.

---

## Technical Context

**Language/Version**: POSIX Shell / Bash 5.2+ (standard on official Arch Linux live media)

**Primary Dependencies**:
- Live environment tooling: `arch-install-scripts` (`pacstrap`, `arch-chroot`, `genfstab`), `gptfdisk` (`sgdisk`), `e2fsprogs` (`mkfs.ext4`), `dosfstools` (`mkfs.vfat`), `util-linux` (`wipefs`, `lsblk`, `findmnt`, `partprobe`)
- Target system core packages: `base`, `base-devel`, `linux`, `linux-firmware`, CPU microcode (`intel-ucode`/`amd-ucode`), `systemd`, `systemd-sysvcompat`, `openssh`, `sudo`, `python`, `git`; optional user packages via `EXTRA_PACKAGES` (e.g., `tmux`, `vim`)
- Bootloader: `systemd-boot` (native UEFI, zero extra packages)
- Network management: `systemd-networkd` + `systemd-resolved` (declarative wired DHCP)

**Storage**:
- Direct bare-metal storage block device (NVMe SSD or SATA drive)
- GPT partition table layout:
  - Partition 1: 1024 MiB FAT32 EFI System Partition (ESP), type `EF00`, mounted at `/boot`
  - Partition 2: 100% remaining disk Ext4 root partition, type `8304`, mounted at `/`

**Testing**:
- Automated pre-flight checks (UEFI mode, connectivity, candidate disk enumeration)
- 10 automated in-chroot pre-reboot assertion checks (fstab, bootctl, user, ssh keys, services, python)
- Runnable verification scenarios in [`quickstart.md`](file:///C:/Users/micro/projects/homelab2/specs/001-initial-arch-install/quickstart.md) for UEFI virtual machines and bare-metal targets

**Target Platform**: x86-64 bare-metal host with native UEFI firmware booted from Arch Linux live USB

**Project Type**: CLI bootstrap toolset and installation libraries (`scripts/install/`)

**Performance Goals**: Complete end-to-end installation from invocation to reboot readiness in under 15 minutes on standard broadband (100 Mbps+) (SC-002); target host boots into SSH-ready state within 90 seconds (SC-003).

**Constraints**:
- Headless first boot: zero interactive prompts or passphrase requirements during boot sequence.
- Safe convergence: 100% of runs require explicit confirmation before disk modification (SC-001).
- Security: Zero cleartext secrets stored; public-key SSH authentication strictly enforced, password login disabled (FR-009, SC-005).

**Scale/Scope**: Single-node bare-metal host bootstrapping Phase 1 of homelab2 architecture.

---

## Constitution Check

*GATE: Evaluated prior to Phase 0 research and re-evaluated post-design.*

| Principle / Gate | Compliance Analysis | Status |
|---|---|---|
| **I. Pragmatic Declarative-First Automation** | Initial OS installation from live media occurs before Python, Ansible, or configuration management agents exist on the target disk. Principle I explicitly permits modular, self-contained shell scripts for hardware-specific partitioning and bootstrap. Scripts have explicit CLI and config contracts. | **PASS** |
| **II. Strict Idempotency & Safe Convergence** | Destructive disk operations (`wipefs`, `sgdisk`, `mkfs`) are strictly guarded by interactive typed confirmation (`nvme0n1`) or explicit `--confirm-destructive` CLI flag. Rejection exits cleanly with zero disk modifications. | **PASS** |
| **III. Automated Verification & Acceptance Gates** | Two-tiered verification: 10 in-chroot assertions execute before unmounting (FR-011: ESP bootctl installed, kernel/initramfs present, fstab UUIDs valid, admin user in wheel, SSH keys permissions verified, sshd and networkd enabled, Python 3 executable; clean exit only upon 100% pass) and an overarching post-reboot integration verification gate (FR-013: unattended UEFI boot, wired DHCP, public-key SSH login, passwordless sudo, Python execution validated via quickstart.md). Phase 1 exception for external telemetry documented and justified. | **PASS** |
| **IV. Zero Cleartext Secrets & Isolated Configuration** | No private keys or cleartext secrets are stored in version control or written unencrypted to disk. Operator provides their existing public SSH key in the live session. Password authentication is disabled on target host. | **PASS** |
| **V. Disaster Recovery & Backup by Design** | Phase 1 hosts no persistent user application data or services. Disaster recovery is satisfied by deterministic re-installation from version-controlled scripts and the operator's public key. | **PASS** |
| **VI. Modular & Decoupled Architecture** | Scripts are decomposed into modular libraries (`lib/common.sh`, `lib/preflight.sh`, `lib/disk.sh`, `lib/bootstrap.sh`, `lib/configure.sh`, `lib/verify.sh`) with dedicated responsibilities. | **PASS** |
| **VII. Stability-First & Annual Maintenance** | Uses official Arch `base` packages, stable Linux kernel, native `systemd-boot`, and standard Ext4 filesystem. No experimental filesystems or volatile customizations. | **PASS** |

**Constitution Gate Outcome**: **PASS**. Zero principle violations; no exemptions or complexity overrides required.

---

## Project Structure

### Documentation (this feature)

```text
specs/001-initial-arch-install/
├── plan.md              # This file (/speckit-plan output)
├── research.md          # Phase 0 output (/speckit-plan output)
├── data-model.md        # Phase 1 output (/speckit-plan output)
├── quickstart.md        # Phase 1 output (/speckit-plan output)
├── contracts/           # Phase 1 output (/speckit-plan output)
│   ├── installer-cli.md # CLI invocation syntax, flags, exit codes
│   └── install-config.md# Configuration file schema and variable precedence
└── tasks.md             # Phase 2 output (/speckit-tasks command)
```

### Source Code (repository root)

```text
scripts/
└── install/
    ├── install.sh              # Main installer orchestrator CLI entrypoint
    ├── install.conf.example     # Example configuration profile
    └── lib/
        ├── common.sh           # Common logging, colors, error traps, assertion helpers
        ├── preflight.sh        # UEFI mode, connectivity, disk enumeration, secrets validation
        ├── disk.sh             # Confirmation safety guard, wipefs, partitioning, format, mount
        ├── bootstrap.sh        # Pacman mirror optimization, pacstrap base packages, fstab
        ├── configure.sh        # In-chroot config (locale, timezone, hostname, sshd, networkd, bootctl)
        └── verify.sh           # Pre-reboot in-chroot assertion test suite & clean unmount
```

**Structure Decision**: Modular shell scripts organized in `scripts/install/lib/` invoked by top-level executable `scripts/install/install.sh`. This provides clean isolation between safety/preflight checks, disk operations, base package bootstrapping, and post-install system configuration.

---

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

*No violations identified. The design strictly adheres to all ratified Constitution principles.*
