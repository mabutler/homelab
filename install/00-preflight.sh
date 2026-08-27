#!/usr/bin/env bash
# install/00-preflight.sh — report what this machine looks like and verify it
# matches drives.conf.
#
# Reads only, changes nothing, and asks nothing. Safe to run as often as you
# like. Its whole job is to make the next script's damage predictable.

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

# --- what 01 will do -------------------------------------------------------
# Shown here so you can read it without committing to anything. The typed
# confirmation lives in 01-partition.sh, next to the destruction it guards:
# a prompt on a script that erases nothing only teaches you to clear prompts.
report_target_drive "$ssd_serial" "$ssd_dev"

ok "preflight passed — nothing has been changed. Next: install/01-partition.sh"
