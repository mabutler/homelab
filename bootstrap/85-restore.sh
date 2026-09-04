#!/usr/bin/env bash
# bootstrap/85-restore.sh — pull application state back from the restic
# repository onto a freshly provisioned host.
#
# Runs last, after 80-backup.sh has written /etc/homelab/backup.env. Restores
# each app's data ONLY when that app's /opt/appdata/<app> directory does not
# already exist. On a live host every one of those already exists, so this
# step is always a no-op there — the same convention every other idempotent
# step in bootstrap/ follows for its own state. It only does something the
# first time run.sh reaches this point after a fresh install/, which is
# exactly when it is needed: "start over and run everything again" should
# come back with your data, not empty apps.
#
# Restored: whole-directory content per app (attachments, RSA keys, recipe
# images...), the SQLite dumps materialised back into live databases, the
# photo library, and any apps/<name>/<name>.env this host does not already
# have.
#
# NOT restored here: Immich's PostgreSQL database. Restoring it needs
# pg_restore against a RUNNING container, and immich-database does not exist
# until deploy.sh has started it — which has not happened yet at this point
# in the sequence. Its dump is staged instead, and the one command to finish
# the job is printed at the end, to run after `deploy.sh immich`.
#
# Safe against an empty or unreachable repository: every check below finds
# nothing and this is a no-op, which is the correct behaviour on a genuinely
# first-ever build, before homelab-backup has ever run.

source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

require_root
require_installed_system
load_host_conf
require_conf RESTIC_REPOSITORY RESTIC_PASSWORD

BACKUP_ENV=/etc/homelab/backup.env
[[ -r "$BACKUP_ENV" ]] || die "missing $BACKUP_ENV — run bootstrap/80-backup.sh first"
# shellcheck source=/dev/null
set -a; source "$BACKUP_ENV"; set +a

APPDATA=/opt/appdata
STAGING=/var/lib/homelab/backup
RESTORE_STAGE=/var/lib/homelab/restore
IMMICH_DUMP_STAGED=0

# ---------------------------------------------------------------------------
# Is there anything to restore at all?
# ---------------------------------------------------------------------------
# Same non-negotiable as homelab-backup itself: show restic's own error rather
# than a guess. A precondition that hides the error it is checking for has
# cost an hour here before.
if ! repo_err="$(restic snapshots --tag homelab 2>&1 >/dev/null)"; then
    warn "cannot reach the restic repository — skipping restore:"
    [[ -n "$repo_err" ]] && warn "$repo_err"
    ok "nothing restored — proceeding as a from-scratch build"
    exit 0
fi

if ! restic snapshots --tag homelab --latest 1 --json 2>/dev/null | grep -q '"short_id"'; then
    ok "repository reachable, no snapshots yet — nothing to restore"
    exit 0
fi

log "backups found — restoring whatever this host does not already have"

RESTORE_PROBLEMS=0

# restore_path <absolute-path> — pulls one path from the latest snapshot back
# to where it came from. restic restores an absolute path under --target / to
# that same absolute location, which is what makes this an in-place restore
# rather than a stage-then-copy dance.
#
# Never dies on its own: an --include matching nothing (an app added after
# the last backup, say) is a normal, expected shape, not a failure, and one
# bad path should not stop the rest of the restore from being attempted. It
# counts the problem instead, and the script fails loudly at the very end if
# anything actually went wrong — never silently, mid-run.sh, on a partial
# restore nobody noticed.
restore_path() {
    local out
    if out="$(restic restore latest --tag homelab --target / --include "$1" 2>&1)"; then
        return 0
    fi
    warn "restoring $1 failed:"
    [[ -n "$out" ]] && warn "$out"
    RESTORE_PROBLEMS=$(( RESTORE_PROBLEMS + 1 ))
    return 1
}

# ---------------------------------------------------------------------------
# The small SQLite apps and Vaultwarden
# ---------------------------------------------------------------------------
# restore_sqlite_app <app> <live-db-path> <dump-name> <uid> <gid>
#
# The dump is SQLite's `.backup` output, which is already a complete, valid
# database — restoring it is a copy into the live filename, not a replay.
# Verified with the same PRAGMA integrity_check homelab-backup runs before it
# lets a dump into the repository, so a corrupt dump is refused here too
# rather than installed as-is.
restore_sqlite_app() {
    local app="$1" live_db="$2" dump="$3" uid="$4" gid="$5"
    local appdir="$APPDATA/$app" dumped="$STAGING/db/$dump"

    [[ -e "$appdir" ]] && return 0

    log "restoring $app from backup"
    restore_path "$appdir" || true
    restore_path "$dumped" || true

    if [[ ! -f "$dumped" ]]; then
        warn "$app: directory restored, but no $dump in the snapshot — nothing to install as its database"
        return 0
    fi

    sqlite3 "$dumped" 'PRAGMA integrity_check;' | grep -qx ok \
        || die "$app: restored dump fails integrity_check — refusing to install it as the live database"

    run mkdir -p -- "$(dirname -- "$live_db")"
    run install -o "$uid" -g "$gid" -m 0600 -- "$dumped" "$live_db"
    run chown -R "$uid:$gid" -- "$appdir"
    run rm -f -- "$dumped"
    ok "$app restored"
}

# Ownership matches system/tmpfiles/*.conf: mealie and vikunja honour a fixed
# uid 1000, vaultwarden and memos run root inside their containers.
restore_sqlite_app vaultwarden "$APPDATA/vaultwarden/db.sqlite3"        vaultwarden.sqlite3.dump root root
restore_sqlite_app mealie      "$APPDATA/mealie/mealie.db"              mealie.sqlite3.dump      1000 1000
restore_sqlite_app vikunja     "$APPDATA/vikunja/db/vikunja.db"         vikunja.sqlite3.dump     1000 1000
restore_sqlite_app memos       "$APPDATA/memos/memos_prod.db"           memos.sqlite3.dump       root root

# ---------------------------------------------------------------------------
# The photo library
# ---------------------------------------------------------------------------
if ! mountpoint -q /mnt/pool; then
    warn "/mnt/pool is not mounted — skipping photo library restore (bootstrap/40-storage.sh should have run first)"
elif [[ -d /mnt/pool/photos && -n "$(ls -A /mnt/pool/photos 2>/dev/null)" ]]; then
    : # already has photos — not fresh, leave it alone
else
    log "restoring the photo library"
    restore_path /mnt/pool/photos && ok "photo library restored"
fi

# ---------------------------------------------------------------------------
# Immich's database — staged, not restored
# ---------------------------------------------------------------------------
if [[ ! -d "$APPDATA/immich/postgres" ]]; then
    restore_path "$STAGING/db/immich.sql.dump.gz" || true
    if [[ -f "$STAGING/db/immich.sql.dump.gz" ]]; then
        run mkdir -p -- "$RESTORE_STAGE"
        run chmod 0700 -- "$RESTORE_STAGE"
        run mv -- "$STAGING/db/immich.sql.dump.gz" "$RESTORE_STAGE/immich.sql.dump.gz"
        IMMICH_DUMP_STAGED=1
    fi
fi

# ---------------------------------------------------------------------------
# App secrets — apps/<name>/<name>.env this host does not already have
# ---------------------------------------------------------------------------
# These are what deploy.sh otherwise makes you recreate by hand for every
# app: Vaultwarden's ADMIN_TOKEN, Immich's DB_PASSWORD, and so on. Only ever
# fills in a file that is missing — an existing one is never touched, and
# alerting.env/backup.env are skipped because 60-alerting.sh and this app's
# own 80-backup.sh regenerate them from host.conf regardless.
restore_path "$STAGING/secrets" || true
if [[ -d "$STAGING/secrets" ]]; then
    for f in "$STAGING/secrets"/*.env; do
        [[ -f "$f" ]] || continue
        name="$(basename -- "$f" .env)"
        case "$name" in
            alerting|backup) continue ;;
        esac
        [[ -d "$REPO_ROOT/apps/$name" ]] || continue
        dest="$REPO_ROOT/apps/$name/$name.env"
        [[ -f "$dest" ]] && continue
        run install -m 0600 -- "$f" "$dest"
        ok "restored apps/$name/$name.env"
    done
fi

# The staging directory held every secret and database dump on this host
# briefly. It does not outlive the run, same as in homelab-backup itself.
run rm -rf -- "$STAGING"

if (( IMMICH_DUMP_STAGED )); then
    cat >&2 <<EOF

  ────────────────────────────────────────────────────────────
  Immich's photos and secrets are restored. Its database is NOT —
  finish it once immich-database is running:

    sudo ./deploy.sh immich
    gunzip -c $RESTORE_STAGE/immich.sql.dump.gz | \\
      sudo podman exec -i -e PGPASSWORD=\$(grep -m1 '^DB_PASSWORD=' \\
        apps/immich/immich.env | cut -d= -f2-) immich-database \\
      psql -U postgres immich

  Then remove the staged dump: sudo rm -rf $RESTORE_STAGE
  ────────────────────────────────────────────────────────────
EOF
fi

if (( RESTORE_PROBLEMS > 0 )); then
    die "$RESTORE_PROBLEMS restore problem(s) above — fix the cause and re-run: sudo ./run.sh --only 85"
fi

ok "restore complete"
