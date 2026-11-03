# Contract: Transactional Backup & Restoration Specification

**Feature**: `005-vaultwarden-app` | **Date**: 2026-11-01

This contract defines the execution interface, behavior, file layout, and recovery guarantees for the Vaultwarden transactional backup and disaster recovery automation.

---

## 1. Backup Routine Contract (`backup.sh`)

### CLI Interface
```bash
/opt/services/vaultwarden/scripts/backup.sh [--retention-days <days>] [--force]
```

### Exit Codes
- `0`: Backup completed successfully, SQLite integrity verified, archive created, and expired backups pruned.
- `1`: Preconditions failed (e.g. data directory missing, insufficient disk space).
- `2`: Transactional SQLite snapshot failed.
- `3`: Integrity check failed (`PRAGMA integrity_check;` returned non-`ok`).
- `4`: Packaging or archive compression failed.

### Operational Sequence
1. **Pre-flight Checks**:
   - Verify existence of `/opt/services/vaultwarden/data/db.sqlite3`.
   - Ensure staging directory `/opt/services/vaultwarden/backups` exists with mode `0750`.
2. **Transactional Database Snapshot**:
   - Execute SQLite `VACUUM INTO`:
     ```bash
     sqlite3 /opt/services/vaultwarden/data/db.sqlite3 "VACUUM INTO '/opt/services/vaultwarden/backups/snapshot.sqlite3'"
     ```
   - *Guarantee*: Service remains 100% online; concurrent reads and writes continue uninterrupted.
3. **Automated Integrity Verification**:
   - Execute integrity check on snapshot:
     ```bash
     CHECK_RESULT=$(sqlite3 /opt/services/vaultwarden/backups/snapshot.sqlite3 "PRAGMA integrity_check;")
     if [ "$CHECK_RESULT" != "ok" ]; then
         echo "ERROR: Backup integrity check failed: $CHECK_RESULT" >&2
         rm -f /opt/services/vaultwarden/backups/snapshot.sqlite3
         exit 3
     fi
     ```
4. **Archive Packaging**:
   - Create dated tarball containing the verified database snapshot, RSA keys, and attachments:
     ```bash
     tar -czf /opt/services/vaultwarden/backups/vaultwarden-backup-$(date +%Y%m%d-%H%M%S).tar.gz \
       -C /opt/services/vaultwarden/backups snapshot.sqlite3 \
       -C /opt/services/vaultwarden data/attachments data/rsa_key.*
     rm -f /opt/services/vaultwarden/backups/snapshot.sqlite3
     ```
5. **Retention Pruning**:
   - Remove archives older than configured retention period (default: 30 days):
     ```bash
     find /opt/services/vaultwarden/backups -name "vaultwarden-backup-*.tar.gz" -type f -mtime +30 -delete
     ```

---

## 2. Systemd Automation Contract

Scheduled via standard systemd timer units:
- Unit: `/etc/systemd/system/vaultwarden-backup.service`
- Timer: `/etc/systemd/system/vaultwarden-backup.timer`
- Default Schedule: Daily at 03:30 AM (`OnCalendar=*-*-* 03:30:00`), `Persistent=true`.

---

## 3. Disaster Recovery & Restore Contract (`restore.sh`)

### CLI Interface
```bash
/opt/services/vaultwarden/scripts/restore.sh <path-to-backup-tarball> [--force]
```

### Operational Sequence
1. **Safety Confirmation**: Unless `--force` is supplied, prompt administrator for explicit confirmation before touching live data.
2. **Service Stop**: Stop the container service cleanly: `systemctl stop vaultwarden.service`.
3. **Data Evacuation**: Move current `/opt/services/vaultwarden/data` to `/opt/services/vaultwarden/data.broken.<timestamp>` for rollback safety.
4. **Archive Extraction**:
   - Untar the backup tarball to restore `db.sqlite3`, `rsa_key.*`, and `attachments/`.
5. **Ownership & Permissions Enforcement**:
   - Ensure permissions are strictly `chown -R 1000:1000 /opt/services/vaultwarden/data` and `chmod 0750`.
6. **Service Start & Verification**:
   - Start the container service: `systemctl start vaultwarden.service`.
   - Wait up to 30s for `http://127.0.0.1:8088/alive` to respond HTTP 200.
