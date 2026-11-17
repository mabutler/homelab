# Contract: Staged Backup & Disaster Recovery Verification

**Contract Identifier**: `BACKUP-VERIFICATION-V2` (extends `BACKUP-VERIFICATION-V1`)  
**Test Runners**:
- `scripts/verify-phase5-backup.sh`
- `scripts/verify-phase5-backup.ps1`
- `ansible/playbooks/verify-phase5-backup.yml`
**Target Host**: `admin@192.168.4.57` (`fidelacchius`)

---

## 1. Acceptance Assertions Matrix (`BK-001` through `BK-012`)

The verification suite preserves all 8 foundational backup assertions (`BK-001` through `BK-008`) and adds 4 staged disaster recovery assertions (`BK-009` through `BK-012`).

| ID | Assertion Name | Command / Check | Pass Criteria | Constitutional Basis |
|---|---|---|---|---|
| **BK-001** | Restic Binary Installed | `command -v restic && restic version` | Exit code `0` | Principle I |
| **BK-002** | Backup Environment Permissions | `stat -c "%a %U:%G" /etc/homelab/backup.env` | Exact match `600 root:root` | Principle IV |
| **BK-003** | B2 Cloud Repository Target & Connectivity | `restic -r "$RESTIC_REPOSITORY" snapshots --json` | Target is `b2:fidelacchius-backups:fidelacchius` and exit code `0` | Principle V |
| **BK-004** | Secret File Included in Snapshot | `restic -r "$RESTIC_REPOSITORY" ls latest \| grep -E '(^\|/)etc/homelab/vault\.yml'` | Exit code `0` | Principle IV & V |
| **BK-005** | Live DB Excluded from Snapshot | `! restic -r "$RESTIC_REPOSITORY" ls latest \| grep -E 'db\.sqlite3$'` | Exit code `0` (no live SQLite files) | Principle V |
| **BK-006** | Pre-Backup Hook & Snapshot Verified | `/usr/local/bin/homelab-backup run --dry-run` | Exit code `0` | Principle III & V |
| **BK-007** | Automated Timers Active | `systemctl is-active homelab-backup.timer homelab-backup-check.timer` | Both timers `active` | Principle V |
| **BK-008** | Non-Destructive Restore Viability | `restore-from-b2.sh --target-dir /tmp/b2-test-restore --include-path etc/homelab/vault.yml --force` | Exit code `0` & SHA-256 matches `/etc/homelab/vault.yml` | Principle V |
| **BK-009** | Stage 1 Dry-Run Path Filtering | `restore-from-b2.sh --stage config --dry-run` | Exit code `0`, output includes `/etc/homelab/vault.yml` and excludes `/mnt/storage` | Principle V & VI |
| **BK-010** | Stage 2 Unmounted Storage Guard | `restore-from-b2.sh --stage data --target-dir /tmp/b2-unmounted-test --force` | Exit code `1` (non-zero) and stderr contains `CRITICAL` mountpoint error | Principle II & VI |
| **BK-011** | Invalid Stage Argument Rejection | `restore-from-b2.sh --stage invalid --dry-run` | Exit code `1` (non-zero) | Principle II |
| **BK-012** | Stage 1 Non-Destructive Bootstrap Restore | `restore-from-b2.sh --stage 1 --target-dir /tmp/b2-stage1-test --include-path etc/homelab/vault.yml --force` | Exit code `0`, `vault.yml` restored with mode `600`, `/tmp/b2-stage1-test/mnt/storage` does not exist | Principle IV, V & VI |

---

## 2. JSON Output Schema (`--json`)

When `scripts/verify-phase5-backup.sh --json` is executed, it emits structured JSON to `stdout`:

```json
{
  "timestamp": "2026-11-10T12:00:00-05:00",
  "feature": "014-staged-b2-restore",
  "target": "fidelacchius",
  "summary": {
    "total": 13,
    "passed": 13,
    "failed": 0,
    "duration_ms": 6500
  },
  "assertions": [
    {"id": "BK-001", "name": "Restic Binary Installed", "status": "PASS", "duration_ms": 15},
    {"id": "BK-002", "name": "Backup Environment Permissions", "status": "PASS", "duration_ms": 5},
    {"id": "BK-003", "name": "B2 Cloud Repository Target (fidelacchius-backups)", "status": "PASS", "duration_ms": 4},
    {"id": "BK-003-CONN", "name": "B2 Cloud Repository Connectivity", "status": "PASS", "duration_ms": 980},
    {"id": "BK-004", "name": "Secret File Included in Snapshot", "status": "PASS", "duration_ms": 840},
    {"id": "BK-005", "name": "Live DB Excluded from Snapshot", "status": "PASS", "duration_ms": 820},
    {"id": "BK-006", "name": "Pre-Backup Hook & Snapshot Verified", "status": "PASS", "duration_ms": 1400},
    {"id": "BK-007", "name": "Automated Timers Active", "status": "PASS", "duration_ms": 12},
    {"id": "BK-008", "name": "Non-Destructive Restore Viability", "status": "PASS", "duration_ms": 910},
    {"id": "BK-009", "name": "Stage 1 Dry-Run Path Filtering", "status": "PASS", "duration_ms": 860},
    {"id": "BK-010", "name": "Stage 2 Unmounted Storage Guard", "status": "PASS", "duration_ms": 810},
    {"id": "BK-011", "name": "Invalid Stage Argument Rejection", "status": "PASS", "duration_ms": 8},
    {"id": "BK-012", "name": "Stage 1 Non-Destructive Bootstrap Restore", "status": "PASS", "duration_ms": 920}
  ]
}
```
