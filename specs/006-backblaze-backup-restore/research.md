# Research & Architecture Decisions: Centralized Backblaze B2 Backup & Automated Disaster Recovery

**Feature**: `006-backblaze-backup-restore`  
**Status**: Completed  
**Author**: Antigravity Assistant  

---

## 1. Restic & Backblaze B2 Integration

### Decision
Use **Restic** (`restic` on Arch Linux) with native Backblaze B2 API integration (`b2:<bucket-name>:<subpath>`), authenticating via `B2_ACCOUNT_ID` and `B2_ACCOUNT_KEY` environment variables, and encrypting with AES-256 / Poly1305 via `RESTIC_PASSWORD`.

### Rationale
- Restic has first-class native B2 support without requiring external S3 gateway tools or MinIO intermediaries.
- Native B2 integration handles large file chunking, b2 retry logic, and concurrent uploads efficiently over standard HTTPS.
- Client-side encryption ensures Backblaze B2 only ever receives ciphertext blocks. Zero plaintext or unencrypted metadata is exposed off-host.
- Restic is lightweight, statically compilable in Go, has no external runtime daemon requirements, and fits Constitution Principle I (Minimalist Footprint) and Principle V (Disaster Recovery & Backup by Design).

### Alternatives Considered
- **BorgBackup**: Excellent deduplication, but lacks native cloud object store support (requires SSH target, BorgBase, or rclone pipes).
- **Rclone + Borg / Rclone directly**: Rclone sync lacks cryptographic snapshotting and atomic versioned rollbacks unless layered on top of another tool.
- **Kopia**: Good architecture, but Restic has broader adoption, more mature system package availability in Arch Linux core/extra repos, and simpler CLI scripting contracts.

---

## 2. Prevention of Torn SQLite Database Images & Atomic Pre-Backup Hooks

### Decision
Implement a decoupled pre-backup hook architecture in `/etc/homelab/backup.d/`. For SQLite-backed services (e.g., Vaultwarden), the hook performs an atomic online snapshot using `sqlite3 "$DATA_DIR/db.sqlite3" "VACUUM INTO '$SNAPSHOT_PATH'"` and validates data integrity via `sqlite3 "$SNAPSHOT_PATH" "PRAGMA integrity_check;" == "ok"`. Live database files (`*.sqlite3`, `*.db`, `*.sqlite3-wal`, `*.sqlite3-shm`) are explicitly excluded from Restic via an exclude file (`/etc/homelab/backup-excludes.txt`).

### Rationale
- Directly backing up an active SQLite database with WAL mode running causes corrupted or "torn" snapshots if a transaction is committed mid-read.
- SQLite's `VACUUM INTO` creates a clean, transactionally consistent, defragmented database file safely while the live container continues to process queries.
- Verifying `PRAGMA integrity_check;` before snapshot archiving guarantees that corrupted source data will not overwrite healthy offsite backups.
- Excluding live database files globally prevents unintentional capture of uncoordinated database files across future Phase 5 services.

### Alternatives Considered
- **Container Stop / Start**: Stopping containers during backup introduces service downtime and disrupts client synchronizations.
- **SQLite `.backup` CLI command**: `VACUUM INTO` is faster, produces a compacted single-file database, and is native in modern SQLite (3.27+).
- **Filesystem LVM / Btrfs snapshots**: Host filesystem is standard Ext4 on NVMe; filesystem snapshots would require LVM/ZFS/Btrfs overhead which was intentionally avoided in Phase 1 & 4.

---

## 3. Secret Management & Disaster Recovery Bootstrapping

### Decision
Store the 4 bootstrap master credentials:
1. `vault_b2_account_id` (B2 Application Key ID)
2. `vault_b2_account_key` (B2 Application Key)
3. `vault_restic_repository` (e.g. `b2:homelab2-backup:node01`)
4. `vault_restic_password` (Restic encryption passphrase)

in the uncommitted, gitignored file `ansible/inventory/group_vars/all/vault.yml`. On the target server, deploy these credentials into `/etc/homelab/backup.env` (permissions `0600 root:root`) and deploy the full host secrets into `/etc/homelab/vault.yml` (`0600 root:root`). Include `/etc/homelab/vault.yml` and `/etc/homelab/apps/*.env` in the Restic backup paths.

Provide a standalone disaster recovery script `scripts/restore-from-b2.sh` (and workstation companion `scripts/restore-from-b2.ps1`) that takes these 4 credentials as arguments or environment variables and reconstructs the filesystem.

### Rationale
- Completely eliminates encrypted blobs and plaintext credentials from git (Constitutional Principle IV: Zero Secrets in Version Control).
- A disaster recovery operator only needs the git repository and these 4 bootstrap credentials to restore every secret, token, and application database across the homelab.
- Once `restore-from-b2.sh` runs, `/etc/homelab/vault.yml` is recovered, enabling subsequent Ansible runs (`apply-phase5.ps1`) to succeed with zero manual credential re-entry.

### Alternatives Considered
- **SOPS/Age encrypted file in Git**: Prohibited by ratified Constitution v1.3.0 Principle IV (Zero Secrets in Version Control & Isolated Configuration).
- **Manual secret re-entry post-disaster**: Highly error-prone and violates automated disaster recovery (Principle V).

---

## 4. Standardized Per-App Backup Onboarding Contract

### Decision
Establish an app backup contract consisting of:
1. **Hook Directory**: `/etc/homelab/backup.d/` containing executable scripts named `<order>-<app>.sh` (e.g., `10-vaultwarden.sh`).
2. **Hook Interface**:
   - `pre-backup`: Run transactional database dumps or pre-freeze routines. Place snapshots in `/opt/services/<app>/backups/snapshot.*`. Exit 0 on success.
   - `post-restore`: Restore snapshot to active data directory if needed, correct file ownership (e.g., `1000:1000`), and restart service containers.
3. **Inclusion Manifest**: `/etc/homelab/backup-include.txt` managed by Ansible, containing:
   ```text
   /etc/homelab/vault.yml
   /etc/homelab/apps
   /opt/services
   ```
4. **Exclusion Manifest**: `/etc/homelab/backup-excludes.txt` managed by Ansible, containing:
   ```text
   *.sqlite3
   *.db
   *.sqlite3-wal
   *.sqlite3-shm
   *.sock
   *.log
   /opt/services/*/backups/vaultwarden-backup-*.tar.gz
   ```

### Rationale
- Decouples individual applications from the centralized backup orchestrator.
- New applications (Phase 5 Home Assistant, Immich, Mealie) simply drop a shell hook into `/etc/homelab/backup.d/` and their persistent directory under `/opt/services/<app>`.
- Preserves modularity (Principle VI) and single-responsibility scripts (Principle I).

### Alternatives Considered
- **Monolithic backup script with hardcoded app logic**: Becomes brittle and unmaintainable as new applications are added.
- **Container labels / Docker backup sidecars**: Requires background sidecar containers consuming memory and system resources for simple periodic tasks (violates Minimalist Footprint).

---

## 5. Retention Pruning & Integrity Check Scheduling

### Decision
Implement two independent systemd timers:
1. `homelab-backup.timer`:
   - Runs daily at `02:30:00` with `Persistent=true`.
   - Triggers `homelab-backup.service` (`/usr/local/bin/homelab-backup`).
   - Executes pre-backup hooks, runs `restic backup`, and runs `restic forget --keep-daily 7 --keep-weekly 5 --keep-monthly 12 --prune`.
2. `homelab-backup-check.timer`:
   - Runs weekly on Sundays at `04:00:00` with `Persistent=true`.
   - Triggers `homelab-backup-check.service` (`/usr/local/bin/homelab-backup check`).
   - Executes `restic check --read-data-subset=5%` to verify repository integrity and pack file hashes without excessive egress costs.

### Rationale
- Pruning immediately after backup reclaims space and bounds Backblaze B2 storage costs.
- The 7-daily, 5-weekly, 12-monthly retention policy provides 1 year of recovery history with minimal deduplicated storage overhead.
- Running a 5% data subset check weekly catches bitrot or corrupted packs early without downloading the entire repository, conserving network bandwidth and B2 Class B API / download costs.

### Alternatives Considered
- **Pruning in a separate weekly job**: Leaves unreferenced blobs accumulating for days.
- **Full repository check (`--read-data`) weekly**: Would download 100% of repository data each week, incurring excessive cloud egress fees.

---

## 6. Disaster Recovery & Remote Verification Tooling

### Decision
Provide two operator-facing toolsets:
1. **Disaster Recovery Restore**:
   - `scripts/restore-from-b2.sh`: Standalone Bash script runnable on bare metal or VM with curl/restic. Restores files to `/` or custom target `--target-dir <path>`, safeguards existing files unless `--force`, validates checksums, and restores permissions.
   - `scripts/restore-from-b2.ps1`: Workstation PowerShell wrapper to run the restore remotely via SSH or locally.
2. **Acceptance Verification**:
   - `scripts/verify-phase5-backup.sh`: Server-side bash test runner with 8 automated assertions.
   - `scripts/verify-phase5-backup.ps1`: Workstation PowerShell test runner executing verification against `admin@192.168.4.57`.
   - `ansible/playbooks/verify-phase5-backup.yml`: Ansible playbook test suite integrated into `ansible/playbooks/verify.yml`.

### Rationale
- Fulfills Constitution Principle III (Automated Verification & Acceptance Gates) and FR-011 / FR-012.
- Enables continuous CI/CD or operator-driven verification of offsite backup posture.
