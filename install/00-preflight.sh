#!/usr/bin/env bash
# install/00-preflight.sh — report what this machine looks like, verify it
# matches drives.conf, and get typed confirmation for the one drive that is
# about to be destroyed.
#
# Reads only. Nothing here writes to any disk. Its whole job is to make the
# next script's damage predictable.

# shellcheck source=lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

require_root
require_live_iso
require_cmd lsblk blkid sgdisk
load_host_conf
load_drives_conf

ssd_serial="$(serials_with_role ssd)"

# --- firmware --------------------------------------------------------------
if [[ -d /sys/firmware/efi ]]; then
    FIRMWARE=uefi
    log "firmware: UEFI — 01-partition.sh will create a 1 GiB FAT32 ESP at /boot"
else
    FIRMWARE=bios
    log "firmware: legacy BIOS — 01-partition.sh will create a 1 MiB ef02 BIOS boot partition"
fi
export FIRMWARE

# --- drives ----------------------------------------------------------------
log "verifying attached drives against $DRIVES_CONF"
report_drives || die "fix the drive table or the cabling before continuing"

ssd_dev="$(resolve_serial "$ssd_serial")"

# No guard here second-guesses drives.conf. If the table says this serial is
# the OS drive, that is the answer — you may one day put an SSD in the pool, or
# promote a pool drive to be the OS disk, and a script that refuses on the
# shape of the hardware would be wrong in both cases.
#
# The protection is the confirmation below: it shows what is actually on the
# drive right now, and makes you type its device node.

# --- TRIM ------------------------------------------------------------------
disc_gran="$(lsblk -dno DISC-GRAN -- "$ssd_dev" 2>/dev/null | tr -d ' ')"
if [[ -n "$disc_gran" && "$disc_gran" != "0B" ]]; then
    ok "TRIM supported (DISC-GRAN $disc_gran) — /opt/appdata takes the full remainder"
else
    warn "TRIM not reported — consider shrinking the appdata partition by 8 GiB for overprovisioning"
fi

# --- the destructive summary -----------------------------------------------
model="$(lsblk -dno MODEL -- "$ssd_dev" | sed 's/[[:space:]]*$//')"
size="$(size_of "$ssd_dev")"

cat >&2 <<EOF

  ────────────────────────────────────────────────────────────────
  01-partition.sh will ERASE this drive and nothing else:

      device   $ssd_dev
      serial   $ssd_serial
      model    $model
      size     $size

  Current contents of that drive:
EOF
lsblk -o NAME,SIZE,FSTYPE,LABEL -- "$ssd_dev" | sed 's/^/      /' >&2

# Said out loud rather than enforced. A whole-disk filesystem is how the pool
# drives are formatted, so seeing one here is worth a second look — but it is
# your call, not the script's, and promoting a pool drive to OS duty is a
# legitimate thing to do.
whole_disk_fs="$(blkid -s TYPE -o value -- "$ssd_dev" 2>/dev/null || true)"
if [[ -n "$whole_disk_fs" ]]; then
    cat >&2 <<EOF

      NOTE: this drive carries a $whole_disk_fs filesystem directly on the
      whole disk, with no partition table. That is how the pool drives are
      formatted. Check the serial above against drives.conf before confirming.
EOF
fi

cat >&2 <<EOF

  It will become:

      p1  1 MiB        BIOS boot (ef02)
      p2  $ROOT_SIZE       Btrfs      label archroot   -> /
      p3  remainder    ext4       label APPDATA    -> /opt/appdata

  The $(( ${#DRIVE_SERIALS[@]} - 1 )) pool drives listed above are NOT touched by any
  script in install/. They are verified and left alone.
  ────────────────────────────────────────────────────────────────
EOF

confirm "ERASE $ssd_dev"

ok "preflight passed — next: install/01-partition.sh"
