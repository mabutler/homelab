# Contract: Immich Disaster Recovery & Backup Integration (`IMMICH-BACKUP-V1`)

**Feature**: `013-immich-setup`  
**Date**: 2026-11-06  
**Requirements Covered**: FR-007, Principle V

---

## 1. Backup Integration Hook (`/etc/homelab/backup.d/30-immich.sh`)

```bash
#!/usr/bin/env bash
# /etc/homelab/backup.d/30-immich.sh - Immich backup integration hook
# Managed by Ansible - homelab2
# Contract: IMMICH-BACKUP-V1
set -euo pipefail

APP_NAME="immich"
SERVICE_DIR="/opt/services/immich"
BACKUP_DIR="$SERVICE_DIR/backups"
DUMP_FILENAME="immich_db_backup.dump"
SNAPSHOT_PATH="$BACKUP_DIR/$DUMP_FILENAME"

ACTION="${1:-pre-backup}"

case "$ACTION" in
    pre-backup)
        mkdir -p "$BACKUP_DIR"
        chmod 0750 "$BACKUP_DIR"

        if [ ! -f "$SERVICE_DIR/.env" ]; then
            echo "ERROR: $APP_NAME .env not found at $SERVICE_DIR/.env" >&2
            exit 1
        fi

        # Source DB credentials from .env
        DB_USER=$(grep -E '^DB_USERNAME=' "$SERVICE_DIR/.env" | cut -d '=' -f2- || echo "immich")
        DB_NAME=$(grep -E '^DB_DATABASE_NAME=' "$SERVICE_DIR/.env" | cut -d '=' -f2- || echo "immich")

        echo "Generating transactional PostgreSQL dump for $APP_NAME..."
        rm -f "$SNAPSHOT_PATH"

        # Execute pg_dump inside immich_postgres container
        if ! docker compose -f "$SERVICE_DIR/compose.yml" exec -T database \
            pg_dump -U "$DB_USER" -d "$DB_NAME" --clean --if-exists --format=custom -f "/backups/$DUMP_FILENAME"; then
            echo "ERROR: pg_dump failed for $APP_NAME" >&2
            exit 1
        fi

        # Validate non-empty dump
        if [ ! -s "$SNAPSHOT_PATH" ]; then
            echo "ERROR: $APP_NAME dump file is empty or missing: $SNAPSHOT_PATH" >&2
            rm -f "$SNAPSHOT_PATH"
            exit 1
        fi

        chmod 0640 "$SNAPSHOT_PATH"
        DUMP_SIZE=$(stat -c%s "$SNAPSHOT_PATH")
        echo "$APP_NAME pre-backup dump verified ok ($DUMP_SIZE bytes)."
        ;;

    post-restore)
        if [ ! -f "$SNAPSHOT_PATH" ]; then
            echo "WARN: $APP_NAME snapshot not found at $SNAPSHOT_PATH. Skipping DB restore." >&2
            exit 0
        fi

        DB_USER=$(grep -E '^DB_USERNAME=' "$SERVICE_DIR/.env" | cut -d '=' -f2- || echo "immich")
        DB_NAME=$(grep -E '^DB_DATABASE_NAME=' "$SERVICE_DIR/.env" | cut -d '=' -f2- || echo "immich")

        echo "Restoring $APP_NAME database from snapshot..."
        docker compose -f "$SERVICE_DIR/compose.yml" exec -T database \
            pg_restore -U "$DB_USER" -d "$DB_NAME" --clean --if-exists "/backups/$DUMP_FILENAME" || true

        if [ -f "$SERVICE_DIR/.env" ]; then
            chmod 0600 "$SERVICE_DIR/.env"
        fi
        echo "$APP_NAME post-restore verification completed."
        ;;

    *)
        echo "Usage: $0 {pre-backup|post-restore}" >&2
        exit 1
        ;;
esac
```

---

## 2. Restic Backup Selection Rules

### Included Paths (Captured by Restic to Backblaze B2)
1. `/opt/services/immich`:
   - `compose.yml`
   - `.env`
   - `backups/immich_db_backup.dump` (Transactional database snapshot with vector embeddings)
   - `data/profile` (User profile images)
2. `/mnt/storage/media/photos/library`:
   - Primary full-resolution photos, videos, and Live Photo assets

### Excluded Patterns (Excluded from Offsite Backup to Prevent Bloat)
1. `/opt/services/immich/data/postgres/**` (Live database cluster files excluded; captured via dump)
2. `/opt/services/immich/data/thumbs/**` (Pre-generated thumbnails; regenerable)
3. `/opt/services/immich/data/model-cache/**` (Cached ML weights; redownloadable)
4. `/mnt/storage/media/photos/upload/**` (Transient upload chunks)
5. `/mnt/storage/media/photos/encoded-video/**` (Transcoded web video streaming cache; regenerable)
