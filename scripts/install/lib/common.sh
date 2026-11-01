#!/usr/bin/env bash
# ==============================================================================
# common.sh - Common Logging, Exit Codes, and Cleanup Traps
# ==============================================================================

# Exit Code Constants
readonly SUCCESS=0
readonly ERR_PREFLIGHT=1
readonly ERR_CONFIRMATION_REJECTED=2
readonly ERR_DISK_PREP=3
readonly ERR_PACSTRAP=4
readonly ERR_CHROOT_CONFIG=5
readonly ERR_VERIFICATION=6
readonly ERR_INTERRUPTED=130

# Colors (ANSI)
if [[ -t 1 ]] && [[ -t 2 ]]; then
    COLOR_RESET="\033[0m"
    COLOR_BLUE="\033[1;34m"
    COLOR_GREEN="\033[1;32m"
    COLOR_YELLOW="\033[1;33m"
    COLOR_RED="\033[1;31m"
else
    COLOR_RESET=""
    COLOR_BLUE=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_RED=""
fi

# Log file sink
INSTALL_LOG="${INSTALL_LOG:-/var/log/homelab-install.log}"

# Ensure log directory exists if possible
mkdir -p "$(dirname "$INSTALL_LOG")" 2>/dev/null || true

_log_to_file() {
    local level="$1"
    shift
    local timestamp
    timestamp="$(date -u +"%Y-%m-%d %H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%d %H:%M:%S")"
    if [[ -w "$(dirname "$INSTALL_LOG")" ]] || [[ -w "$INSTALL_LOG" ]]; then
        printf "[%s] [%s] %s\n" "$timestamp" "$level" "$*" >> "$INSTALL_LOG" 2>/dev/null || true
    fi
}

log_info() {
    printf "%b[INFO]%b %s\n" "$COLOR_BLUE" "$COLOR_RESET" "$*"
    _log_to_file "INFO" "$*"
}

log_success() {
    printf "%b[SUCCESS]%b %s\n" "$COLOR_GREEN" "$COLOR_RESET" "$*"
    _log_to_file "SUCCESS" "$*"
}

log_warn() {
    printf "%b[WARN]%b %s\n" "$COLOR_YELLOW" "$COLOR_RESET" "$*"
    _log_to_file "WARN" "$*"
}

log_error() {
    printf "%b[ERROR]%b %s\n" "$COLOR_RED" "$COLOR_RESET" "$*" >&2
    _log_to_file "ERROR" "$*"
}

# Cleanup and unmount handler
cleanup_mounts() {
    local target_mount="${1:-/mnt}"
    if mountpoint -q "$target_mount" 2>/dev/null || findmnt -rno TARGET "$target_mount" >/dev/null 2>&1; then
        log_warn "Cleaning up active mounts under $target_mount..."
        # First sync filesystems
        sync
        # Attempt recursive unmount
        umount -R "$target_mount" 2>/dev/null || true
    fi
}

on_sigint() {
    printf "\n"
    log_error "Installation interrupted by operator (SIGINT)."
    cleanup_mounts "/mnt"
    exit "$ERR_INTERRUPTED"
}

on_err() {
    local exit_code=$?
    log_error "Unexpected error occurred during execution (exit code: $exit_code)."
    cleanup_mounts "/mnt"
    exit "$exit_code"
}

# Trap registrations
trap on_sigint SIGINT
