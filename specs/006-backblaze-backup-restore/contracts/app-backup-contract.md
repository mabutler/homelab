# Contract: Application Backup Onboarding

**Contract Identifier**: `APP-BACKUP-V1`  
**Hook Directory**: `/etc/homelab/backup.d/`  
**Applicability**: All Phase 5 stateful applications (Vaultwarden, Home Assistant, Immich, Mealie, etc.)  

---

## 1. Specification

Every stateful application deployed on the homelab host MUST provide a backup hook script in `/etc/homelab/backup.d/`.

### File Naming Convention
`<priority>-<app-name>.sh`
- `priority`: Two-digit zero-padded integer (`10` through `90`) defining execution sequence.
- `app-name`: Application identifier (e.g. `10-vaultwarden.sh`).
- Permissions: `0750`, owned by `root:root`.

### Subcommand Interface

The hook script MUST implement two subcommands:

#### 1. `pre-backup`
- Invoked before Restic snapshots the filesystem.
- Responsibilities:
  - Perform online transactional database snapshot (e.g., `sqlite3 VACUUM INTO`, `pg_dump`, `mysqldump`).
  - Validate database integrity (e.g., `PRAGMA integrity_check; == "ok"`).
  - Place clean snapshot files in `/opt/services/<app-name>/backups/snapshot.*`.
  - Exit `0` on success, or non-zero with error message on `stderr` to abort the backup run.

#### 2. `post-restore`
- Invoked following a disaster recovery restoration of the application data directory.
- Responsibilities:
  - Detect restored snapshot files in `/opt/services/<app-name>/backups/`.
  - Atomically copy/restore the snapshot to the active database path (`db.sqlite3`) if active DB is missing or corrupted.
  - Assert correct ownership (e.g., `chown -R 1000:1000 /opt/services/<app-name>/data`).
  - Set secure permissions (`chmod -R 0700 /opt/services/<app-name>/data`).
  - Exit `0` on success.

---

## 2. Vaultwarden Implementation (`10-vaultwarden.sh`)

```bash
#!/usr/bin/env bash
# /etc/homelab/backup.d/10-vaultwarden.sh
set -euo pipefail

APP_NAME="vaultwarden"
SERVICE_DIR="/opt/services/vaultwarden"
DATA_DIR="$SERVICE_DIR/data"
BACKUP_DIR="$SERVICE_DIR/backups"
SNAPSHOT_PATH="$BACKUP_DIR/snapshot.sqlite3"

ACTION="${1:-pre-backup}"

case "$ACTION" in
    pre-backup)
        mkdir -p "$BACKUP_DIR"
        chmod 0750 "$BACKUP_DIR"

        if [ ! -f "$DATA_DIR/db.sqlite3" ]; then
            echo "WARN: Vaultwarden database not found at $DATA_DIR/db.sqlite3. Skipping dump." >&2
            exit 0
        fi

        rm -f "$SNAPSHOT_PATH"
        if ! sqlite3 "$DATA_DIR/db.sqlite3" "VACUUM INTO '$SNAPSHOT_PATH'"; then
            echo "ERROR: sqlite3 VACUUM INTO failed for Vaultwarden" >&2
            exit 1
        fi

        INTEGRITY=$(sqlite3 "$SNAPSHOT_PATH" "PRAGMA integrity_check;")
        if [ "$INTEGRITY" != "ok" ]; then
            echo "ERROR: Vaultwarden snapshot integrity check failed: $INTEGRITY" >&2
            rm -f "$SNAPSHOT_PATH"
            exit 1
        fi

        chmod 0640 "$SNAPSHOT_PATH"
        echo "Vaultwarden transactional pre-backup snapshot verified ok."
        ;;

    post-restore)
        if [ -f "$SNAPSHOT_PATH" ] && [ ! -f "$DATA_DIR/db.sqlite3" ]; then
            mkdir -p "$DATA_DIR"
            cp "$SNAPSHOT_PATH" "$DATA_DIR/db.sqlite3"
            echo "Restored db.sqlite3 from snapshot."
        fi

        if [ -d "$DATA_DIR" ]; then
            chown -R 1000:1000 "$DATA_DIR"
            chmod 0700 "$DATA_DIR"
            find "$DATA_DIR" -type f -exec chmod 0600 {} +
            echo "Vaultwarden permissions set to 1000:1000 (0700/0600)."
        fi
        ;;

    *)
        echo "Usage: $0 {pre-backup|post-restore}" >&2
        exit 1
        ;;
esac
```
