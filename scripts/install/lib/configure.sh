#!/usr/bin/env bash
# ==============================================================================
# configure.sh - In-Chroot System, User, Network, SSH, Bootloader & Sudo Config
# ==============================================================================

configure_networking() {
    local mount_root="${1:-/mnt}"
    local iface_pattern="${2:-en* eth*}"

    log_info "Configuring network management with systemd-networkd..."
    mkdir -p "$mount_root/etc/systemd/network"

    cat > "$mount_root/etc/systemd/network/20-wired.network" <<EOF
[Match]
Name=$iface_pattern

[Network]
DHCP=yes
EOF

    log_info "Enabling systemd-networkd and systemd-resolved services..."
    if ! arch-chroot "$mount_root" systemctl enable systemd-networkd.service systemd-resolved.service >> "$INSTALL_LOG" 2>&1; then
        log_error "Failed to enable network services in target system."
        exit "$ERR_CHROOT_CONFIG"
    fi

    log_info "Configuring DNS resolver stub symlink (/etc/resolv.conf)..."
    rm -f "$mount_root/etc/resolv.conf"
    ln -sf /run/systemd/resolve/stub-resolv.conf "$mount_root/etc/resolv.conf"
}

configure_host_identity_and_locale() {
    local mount_root="${1:-/mnt}"
    local hostname="${2:-homelab}"
    local timezone="${3:-UTC}"
    local locale="${4:-en_US.UTF-8}"
    local keymap="${5:-us}"

    log_info "Configuring hostname ($hostname)..."
    echo "$hostname" > "$mount_root/etc/hostname"

    cat > "$mount_root/etc/hosts" <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${hostname}.localdomain $hostname
EOF

    log_info "Configuring timezone ($timezone)..."
    if [[ ! -f "$mount_root/usr/share/zoneinfo/$timezone" ]]; then
        log_warn "Timezone '$timezone' not found in zoneinfo; falling back to UTC."
        timezone="UTC"
    fi
    arch-chroot "$mount_root" ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
    arch-chroot "$mount_root" hwclock --systohc 2>/dev/null || true

    log_info "Configuring locale ($locale) and keymap ($keymap)..."
    echo "KEYMAP=$keymap" > "$mount_root/etc/vconsole.conf"
    echo "LANG=$locale" > "$mount_root/etc/locale.conf"

    # Ensure locale is present in locale.gen
    if [[ -f "$mount_root/etc/locale.gen" ]]; then
        sed -i "/^#\?${locale//\./\\.}/s/^#\s*//" "$mount_root/etc/locale.gen"
        if ! grep -q "^${locale}" "$mount_root/etc/locale.gen"; then
            echo "$locale UTF-8" >> "$mount_root/etc/locale.gen"
        fi
    else
        echo "$locale UTF-8" > "$mount_root/etc/locale.gen"
    fi

    if ! arch-chroot "$mount_root" locale-gen >> "$INSTALL_LOG" 2>&1; then
        log_error "Failed to generate locales via locale-gen."
        exit "$ERR_CHROOT_CONFIG"
    fi
}

configure_admin_user() {
    local mount_root="${1:-/mnt}"
    local admin_user="${2:-admin}"
    local ssh_key_file="$3"
    local user_shell="${4:-/bin/bash}"

    log_info "Provisioning administrative user '$admin_user'..."

    # Validate admin username format: ^[a-z_][a-z0-9_-]{1,31}$ and not root
    if [[ "$admin_user" == "root" ]]; then
        log_error "Administrative user cannot be 'root'."
        exit "$ERR_CHROOT_CONFIG"
    fi

    if ! [[ "$admin_user" =~ ^[a-z_][a-z0-9_-]{1,31}$ ]]; then
        log_error "Invalid administrative username: '$admin_user'. Must match ^[a-z_][a-z0-9_-]{1,31}$."
        exit "$ERR_CHROOT_CONFIG"
    fi

    # Create user if does not exist
    if ! arch-chroot "$mount_root" id -u "$admin_user" >/dev/null 2>&1; then
        if ! arch-chroot "$mount_root" useradd -m -g users -G wheel -s "$user_shell" "$admin_user" >> "$INSTALL_LOG" 2>&1; then
            log_error "Failed to create user '$admin_user'."
            exit "$ERR_CHROOT_CONFIG"
        fi
    else
        arch-chroot "$mount_root" usermod -aG wheel -s "$user_shell" "$admin_user" >> "$INSTALL_LOG" 2>&1
    fi

    # Lock root password for headless security
    arch-chroot "$mount_root" passwd -l root >> "$INSTALL_LOG" 2>&1 || true

    # Install authorized SSH public key
    if [[ -n "$ssh_key_file" ]] && [[ -f "$ssh_key_file" ]]; then
        log_info "Installing authorized SSH key for '$admin_user'..."
        local user_ssh_dir="$mount_root/home/$admin_user/.ssh"
        mkdir -p "$user_ssh_dir"
        chmod 0700 "$user_ssh_dir"

        cp "$ssh_key_file" "$user_ssh_dir/authorized_keys"
        chmod 0600 "$user_ssh_dir/authorized_keys"

        # Ensure correct ownership
        arch-chroot "$mount_root" chown -R "$admin_user:users" "/home/$admin_user/.ssh"
    else
        log_error "No valid SSH public key file specified for administrative user."
        exit "$ERR_CHROOT_CONFIG"
    fi
}

configure_ssh_daemon() {
    local mount_root="${1:-/mnt}"

    log_info "Hardening OpenSSH daemon configuration..."
    mkdir -p "$mount_root/etc/ssh/sshd_config.d"

    cat > "$mount_root/etc/ssh/sshd_config.d/10-homelab.conf" <<EOF
# Hardened SSH configuration for homelab2
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
EOF

    chmod 0644 "$mount_root/etc/ssh/sshd_config.d/10-homelab.conf"

    log_info "Enabling sshd.service..."
    if ! arch-chroot "$mount_root" systemctl enable sshd.service >> "$INSTALL_LOG" 2>&1; then
        log_error "Failed to enable sshd.service in target system."
        exit "$ERR_CHROOT_CONFIG"
    fi
}

configure_sudo_policy() {
    local mount_root="${1:-/mnt}"
    local sudo_policy="${2:-wheel_nopasswd}"

    log_info "Configuring sudo policy ($sudo_policy)..."
    mkdir -p "$mount_root/etc/sudoers.d"

    local sudo_file="$mount_root/etc/sudoers.d/10-wheel"
    case "$sudo_policy" in
        wheel_nopasswd)
            echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > "$sudo_file"
            ;;
        wheel_passwd)
            echo "%wheel ALL=(ALL:ALL) ALL" > "$sudo_file"
            ;;
        *)
            echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > "$sudo_file"
            ;;
    esac

    chmod 0440 "$sudo_file"

    # Validate sudoers syntax
    if ! arch-chroot "$mount_root" visudo -cf /etc/sudoers.d/10-wheel >> "$INSTALL_LOG" 2>&1; then
        log_error "visudo syntax check failed for /etc/sudoers.d/10-wheel."
        exit "$ERR_CHROOT_CONFIG"
    fi

    log_success "Sudo policy successfully applied and validated."
}

configure_bootloader() {
    local mount_root="${1:-/mnt}"
    local root_dev="$2"
    local cpu_vendor="$3"

    log_info "Installing systemd-boot to /boot..."
    if ! arch-chroot "$mount_root" bootctl --path=/boot install >> "$INSTALL_LOG" 2>&1; then
        log_error "Failed to install systemd-boot via bootctl."
        exit "$ERR_CHROOT_CONFIG"
    fi

    mkdir -p "$mount_root/boot/loader/entries"

    log_info "Writing /boot/loader/loader.conf..."
    cat > "$mount_root/boot/loader/loader.conf" <<EOF
default arch.conf
timeout 3
console-mode max
editor no
EOF

    # Extract PARTUUID of root partition
    local root_partuuid
    root_partuuid="$(lsblk -no PARTUUID "$root_dev" 2>/dev/null | tr -d ' ')"
    if [[ -z "$root_partuuid" ]]; then
        log_error "Could not extract PARTUUID for root partition $root_dev."
        exit "$ERR_CHROOT_CONFIG"
    fi

    log_info "Creating bootloader entry /boot/loader/entries/arch.conf with root=PARTUUID=$root_partuuid..."
    
    local ucode_line=""
    if [[ -f "$mount_root/boot/intel-ucode.img" ]]; then
        ucode_line="initrd  /intel-ucode.img"
    elif [[ -f "$mount_root/boot/amd-ucode.img" ]]; then
        ucode_line="initrd  /amd-ucode.img"
    fi

    cat > "$mount_root/boot/loader/entries/arch.conf" <<EOF
title   Arch Linux
linux   /vmlinuz-linux
EOF

    if [[ -n "$ucode_line" ]]; then
        echo "$ucode_line" >> "$mount_root/boot/loader/entries/arch.conf"
    fi

    cat >> "$mount_root/boot/loader/entries/arch.conf" <<EOF
initrd  /initramfs-linux.img
options root=PARTUUID=$root_partuuid rw
EOF

    log_success "Bootloader configured successfully."
}
