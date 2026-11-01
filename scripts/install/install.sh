#!/usr/bin/env bash
# ==============================================================================
# install.sh - homelab2 Arch Linux Installation Orchestrator
# ==============================================================================

set -euo pipefail

# Resolve script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Source library modules
# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=lib/preflight.sh
source "$LIB_DIR/preflight.sh"
# shellcheck source=lib/disk.sh
source "$LIB_DIR/disk.sh"
# shellcheck source=lib/bootstrap.sh
source "$LIB_DIR/bootstrap.sh"
# shellcheck source=lib/configure.sh
source "$LIB_DIR/configure.sh"
# shellcheck source=lib/verify.sh
source "$LIB_DIR/verify.sh"

show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Headless, automated Arch Linux installation bootstrap orchestrator for homelab2.

Options:
  -c, --config <PATH>          Path to installation configuration file (default: ./install.conf if present)
  -d, --disk <DEVICE>          Target storage block device (e.g. /dev/nvme0n1, /dev/sda)
  -u, --user <USERNAME>        Designated administrative username (default: admin)
  -k, --ssh-key <PATH>         Path to public SSH key file for the admin user
  -h, --hostname <NAME>        Target system hostname (default: homelab)
  -z, --timezone <TZ>          Target system timezone (default: UTC)
      --confirm-destructive    Bypass interactive disk confirmation prompt (use with caution)
      --help                   Show this help message and exit

Environment Variables:
  HOMELAB_TARGET_DISK          Target storage block device
  HOMELAB_ADMIN_USER           Administrative username
  HOMELAB_SSH_KEY_FILE         Path to public SSH key file
  HOMELAB_HOSTNAME             System hostname
  HOMELAB_TIMEZONE             System timezone
  HOMELAB_CONFIRM_DESTRUCTIVE  Set to '1' or 'true' to bypass confirmation prompt

Exit Codes:
  0    SUCCESS: Installation and all verification assertions passed. Host ready for reboot.
  1    ERR_PREFLIGHT: Environment validation failed (UEFI, internet, root).
  2    ERR_CONFIRMATION_REJECTED: Operator cancelled or rejected disk formatting.
  3    ERR_DISK_PREP: Disk wipe, partitioning, formatting, or mounting failed.
  4    ERR_PACSTRAP: Base system bootstrap or fstab generation failed.
  5    ERR_CHROOT_CONFIG: In-chroot configuration or bootloader install failed.
  6    ERR_VERIFICATION: Pre-reboot assertion checks failed.
  130  ERR_INTERRUPTED: Interrupted by operator (SIGINT).
EOF
}

# 1. Defaults
CLI_CONFIG=""
CONFIG_FILE="./install.conf"

TARGET_DISK=""
CONFIRM_DESTRUCTIVE="0"
HOSTNAME="homelab"
TIMEZONE="UTC"
LOCALE="en_US.UTF-8"
KEYMAP="us"
ADMIN_USER="admin"
SUDO_POLICY="wheel_nopasswd"
SSH_KEY_FILE=""
ESP_SIZE_MIB=1024
ROOT_LABEL="arch_root"
EXTRA_PACKAGES="tmux vim"

# Explicit CLI override tracking
CLI_TARGET_DISK=""
CLI_CONFIRM_DESTRUCTIVE=""
CLI_HOSTNAME=""
CLI_TIMEZONE=""
CLI_ADMIN_USER=""
CLI_SSH_KEY_FILE=""

# 2. Parse CLI Options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--config)
            CLI_CONFIG="$2"
            shift 2
            ;;
        -d|--disk)
            CLI_TARGET_DISK="$2"
            shift 2
            ;;
        -u|--user)
            CLI_ADMIN_USER="$2"
            shift 2
            ;;
        -k|--ssh-key)
            CLI_SSH_KEY_FILE="$2"
            shift 2
            ;;
        -h|--hostname)
            CLI_HOSTNAME="$2"
            shift 2
            ;;
        -z|--timezone)
            CLI_TIMEZONE="$2"
            shift 2
            ;;
        --confirm-destructive)
            CLI_CONFIRM_DESTRUCTIVE="1"
            shift 1
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# 3. Load Configuration File
ACTIVE_CONFIG=""
if [[ -n "$CLI_CONFIG" ]]; then
    ACTIVE_CONFIG="$CLI_CONFIG"
elif [[ -f "$CONFIG_FILE" ]]; then
    ACTIVE_CONFIG="$CONFIG_FILE"
elif [[ -f "$SCRIPT_DIR/install.conf" ]]; then
    ACTIVE_CONFIG="$SCRIPT_DIR/install.conf"
fi

if [[ -n "$ACTIVE_CONFIG" ]]; then
    if [[ -f "$ACTIVE_CONFIG" ]]; then
        log_info "Loading configuration profile from $ACTIVE_CONFIG..."
        # Source the configuration file
        # shellcheck disable=SC1090
        source "$ACTIVE_CONFIG"
    else
        log_error "Specified configuration file '$ACTIVE_CONFIG' does not exist."
        exit "$ERR_PREFLIGHT"
    fi
fi

# 4. Apply Environment Variable Overrides
[[ -n "${HOMELAB_TARGET_DISK:-}" ]] && TARGET_DISK="$HOMELAB_TARGET_DISK"
[[ -n "${HOMELAB_CONFIRM_DESTRUCTIVE:-}" ]] && CONFIRM_DESTRUCTIVE="$HOMELAB_CONFIRM_DESTRUCTIVE"
[[ -n "${HOMELAB_HOSTNAME:-}" ]] && HOSTNAME="$HOMELAB_HOSTNAME"
[[ -n "${HOMELAB_TIMEZONE:-}" ]] && TIMEZONE="$HOMELAB_TIMEZONE"
[[ -n "${HOMELAB_ADMIN_USER:-}" ]] && ADMIN_USER="$HOMELAB_ADMIN_USER"
[[ -n "${HOMELAB_SSH_KEY_FILE:-}" ]] && SSH_KEY_FILE="$HOMELAB_SSH_KEY_FILE"

# 5. Apply CLI Flag Overrides (Highest Precedence)
[[ -n "$CLI_TARGET_DISK" ]] && TARGET_DISK="$CLI_TARGET_DISK"
[[ -n "$CLI_CONFIRM_DESTRUCTIVE" ]] && CONFIRM_DESTRUCTIVE="$CLI_CONFIRM_DESTRUCTIVE"
[[ -n "$CLI_HOSTNAME" ]] && HOSTNAME="$CLI_HOSTNAME"
[[ -n "$CLI_TIMEZONE" ]] && TIMEZONE="$CLI_TIMEZONE"
[[ -n "$CLI_ADMIN_USER" ]] && ADMIN_USER="$CLI_ADMIN_USER"
[[ -n "$CLI_SSH_KEY_FILE" ]] && SSH_KEY_FILE="$CLI_SSH_KEY_FILE"

# Autodetect SSH key file if still unset
if [[ -z "$SSH_KEY_FILE" ]]; then
    if [[ -f "$SCRIPT_DIR/../../secrets/id_ed25519.pub" ]]; then
        SSH_KEY_FILE="$(cd "$SCRIPT_DIR/../../secrets" && pwd)/id_ed25519.pub"
    elif [[ -f "./secrets/id_ed25519.pub" ]]; then
        SSH_KEY_FILE="$(pwd)/secrets/id_ed25519.pub"
    elif [[ -f "$HOME/.ssh/authorized_keys" ]]; then
        SSH_KEY_FILE="$HOME/.ssh/authorized_keys"
    elif [[ -f "$HOME/.ssh/id_ed25519.pub" ]]; then
        SSH_KEY_FILE="$HOME/.ssh/id_ed25519.pub"
    fi
fi

# Setup error trap to clean up mounts on failure
trap on_err ERR

log_info "================================================================================"
log_info "Starting homelab2 Arch Linux Installation Bootstrap"
log_info "================================================================================"

# 6. Pre-flight Checks
SECRETS_DIR="$(dirname "$SSH_KEY_FILE" 2>/dev/null || true)"
run_preflight_checks "${SECRETS_DIR:-}" "$SSH_KEY_FILE"

# 7. CPU Vendor Detection
CPU_VENDOR="$(detect_cpu_vendor)"
log_info "Detected CPU vendor architecture: $CPU_VENDOR"

# 8. Disk Selection & Validation
if [[ -z "$TARGET_DISK" ]]; then
    printf "\n"
    list_candidate_disks
    printf "\n"
    printf "Enter target block device for installation (e.g. /dev/nvme0n1 or /dev/sda): "
    read -r TARGET_DISK
fi

validate_target_disk "$TARGET_DISK"

# 9. Safety Confirmation Guard
confirm_destructive_guard "$TARGET_DISK" "$CONFIRM_DESTRUCTIVE"

# 10. Derive Partition Devices
ESP_DEV="$(get_partition_device "$TARGET_DISK" 1)"
ROOT_DEV="$(get_partition_device "$TARGET_DISK" 2)"
log_info "Target partition map: ESP -> $ESP_DEV | Root -> $ROOT_DEV"

# 11. Wipe and Partition Disk
wipe_and_partition_disk "$TARGET_DISK" "$ESP_SIZE_MIB"

# 12. Format and Mount Filesystems
format_and_mount_filesystems "$ESP_DEV" "$ROOT_DEV" "$ROOT_LABEL" "/mnt"

# 13. Pacstrap Base OS
bootstrap_base_system "/mnt" "$CPU_VENDOR" "$EXTRA_PACKAGES"

# 14. Generate and Validate fstab
generate_and_validate_fstab "/mnt"

# 15. In-Chroot System Configuration
configure_networking "/mnt" "en* eth*"
configure_host_identity_and_locale "/mnt" "$HOSTNAME" "$TIMEZONE" "$LOCALE" "$KEYMAP"
configure_admin_user "/mnt" "$ADMIN_USER" "$SSH_KEY_FILE" "/bin/bash"
configure_ssh_daemon "/mnt"
configure_sudo_policy "/mnt" "$SUDO_POLICY"
configure_bootloader "/mnt" "$ROOT_DEV" "$CPU_VENDOR"

# 16. In-Chroot Pre-Reboot Verification Assertions
run_pre_reboot_assertions "/mnt" "$ESP_DEV" "$ROOT_DEV" "$ADMIN_USER"

# 17. Clean Filesystem Unmount
if ! unmount_target_filesystems "/mnt"; then
    log_error "Target unmount failed. System may have busy mounts."
    exit "$ERR_DISK_PREP"
fi

# Reset traps before clean exit
trap - SIGINT ERR

printf "\n"
log_success "================================================================================"
log_success "Installation complete! The host is ready for reboot."
log_success "Target host will boot unattended into SSH-ready Arch Linux."
log_success "Administrative user: $ADMIN_USER (Public-key SSH only, passwordless sudo)."
log_success "================================================================================"

exit "$SUCCESS"
