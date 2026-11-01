#!/usr/bin/env bash
# ==============================================================================
# preflight.sh - Host Environment, Firmware, Connectivity, and Disk Validators
# ==============================================================================

# Minimum disk size: 16 GiB (17,179,869,184 bytes)
readonly MIN_DISK_BYTES=17179869184

check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        log_error "Installer must be executed as root (UID 0)."
        return 1
    fi
}

check_firmware_uefi() {
    if [[ ! -d /sys/firmware/efi ]]; then
        log_error "System was not booted in native UEFI mode (/sys/firmware/efi not found)."
        log_error "Please reboot into UEFI setup and ensure UEFI boot mode is enabled."
        return 1
    fi
}

check_internet_connectivity() {
    log_info "Verifying internet connectivity..."
    local test_hosts=("1.1.1.1" "8.8.8.8" "archlinux.org")
    local connected=false

    for host in "${test_hosts[@]}"; do
        if ping -c 1 -W 3 "$host" >/dev/null 2>&1; then
            connected=true
            break
        fi
    done

    if [[ "$connected" != true ]]; then
        log_error "No active internet connection detected. A working network is required for pacstrap."
        return 1
    fi
}

check_secrets_bundle() {
    local bundle_path="$1"
    local ssh_key_file="$2"

    if [[ -n "$bundle_path" ]] && [[ ! -d "$bundle_path" ]]; then
        log_error "Secrets bundle directory does not exist or is not readable: $bundle_path"
        return 1
    fi

    if [[ -n "$ssh_key_file" ]]; then
        if [[ ! -f "$ssh_key_file" ]] || [[ ! -r "$ssh_key_file" ]]; then
            log_error "SSH public key file does not exist or is not readable: $ssh_key_file"
            return 1
        fi
        # Check that file contains at least one valid SSH key line
        if ! grep -qE "^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+|sk-ssh-ed25519@openssh\.com) " "$ssh_key_file"; then
            log_error "SSH public key file ($ssh_key_file) does not contain a valid OpenSSH public key format."
            return 1
        fi
    fi
}

detect_cpu_vendor() {
    local vendor="unknown"
    if grep -qi "GenuineIntel" /proc/cpuinfo 2>/dev/null; then
        vendor="intel"
    elif grep -qi "AuthenticAMD" /proc/cpuinfo 2>/dev/null; then
        vendor="amd"
    fi
    echo "$vendor"
}

get_installer_media_disk() {
    local bootmnt_dev=""
    if mountpoint -q /run/archiso/bootmnt 2>/dev/null; then
        bootmnt_dev="$(findmnt -n -o SOURCE /run/archiso/bootmnt 2>/dev/null)"
    elif mountpoint -q /run/archiso/cowspace 2>/dev/null; then
        bootmnt_dev="$(findmnt -n -o SOURCE /run/archiso/cowspace 2>/dev/null)"
    fi

    if [[ -n "$bootmnt_dev" ]]; then
        # Resolve to base block device if partition
        local pkname
        pkname="$(lsblk -no PKNAME "$bootmnt_dev" 2>/dev/null | head -n1)"
        if [[ -n "$pkname" ]]; then
            echo "/dev/$pkname"
            return 0
        fi
        echo "$bootmnt_dev"
        return 0
    fi
    echo ""
}

list_candidate_disks() {
    local installer_disk
    installer_disk="$(get_installer_media_disk)"

    log_info "Scanning for candidate storage block devices (>= 16 GiB)..."
    printf "%-12s %-10s %-8s %-20s %-20s\n" "DEVICE" "SIZE" "TRAN" "MODEL" "SERIAL"
    printf "%s\n" "--------------------------------------------------------------------------------"

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local NAME="" SIZE="" TYPE="" TRAN="" MODEL="" SERIAL=""
        eval "$line"

        [[ "$TYPE" != "disk" ]] && continue

        local full_dev="/dev/$NAME"

        # Check if installer media
        if [[ -n "$installer_disk" ]] && [[ "$full_dev" == "$installer_disk"* ]]; then
            continue
        fi

        # Check size >= 16 GiB
        if [[ "$SIZE" -ge "$MIN_DISK_BYTES" ]]; then
            local human_size
            human_size="$(lsblk -d -n -o SIZE "$full_dev" 2>/dev/null | tr -d ' ')"
            printf "%-12s %-10s %-8s %-20s %-20s\n" "$full_dev" "$human_size" "${TRAN:-unknown}" "${MODEL:-unknown}" "${SERIAL:-unknown}"
        fi
    done < <(lsblk -d -b -P -o NAME,SIZE,TYPE,TRAN,MODEL,SERIAL)
}

validate_target_disk() {
    local disk="$1"

    if [[ -z "$disk" ]]; then
        log_error "Target disk must be specified."
        return 1
    fi

    if [[ ! -b "$disk" ]]; then
        log_error "Specified target disk '$disk' is not a valid block device."
        return 1
    fi

    local installer_disk
    installer_disk="$(get_installer_media_disk)"
    if [[ -n "$installer_disk" ]] && [[ "$disk" == "$installer_disk"* ]]; then
        log_error "Selected disk '$disk' is the active Arch Linux installer media! Operation aborted."
        return 1
    fi

    local size_bytes
    size_bytes="$(lsblk -b -d -n -o SIZE "$disk" 2>/dev/null | tr -d ' ')"
    if [[ -z "$size_bytes" ]] || [[ "$size_bytes" -lt "$MIN_DISK_BYTES" ]]; then
        log_error "Disk '$disk' size (${size_bytes:-0} bytes) is less than the required 16 GiB ($MIN_DISK_BYTES bytes)."
        return 1
    fi

    return 0
}

run_preflight_checks() {
    local bundle_path="$1"
    local ssh_key_file="$2"

    log_info "Running pre-flight environment checks..."

    if ! check_root; then
        exit "$ERR_PREFLIGHT"
    fi

    if ! check_firmware_uefi; then
        exit "$ERR_PREFLIGHT"
    fi

    if ! check_internet_connectivity; then
        exit "$ERR_PREFLIGHT"
    fi

    if ! check_secrets_bundle "$bundle_path" "$ssh_key_file"; then
        exit "$ERR_PREFLIGHT"
    fi

    log_success "Pre-flight environment checks passed (UEFI mode verified, internet active, credentials valid)."
}
