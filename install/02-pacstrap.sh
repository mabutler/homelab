#!/usr/bin/env bash
# install/02-pacstrap.sh — install the base system onto the mounted target.
#
# Runs from the live ISO, after 01-partition.sh has left the target mounted.
# Downloads and writes a lot; changes nothing that is not under $TARGET_MNT.

# shellcheck source=lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

require_root
require_live_iso
require_cmd pacstrap genfstab findmnt
load_host_conf
load_drives_conf

TARGET_MNT="${TARGET_MNT:-/mnt}"

# --- verify we are pointed at the target, not at the live ISO --------------
# pacstrap into the wrong path is a slow, quiet mistake: it appears to work and
# you find out at reboot. These four checks make it loud instead.
findmnt -M "$TARGET_MNT" >/dev/null \
    || die "$TARGET_MNT is not a mount point — run install/01-partition.sh first"

root_src="$(findmnt -no SOURCE -M "$TARGET_MNT")"
root_fs="$(findmnt -no FSTYPE -M "$TARGET_MNT")"
root_opts="$(findmnt -no OPTIONS -M "$TARGET_MNT")"

[[ "$root_fs" == "btrfs" ]] \
    || die "$TARGET_MNT is $root_fs, expected btrfs — is this really the target?"
[[ "$root_opts" == *"subvol=/@"* ]] \
    || die "$TARGET_MNT is not the @ subvolume (options: $root_opts)"
findmnt -M "$TARGET_MNT/opt/appdata" >/dev/null \
    || die "$TARGET_MNT/opt/appdata is not mounted — 01-partition.sh did not finish"

# And that the thing mounted there is the drive drives.conf calls the OS disk.
ssd_serial="$(serials_with_role ssd)"
ssd_dev="$(resolve_serial "$ssd_serial")"
[[ "$(readlink -f -- "$root_src")" == "$ssd_dev"* ]] \
    || die "$TARGET_MNT is backed by $root_src, which is not on $ssd_dev ($ssd_serial)"

ok "target verified: $root_src on $TARGET_MNT (subvol=@)"

# --- packages --------------------------------------------------------------
# Minimal on purpose. Applications arrive as containers, so the host stays
# small enough to reason about, and nothing here builds kernel modules —
# which is what makes a rolling-release host safe to leave alone for a quarter.
PACKAGES=(
    base                # the meta package: bash, coreutils, systemd, pacman, iproute2 …
    linux-lts           # primary kernel — longterm, so it skips mainline regressions
    linux               # fallback boot entry, for when an LTS update is the problem
    linux-firmware
    intel-ucode         # Sandy Bridge microcode; GRUB picks it up automatically

    btrfs-progs         # root filesystem
    e2fsprogs           # /opt/appdata and the pool drives
    dosfstools          # only used on a UEFI host, but cheap to carry

    grub

    openssh
    sudo

    git                 # /opt/stack is a git checkout on the running host
    vim
    less                # journalctl without a pager is not troubleshooting
    man-db
    man-pages
    pacman-contrib      # pacdiff and paccache — the quarterly update ritual
    tmux
)

# Deliberately absent: base-devel (nothing is built here), a text-mode browser,
# networkmanager (systemd-networkd is already in base), and smartmontools,
# mergerfs and snapraid — those belong to bootstrap/, so this script stays
# "what it takes to boot and be reachable" and nothing more.

log "pacstrap ${#PACKAGES[@]} packages into $TARGET_MNT (this is the slow step)"
pacstrap -K "$TARGET_MNT" "${PACKAGES[@]}"

# --- fstab -----------------------------------------------------------------
# -L writes LABEL= entries. Device letters shuffle between boots on a machine
# with this many controllers, so a /dev/sdX in fstab is a future emergency
# shell; the check below refuses to leave one behind.
log "generating fstab by label"
genfstab -L -p "$TARGET_MNT" >> "$TARGET_MNT/etc/fstab"

if grep -qE '^/dev/(sd|nvme|hd)' "$TARGET_MNT/etc/fstab"; then
    grep -nE '^/dev/(sd|nvme|hd)' "$TARGET_MNT/etc/fstab" >&2
    die "fstab contains device paths instead of labels — fix before rebooting"
fi

grep -v '^#' "$TARGET_MNT/etc/fstab" | grep -v '^[[:space:]]*$' >&2

ok "base system installed — next: install/03-chroot.sh"
