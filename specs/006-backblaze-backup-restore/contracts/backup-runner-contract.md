# Contract: Backup Runner & Systemd Supervision

**Contract Identifier**: `BACKUP-RUNNER-V1`  
**Target Path**: `/usr/local/bin/homelab-backup`  
**Supervision**: `homelab-backup.service`, `homelab-backup.timer`, `homelab-backup-check.service`, `homelab-backup-check.timer`  

---

## 1. CLI Interface

### Usage
```bash
homelab-backup [COMMAND] [OPTIONS]
```

### Commands

| Command | Description | Default When Omitted |
|---|---|---|
| `run` | Execute pre-backup hooks, run Restic backup to Backblaze B2, and prune retention. | Yes (default action) |
| `check` | Execute repository integrity check (`restic check --read-data-subset=5%`). | No |
| `snapshots` | List current snapshots in the Backblaze B2 repository. | No |
| `prune` | Run `restic forget --keep-daily 7 --keep-weekly 5 --keep-monthly 12 --prune` explicitly. | No |
| `unlock` | Remove stale locks on the Restic repository (`restic unlock`). | No |

### Options

| Flag | Type | Description |
|---|---|---|
| `--dry-run` | boolean | Execute pre-backup hooks and run `restic backup --dry-run` without persisting data. |
| `--verbose` | boolean | Enable detailed Restic transfer logs and verbose output. |
| `--config-file` | path | Path to environment credentials file (Default: `/etc/homelab/backup.env`). |

### Exit Codes
- `0`: Success.
- `1`: Configuration or environment error (missing credentials, unreadable files).
- `2`: Pre-backup hook execution failure (transactional dump or integrity check failed).
- `3`: Restic backup transmission failure (network timeout, authentication failure, bucket error).
- `4`: Post-backup retention pruning failure.
- `5`: Integrity verification check failure (`check` command detected data corruption).

---

## 2. Configuration & Secrets Contract

The backup runner reads its credentials from `/etc/homelab/backup.env`:
```bash
# /etc/homelab/backup.env
# Permissions: 0600 root:root
B2_ACCOUNT_ID="00xxxxxxxxxxxxxxx"
B2_ACCOUNT_KEY="K00xxxxxxxxxxxxxxxxxxxx"
RESTIC_REPOSITORY="b2:my-bucket:homelab2"
RESTIC_PASSWORD="very-strong-restic-encryption-password"
```

### Inclusion Contract (`/etc/homelab/backup-include.txt`)
Lines matching files or directory trees to back up:
```text
/etc/homelab/vault.yml
/etc/homelab/apps
/opt/services
```

### Exclusion Contract (`/etc/homelab/backup-excludes.txt`)
Glob patterns explicitly omitted from snapshots:
```text
*.sqlite3
*.db
*.sqlite3-wal
*.sqlite3-shm
*.sock
*.log
*.tmp
/opt/services/*/backups/vaultwarden-backup-*.tar.gz
```

---

## 3. Systemd Unit Contracts

### 3.1 Backup Service (`homelab-backup.service`)
```ini
[Unit]
Description=Homelab2 Centralized Backblaze B2 Restic Backup
Documentation=file:///docs/roadmap.md
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=root
Group=root
EnvironmentFile=/etc/homelab/backup.env
ExecStart=/usr/local/bin/homelab-backup run
StandardOutput=journal
StandardError=journal
TimeoutSec=900
```

### 3.2 Backup Timer (`homelab-backup.timer`)
```ini
[Unit]
Description=Daily Homelab2 Backblaze B2 Backup Timer
PartOf=homelab-backup.service

[Timer]
OnCalendar=*-*-* 02:30:00
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
```

### 3.3 Check Service (`homelab-backup-check.service`)
```ini
[Unit]
Description=Homelab2 Restic Repository Integrity Check
Documentation=file:///docs/roadmap.md
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=root
Group=root
EnvironmentFile=/etc/homelab/backup.env
ExecStart=/usr/local/bin/homelab-backup check
StandardOutput=journal
StandardError=journal
TimeoutSec=1800
```

### 3.4 Check Timer (`homelab-backup-check.timer`)
```ini
[Unit]
Description=Weekly Homelab2 Restic Repository Integrity Check Timer
PartOf=homelab-backup-check.service

[Timer]
OnCalendar=Sun *-*-* 04:00:00
Persistent=true

[Install]
WantedBy=timers.target
```
