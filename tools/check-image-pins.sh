#!/usr/bin/env bash
# tools/check-image-pins.sh — has upstream moved a pinned image out from under us?
#
# Some images cannot safely auto-update, because the update needs a migration
# step that swapping a container image does not perform. Those are pinned to an
# exact tag. A pin is only responsible if something notices when upstream moves
# past it — otherwise "read the release notes" is the entire safety mechanism,
# and nobody reads release notes for software that is working.
#
# This compares what we pin against what upstream currently ships, and says so.
# It changes nothing. Run it from the quarterly ritual.
#
#   ./tools/check-image-pins.sh          report
#   ./tools/check-image-pins.sh --notify also push a summary when drifted

# shellcheck source=lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

NOTIFY=0
[[ "${1:-}" == "--notify" ]] && NOTIFY=1

require_cmd curl

drifted=0
report=''

note() { report+="$1"$'\n'; }

# ---------------------------------------------------------------------------
# Immich's database
# ---------------------------------------------------------------------------
# Immich publishes the compose file it supports with each release. The database
# image there is the recommendation; ours is in the unit file.
#
# Why this one is pinned rather than left to podman-auto-update:
#
#   * A PostgreSQL MAJOR bump changes the on-disk format. The new binary
#     refuses to start against the old data directory — it fails closed rather
#     than corrupting anything, but the service is down until you run
#     pg_upgrade or a dump/restore.
#   * A VectorChord EXTENSION bump needs SQL that no image swap performs:
#         ALTER EXTENSION vchord UPDATE;
#         REINDEX INDEX face_index;
#         REINDEX INDEX clip_index;
#     Skip it and you have a database that starts, serves, and has stale
#     indexes — the worst shape of failure, because nothing complains.
#
# The tag names the major AND both extension versions, so auto-update can only
# deliver rebuilds of that exact combination: patched 14.x, same extensions, no
# migration needed. That is what makes AutoUpdate=registry safe on it.
check_immich_db() {
    local unit="$REPO_ROOT/apps/immich/immich-database.container"
    [[ -f "$unit" ]] || return 0

    local ours upstream compose
    ours="$(grep -m1 '^Image=' "$unit" || true)"
    ours="${ours#Image=}"
    [[ -n "$ours" ]] || { warn "could not read the pinned image from $unit"; return 0; }

    compose="$(curl -fsSL --max-time 20 \
        https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml \
        2>/dev/null || true)"
    if [[ -z "$compose" ]]; then
        warn "could not fetch Immich's current compose file — skipping this check"
        return 0
    fi

    # The database service's image line. Strip any @sha256 digest: we compare
    # tags, because the digest changes on every rebuild and that is exactly the
    # movement auto-update is allowed to follow.
    upstream="$(grep -oE 'ghcr\.io/immich-app/postgres:[A-Za-z0-9._-]+' <<<"$compose" | head -1)"
    if [[ -z "$upstream" ]]; then
        warn "Immich's compose no longer names a ghcr.io/immich-app/postgres image — check by hand"
        return 0
    fi

    local ours_tag="${ours##*:}" up_tag="${upstream##*:}"
    ours_tag="${ours_tag%%@*}"

    if [[ "$ours_tag" == "$up_tag" ]]; then
        ok "immich database pin matches upstream ($ours_tag)"
        return 0
    fi

    drifted=1
    err "immich database pin has drifted"
    note "Immich database image"
    note "  pinned here: $ours_tag"
    note "  upstream now: $up_tag"
    note ""
    note "This does NOT apply itself. Before changing the tag:"
    note "  1. Read Immich's release notes for the migration steps."
    note "  2. Take a snapshot."
    note "  3. If the PostgreSQL major changed, plan a dump/restore —"
    note "     the new binary will not start on the old data directory."
    note "  4. If VectorChord changed, after it starts run:"
    note "       ALTER EXTENSION vchord UPDATE;"
    note "       REINDEX INDEX face_index;"
    note "       REINDEX INDEX clip_index;"
}

# ---------------------------------------------------------------------------

section "Pinned images"
check_immich_db

if (( drifted )); then
    printf '\n%s\n' "$report" >&2
    if (( NOTIFY )) && [[ -x /usr/local/bin/ntfy-alert ]]; then
        /usr/local/bin/ntfy-alert "pinned image drift" "$report" default pushpin || true
    fi
    exit 1
fi

ok "every pinned image matches upstream"
