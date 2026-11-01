# Interface Contract: Arch Linux Bootstrap Installer CLI

**Feature Branch**: `001-initial-arch-install`  
**Date**: 2026-10-11  
**Spec Reference**: [`specs/001-initial-arch-install/spec.md`](file:///C:/Users/micro/projects/homelab2/specs/001-initial-arch-install/spec.md)

---

## 1. Command Syntax

```bash
install.sh [OPTIONS]
```

The script is intended to be executed from within an active Arch Linux live USB environment as root (UID 0).

---

## 2. Command-Line Options

| Option | Long Option | Argument | Description | Default |
|---|---|---|---|---|
| `-c` | `--config` | `<PATH>` | Path to configuration file | `./install.conf` (if present) |
| `-d` | `--disk` | `<DEVICE>` | Target block device (e.g., `/dev/nvme0n1` or `/dev/sda`) | Interactive prompt |
| `-u` | `--user` | `<USERNAME>` | Initial administrative username | `admin` |
| `-k` | `--ssh-key` | `<PATH>` | Path to public SSH key file for the admin user | `~/.ssh/authorized_keys` or `./secrets/id_ed25519.pub` |
| `-h` | `--hostname` | `<NAME>` | Hostname to assign to the installed system | `homelab` |
| `-z` | `--timezone` | `<TZ>` | System timezone identifier (e.g. `America/New_York`) | `UTC` |
| | `--confirm-destructive` | None | Bypasses interactive disk confirmation prompt (for automated CI/VM tests) | Disabled |
| | `--help` | None | Prints usage help and exit options | |

---

## 3. Environment Variables

Environment variables are evaluated if CLI flags are omitted. CLI options take precedence over environment variables.

| Variable | Type | Description | Default |
|---|---|---|---|
| `HOMELAB_TARGET_DISK` | String | Target block device (e.g. `/dev/nvme0n1`) | Unset (prompts operator) |
| `HOMELAB_ADMIN_USER` | String | Administrative username | `admin` |
| `HOMELAB_SSH_KEY_FILE` | String | Path to public SSH key | Autodetected from `./secrets/` |
| `HOMELAB_HOSTNAME` | String | Target host network name | `homelab` |
| `HOMELAB_TIMEZONE` | String | Target timezone | `UTC` |
| `HOMELAB_CONFIRM_DESTRUCTIVE` | String | Set to `1` or `true` to skip interactive prompt | `0` |

---

## 4. Exit Codes

The installer strictly enforces semantic exit codes to signal success, cancellation, or failure modes:

| Exit Code | Name | Description |
|---|---|---|
| `0` | `SUCCESS` | Installation, configuration, and all 10 pre-reboot assertions passed. Filesystems unmounted cleanly; host is ready for reboot. |
| `1` | `ERR_PREFLIGHT` | Pre-flight validation failure (system not booted in UEFI mode, no internet connection, or live environment missing required tools). |
| `2` | `ERR_CONFIRMATION_REJECTED` | Operator cancelled or declined the destructive disk confirmation prompt, or invalid disk specified. Zero modifications made. |
| `3` | `ERR_DISK_PREP` | Partitioning (`sgdisk`), wiping (`wipefs`), formatting (`mkfs`), or mounting failed. |
| `4` | `ERR_PACSTRAP` | Package installation via `pacstrap` failed (mirror unreachable, network dropped, or package conflict). |
| `5` | `ERR_CHROOT_CONFIG` | In-chroot configuration failed (user creation, sshd configuration, network unit, or `bootctl install`). |
| `6` | `ERR_VERIFICATION` | One or more pre-reboot verification assertions failed. Filesystems left intact for operator debugging; host NOT ready for reboot. |
| `130` | `ERR_INTERRUPTED` | Execution interrupted via `SIGINT` (Ctrl+C). Cleanup trap safely unmounts filesystems. |

---

## 5. Output and Logging Format

- **Standard Output (`stdout`)**:
  - High-level human-readable progress markers prefixed with color-coded tags:
    - `[INFO]` (Blue): Informational milestones and step transitions.
    - `[SUCCESS]` (Green): Successful completion of stages and assertions.
    - `[WARN]` (Yellow): Cautionary advisories or warnings.
    - `[ERROR]` (Red): Critical failures and assertion violations (directed to `stderr`).
- **Log File (`/var/log/homelab-install.log`)**:
  - Full, unbuffered diagnostic stream including complete `pacstrap` output, filesystem creation logs, and command traces.
