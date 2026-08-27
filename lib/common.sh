#!/usr/bin/env bash
# lib/common.sh — shared helpers. Sourced by every script in this repository;
# never executed on its own.
#
# Every script starts with:
#
#     source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
#
# which also applies `set -euo pipefail`.

[[ -n "${_HOMELAB_COMMON_SOURCED:-}" ]] && return 0
_HOMELAB_COMMON_SOURCED=1

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
# Resolved from this file's own location, so scripts behave the same whether
# they are invoked as ./bootstrap/10-base.sh or /opt/stack/bootstrap/10-base.sh.
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FILES_DIR="$REPO_ROOT/files"
HOST_CONF="${HOST_CONF:-$REPO_ROOT/host.conf}"
DRIVES_CONF="${DRIVES_CONF:-$REPO_ROOT/drives.conf}"

# The by-id directory. Overridable only so the resolver can be exercised
# against a fixture; nothing in this repository ever sets it.
BYID_DIR="${BYID_DIR:-/dev/disk/by-id}"

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
# All diagnostics go to stderr so a function's stdout stays usable as a value.
if [[ -t 2 ]]; then
    _C_RESET=$'\033[0m'
    _C_BLUE=$'\033[34m'
    _C_GREEN=$'\033[32m'
    _C_YELLOW=$'\033[33m'
    _C_RED=$'\033[31m'
    _C_DIM=$'\033[2m'
else
    _C_RESET='' _C_BLUE='' _C_GREEN='' _C_YELLOW='' _C_RED='' _C_DIM=''
fi

log()  { printf '%s==>%s %s\n'  "$_C_BLUE"   "$_C_RESET" "$*" >&2; }
ok()   { printf '%s ok %s %s\n' "$_C_GREEN"  "$_C_RESET" "$*" >&2; }
warn() { printf '%swarn%s %s\n' "$_C_YELLOW" "$_C_RESET" "$*" >&2; }
err()  { printf '%sERR %s %s\n' "$_C_RED"    "$_C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }

VERBOSE="${VERBOSE:-}"

dbg() {
    [[ -n "$VERBOSE" ]] || return 0
    printf '%s  . %s %s\n' "$_C_DIM" "$_C_RESET" "$*" >&2
}

# ---------------------------------------------------------------------------
# Dry run
# ---------------------------------------------------------------------------
# DRY_RUN=1 makes run() print instead of execute. It is meaningful for
# bootstrap/ (idempotent, re-runnable) and NOT for install/ — a dry run of a
# partitioning script cannot report what the next step would have found, so
# install/ scripts do not honour it.
DRY_RUN="${DRY_RUN:-}"

run() {
    if [[ -n "$DRY_RUN" ]]; then
        printf '%sdry %s %s\n' "$_C_DIM" "$_C_RESET" "$*" >&2
        return 0
    fi
    "$@"
}

# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------
require_root() {
    [[ ${EUID:-$(id -u)} -eq 0 ]] || die "must run as root (try: sudo $0)"
}

require_cmd() {
    local c missing=()
    for c in "$@"; do
        command -v -- "$c" >/dev/null 2>&1 || missing+=("$c")
    done
    (( ${#missing[@]} == 0 )) || die "required command(s) not found: ${missing[*]}"
}

on_live_iso() { [[ -d /run/archiso ]]; }

require_live_iso() {
    on_live_iso || die "this script is destructive and runs only from the Arch live ISO"
}

require_installed_system() {
    ! on_live_iso || die "this script runs on the installed system, not the live ISO"
}

# confirm <phrase>
# Typed confirmation. Nothing destructive proceeds without it, and the phrase
# is deliberately not "yes" — it names what is about to happen, so a reflexive
# keypress cannot clear the gate.
confirm() {
    local want="$1" got=''
    printf '\n%stype %s to continue (anything else aborts): %s' \
        "$_C_YELLOW" "$want" "$_C_RESET" >&2
    read -r got || true
    [[ "$got" == "$want" ]] || die "aborted at confirmation prompt"
}

# ---------------------------------------------------------------------------
# host.conf
# ---------------------------------------------------------------------------
# The only per-machine file. Gitignored; the real copy lives in the password
# manager, because a rebuild restores this repository but not this machine's
# identity.
# Only the identity values are required to load. Alerting values are not
# needed to partition a disk, and demanding an ntfy topic before install/ will
# run just teaches you to put a placeholder there. Scripts that need more call
# require_conf for exactly what they use.
load_host_conf() {
    [[ -f "$HOST_CONF" ]] \
        || die "missing $HOST_CONF — copy host.conf.example to host.conf and fill it in"

    # shellcheck source=/dev/null
    source "$HOST_CONF"

    require_conf TARGET_HOSTNAME ADMIN_USER TIMEZONE LOCALE KEYMAP ROOT_SIZE

    dbg "host.conf: $TARGET_HOSTNAME, admin=$ADMIN_USER, tz=$TIMEZONE"
}

# require_conf <VAR>... — fatal unless every named value is set and non-empty.
# Call at the top of any script that depends on an optional host.conf value, so
# the failure names the missing key instead of surfacing later as an empty
# string substituted into a config file.
require_conf() {
    local v missing=()
    for v in "$@"; do
        [[ -n "${!v:-}" ]] || missing+=("$v")
    done
    (( ${#missing[@]} == 0 )) \
        || die "$HOST_CONF is missing values needed here: ${missing[*]}"
}

# ---------------------------------------------------------------------------
# drives.conf
# ---------------------------------------------------------------------------
# Serials are the only stable identity a drive has on this machine: it has a
# SATA add-on card and an external tower, and device letters shuffle between
# boots. No script in this repository accepts a /dev/sdX path.
declare -a DRIVE_SERIALS=()
declare -A DRIVE_LABEL=()
declare -A DRIVE_ROLE=()
# DRIVE_SIZE is documentary only — consumed by install/00-preflight.sh when it
# reports what it is about to destroy, so the operator can compare against lsblk.
declare -A DRIVE_SIZE=()

load_drives_conf() {
    [[ -f "$DRIVES_CONF" ]] || die "missing $DRIVES_CONF"

    DRIVE_SERIALS=()
    DRIVE_LABEL=()
    DRIVE_ROLE=()
    DRIVE_SIZE=()

    local serial label role size rest lineno=0
    while IFS=$' \t' read -r serial label role size rest || [[ -n "$serial" ]]; do
        lineno=$(( lineno + 1 ))

        if [[ -z "$serial" || "$serial" == '#'* ]]; then
            continue
        fi
        if [[ -z "$label" || -z "$role" ]]; then
            die "$DRIVES_CONF:$lineno: incomplete row (want: serial label role size)"
        fi
        case "$role" in
            ssd|parity|data) ;;
            *) die "$DRIVES_CONF:$lineno: unknown role '$role' (want ssd, parity or data)" ;;
        esac
        if [[ -n "${DRIVE_LABEL[$serial]:-}" ]]; then
            die "$DRIVES_CONF:$lineno: duplicate serial $serial"
        fi

        DRIVE_SERIALS+=("$serial")
        DRIVE_LABEL["$serial"]="$label"
        DRIVE_ROLE["$serial"]="$role"
        # shellcheck disable=SC2034  # read by install/00-preflight.sh
        DRIVE_SIZE["$serial"]="${size:-?}"
    done < "$DRIVES_CONF"

    (( ${#DRIVE_SERIALS[@]} > 0 )) || die "$DRIVES_CONF lists no drives"

    # Exactly one SSD, exactly one parity, at least one data drive.
    local s ssd=0 parity=0 data=0
    for s in "${DRIVE_SERIALS[@]}"; do
        case "${DRIVE_ROLE[$s]}" in
            ssd)    ssd=$(( ssd + 1 )) ;;
            parity) parity=$(( parity + 1 )) ;;
            data)   data=$(( data + 1 )) ;;
        esac
    done
    (( ssd == 1 ))    || die "$DRIVES_CONF: expected exactly one 'ssd' row, found $ssd"
    (( parity == 1 )) || die "$DRIVES_CONF: expected exactly one 'parity' row, found $parity"
    (( data >= 1 ))   || die "$DRIVES_CONF: expected at least one 'data' row"

    dbg "drives.conf: ${#DRIVE_SERIALS[@]} drives (${ssd} ssd, ${parity} parity, ${data} data)"
}

# serials_with_role <ssd|parity|data> — prints matching serials, one per line.
serials_with_role() {
    local want="$1" s
    for s in "${DRIVE_SERIALS[@]}"; do
        [[ "${DRIVE_ROLE[$s]}" == "$want" ]] && printf '%s\n' "$s"
    done
    return 0
}

# ---------------------------------------------------------------------------
# Serial -> device resolution
# ---------------------------------------------------------------------------
# Only ata-* and nvme-* by-id links are considered. This machine has a USB
# multi-card reader that presents four zero-byte pseudo-devices sharing one
# serial (058F63626420); a loose glob over /dev/disk/by-id/* would match them
# and a partition-suffixed link would match a partition instead of the disk.
#
# stdout: the resolved /dev node. Returns 1 if the serial is not present.
serial_to_dev() {
    local serial="$1" link dev
    local -a matches=()

    for link in "$BYID_DIR/ata-"*"_${serial}" \
                "$BYID_DIR/nvme-"*"_${serial}"; do
        [[ -e "$link" ]] || continue
        [[ "$link" == *-part[0-9]* ]] && continue
        dev="$(readlink -f -- "$link")"
        [[ -b "$dev" ]] || continue
        local m seen=0
        for m in ${matches[@]+"${matches[@]}"}; do
            [[ "$m" == "$dev" ]] && seen=1
        done
        (( seen )) || matches+=("$dev")
    done

    case ${#matches[@]} in
        0) return 1 ;;
        1) printf '%s\n' "${matches[0]}" ;;
        *) die "serial '$serial' resolves to more than one device: ${matches[*]}" ;;
    esac
}

# resolve_serial <serial> — as serial_to_dev, but fatal when absent.
resolve_serial() {
    local serial="$1" dev
    dev="$(serial_to_dev "$serial")" \
        || die "no drive with serial '$serial' is attached (listed in $DRIVES_CONF)"
    printf '%s\n' "$dev"
}

# dev_serial <device> — reverse lookup, for reporting on something found on
# the machine that drives.conf does not mention.
dev_serial() {
    lsblk -dno SERIAL -- "$1" 2>/dev/null || true
}

# label_of <device> — whole-disk filesystem label, empty if none.
#
# blkid first: it probes the device directly. lsblk's LABEL column is served
# from the udev database, which can be empty on a live ISO shortly after drives
# are attached — and since 40-storage.sh refuses to proceed on a label
# mismatch, a cold udev db would abort the build over a label that is really
# there. lsblk is the fallback for the unprivileged case, where blkid cannot
# open the device.
#
# This reads the disk itself, not its partitions. The pool drives are
# unpartitioned ext4 so their label is here; the SSD's label lives on p2, and
# this correctly returns empty for it.
label_of() {
    local dev="$1" found
    found="$(blkid -s LABEL -o value -- "$dev" 2>/dev/null || true)"
    [[ -n "$found" ]] || found="$(lsblk -dno LABEL -- "$dev" 2>/dev/null || true)"
    printf '%s\n' "${found//[[:space:]]/}"
}

# size_of <device> — as lsblk renders it, e.g. "1.8T".
size_of() {
    lsblk -dno SIZE -- "$1" 2>/dev/null | tr -d ' ' || true
}

# is_rotational <device> — true for spinning rust, false for SSD.
is_rotational() {
    [[ "$(lsblk -dno ROTA -- "$1" 2>/dev/null | tr -d ' ')" == "1" ]]
}

# ---------------------------------------------------------------------------
# Drive verification
# ---------------------------------------------------------------------------
# Shared by install/00-preflight.sh and bootstrap/40-storage.sh, and runnable
# on its own as tools/check-drives.sh. Reads only; never writes to a drive.
#
# Checks, by role:
#   all          the serial resolves, and no two rows resolve to the same device
#   parity/data  the whole-disk label matches drives.conf — these drives are
#                unpartitioned ext4, so the label is a PRECONDITION, and a
#                mismatch means stop, not relabel
#   ssd          the drive is non-rotational. Its label is an OUTPUT of
#                01-partition.sh, applied to p2, so there is nothing to compare
#                before the install has run.
#
# Size is compared as lsblk renders it and reported as a warning, not a
# failure: a mismatch means drives.conf is stale, which is worth knowing but
# is not itself unsafe.
#
# Returns 0 only when every row passes.
report_drives() {
    local s dev want role size mark row_bad
    local problems=0 warnings=0
    local -A seen_dev=()

    printf '%-18s %-9s %-7s %-10s %-8s %s\n' \
        SERIAL LABEL ROLE DEVICE SIZE RESULT >&2

    for s in "${DRIVE_SERIALS[@]}"; do
        want="${DRIVE_LABEL[$s]}"
        role="${DRIVE_ROLE[$s]}"
        dev="$(serial_to_dev "$s" || true)"

        if [[ -z "$dev" ]]; then
            printf '%-18s %-9s %-7s %-10s %-8s %s\n' \
                "$s" "$want" "$role" '-' '-' 'NOT ATTACHED' >&2
            problems=$(( problems + 1 ))
            continue
        fi

        size="$(size_of "$dev")"
        mark='ok'
        row_bad=0

        if [[ -n "${seen_dev[$dev]:-}" ]]; then
            mark="DUPLICATE — also matched by ${seen_dev[$dev]}"
            row_bad=1
        fi
        seen_dev["$dev"]="$s"

        if (( ! row_bad )); then
            case "$role" in
                parity|data)
                    local found
                    found="$(label_of "$dev")"
                    if [[ "$found" != "$want" ]]; then
                        mark="LABEL IS '${found:-none}', EXPECTED '$want'"
                        row_bad=1
                    fi
                    ;;
                ssd)
                    if is_rotational "$dev"; then
                        mark="ROTATIONAL — this is not the SSD"
                        row_bad=1
                    else
                        mark='ok (label applied by 01-partition.sh)'
                    fi
                    ;;
            esac
        fi

        if (( ! row_bad )) && [[ "${DRIVE_SIZE[$s]}" != '?' && "$size" != "${DRIVE_SIZE[$s]}" ]]; then
            mark="$mark — size reads $size, drives.conf says ${DRIVE_SIZE[$s]}"
            warnings=$(( warnings + 1 ))
        fi

        (( row_bad )) && problems=$(( problems + 1 ))

        printf '%-18s %-9s %-7s %-10s %-8s %s\n' \
            "$s" "$want" "$role" "$dev" "$size" "$mark" >&2
    done

    if (( problems )); then
        err "$problems of ${#DRIVE_SERIALS[@]} drives failed verification"
        return 1
    fi
    if (( warnings )); then
        warn "all ${#DRIVE_SERIALS[@]} drives verified, with $warnings size warning(s)"
        return 0
    fi
    ok "all ${#DRIVE_SERIALS[@]} drives verified against $DRIVES_CONF"
}

# ---------------------------------------------------------------------------
# Packages and units
# ---------------------------------------------------------------------------
pkg_install() {
    (( $# > 0 )) || return 0
    local p want=()
    for p in "$@"; do
        pacman -Qq -- "$p" >/dev/null 2>&1 || want+=("$p")
    done
    if (( ${#want[@]} == 0 )); then
        dbg "already installed: $*"
        return 0
    fi
    log "pacman: ${want[*]}"
    run pacman -S --needed --noconfirm -- "${want[@]}"
}

# unit_enable [--now] <unit>...
unit_enable() {
    local now=0
    if [[ "${1:-}" == "--now" ]]; then
        now=1
        shift
    fi
    local u
    for u in "$@"; do
        if systemctl is-enabled --quiet -- "$u" 2>/dev/null; then
            dbg "already enabled: $u"
            (( now )) && ! systemctl is-active --quiet -- "$u" 2>/dev/null \
                && run systemctl start -- "$u"
            continue
        fi
        log "enable $u"
        if (( now )); then
            run systemctl enable --now -- "$u"
        else
            run systemctl enable -- "$u"
        fi
    done
    return 0
}

unit_reload() {
    log "systemctl daemon-reload"
    run systemctl daemon-reload
}

# ---------------------------------------------------------------------------
# Installing configuration from files/
# ---------------------------------------------------------------------------
# Convention 1: configuration lives in files/ and is installed verbatim.
# Scripts never write config with heredocs — a file in the tree is diffable
# and greppable, a heredoc is neither.

# install_file <path-under-files/> [mode]
#   install_file etc/systemd/zram-generator.conf
# copies files/etc/systemd/zram-generator.conf to /etc/systemd/zram-generator.conf.
# Idempotent: identical content is a no-op, and reports nothing at default
# verbosity, which is what makes a second run.sh pass produce no output.
install_file() {
    local rel="${1#/}" mode="${2:-0644}"
    local src="$FILES_DIR/$rel" dst="/$rel"

    [[ -f "$src" ]] || die "missing repo file: files/$rel"

    if [[ -f "$dst" ]] && cmp -s -- "$src" "$dst"; then
        dbg "unchanged: $dst"
        return 0
    fi
    log "install $dst"
    run install -Dm"$mode" -- "$src" "$dst"
}

# install_template <path-under-files/> [mode]
# As install_file, but substitutes @NAME@ placeholders from host.conf.
# Convention 5: a single substitution pass over a fixed key list. No template
# engine, and an unknown @PLACEHOLDER@ is a hard error rather than silently
# shipping literal text into a config file.
install_template() {
    local rel="${1#/}" mode="${2:-0644}"
    local src="$FILES_DIR/$rel" dst="/$rel" tmp leftover

    [[ -f "$src" ]] || die "missing repo template: files/$rel"

    tmp="$(mktemp)"

    sed -e "s|@HOSTNAME@|${TARGET_HOSTNAME:-}|g" \
        -e "s|@ADMIN_USER@|${ADMIN_USER:-}|g" \
        -e "s|@TIMEZONE@|${TIMEZONE:-}|g" \
        -e "s|@NTFY_SERVER@|${NTFY_SERVER:-}|g" \
        -e "s|@NTFY_TOPIC@|${NTFY_TOPIC:-}|g" \
        -e "s|@HC_HEARTBEAT_URL@|${HC_HEARTBEAT_URL:-}|g" \
        -e "s|@HC_SNAPRAID_SYNC_URL@|${HC_SNAPRAID_SYNC_URL:-}|g" \
        -e "s|@HC_SNAPRAID_SCRUB_URL@|${HC_SNAPRAID_SCRUB_URL:-}|g" \
        -e "s|@HC_SMART_URL@|${HC_SMART_URL:-}|g" \
        -- "$src" > "$tmp"

    leftover="$(grep -o '@[A-Z_]\+@' -- "$tmp" | sort -u | tr '\n' ' ' || true)"
    if [[ -n "${leftover// /}" ]]; then
        rm -f -- "$tmp"
        die "files/$rel has unsubstituted placeholders: $leftover"
    fi

    if [[ -f "$dst" ]] && cmp -s -- "$tmp" "$dst"; then
        rm -f -- "$tmp"
        dbg "unchanged: $dst"
        return 0
    fi
    log "install $dst (templated)"
    run install -Dm"$mode" -- "$tmp" "$dst"
    rm -f -- "$tmp"
}
