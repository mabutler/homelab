#!/usr/bin/env bash
# ==============================================================================
# bootstrap.sh - Pacman Mirrors, Pacstrap Base Packages, and fstab Generation
# ==============================================================================

optimize_mirrors() {
    log_info "Checking pacman mirrors..."
    if command -v reflector >/dev/null 2>&1; then
        log_info "Optimizing pacman mirrorlist using reflector..."
        if ! reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist >> "$INSTALL_LOG" 2>&1; then
            log_warn "Reflector mirror ranking encountered an issue; proceeding with existing mirrorlist."
        fi
    fi
}

bootstrap_base_system() {
    local mount_root="${1:-/mnt}"
    local cpu_vendor="$2"
    local extra_packages="$3"

    optimize_mirrors

    local -a packages=(
        "base"
        "base-devel"
        "linux"
        "linux-firmware"
        "systemd"
        "systemd-sysvcompat"
        "openssh"
        "sudo"
        "python"
        "git"
    )

    # Microcode package selection
    case "$cpu_vendor" in
        intel)
            log_info "Detected Intel CPU; adding intel-ucode package."
            packages+=("intel-ucode")
            ;;
        amd)
            log_info "Detected AMD CPU; adding amd-ucode package."
            packages+=("amd-ucode")
            ;;
        *)
            log_warn "Unknown or virtual CPU vendor ($cpu_vendor); skipping vendor-specific microcode."
            ;;
    esac

    # Append extra user packages if provided
    if [[ -n "$extra_packages" ]]; then
        read -r -a extra_pkg_arr <<< "$extra_packages"
        for pkg in "${extra_pkg_arr[@]}"; do
            [[ -n "$pkg" ]] && packages+=("$pkg")
        done
    fi

    log_info "Installing base system packages via pacstrap to $mount_root..."
    log_info "Package set: ${packages[*]}"

    # Use pacstrap (supports -K to copy host keyring if available, otherwise fallback)
    local pacstrap_cmd="pacstrap"
    if pacstrap -h 2>&1 | grep -q -- "-K"; then
        pacstrap_cmd="pacstrap -K"
    fi

    if ! $pacstrap_cmd "$mount_root" "${packages[@]}" 2>&1 | tee -a "$INSTALL_LOG"; then
        log_error "pacstrap failed during base system installation."
        exit "$ERR_PACSTRAP"
    fi

    log_success "Base system packages installed successfully via pacstrap."
}

generate_and_validate_fstab() {
    local mount_root="${1:-/mnt}"

    log_info "Generating persistent filesystem table (/etc/fstab) with UUIDs..."
    mkdir -p "$mount_root/etc"
    if ! genfstab -U "$mount_root" > "$mount_root/etc/fstab"; then
        log_error "Failed to generate /etc/fstab via genfstab."
        exit "$ERR_PACSTRAP"
    fi

    log_info "Validating /etc/fstab entries..."
    if [[ ! -s "$mount_root/etc/fstab" ]]; then
        log_error "Generated /etc/fstab is empty."
        exit "$ERR_PACSTRAP"
    fi

    # Check for root mount entry (mountpoint /)
    if ! awk '$2 == "/" && $1 ~ /^UUID=/ {found=1} END {exit !found}' "$mount_root/etc/fstab"; then
        log_error "/etc/fstab is missing a valid UUID-based entry for the root filesystem ('/')."
        exit "$ERR_PACSTRAP"
    fi

    # Check for boot mount entry (mountpoint /boot)
    if ! awk '$2 == "/boot" && $1 ~ /^UUID=/ {found=1} END {exit !found}' "$mount_root/etc/fstab"; then
        log_error "/etc/fstab is missing a valid UUID-based entry for the EFI partition ('/boot')."
        exit "$ERR_PACSTRAP"
    fi

    log_success "Generated /etc/fstab validated with correct UUID mappings."
}
