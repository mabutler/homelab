#!/usr/bin/env bash
# ==============================================================================
# verify.sh - In-Chroot Pre-Reboot Verification Assertions
# ==============================================================================

run_pre_reboot_assertions() {
    local mount_root="${1:-/mnt}"
    local esp_dev="$2"
    local root_dev="$3"
    local admin_user="${4:-admin}"

    log_info "Executing 10 automated pre-reboot verification assertions..."

    local failed=0
    local total=10
    local passed=0

    # Assertion 1: ESP & bootctl installed
    log_info "Assertion 1/10: Verifying systemd-boot installation..."
    if arch-chroot "$mount_root" bootctl is-installed >> "$INSTALL_LOG" 2>&1; then
        log_success "  [1/10] PASS: bootctl is installed."
        passed=$((passed + 1))
    else
        log_error "  [1/10] FAIL: bootctl is NOT installed."
        failed=$((failed + 1))
    fi

    # Assertion 2: Kernel & initramfs presence
    log_info "Assertion 2/10: Verifying kernel and initramfs files..."
    if [[ -f "$mount_root/boot/vmlinuz-linux" ]] && [[ -f "$mount_root/boot/initramfs-linux.img" ]]; then
        log_success "  [2/10] PASS: /boot/vmlinuz-linux and /boot/initramfs-linux.img are present."
        passed=$((passed + 1))
    else
        log_error "  [2/10] FAIL: Kernel or initramfs missing in $mount_root/boot."
        failed=$((failed + 1))
    fi

    # Assertion 3: Loader entry PARTUUID match
    log_info "Assertion 3/10: Verifying bootloader PARTUUID configuration..."
    local expected_partuuid
    expected_partuuid="$(lsblk -no PARTUUID "$root_dev" 2>/dev/null | tr -d ' ')"
    if [[ -n "$expected_partuuid" ]] && grep -q "root=PARTUUID=$expected_partuuid" "$mount_root/boot/loader/entries/arch.conf" 2>/dev/null; then
        log_success "  [3/10] PASS: loader entry contains correct root=PARTUUID=$expected_partuuid."
        passed=$((passed + 1))
    else
        log_error "  [3/10] FAIL: loader entry root=PARTUUID does not match root partition PARTUUID ($expected_partuuid)."
        failed=$((failed + 1))
    fi

    # Assertion 4: fstab UUID validity
    log_info "Assertion 4/10: Verifying fstab UUID mappings..."
    local expected_root_uuid expected_esp_uuid
    expected_root_uuid="$(lsblk -no UUID "$root_dev" 2>/dev/null | tr -d ' ')"
    expected_esp_uuid="$(lsblk -no UUID "$esp_dev" 2>/dev/null | tr -d ' ')"

    local fstab_root_match=false
    local fstab_esp_match=false

    if grep -q "UUID=$expected_root_uuid" "$mount_root/etc/fstab" 2>/dev/null; then
        fstab_root_match=true
    fi
    if grep -q "UUID=$expected_esp_uuid" "$mount_root/etc/fstab" 2>/dev/null; then
        fstab_esp_match=true
    fi

    if [[ "$fstab_root_match" == true ]] && [[ "$fstab_esp_match" == true ]]; then
        log_success "  [4/10] PASS: /etc/fstab contains valid UUIDs for root and boot partitions."
        passed=$((passed + 1))
    else
        log_error "  [4/10] FAIL: /etc/fstab missing matching UUIDs for root ($expected_root_uuid) or boot ($expected_esp_uuid)."
        failed=$((failed + 1))
    fi

    # Assertion 5: Admin user & wheel membership
    log_info "Assertion 5/10: Verifying administrative user ($admin_user) and wheel membership..."
    if arch-chroot "$mount_root" id "$admin_user" 2>/dev/null | grep -q "(wheel)"; then
        log_success "  [5/10] PASS: User '$admin_user' exists and is a member of 'wheel'."
        passed=$((passed + 1))
    else
        log_error "  [5/10] FAIL: User '$admin_user' does not exist or lacks 'wheel' group membership."
        failed=$((failed + 1))
    fi

    # Assertion 6: authorized_keys permissions and non-empty content
    log_info "Assertion 6/10: Verifying authorized_keys permissions..."
    local ssh_dir="$mount_root/home/$admin_user/.ssh"
    local auth_keys="$ssh_dir/authorized_keys"

    local ssh_dir_perm auth_keys_perm
    ssh_dir_perm="$(stat -c "%a" "$ssh_dir" 2>/dev/null || true)"
    auth_keys_perm="$(stat -c "%a" "$auth_keys" 2>/dev/null || true)"

    if [[ "$ssh_dir_perm" == "700" ]] && [[ "$auth_keys_perm" == "600" ]] && [[ -s "$auth_keys" ]]; then
        log_success "  [6/10] PASS: .ssh directory is 0700 and authorized_keys is 0600 with valid key content."
        passed=$((passed + 1))
    else
        log_error "  [6/10] FAIL: authorized_keys permission check failed (ssh_dir: $ssh_dir_perm, auth_keys: $auth_keys_perm)."
        failed=$((failed + 1))
    fi

    # Assertion 7: sshd service enabled
    log_info "Assertion 7/10: Verifying sshd service status..."
    if arch-chroot "$mount_root" systemctl is-enabled sshd.service >> "$INSTALL_LOG" 2>&1; then
        log_success "  [7/10] PASS: sshd.service is enabled."
        passed=$((passed + 1))
    else
        log_error "  [7/10] FAIL: sshd.service is NOT enabled."
        failed=$((failed + 1))
    fi

    # Assertion 8: systemd-networkd service enabled
    log_info "Assertion 8/10: Verifying systemd-networkd service status..."
    if arch-chroot "$mount_root" systemctl is-enabled systemd-networkd.service >> "$INSTALL_LOG" 2>&1; then
        log_success "  [8/10] PASS: systemd-networkd.service is enabled."
        passed=$((passed + 1))
    else
        log_error "  [8/10] FAIL: systemd-networkd.service is NOT enabled."
        failed=$((failed + 1))
    fi

    # Assertion 9: Python 3 executable operational
    log_info "Assertion 9/10: Verifying Python 3 runtime..."
    local py_ver
    py_ver="$(arch-chroot "$mount_root" python3 --version 2>&1 || true)"
    if [[ "$py_ver" =~ Python[[:space:]]+3 ]]; then
        log_success "  [9/10] PASS: $py_ver is operational."
        passed=$((passed + 1))
    else
        log_error "  [9/10] FAIL: Python 3 is not operational in target system."
        failed=$((failed + 1))
    fi

    # Assertion 10: Git executable operational
    log_info "Assertion 10/10: Verifying git runtime..."
    local git_ver
    git_ver="$(arch-chroot "$mount_root" git --version 2>&1 || true)"
    if [[ "$git_ver" =~ git[[:space:]]+version ]]; then
        log_success "  [10/10] PASS: $git_ver is operational."
        passed=$((passed + 1))
    else
        log_error "  [10/10] FAIL: git is not operational in target system."
        failed=$((failed + 1))
    fi

    printf "\n"
    log_info "Verification Summary: $passed/$total passed, $failed failed."

    if [[ "$failed" -gt 0 ]]; then
        log_error "Pre-reboot assertions failed! Target system is NOT ready for reboot."
        exit "$ERR_VERIFICATION"
    fi

    log_success "All $total pre-reboot verification assertions passed successfully!"
    return 0
}
