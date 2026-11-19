# Contract: Media & Arr Stage 1 Disaster Recovery & Backup Integration (`ARR-BACKUP-V1`)

**Feature**: `015-media-arr-stage1`  
**Date**: 2026-11-17  
**Requirements Covered**: FR-008, FR-011, SC-005, Principle V

---

## 1. Backup Integration Hook (`/etc/homelab/backup.d/40-arr.sh`)

```bash
#!/usr/bin/env bash
# /etc/homelab/backup.d/40-arr.sh - Media & Arr Stack backup integration hook
# Managed by Ansible - homelab2
# Contract: ARR-BACKUP-V1
set -euo pipefail

APP_NAME="arr"
SERVICE_DIR="{{ arr_service_dir | default('/opt/services/arr') }}"
BACKUP_DIR="{{ arr_backups_dir | default('/opt/services/arr/backups') }}"
CONFIG_ARCHIVE="$BACKUP_DIR/arr-configs-snapshot.tar.gz"

ACTION="${1:-pre-backup}"

case "$ACTION" in
    pre-backup)
        echo "INFO: Starting online SQLite & config backup hook for $APP_NAME..."
        mkdir -p "$BACKUP_DIR"
        chmod 0750 "$BACKUP_DIR"

        if [ ! -f "$SERVICE_DIR/.env" ]; then
            echo "CRITICAL: $APP_NAME .env not found at $SERVICE_DIR/.env" >&2
            exit 1
        fi

        # Clean prior SQLite snapshots before generating fresh point-in-time copies
        rm -f "$BACKUP_DIR"/*.sqlite3 "$BACKUP_DIR"/*.db "$CONFIG_ARCHIVE"

        SNAPSHOT_COUNT=0
        while IFS= read -r -d '' db_file; do
            rel_path="${db_file#"$SERVICE_DIR"/}"
            safe_name="$(echo "$rel_path" | tr '/' '_')"
            snapshot_target="$BACKUP_DIR/${safe_name}.sqlite3"

            if ! sqlite3 "$db_file" "VACUUM INTO '$snapshot_target'"; then
                echo "CRITICAL: sqlite3 VACUUM INTO failed for $db_file" >&2
                rm -f "$snapshot_target"
                exit 1
            fi

            integrity="$(sqlite3 "$snapshot_target" "PRAGMA integrity_check;")"
            if [ "$integrity" != "ok" ]; then
                echo "CRITICAL: $APP_NAME snapshot integrity check failed for $snapshot_target: $integrity" >&2
                rm -f "$snapshot_target"
                exit 1
            fi

            chmod 0640 "$snapshot_target"
            SNAPSHOT_COUNT=$((SNAPSHOT_COUNT + 1))
        done < <(find "$SERVICE_DIR" -mindepth 2 -maxdepth 5 -path "*/config/*" \( -name "*.db" -o -name "*.sqlite3" \) -type f -print0 2>/dev/null)

        # Stage service XML/YAML/JSON/CONF files into a verified archive
        tar -czf "$CONFIG_ARCHIVE" \
            --exclude='*.db' \
            --exclude='*.sqlite3' \
            --exclude='*.db-wal' \
            --exclude='*.db-shm' \
            --exclude='*/cache/*' \
            --exclude='*/metadata/*' \
            --exclude='*/transcodes/*' \
            --exclude='backups/*' \
            -C "$SERVICE_DIR" .
        chmod 0640 "$CONFIG_ARCHIVE"

        echo "INFO: $APP_NAME pre-backup snapshot verified ok ($SNAPSHOT_COUNT SQLite DBs + config archive)."
        ;;

    post-restore)
        echo "INFO: Running post-restore hook for $APP_NAME..."
        if [ -f "$CONFIG_ARCHIVE" ]; then
            tar -xzf "$CONFIG_ARCHIVE" -C "$SERVICE_DIR" --keep-old-files 2>/dev/null || true
        fi

        for snapshot_file in "$BACKUP_DIR"/*.sqlite3; do
            [ -e "$snapshot_file" ] || continue
            base_name="$(basename "$snapshot_file" .sqlite3)"
            # Restore Jellyfin core databases if missing
            if [ "$base_name" = "jellyfin_config_data_jellyfin.db" ] && [ ! -f "$SERVICE_DIR/jellyfin/config/data/jellyfin.db" ]; then
                mkdir -p "$SERVICE_DIR/jellyfin/config/data"
                cp "$snapshot_file" "$SERVICE_DIR/jellyfin/config/data/jellyfin.db"
            elif [ "$base_name" = "jellyfin_config_data_library.db" ] && [ ! -f "$SERVICE_DIR/jellyfin/config/data/library.db" ]; then
                mkdir -p "$SERVICE_DIR/jellyfin/config/data"
                cp "$snapshot_file" "$SERVICE_DIR/jellyfin/config/data/library.db"
            fi
        done

        if [ -f "$SERVICE_DIR/.env" ]; then
            chmod 0600 "$SERVICE_DIR/.env"
        fi
        if [ -d "$SERVICE_DIR/vpn/config" ]; then
            chmod 0700 "$SERVICE_DIR/vpn/config"
            chown -R root:root "$SERVICE_DIR/vpn" 2>/dev/null || true
        fi
        chown -R 1000:1001 "$SERVICE_DIR"/{gluetun,qbittorrent,jellyfin,ersatztv,jellyseerr,prowlarr,radarr,sonarr} 2>/dev/null || true
        echo "INFO: $APP_NAME post-restore verification completed."
        ;;

    *)
        echo "Usage: $0 {pre-backup|post-restore}" >&2
        exit 1
        ;;
esac
```

---

## 2. Restic Backup Selection & Exclusion Rules

### Included Paths (Captured by Restic to Backblaze B2 via `/opt/services`)
1. `/opt/services/arr/compose.yml`, `/opt/services/arr/.env` (`0600`), and `/opt/services/arr/vpn/{killswitch,healthcheck}.sh`
2. `/opt/services/arr/backups/*.sqlite3` & `arr-configs-snapshot.tar.gz`
3. `/opt/services/arr/{vpn,gluetun,qbittorrent,jellyfin,ersatztv,jellyseerr,prowlarr,radarr,sonarr}/config` (XML/CONF/JSON/YAML/state configuration files)

### Excluded Patterns (`/etc/homelab/backup-excludes.txt`)
1. `/mnt/scratch` & `/mnt/scratch/**` (Tier 2 incomplete torrent downloads)
2. `/mnt/storage/downloads/**` (Tier 1 completed torrent downloads)
3. `/mnt/storage/media/movies/**` & `/mnt/storage/media/tv/**` (Bulk movie and TV libraries)
4. `/opt/services/arr/*/config/**/*.db` & `*.sqlite3` (Live mutated SQLite files; captured via `backups/*.sqlite3` snapshots)
5. `/opt/services/arr/jellyfin/config/cache/**`, `/opt/services/arr/jellyfin/config/metadata/**`, and `/opt/services/arr/jellyfin/config/transcodes/**` (Regenerable Jellyfin caches and transcode scratch)
