# Contract: Frigate Transactional Backup & Scratch Exclusion (`FRIGATE-BACKUP-V1`)

**Feature**: `009-frigate-nvr-setup`  
**Date**: 2026-11-04  
**Requirements Covered**: FR-006, FR-007, FR-011, SC-004, Constitution Principle V

---

## 1. Per-Application Backup Hook (`/etc/homelab/backup.d/20-frigate.sh`)

Follows the `APP-BACKUP-V1` contract invoked automatically by `/usr/local/bin/homelab-backup` prior to each Restic snapshot and after disaster recovery restoration.

### CLI Interface

```text
/etc/homelab/backup.d/20-frigate.sh {pre-backup|post-restore}
```

### `pre-backup` Behavior
1. Ensures `/opt/services/frigate/backups` exists with mode `0750`.
2. Checks if `/opt/services/frigate/config/frigate.db` exists:
   - If the database does not exist yet, logs a warning to stderr and exits `0`.
   - If present, removes any stale `/opt/services/frigate/backups/snapshot.sqlite3` and executes an online atomic snapshot:
     ```bash
     sqlite3 /opt/services/frigate/config/frigate.db "VACUUM INTO '/opt/services/frigate/backups/snapshot.sqlite3'"
     ```
3. Verifies snapshot integrity:
   ```bash
   sqlite3 /opt/services/frigate/backups/snapshot.sqlite3 "PRAGMA integrity_check;"
   ```
   - Must return `"ok"`. If not `"ok"`, deletes the corrupt snapshot and exits non-zero (`1`), halting the backup run with a clear error message.
4. Sets `/opt/services/frigate/backups/snapshot.sqlite3` permissions to `0640`.

### `post-restore` Behavior
1. If `/opt/services/frigate/backups/snapshot.sqlite3` exists and `/opt/services/frigate/config/frigate.db` is absent, copies `snapshot.sqlite3` to `/opt/services/frigate/config/frigate.db`.
2. Ensures `/opt/services/frigate/.env` has `0600` permissions and `/opt/services/frigate/config` is readable/writable by the Frigate service.

---

## 2. Restic Inclusion & Exclusion Contract (`/etc/homelab/backup-include.txt` & `backup-excludes.txt`)

### Included Paths (`/etc/homelab/backup-include.txt`)
- `/etc/homelab/vault.yml` (captures Ansible secret variables including Frigate RTSP URLs)
- `/etc/homelab/apps`
- `/opt/services` (captures `/opt/services/frigate/compose.yml`, `/opt/services/frigate/.env`, `/opt/services/frigate/config/config.yml`, and `/opt/services/frigate/backups/snapshot.sqlite3`)

### Excluded Patterns (`/etc/homelab/backup-excludes.txt`)
- `/opt/services/*/config/*.db` (live SQLite database file; backed up via `snapshot.sqlite3`)
- `*.db-wal`
- `*.db-shm`
- `/opt/services/frigate/config/model_cache` (regenerable OpenVINO compiled model kernels)
- `/mnt/scratch`
- `/mnt/scratch/**` (defense-in-depth guarantee that 0 bytes of raw CCTV footage are ever transmitted to Backblaze B2)
