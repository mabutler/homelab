# Phase 0 Research: Initial Arch Linux Installation Bootstrap

**Feature Branch**: `001-initial-arch-install`  
**Date**: 2026-10-11  
**Spec Reference**: [`specs/001-initial-arch-install/spec.md`](file:///C:/Users/micro/projects/homelab2/specs/001-initial-arch-install/spec.md)

---

## 1. Bootloader Selection

- **Decision**: `systemd-boot` (installed via `bootctl install` inside `arch-chroot`).
- **Rationale**: 
  - `systemd-boot` is already bundled inside `systemd` (a core component of the `base` package), requiring zero external dependencies or compilation.
  - Native UEFI implementation with clean, declarative text configuration files (`/boot/loader/loader.conf` and `/boot/loader/entries/*.conf`).
  - Extremely fast, lightweight, and resilient for headless servers. It boots directly without complicated shell parsing, interactive timeouts, or legacy MBR baggage.
  - Automatically hooks into kernel updates when the ESP is mounted at `/boot`.
- **Alternatives Considered**:
  - `GRUB`: Significantly heavier, complex configuration generation (`grub-mkconfig`), multi-layered scripts prone to divergence on rolling-release Arch, and unnecessary legacy BIOS multi-boot support for a dedicated UEFI server.
  - `rEFInd`: Geared towards graphical dual-boot workstations with desktop monitors; excessive complexity and dependencies for a headless homelab host.
  - Direct EFISTUB (`efibootmgr` only): Stores kernel command line parameters in motherboard NVRAM. Harder to inspect, edit, or recover out-of-band during headless troubleshooting compared to plain text configuration files on the ESP.

---

## 2. Root Filesystem Selection

- **Decision**: Plain, unencrypted `ext4` filesystem for the root partition.
- **Rationale**:
  - Standard, battle-tested, rock-solid filesystem with decades of production stability and ubiquitous recovery tooling (`e2fsck`, `tune2fs`).
  - Zero operational overhead or memory footprint for the minimal base operating system.
  - Eliminates boot-time passphrase prompts, dropbear SSH-in-initramfs networking, or network-bound disk encryption (Clevis/Tang) during initial bootstrap, satisfying FR-004 and SC-003 for unattended headless first boot.
  - Storage pooling, snapshotting, and parity protection for persistent data are cleanly decoupled into Phase 4 (MergerFS + SnapRAID) and Phase 7 (Restic offsite backups).
- **Alternatives Considered**:
  - `btrfs`: Offers subvolumes and copy-on-write snapshots, but adds subvolume layout complexity (`@`, `@home`, `@var`), requires CoW disabling for databases/VMs (`chattr +C`), and introduces metadata fragmentation risks. Homelab2 decouples app data onto dedicated NVMe/pools in subsequent phases; Btrfs is therefore out of scope for the Phase 1 base OS root filesystem and reserved as an alternative for storage pooling in Phase 4.
  - `xfs`: High performance for large filesystems, but cannot be shrunk if partition layouts need rebalancing and offers no tangible advantage for a minimal base OS root.
  - `zfs`: Out-of-tree kernel module, DKMS compile delays on kernel updates on Arch, violating the stability-first mandate for the minimal base OS.

---

## 3. Partition Scheme and Mount Hierarchy

- **Decision**: GPT partition table with 2 partitions:
  1. **Partition 1 (ESP)**: 1024 MiB (1 GiB) FAT32 (`mkfs.vfat -F 32`), partition type `EF00` (EFI System Partition), mounted at `/mnt/boot` (becomes `/boot` in target system).
  2. **Partition 2 (Root)**: 100% of remaining disk space, Ext4 (`mkfs.ext4 -F -L arch_root`), partition type `8304` (Linux root x86-64), mounted at `/mnt`.
- **Rationale**:
  - Arch Linux official recommendation for `systemd-boot` is mounting the ESP directly at `/boot`. The kernel (`vmlinuz-linux`) and initramfs (`initramfs-linux.img`) installed by `pacstrap base linux` are written directly to `/boot`, allowing `systemd-boot` to access them natively without separate EFI kernel copy hooks or XBOOTLDR complexity.
  - 1 GiB ESP provides generous headroom for multiple kernels (primary `linux`, fallback `initramfs-linux-fallback.img`, optional `linux-lts`), plus CPU microcode images (`intel-ucode.img` / `amd-ucode.img`).
- **Alternatives Considered**:
  - Small ESP (512 MiB): Prone to running out of space during kernel updates if multiple initramfs images and microcodes are stored simultaneously.
  - ESP at `/efi` with XBOOTLDR at `/boot`: Adds dual-partition bootloader complexity with no benefit for a single dedicated server operating system.

---

## 4. Disk Partitioning and Formatting Tooling

- **Decision**: `sgdisk` (from `gptfdisk`) for non-interactive GPT manipulation, combined with `wipefs -a` and `partprobe`.
- **Rationale**:
  - `sgdisk` is purpose-built for scripted, deterministic GPT partition table creation. It supports unambiguous flags (`--zap-all`, `--new`, `--typecode`, `--change-name`) without interactive prompts.
  - Present by default on official Arch Linux live media.
  - `wipefs -a` cleanly removes prior filesystem, LVM, or partition table signatures before creating new partitions, avoiding partition table conflicts.
- **Alternatives Considered**:
  - `parted`: Scripting mode (`parted -s`) can emit interactive warnings or alignment prompts that stall unattended scripts or behave inconsistently across disk geometry types.
  - `fdisk`: Requires piping standard input strings (`echo -e "g\nn\n..." | fdisk`), which is error-prone, fragile across fdisk versions, and hard to maintain.

---

## 5. Network Configuration Management for Base OS

- **Decision**: `systemd-networkd` + `systemd-resolved`.
- **Rationale**:
  - Built directly into `systemd` (already installed as part of the `base` package group); zero additional package dependencies.
  - Extremely lightweight with near-instant startup.
  - Standard declarative configuration: writing `/etc/systemd/network/20-wired.network` with `[Match] Name=en* eth*` and `[Network] DHCP=yes` brings up any wired Ethernet interface automatically upon boot.
  - Satisfies FR-005: automatically requests DHCP lease, allowing router MAC reservation to assign predictable IP while minimizing local configuration drift.
- **Alternatives Considered**:
  - `NetworkManager`: Full-featured for desktop environments with Wi-Fi and VPNs, but introduces heavy D-Bus/polkit dependencies and unnecessary background daemon overhead for a wired headless server.
  - `dhcpcd`: Independent daemon requiring extra installation and unit management when `systemd-networkd` is already built-in.

---

## 6. Destructive Disk Safety Confirmation Guard

- **Decision**: Interactive typed-confirmation guard with target drive inspection display, complemented by a strict `--disk /dev/... --confirm-destructive` CLI bypass for automated test harnesses.
- **Rationale**:
  - Satisfies Constitution Principle II (*Strict Idempotency & Safe Convergence*): destructive disk operations must never run silently or by default.
  - Presents block devices using `lsblk -o NAME,MODEL,SERIAL,SIZE,TYPE,TRAN` so the operator clearly distinguishes between installation USB flash drives, NVMe drives, and existing bulk storage disks.
  - In interactive mode, requires the operator to type the exact device basename (e.g. `nvme0n1` or `sda`) or type `YES-DESTROY-DATA` before proceeding.
  - If confirmation fails or is rejected, the script immediately terminates with exit code 1 with zero disk modifications (FR-003, SC-001).
- **Alternatives Considered**:
  - Single `[y/N]` prompt: Highly vulnerable to accidental Enter/Y keypresses by an operator.
  - Hardcoded disk path (e.g. `/dev/nvme0n1` hardcoded): Extremely dangerous across different hardware topologies where drive enumeration orders differ.

---

## 7. Secrets and Administrative Identity Ingestion

- **Decision**: Decoupled staging model using an optional configuration file (`install.conf`), command-line flags, and a secrets staging directory containing the operator's public SSH key (`secrets/id_ed25519.pub` or `~/.ssh/authorized_keys`).
- **Rationale**:
  - Satisfies Constitution Principle IV (*Zero Cleartext Secrets*): No private keys or cleartext credentials are ever checked into git or required on the live ISO.
  - The operator provides their existing public SSH key. The installer sets up the admin user, disables root SSH login, disables password-based SSH authentication (`PasswordAuthentication no`), and writes the authorized public key with strict `0600` permissions and `admin:wheel` ownership.
  - Python runtime (`python`) is installed via pacstrap so downstream Ansible management (Phase 2) can connect via SSH and execute playbooks immediately without manual bootstrapping.
- **Alternatives Considered**:
  - Prompting for root password over interactive prompt: Violates headless public-key security standards and encourages insecure password authentication over SSH.
  - Running full SOPS/Ansible decryption during live install: Injects heavy toolchains into the live Arch ISO before the base system even exists. Staging the public key directly during bootstrap and deferring encrypted vault playbooks to Phase 2 keeps Phase 1 lean and reliable.

---

## 8. Automated Pre-Reboot Verification Assertions

- **Decision**: In-chroot verification harness running as the final execution stage prior to filesystem unmount.
- **Rationale**:
  - Satisfies Constitution Principle III (*Automated Verification & Acceptance Gates*) and FR-011.
  - Checks verified inside `/mnt`:
    1. ESP mounted and `bootctl is-installed` returns 0.
    2. Kernel image `/boot/vmlinuz-linux` and `/boot/initramfs-linux.img` exist.
    3. Bootloader entry `/boot/loader/entries/arch.conf` points to valid root PARTUUID.
    4. `/etc/fstab` exists, contains valid UUIDs for `/` and `/boot`, and passes `findmnt --verify` checks.
    5. Admin user exists in `/etc/passwd` and belongs to group `wheel`.
    6. `/etc/sudoers.d/wheel` (or sudo policy) permits wheel escalation.
    7. Authorized SSH keys file exists, is non-empty, and has `0600` permissions.
    8. SSH daemon service (`sshd.service`) is enabled.
    9. Network daemon service (`systemd-networkd.service` & `systemd-resolved.service`) is enabled.
    10. Python 3 is installed and executable (`python3 --version`).
  - If all assertions pass, filesystems are safely unmounted (`umount -R /mnt`) and status reported as green. If any assertion fails, the installer aborts before rebooting, preventing an unbootable black box.
- **Alternatives Considered**:
  - Unconditional reboot without validation: Fails immediately when subtle errors (like missing microcode, ungenerated fstab, or disabled sshd) leave the server unreachable headlessly.

---

## 9. Modular Codebase Architecture

- **Decision**: Structured modular shell scripts organized under `scripts/install/`:
  - `scripts/install/install.sh`: Top-level orchestrator and CLI parser.
  - `scripts/install/lib/common.sh`: Colors, structured logging, assertion helpers, error trap.
  - `scripts/install/lib/preflight.sh`: UEFI mode, connectivity, disk enumeration, secrets validation.
  - `scripts/install/lib/disk.sh`: Safety guard confirmation, wipefs, sgdisk partitioning, formatting, mounting.
  - `scripts/install/lib/bootstrap.sh`: Mirror ranking, pacstrap base packages, fstab generation.
  - `scripts/install/lib/configure.sh`: Chroot configuration (timezone, locale, hostname, admin user, sshd, networkd, bootctl).
  - `scripts/install/lib/verify.sh`: Pre-reboot verification assertions and clean unmount.
  - `scripts/install/install.conf.example`: Example configuration profile.
- **Rationale**:
  - Satisfies Constitution Principle I (*Pragmatic Declarative-First Automation* fallback to modular shell scripts with explicit contracts).
  - Clean separation of concerns makes individual phases testable, readable, and lintable via `shellcheck`.
