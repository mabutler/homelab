#!/usr/bin/env bash
# bootstrap/20-snapshots.sh — snapper, snap-pac and grub-btrfs, so every
# package transaction is bracketed by a pair of bootable snapshots.
#
# This is what makes a rolling-release host safe to update and walk away from:
# a bad `pacman -Syu` becomes a two-minute rollback from the GRUB menu instead
# of a rebuild.
#
# Idempotent.

# shellcheck source=lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

require_root
require_installed_system
require_cmd btrfs findmnt
load_host_conf

SNAP_DIR=/.snapshots

# inotify-tools is an *optional* dependency of grub-btrfs, so pacman will not
# pull it in — but grub-btrfsd watches the snapshot directory with inotifywait
# and exits 1 immediately without it. Optional to the package, mandatory to the
# daemon we are about to enable.
pkg_install snapper snap-pac grub-btrfs inotify-tools

# ---------------------------------------------------------------------------
# The config, and the subvolume collision
# ---------------------------------------------------------------------------
# install/01-partition.sh already created @snapshots and fstab mounts it at
# /.snapshots. `snapper create-config` insists on creating its own .snapshots
# subvolume and fails if anything is already there, so the sequence is: step
# out of the way, let snapper do its thing, delete what it made, and put ours
# back.
#
# Ours is kept rather than snapper's because it is a first-class subvolume
# outside @ — a rollback of the root subvolume must not take the snapshots
# with it, which is exactly what would happen if snapshots lived inside @.
if ! grep_output '(^|[[:space:]])root([[:space:]]|$)' snapper list-configs; then
    log "creating the snapper config for /"

    was_mounted=0
    if findmnt -M "$SNAP_DIR" >/dev/null 2>&1; then
        was_mounted=1
        run umount -- "$SNAP_DIR"
    fi
    [[ -d "$SNAP_DIR" ]] && run rmdir -- "$SNAP_DIR"

    run snapper -c root create-config /

    # Delete the subvolume snapper just made and restore our own mount.
    if [[ -d "$SNAP_DIR" ]]; then
        run btrfs subvolume delete "$SNAP_DIR"
    fi
    run mkdir -p "$SNAP_DIR"
    if (( was_mounted )); then
        run mount -- "$SNAP_DIR"        # from fstab, by label, subvol=/@snapshots
    fi
fi

# Only root reads snapshots here; 750 keeps the directory out of reach of any
# unprivileged process that wanders in.
run chmod 0750 -- "$SNAP_DIR"

# The dance above is the one step in this repository that could quietly leave
# the host without its snapshot subvolume mounted. Check rather than hope.
snap_opts="$(findmnt -no OPTIONS -- "$SNAP_DIR" 2>/dev/null || true)"
[[ "$snap_opts" == *"subvol=/@snapshots"* ]] \
    || die "$SNAP_DIR is not the @snapshots subvolume (options: ${snap_opts:-not mounted}) — fix before continuing, snapshots would land inside @"

# ---------------------------------------------------------------------------
# Retention
# ---------------------------------------------------------------------------
# Set through `snapper set-config` rather than a file in files/, which is a
# deliberate exception to convention 1: snapper generates this config with
# values it computes per filesystem, and shipping a whole file would silently
# drop any key a future snapper version adds.
#
# TIMELINE_CREATE=no is the significant choice. Timeline snapshots fire hourly;
# on a host updated quarterly, whose root filesystem barely changes except
# during a pacman transaction, that is thousands of near-identical snapshots to
# say nothing. snap-pac's pre/post pairs are the ones with information in them.
log "setting snapper retention for root"
run snapper -c root set-config \
    TIMELINE_CREATE=no \
    TIMELINE_CLEANUP=yes \
    NUMBER_CLEANUP=yes \
    NUMBER_MIN_AGE=1800 \
    NUMBER_LIMIT=12 \
    NUMBER_LIMIT_IMPORTANT=8

# Cleanup applies the limits above. The timeline timer stays off to match
# TIMELINE_CREATE=no — enabling a timer that creates nothing is just noise in
# `systemctl list-timers`.
unit_enable --now snapper-cleanup.timer

# ---------------------------------------------------------------------------
# Boot menu entries
# ---------------------------------------------------------------------------
# grub-btrfsd watches the snapshot directory and regenerates the GRUB snapshot
# submenu when it changes, so a snapshot taken during a pacman transaction is
# bootable without anyone remembering to run grub-mkconfig.
unit_enable --now grub-btrfsd.service

# `systemctl enable --now` returns success for a Type=simple unit as soon as
# the exec succeeds, so a daemon that dies a second later still looks like it
# started. Give it a moment and check that it is actually alive.
sleep 2
if ! systemctl is-active --quiet grub-btrfsd.service; then
    journalctl -u grub-btrfsd.service -n 20 --no-pager >&2 || true
    die "grub-btrfsd is enabled but not running — snapshots would never reach the GRUB menu"
fi

log "regenerating grub.cfg so the snapshot submenu exists now"
run grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null

# The GRUB default is pinned by menu entry name (see files/etc/default/grub).
# grub-btrfs adds a submenu; confirm it did not displace the entry that name
# refers to, or the next boot silently picks something else.
#
# grep reads the file directly here — no pipeline, so no SIGPIPE hazard.
grep -qF "Arch Linux, with Linux linux-lts'" /boot/grub/grub.cfg \
    || die "the LTS menu entry is missing from grub.cfg after regeneration — GRUB_DEFAULT would not resolve"

ok "snapshots configured — pacman transactions are now bracketed"
