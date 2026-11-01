# Quickstart & Validation Guide: Initial Arch Linux Installation Bootstrap

**Feature Branch**: `001-initial-arch-install`  
**Date**: 2026-10-11  
**Spec Reference**: [`specs/001-initial-arch-install/spec.md`](file:///C:/Users/micro/projects/homelab2/specs/001-initial-arch-install/spec.md)  
**Contracts**: [`contracts/installer-cli.md`](file:///C:/Users/micro/projects/homelab2/specs/001-initial-arch-install/contracts/installer-cli.md) | [`contracts/install-config.md`](file:///C:/Users/micro/projects/homelab2/specs/001-initial-arch-install/contracts/install-config.md)

---

## 1. Prerequisites

Before running the installer, ensure the following conditions are met:

1. **Hardware / VM Requirements**:
   - 64-bit x86-64 machine booted in **native UEFI mode**.
   - Target disk with at least 16 GiB storage (NVMe SSD or SATA drive).
   - Wired Ethernet connection with DHCP and active internet access.
2. **Live Environment Session**:
   - Boot official Arch Linux Live ISO (version 2024.x or later).
   - Establish interactive SSH access to the live environment (or direct console access).
3. **Repository & Operator SSH Key**:
   - Clone the `homelab2` repository into the live environment:
     ```bash
     git clone https://github.com/micro/homelab2.git /root/homelab2
     cd /root/homelab2
     ```
   - Provide the operator's public SSH key at `/root/homelab2/secrets/id_ed25519.pub` or in `~/.ssh/authorized_keys`.

---

## 2. Validation Scenarios

### Scenario 1: Safety Confirmation Guard Rejection (Principle II)
Proves that the destructive disk confirmation guard prevents accidental disk wipes.

**Execution**:
```bash
./scripts/install/install.sh --disk /dev/nvme0n1
# When prompted: "Type 'nvme0n1' to confirm destructive formatting:", enter anything else or press Ctrl+C
```

**Expected Outcome**:
- Installer displays a high-visibility warning banner showing target drive details.
- Entering an incorrect token or pressing Ctrl+C triggers immediate abort.
- Exit code is `2` (`ERR_CONFIRMATION_REJECTED`).
- Partition table and existing filesystem signatures remain completely untouched (`wipefs -n` shows signatures intact).

---

### Scenario 2: Standard Interactive Installation & Pre-Reboot Verification
Executes the full installation workflow, performs base bootstrap, configures system services, and validates all 10 pre-reboot assertions.

**Execution**:
```bash
# 1. Prepare configuration or use CLI arguments
./scripts/install/install.sh \
  --disk /dev/nvme0n1 \
  --user admin \
  --ssh-key ./secrets/id_ed25519.pub \
  --hostname homelab

# 2. Confirm the destructive disk prompt by typing 'nvme0n1'
```

**Expected Output & Step Progression**:
1. `[INFO] Pre-flight checks passed (UEFI mode verified, internet active)`.
2. `[INFO] Wiping existing signatures and partitioning /dev/nvme0n1 (1GB ESP, remainder Root Ext4)`.
3. `[INFO] Formatting filesystems (vfat on ESP, ext4 on Root) and mounting at /mnt`.
4. `[INFO] Pacstrapping minimal base OS, Linux kernel, firmware, python, sshd...`.
5. `[INFO] Configuring system (locale, timezone, hostname, networkd, resolved)`.
6. `[INFO] Configuring user 'admin', wheel sudo permissions, authorized SSH key`.
7. `[INFO] Installing and configuring systemd-boot`.
8. `[INFO] Executing in-chroot pre-reboot verification assertions...`
   - ESP & bootctl installed: `PASS`
   - Kernel and initramfs present: `PASS`
   - Loader entry PARTUUID match: `PASS`
   - fstab UUID validity: `PASS`
   - Admin user & wheel membership: `PASS`
   - SSH authorized_keys permissions: `PASS`
   - sshd enabled: `PASS`
   - systemd-networkd enabled: `PASS`
   - Python 3 executable: `PASS`
   - Git executable: `PASS`
9. `[SUCCESS] All verification assertions passed! Cleanly unmounting /mnt...`
10. `[SUCCESS] Installation complete! The host is ready for reboot.` Exit code `0`.

---

### Scenario 3: Headless First-Boot Remote Access Validation (FR-013 Gate)
Proves that the host boots unattended, acquires a DHCP lease, and permits passwordless SSH login with the administrative key, satisfying the overarching FR-013 integration verification gate.

**Execution**:
```bash
# In the live environment:
reboot

# From the operator workstation:
ssh admin@homelab.local
# Or using the DHCP lease IP:
ssh -i ~/.ssh/id_ed25519 admin@192.168.1.xxx
```

**Verification Commands on Fresh System**:
```bash
# 1. Verify hostname and OS release
uname -a
cat /etc/os-release

# 2. Verify passwordless sudo escalation
sudo -v
sudo whoami
# Expected output: root

# 3. Verify Python runtime is operational for downstream Ansible (Phase 2)
python3 --version
# Expected output: Python 3.12.x or 3.13.x

# 4. Verify systemd-networkd and sshd status
systemctl status systemd-networkd --no-pager
systemctl status sshd --no-pager

# 5. Verify password authentication is rejected over SSH
ssh -o PubkeyAuthentication=no admin@<IP>
# Expected outcome: Permission denied (publickey)
```

---

## 3. Failure Mode & Recovery Checklist

| Symptom | Cause | Resolution |
|---|---|---|
| `ERR_PREFLIGHT`: UEFI directory missing | Host booted in legacy BIOS mode | Enter motherboard BIOS/UEFI settings, disable CSM/Legacy boot, boot live USB in UEFI mode. |
| `ERR_PACSTRAP`: Mirror download error | Pacman mirror list stale or net down | Check network interface; `reflector --fastest 10` to refresh live mirrorlist. |
| `ERR_VERIFICATION`: Bootloader assertion fail | `bootctl install` failed on ESP | Check that ESP partition is FAT32 and mounted cleanly at `/mnt/boot`. |
| Post-reboot: Host does not appear on network | DHCP failure or NIC naming mismatch | Check router DHCP clients table for hostname `homelab`; ensure Ethernet cable is connected. |
