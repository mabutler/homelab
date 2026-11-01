# Interface Contract: Installation Profile Configuration Schema

**Feature Branch**: `001-initial-arch-install`  
**Date**: 2026-10-11  
**Spec Reference**: [`specs/001-initial-arch-install/spec.md`](file:///C:/Users/micro/projects/homelab2/specs/001-initial-arch-install/spec.md)

---

## 1. Overview

The installer supports loading installation parameters from a simple POSIX shell key-value file (default: `./install.conf` or path passed via `--config`).

---

## 2. Configuration Key Specifications

```bash
# ==============================================================================
# homelab2 Installation Configuration Profile
# ==============================================================================

# Target storage block device node (e.g. /dev/nvme0n1, /dev/sda).
# If omitted or empty, the installer will display candidate drives and prompt.
TARGET_DISK="/dev/nvme0n1"

# Set to 1 to bypass the interactive confirmation prompt (use with caution).
CONFIRM_DESTRUCTIVE=0

# Host network name assigned to the installed machine.
# Must be RFC 1123 compliant (alphanumeric and dashes, max 63 characters).
HOSTNAME="homelab"

# System timezone string matching an entry in /usr/share/zoneinfo/.
TIMEZONE="America/New_York"

# Primary system locale to generate and set in /etc/locale.conf.
LOCALE="en_US.UTF-8"

# Keyboard layout keymap for virtual console (/etc/vconsole.conf).
KEYMAP="us"

# Designated administrative user login name.
# Will be added to the wheel group and configured with sudo access.
ADMIN_USER="admin"

# Sudo policy for the admin user:
# - wheel_nopasswd: NOPASSWD access for members of group wheel (%wheel ALL=(ALL:ALL) NOPASSWD: ALL).
# Persisted permanently across all phases for frictionless automation and administration.
SUDO_POLICY="wheel_nopasswd"

# Path to the public SSH key to authorize for ADMIN_USER.
# Can point to a file inside the cloned repository or an external path.
SSH_KEY_FILE="./secrets/id_ed25519.pub"

# Size of the EFI System Partition in MiB.
ESP_SIZE_MIB=1024

# Filesystem volume label for the root partition.
ROOT_LABEL="arch_root"

# Optional user packages to install via pacstrap in addition to mandatory baseline requirements.
# Mandatory baseline packages installed automatically (FR-006):
#   base base-devel linux linux-firmware systemd systemd-sysvcompat
#   openssh sudo python git
# Optional operator packages (e.g., tmux, vim):
EXTRA_PACKAGES="tmux vim"
```

---

## 3. Precedence Hierarchy

Configuration values are resolved in the following strict order (highest to lowest priority):

1. **CLI Flag Arguments** (e.g. `--disk /dev/nvme0n1`)
2. **Environment Variables** (e.g. `HOMELAB_TARGET_DISK=/dev/nvme0n1`)
3. **Configuration File** (`install.conf` variables)
4. **Interactive Prompt / Built-in Defaults**
