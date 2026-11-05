# Contract: Backblaze B2 & Restic Offsite Backup Repository

**Contract ID**: `BACKUP-REPOSITORY-V1`  
**Feature**: `010-fidelacchius-system-rename`  
**Status**: Active  

---

## 1. Storage Repository Target

### 1.1 Cloud Target URI
- **Cloud Provider**: Backblaze B2 (native B2 API via Restic backend)
- **Bucket Name**: `fidelacchius-backups`
- **Sub-repository Path**: `fidelacchius`
- **Full Restic Repository String**: `b2:fidelacchius-backups:fidelacchius`

### 1.2 Environment File (`/etc/homelab/backup.env`)
The backup runner environment file MUST specify:
```ini
B2_ACCOUNT_ID="<B2_KEY_ID>"
B2_ACCOUNT_KEY="<B2_APPLICATION_KEY>"
RESTIC_REPOSITORY="b2:fidelacchius-backups:fidelacchius"
RESTIC_PASSWORD="<CLIENT_SIDE_ENCRYPTION_PASSPHRASE>"
```
- **File Permissions**: `0600`
- **Ownership**: `root:root`

---

## 2. Backup Execution Contract

### 2.1 Runner CLI
- **Runner Path**: `/usr/local/bin/homelab-backup`
- **Execution Command**: `/usr/local/bin/homelab-backup run`
- **Dry-run Command**: `/usr/local/bin/homelab-backup run --dry-run`
- **Tags Applied**: `--tag fidelacchius --tag daily` (or `--tag homelab2 --tag daily`)

### 2.2 Critical Data Inclusions
Snapshots committed to `b2:fidelacchius-backups:fidelacchius` MUST include:
- `/etc/homelab/vault.yml` (Gitignored host secrets)
- `/opt/services/vaultwarden/backups/` (SQLite transactional dumps)
- Any registered pre-backup hook dumps in `/etc/homelab/backup.d/`

---

## 3. Disaster Recovery Restoration Contract

- **Restoration Tool**: `/usr/local/bin/restore-from-b2.sh` (or `scripts/restore-from-b2.sh`)
- **Restoration Test Command**:
  ```bash
  /usr/local/bin/restore-from-b2.sh --target-dir /tmp/b2-test-restore --include-path etc/homelab/vault.yml --force
  ```
- **Integrity Requirement**:
  The restored `/tmp/b2-test-restore/etc/homelab/vault.yml` MUST produce an identical SHA256 checksum to the live `/etc/homelab/vault.yml`.
