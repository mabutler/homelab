#!/usr/bin/env bash
# ==============================================================================
# disk.sh - Disk Confirmation Guard, Wiping, Partitioning, Formatting & Mount
# ==============================================================================

confirm_destructive_guard() {
    local disk="$1"
    local bypass_flag="${2:-0}"

    if [[ "$bypass_flag" == "1" ]] || [[ "$bypass_flag" == "true" ]]; then
        log_warn "Destructive confirmation bypassed via --confirm-destructive / environment setting."
        return 0
    fi

    local disk_base
    disk_base="$(basename "$disk")"

    local model serial size tran
    model="$(lsblk -d -n -o MODEL "$disk" 2>/dev/null | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    serial="$(lsblk -d -n -o SERIAL "$disk" 2>/dev/null | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    size="$(lsblk -d -n -o SIZE "$disk" 2>/dev/null | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    tran="$(lsblk -d -n -o TRAN "$disk" 2>/dev/null | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    printf "\n"
    printf "================================================================================\n"
    printf "%b⚠️  WARNING: DESTRUCTIVE DISK OPERATION REQUESTED ⚠️%b\n" "$COLOR_RED" "$COLOR_RESET"
    printf "================================================================================\n"
    printf " Target Disk:  %s\n" "$disk"
    printf " Model:        %s\n" "${model:-unknown}"
    printf " Serial:       %s\n" "${serial:-unknown}"
    printf " Size:         %s\n" "${size:-unknown}"
    printf " Transport:    %s\n" "${tran:-unknown}"
    printf "================================================================================\n"
    printf " ALL EXISTING DATA AND PARTITIONS ON %s WILL BE PERMANENTLY DESTROYED!\n" "$disk"
    printf "================================================================================\n\n"

    printf "Type '%s' to confirm destructive formatting: " "$disk_base"
    local input_token=""
    if ! read -r input_token; then
        printf "\n"
        log_error "Confirmation prompt cancelled. Operation aborted with zero disk changes."
        exit "$ERR_CONFIRMATION_REJECTED"
    fi

    if [[ "$input_token" != "$disk_base" ]]; then
        log_error "Confirmation token mismatch (received '$input_token', expected '$disk_base'). Operation aborted."
        exit "$ERR_CONFIRMATION_REJECTED"
    fi

    log_warn "Operator confirmed destruction of $disk."
}

get_partition_device() {
    local disk="$1"
    local part_num="$2"

    if [[ "$disk" =~ [0-9]$ ]]; then
        echo "${disk}p${part_num}"
    else
        echo "${disk}${part_num}"
    fi
}

wipe_and_partition_disk() {
    local disk="$1"
    local esp_size_mib="${2:-1024}"

    log_info "Wiping existing partition tables and signatures on $disk..."

    # Ensure any mounted partitions on the target disk are unmounted first
    local mounted_parts
    mounted_parts="$(lsblk -n -o MOUNTPOINT "$disk" 2>/dev/null | grep -v '^$' || true)"
    if [[ -n "$mounted_parts" ]]; then
        log_info "Unmounting active partitions on $disk..."
        while IFS= read -r mp; do
            if [[ -n "$mp" ]]; then
                umount -R "$mp" 2>/dev/null || true
            fi
        done <<< "$mounted_parts"
    fi

    # Wipe signatures
    if ! wipefs -a "$disk" >> "$INSTALL_LOG" 2>&1; then
        log_error "Failed to wipe existing signatures on $disk via wipefs."
        exit "$ERR_DISK_PREP"
    fi

    # Zap GPT and MBR data structures
    if ! sgdisk -Z "$disk" >> "$INSTALL_LOG" 2>&1; then
        log_error "Failed to zap GPT/MBR on $disk via sgdisk -Z."
        exit "$ERR_DISK_PREP"
    fi

    log_info "Creating fresh GPT partition table on $disk..."
    if ! sgdisk -o "$disk" >> "$INSTALL_LOG" 2>&1; then
        log_error "Failed to create new GPT partition table on $disk."
        exit "$ERR_DISK_PREP"
    fi

    # Partition 1: ESP (type EF00, size esp_size_mib)
    log_info "Creating EFI System Partition (ESP, ${esp_size_mib} MiB, type EF00)..."
    if ! sgdisk -n "1:0:+${esp_size_mib}M" -t 1:ef00 -c 1:"EFI System Partition" "$disk" >> "$INSTALL_LOG" 2>&1; then
        log_error "Failed to create ESP partition on $disk."
        exit "$ERR_DISK_PREP"
    fi

    # Partition 2: Linux Root (type 8304, remainder of disk)
    log_info "Creating Root Partition (100% remaining space, type 8304)..."
    if ! sgdisk -n 2:0:0 -t 2:8304 -c 2:"Linux Root" "$disk" >> "$INSTALL_LOG" 2>&1; then
        log_error "Failed to create Root partition on $disk."
        exit "$ERR_DISK_PREP"
    fi

    # Inform OS of partition table changes
    partprobe "$disk" 2>/dev/null || true
    udevadm settle 2>/dev/null || sleep 2

    log_success "Partitioning completed successfully on $disk."
}

format_and_mount_filesystems() {
    local esp_dev="$1"
    local root_dev="$2"
    local root_label="${3:-arch_root}"
    local mount_root="${4:-/mnt}"

    log_info "Formatting EFI System Partition ($esp_dev) as FAT32..."
    if ! mkfs.vfat -F 32 -n "EFI" "$esp_dev" >> "$INSTALL_LOG" 2>&1; then
        log_error "Failed to format ESP partition ($esp_dev) with mkfs.vfat."
        exit "$ERR_DISK_PREP"
    fi

    log_info "Formatting Root Partition ($root_dev) as Ext4 (label: $root_label)..."
    if ! mkfs.ext4 -F -L "$root_label" "$root_dev" >> "$INSTALL_LOG" 2>&1; then
        log_error "Failed to format Root partition ($root_dev) with mkfs.ext4."
        exit "$ERR_DISK_PREP"
    fi

    log_info "Mounting root filesystem to $mount_root..."
    mkdir -p "$mount_root"
    if ! mount "$root_dev" "$mount_root" >> "$INSTALL_LOG" 2>&1; then
        log_error "Failed to mount root partition $root_dev to $mount_root."
        exit "$ERR_DISK_PREP"
    fi

    log_info "Mounting EFI System Partition to $mount_root/boot..."
    mkdir -p "$mount_root/boot"
    if ! mount "$esp_dev" "$mount_root/boot" >> "$INSTALL_LOG" 2>&1; then
        log_error "Failed to mount ESP partition $esp_dev to $mount_root/boot."
        exit "$ERR_DISK_PREP"
    fi

    log_success "Filesystems successfully formatted and mounted at $mount_root."
}

unmount_target_filesystems() {
    local mount_root="${1:-/mnt}"

    log_info "Performing clean unmount of $mount_root..."
    sync
    if ! umount -R "$mount_root" >> "$INSTALL_LOG" 2>&1; then
        log_error "Failed to unmount $mount_root cleanly."
        return 1
    fi

    if mountpoint -q "$mount_root" 2>/dev/null || findmnt -rno TARGET "$mount_root" >/dev/null 2>&1; then
        log_error "Mountpoint $mount_root or submounts remain busy after unmount."
        return 1
    fi

    log_success "All filesystems under $mount_root unmounted cleanly."
    return 0
}
