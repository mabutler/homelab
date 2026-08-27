#!/usr/bin/env bash
# install/01-partition.sh — partition and format the SSD, and nothing else.
#
# DESTRUCTIVE. Runs once, from the live ISO.
#
# Re-runs its own guards rather than trusting that 00-preflight.sh ran: these
# scripts are invoked by hand, one at a time, and "I already checked" is not a
# guarantee the next operator has.
#
# Leaves the new filesystems mounted at /mnt, ready for 02-pacstrap.sh.

# shellcheck source=lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

require_root
require_live_iso
require_cmd sgdisk mkfs.btrfs mkfs.ext4 btrfs lsblk blkid
load_host_conf
load_drives_conf

TARGET_MNT="${TARGET_MNT:-/mnt}"

ssd_serial="$(serials_with_role ssd)"
ssd_dev="$(resolve_serial "$ssd_serial")"

# --- guards ----------------------------------------------------------------
# These check for contradictions in drives.conf, not for whether the choice it
# expresses is a sensible one. Which drive is the OS disk is your decision.
#
# Two rows resolving to one physical device is the exception: that is the table
# disagreeing with itself, which cannot be intent.
for s in "${DRIVE_SERIALS[@]}"; do
    [[ "${DRIVE_ROLE[$s]}" == "ssd" ]] && continue
    pool_dev="$(serial_to_dev "$s" || true)"
    if [[ -n "$pool_dev" && "$pool_dev" == "$ssd_dev" ]]; then
        die "REFUSING: $DRIVES_CONF lists $ssd_dev as both the ssd row and the ${DRIVE_ROLE[$s]} row $s"
    fi
done

# Nothing from the target may be mounted while we repartition it.
if findmnt -rno SOURCE | grep -q "^${ssd_dev}"; then
    die "$ssd_dev has mounted partitions — unmount them first (findmnt | grep $ssd_dev)"
fi

log "erasing and partitioning $ssd_dev ($ssd_serial)"

# --- partition table -------------------------------------------------------
wipefs -a -- "$ssd_dev" >/dev/null
sgdisk --zap-all -- "$ssd_dev" >/dev/null
sgdisk --clear -- "$ssd_dev" >/dev/null

if [[ -d /sys/firmware/efi ]]; then
    # Untested branch: this host is legacy BIOS. Present so a future UEFI
    # machine needs a different host.conf, not a different script.
    sgdisk -n 1:0:+1GiB   -t 1:ef00 -c 1:esp      -- "$ssd_dev" >/dev/null
    BOOT_KIND=esp
else
    sgdisk -n 1:0:+1MiB   -t 1:ef02 -c 1:biosboot -- "$ssd_dev" >/dev/null
    BOOT_KIND=biosboot
fi
sgdisk -n "2:0:+${ROOT_SIZE}" -t 2:8300 -c 2:archroot -- "$ssd_dev" >/dev/null
sgdisk -n 3:0:0               -t 3:8300 -c 3:appdata  -- "$ssd_dev" >/dev/null

settle
partprobe -- "$ssd_dev" 2>/dev/null || true
settle

p2="$(part_link "$ssd_serial" 2)" || die "partition 2 did not appear under $BYID_DIR after partprobe"
p3="$(part_link "$ssd_serial" 3)" || die "partition 3 did not appear under $BYID_DIR after partprobe"
ok "partitions created: p2=$(readlink -f "$p2") p3=$(readlink -f "$p3")"

if [[ "$BOOT_KIND" == "esp" ]]; then
    p1="$(part_link "$ssd_serial" 1)" || die "ESP did not appear under $BYID_DIR"
    mkfs.fat -F32 -n ESP -- "$p1" >/dev/null
fi

# --- filesystems -----------------------------------------------------------
# Root is Btrfs so package transactions can be bracketed by bootable snapshots.
# Application state is ext4 on its own partition: databases behave badly under
# copy-on-write, and app data must not be rewound by an OS snapshot rollback.
log "mkfs.btrfs -L archroot"
mkfs.btrfs -f -L archroot -- "$p2" >/dev/null

log "mkfs.ext4 -L APPDATA"
mkfs.ext4 -q -F -L APPDATA -- "$p3"

# --- subvolumes ------------------------------------------------------------
# Kernels live inside @, so rolling back a snapshot restores a matching kernel
# and initramfs. @var_log and @snapshots stay outside @ so that a rollback does
# not discard the logs explaining why you rolled back, or the other snapshots.
BTRFS_OPTS="noatime,compress=zstd:3"

mount -o "$BTRFS_OPTS" -- "$p2" "$TARGET_MNT"
for sub in @ @home @var_log @containers @snapshots; do
    btrfs subvolume create "$TARGET_MNT/$sub" >/dev/null
    dbg "subvolume $sub"
done
umount -- "$TARGET_MNT"
ok "subvolumes created: @ @home @var_log @containers @snapshots"

# --- mount the target ------------------------------------------------------
mount -o "$BTRFS_OPTS,subvol=@" -- "$p2" "$TARGET_MNT"
mkdir -p "$TARGET_MNT"/{home,var/log,var/lib/containers,.snapshots,opt/appdata,boot}

mount -o "$BTRFS_OPTS,subvol=@home"       -- "$p2" "$TARGET_MNT/home"
mount -o "$BTRFS_OPTS,subvol=@var_log"    -- "$p2" "$TARGET_MNT/var/log"
mount -o "$BTRFS_OPTS,subvol=@containers" -- "$p2" "$TARGET_MNT/var/lib/containers"
mount -o "$BTRFS_OPTS,subvol=@snapshots"  -- "$p2" "$TARGET_MNT/.snapshots"
mount -- "$p3" "$TARGET_MNT/opt/appdata"

if [[ "$BOOT_KIND" == "esp" ]]; then
    mount -- "$(part_link "$ssd_serial" 1)" "$TARGET_MNT/boot"
fi

findmnt -R "$TARGET_MNT" -o TARGET,SOURCE,FSTYPE,OPTIONS >&2

ok "target mounted at $TARGET_MNT — next: install/02-pacstrap.sh"
