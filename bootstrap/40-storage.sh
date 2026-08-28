#!/usr/bin/env bash
# bootstrap/40-storage.sh — mount the pool drives and assemble mergerfs.
#
# CONVENTION 3, and the reason this script is short: nothing here ever writes
# to a pool drive. It verifies that what is attached matches drives.conf, it
# creates mountpoints, it edits fstab, and it mounts. It never formats, never
# relabels, never repairs. Provisioning a replacement drive is a documented
# manual procedure plus tools/format-pool-drive.sh, which takes explicit
# arguments and is never called from here.
#
# Today the pool is empty and a mistake costs nothing. That will not be true
# again, so the refusals below are written for the day it matters.
#
# Idempotent.

# shellcheck source=lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

require_root
require_installed_system
require_cmd findmnt lsblk blkid chattr lsattr
load_host_conf
load_drives_conf

POOL_MNT=/mnt/pool
FSTAB=/etc/fstab
BEGIN_MARK='# >>> homelab pool mounts — generated from drives.conf by bootstrap/40-storage.sh'
END_MARK='# <<< homelab pool mounts'

# Mountpoint for a drive, derived from its label: DISK1 -> /mnt/disk1.
# Deterministic, so nothing has to be recorded twice.
mountpoint_for() { printf '/mnt/%s\n' "${1,,}"; }

# ---------------------------------------------------------------------------
# Verify before touching anything
# ---------------------------------------------------------------------------
log "verifying pool drives against $DRIVES_CONF"
report_drives || die "refusing to assemble a pool that does not match $DRIVES_CONF"

# ---------------------------------------------------------------------------
# Mountpoints, locked before first use
# ---------------------------------------------------------------------------
# The failure this prevents: a pool drive fails to mount, its mountpoint is an
# ordinary empty directory on the root filesystem, and mergerfs cheerfully
# adopts it as a writable branch. Photos then land on the 50 GiB SSD while
# every tool reports the pool as healthy, until the SSD fills.
#
# chmod 0000 makes the directory unusable, chattr +i stops anything creating
# entries in it, and both apply to the *underlying* directory — once a real
# filesystem is mounted over the top, its own root permissions govern.
lock_branch() {
    local d="$1"
    if findmnt -M "$d" >/dev/null 2>&1; then
        dbg "$d is mounted; its underlying directory was locked before first mount"
        return 0
    fi
    if [[ "$(lsattr -d -- "$d" 2>/dev/null | cut -d' ' -f1)" == *i* ]]; then
        dbg "$d already locked"
        return 0
    fi
    log "locking mountpoint $d"
    run chown root:root -- "$d"
    run chmod 0000 -- "$d"
    run chattr +i -- "$d"
}

declare -a DATA_MNTS=()
for s in "${DRIVE_SERIALS[@]}"; do
    role="${DRIVE_ROLE[$s]}"
    [[ "$role" == "ssd" ]] && continue
    mnt="$(mountpoint_for "${DRIVE_LABEL[$s]}")"
    [[ -d "$mnt" ]] || run mkdir -p -- "$mnt"
    lock_branch "$mnt"
    [[ "$role" == "data" ]] && DATA_MNTS+=("$mnt")
done

# The pool mountpoint gets the same treatment for the same reason: if mergerfs
# is not mounted, /mnt/pool must not be a writable directory on the SSD.
[[ -d "$POOL_MNT" ]] || run mkdir -p -- "$POOL_MNT"
lock_branch "$POOL_MNT"

(( ${#DATA_MNTS[@]} > 0 )) || die "no data drives in $DRIVES_CONF"

# ---------------------------------------------------------------------------
# fstab
# ---------------------------------------------------------------------------
# Generated rather than shipped in files/, which is a deliberate exception to
# convention 1: the content is derived entirely from drives.conf, and a second
# committed copy of the drive table is exactly the drift that table exists to
# prevent. genfstab also owns the top of this file, so a managed block is the
# only way to edit it without fighting.
#
# By label, never by device path — this machine has a SATA add-on card and an
# external tower, and /dev/sdX shuffles between boots.
#
# nofail plus a short device timeout is what makes a dead drive a degraded
# pool rather than an emergency shell at boot with no network and no ssh.
POOL_OPTS="defaults,nofail,allow_other,cache.files=partial,dropcacheonclose=true"
POOL_OPTS+=",category.create=mfs,minfreespace=20G,fsname=mergerfs"

block="$(
    printf '%s\n' "$BEGIN_MARK"
    for s in "${DRIVE_SERIALS[@]}"; do
        [[ "${DRIVE_ROLE[$s]}" == "ssd" ]] && continue
        printf 'LABEL=%-10s %-14s ext4  defaults,nofail,x-systemd.device-timeout=5s  0 2\n' \
            "${DRIVE_LABEL[$s]}" "$(mountpoint_for "${DRIVE_LABEL[$s]}")"
    done

    branches="$(IFS=:; printf '%s' "${DATA_MNTS[*]}")"
    requires=''
    for m in "${DATA_MNTS[@]}"; do
        requires+=",x-systemd.requires-mounts-for=$m"
    done
    printf '%-25s %-14s fuse.mergerfs  %s%s  0 0\n' \
        "$branches" "$POOL_MNT" "$POOL_OPTS" "$requires"
    printf '%s\n' "$END_MARK"
)"

# Refuse to edit a file whose markers are damaged. The awk below drops
# everything between them; if the end marker is missing it drops everything
# from the begin marker to EOF, which on /etc/fstab means a machine that boots
# to an emergency shell. Verified by test: 3 lines silently eaten.
have_begin=0; have_end=0
grep -qxF -- "$BEGIN_MARK" "$FSTAB" && have_begin=1
grep -qxF -- "$END_MARK"   "$FSTAB" && have_end=1
if (( have_begin != have_end )); then
    die "$FSTAB has a damaged managed block (begin=$have_begin end=$have_end) — repair the markers by hand before re-running"
fi

# Rebuild the file: everything outside the markers, verbatim, plus our block.
tmp_fstab="$(mktemp)"
awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    $0 == b { skip = 1 }
    !skip   { print }
    $0 == e { skip = 0 }
' "$FSTAB" > "$tmp_fstab"
printf '%s\n' "$block" >> "$tmp_fstab"

if cmp -s -- "$tmp_fstab" "$FSTAB"; then
    dbg "fstab already current"
    rm -f -- "$tmp_fstab"
else
    log "updating the managed block in $FSTAB"
    # One backup, overwritten each time. fstab is boot-critical and this is the
    # only script that rewrites it.
    run install -Dm644 -- "$FSTAB" "${FSTAB}.homelab.bak"
    run install -Dm644 -- "$tmp_fstab" "$FSTAB"
    rm -f -- "$tmp_fstab"

    # Syntax-check what we just wrote, while the old copy is still one cp away.
    if [[ -z "$DRY_RUN" ]] && ! findmnt --verify >/dev/null 2>&1; then
        warn "findmnt --verify is unhappy with the new $FSTAB:"
        findmnt --verify >&2 || true
        warn "the previous version is at ${FSTAB}.homelab.bak"
    fi
    unit_reload
fi

# ---------------------------------------------------------------------------
# Mount
# ---------------------------------------------------------------------------
# mergerfs is AUR-only — see bootstrap/15-aur.sh for why that is unavoidable
# and what it costs. Built from source against this system's fuse3, which means
# a fuse3 soname bump needs a rebuild; `paru -Syu` handles that.
aur_install mergerfs

if [[ -z "$DRY_RUN" ]]; then
    log "mounting everything in fstab that is not already mounted"
    mount -a || warn "mount -a reported a problem — the checks below will say which"
fi

# ---------------------------------------------------------------------------
# Verify the result, and be specific about what is wrong
# ---------------------------------------------------------------------------
if [[ -z "$DRY_RUN" ]]; then
    bad_mounts=0
    for s in "${DRIVE_SERIALS[@]}"; do
        [[ "${DRIVE_ROLE[$s]}" == "ssd" ]] && continue
        lbl="${DRIVE_LABEL[$s]}"
        mnt="$(mountpoint_for "$lbl")"
        src="$(findmnt -no SOURCE -- "$mnt" 2>/dev/null || true)"
        if [[ -z "$src" ]]; then
            err "$lbl is not mounted at $mnt"
            bad_mounts=$(( bad_mounts + 1 ))
            continue
        fi
        found="$(blkid -s LABEL -o value -- "$src" 2>/dev/null || true)"
        if [[ "$found" != "$lbl" ]]; then
            err "$mnt holds label '$found', expected '$lbl'"
            bad_mounts=$(( bad_mounts + 1 ))
        fi
    done
    (( bad_mounts == 0 )) || die "$bad_mounts pool mount(s) wrong — not proceeding to SnapRAID"

    [[ "$(findmnt -no FSTYPE -- "$POOL_MNT" 2>/dev/null || true)" == "fuse.mergerfs" ]] \
        || die "$POOL_MNT is not a mergerfs mount"

    findmnt -no TARGET,SOURCE,FSTYPE,SIZE,AVAIL "$POOL_MNT" >&2
    for m in "${DATA_MNTS[@]}"; do
        findmnt -no TARGET,SOURCE,SIZE,AVAIL "$m" >&2
    done
fi

ok "pool assembled at $POOL_MNT — next: bootstrap/50-snapraid.sh"
