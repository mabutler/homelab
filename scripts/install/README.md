# homelab2 Arch Linux Installation Bootstrap

Automated, safe, and headless Arch Linux installation bootstrap toolset for initializing Phase 1 of the homelab infrastructure.

---

## Overview

The bootstrap installer runs from an official Arch Linux live USB environment. It automates:
1. **Pre-flight verification**: Checks UEFI boot mode, active internet connectivity, and credentials.
2. **Safety guard**: Requires explicit operator confirmation before making any disk modifications.
3. **Partitioning & Filesystems**: Allocates a 1 GiB FAT32 EFI System Partition (ESP) and Ext4 root partition.
4. **Base OS installation**: Uses `pacstrap` to install base Linux system, CPU microcode, python, git, and openssh.
5. **System configuration**: Configures `systemd-networkd` (wired DHCP), `systemd-resolved`, `systemd-boot`, and hardened SSH daemon (passwords disabled, root login disabled).
6. **Administrative user**: Creates administrative user with passwordless `sudo` and OpenSSH public key authentication.
7. **Pre-reboot verification**: Executes 10 automated in-chroot assertion checks before unmounting.

---

## Live USB Prerequisites

1. **Firmware**: Bare-metal or VM target booted in native **UEFI** mode (CSM/Legacy disabled).
2. **Network**: Wired Ethernet connection with active DHCP and internet access.
3. **Storage**: Target disk with at least 16 GiB storage.
4. **Live Environment**: Official Arch Linux ISO (2024.x or later).
5. **SSH Access to Live Environment**:
   ```bash
   # In live environment (if setting temporary password):
   passwd
   ip addr  # note IP address
   ```

---

## Quick Start

### 1. Transfer or Clone Repository to Target

From your operator workstation:
```bash
# Push or clone repository to the live environment:
ssh root@<LIVE_IP> "git clone <REPO_URL> /root/homelab2"
# Or copy the installer and public key:
scp -r ./scripts ./secrets root@<LIVE_IP>:/root/homelab/
```

### 2. Run the Installer

Interactive execution:
```bash
cd /root/homelab2
./scripts/install/install.sh --disk /dev/nvme0n1 --user admin --ssh-key ./secrets/id_ed25519.pub
```

When prompted:
```text
Type 'nvme0n1' to confirm destructive formatting:
```
Type the exact basename of the target disk to confirm.

### 3. Reboot into Installed System

After the installer reports `[SUCCESS] Installation complete! The host is ready for reboot.`:
```bash
reboot
```

### 4. Connect to Fresh Host

```bash
ssh -i ~/.ssh/id_ed25519 admin@<HOST_IP_OR_HOSTNAME>
```

---

## CLI Options

| Option | Long Option | Argument | Description | Default |
|---|---|---|---|---|
| `-c` | `--config` | `<PATH>` | Path to configuration file | `./install.conf` (if present) |
| `-d` | `--disk` | `<DEVICE>` | Target block device (e.g. `/dev/nvme0n1`) | Prompts operator |
| `-u` | `--user` | `<USERNAME>` | Designated administrative username | `admin` |
| `-k` | `--ssh-key` | `<PATH>` | Path to public SSH key file | `./secrets/id_ed25519.pub` |
| `-h` | `--hostname` | `<NAME>` | Hostname for the installed system | `homelab` |
| `-z` | `--timezone` | `<TZ>` | Target timezone | `UTC` |
| | `--confirm-destructive` | None | Bypass interactive confirmation prompt | Disabled |
| | `--help` | None | Display usage help | |

---

## Configuration File Schema

Copy `scripts/install/install.conf.example` to `scripts/install/install.conf` to customize:
```bash
TARGET_DISK="/dev/nvme0n1"
CONFIRM_DESTRUCTIVE=0
HOSTNAME="homelab"
TIMEZONE="America/New_York"
LOCALE="en_US.UTF-8"
KEYMAP="us"
ADMIN_USER="admin"
SUDO_POLICY="wheel_nopasswd"
SSH_KEY_FILE="./secrets/id_ed25519.pub"
ESP_SIZE_MIB=1024
ROOT_LABEL="arch_root"
EXTRA_PACKAGES="tmux vim"
```

---

## Exit Codes

| Exit Code | Constant | Meaning |
|---|---|---|
| `0` | `SUCCESS` | Installation and all 10 pre-reboot assertions passed. |
| `1` | `ERR_PREFLIGHT` | Host environment check failed (UEFI, internet, root). |
| `2` | `ERR_CONFIRMATION_REJECTED` | Confirmation rejected or disk mismatch. Zero changes made. |
| `3` | `ERR_DISK_PREP` | Partitioning, formatting, or mounting failed. |
| `4` | `ERR_PACSTRAP` | Pacstrap package bootstrap or fstab generation failed. |
| `5` | `ERR_CHROOT_CONFIG` | In-chroot configuration or bootloader installation failed. |
| `6` | `ERR_VERIFICATION` | Pre-reboot verification assertion failed. |
| `130` | `ERR_INTERRUPTED` | Interrupted via SIGINT (Ctrl+C). |

---

## Diagnostic Logs

Detailed logs of all pacstrap outputs, mkfs formatting, and commands are appended to:
```text
/var/log/homelab-install.log
```
