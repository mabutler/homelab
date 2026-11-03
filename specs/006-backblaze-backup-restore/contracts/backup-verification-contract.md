# Contract: Automated Backup Acceptance Verification

**Contract Identifier**: `BACKUP-VERIFICATION-V1`  
**Test Runners**: `scripts/verify-phase5-backup.sh`, `scripts/verify-phase5-backup.ps1`, `ansible/playbooks/verify-phase5-backup.yml`  
**Target Host**: `admin@192.168.4.57` (`homelab2`)  

---

## 1. Acceptance Assertions

The backup verification suite executes 8 automated checks across host configuration, Backblaze B2 repository connectivity, snapshot content verification, live database exclusion, and restore viability.

| # | Check Name | Target / Command | Pass Criteria | Constitutional Rationale |
|---|---|---|---|---|
| **BK-001** | Restic Binary Installed | `command -v restic` | Exit code 0, version >= 0.16.0 | Principle I |
| **BK-002** | Backup Environment Permissions | `stat -c "%a %U:%G" /etc/homelab/backup.env` | Exact match: `600 root:root` | Principle IV |
| **BK-003** | B2 Cloud Repository Connectivity | `restic -r "$RESTIC_REPOSITORY" snapshots --json` | Exit code 0, valid JSON returned | Principle V |
| **BK-004** | Secret File Included in Snapshot | `restic -r "$RESTIC_REPOSITORY" ls latest etc/homelab/vault.yml` | Exit code 0, file present in snapshot index | Principle IV & V |
| **BK-005** | Live DB Excluded from Snapshot | `restic -r "$RESTIC_REPOSITORY" ls latest \| grep -E 'db\.sqlite3$'` | Exit code 1 (no live `db.sqlite3` in snapshot paths) | Principle V |
| **BK-006** | Pre-Backup Hook & Snapshot Verified | `/usr/local/bin/homelab-backup run --dry-run` | Exit code 0, snapshot integrity check passes | Principle III & V |
| **BK-007** | Automated Timers Active | `systemctl is-active homelab-backup.timer homelab-backup-check.timer` | Both timers report `active` | Principle V |
| **BK-008** | Non-Destructive Restore Viability | `./scripts/restore-from-b2.sh --target-dir /tmp/b2-test-restore --include-path etc/homelab/vault.yml --force` | Exit code 0, restored file checksum matches `/etc/homelab/vault.yml` | Principle V |

---

## 2. Test Runner Schema & Output

### JSON Report Format
When invoked with `--json`, `scripts/verify-phase5-backup.sh` outputs:
```json
{
  "timestamp": "2026-11-02T21:00:00Z",
  "feature": "006-backblaze-backup-restore",
  "target": "homelab2",
  "summary": {
    "total": 8,
    "passed": 8,
    "failed": 0,
    "duration_ms": 4200
  },
  "assertions": [
    {"id": "BK-001", "name": "Restic Binary Installed", "status": "PASS", "duration_ms": 12},
    {"id": "BK-002", "name": "Backup Environment Permissions", "status": "PASS", "duration_ms": 8},
    {"id": "BK-003", "name": "B2 Cloud Repository Connectivity", "status": "PASS", "duration_ms": 1240},
    {"id": "BK-004", "name": "Secret File Included in Snapshot", "status": "PASS", "duration_ms": 850},
    {"id": "BK-005", "name": "Live DB Excluded from Snapshot", "status": "PASS", "duration_ms": 420},
    {"id": "BK-006", "name": "Pre-Backup Hook & Snapshot Verified", "status": "PASS", "duration_ms": 950},
    {"id": "BK-007", "name": "Automated Timers Active", "status": "PASS", "duration_ms": 15},
    {"id": "BK-008", "name": "Non-Destructive Restore Viability", "status": "PASS", "duration_ms": 705}
  ]
}
```
