# Contract: Staged Disaster Recovery Restoration CLI

**Contract Identifier**: `STAGED-DISASTER-RECOVERY-V2` (supersedes `DISASTER-RECOVERY-V1`)  
**Target Scripts**:
- `scripts/restore-from-b2.sh` (POSIX / Arch Linux Target Host)
- `ansible/roles/backup/files/restore-from-b2.sh` (Deployed to `/usr/local/bin/restore-from-b2.sh`)
- `scripts/restore-from-b2.ps1` (Windows Workstation SSH Orchestrator)

---

## 1. CLI Synopsis

### Linux Target Host (`restore-from-b2.sh`)
```bash
./scripts/restore-from-b2.sh [OPTIONS]
```

### Windows Operator Workstation (`restore-from-b2.ps1`)
```powershell
./scripts/restore-from-b2.ps1 [-HostAddress <IP>] [-User <user>] [-Stage <config|1|data|2|all>] [OPTIONS]
```

---

## 2. Parameters & Flags

| Bash Flag | PowerShell Parameter | Allowed Values | Default | Description |
|---|---|---|---|---|
| `--stage` | `-Stage` | `config`, `1`, `data`, `2`, `all` (case-insensitive) | `all` | Selects the restoration stage: Stage 1 (`config`/`1`), Stage 2 (`data`/`2`), or unified (`all`). |
| `--account-id` | `-AccountId` | Non-empty string | `$B2_ACCOUNT_ID` | Backblaze B2 Application Key ID. |
| `--account-key` | `-AccountKey` | Non-empty string | `$B2_ACCOUNT_KEY` | Backblaze B2 Application Key secret. |
| `--repository` | `-Repository` | `b2:<bucket>:<path>` | `$RESTIC_REPOSITORY` | Restic repository URI. |
| `--password` | `-Password` | Non-empty string | `$RESTIC_PASSWORD` | Restic encryption passphrase. |
| `--snapshot` | `-Snapshot` | Snapshot ID or `latest` | `latest` | Snapshot identifier to restore. |
| `--target-dir` | `-TargetDir` | Filesystem path | `/` | Target root directory for file extraction. |
| `--include-path` | `-IncludePath` | Relative or absolute path | `""` (stage default) | Optional subpath filter within the selected stage. |
| `--force` | `-Force` | Flag / Switch | `false` | Permit restoration into an existing non-empty `--target-dir`. |
| `--dry-run` | `-DryRun` | Flag / Switch | `false` | Validate credentials and list snapshot files matching stage filters without modifying disk. |
| `-h`, `--help` | `-?`, `Get-Help` | None | N/A | Print usage synopsis and exit `0`. |

---

## 3. Stage Behavioral Contracts

### 3.1 Stage 1: System Bootstrap & Secrets (`--stage config` | `--stage 1`)
1. **Path Inclusion**: Passes `--include /etc/homelab --include /home/admin/.ssh --include /home/admin/.gemini --include /home/admin/projects` (plus relative equivalents without leading slash for Restic path matching) to `restic restore` (or filters `restic ls` output in `--dry-run` mode).
2. **Bulk Storage Exclusion**: Explicitly passes `--exclude /mnt/storage --exclude mnt/storage` to `restic restore` and filters out `/mnt/storage` in `--dry-run` mode.
3. **Mountpoint Guard**: Does NOT require `/mnt/storage` to exist or be mounted.
4. **Permissions & Ownership**:
   - Enforces `0600` on `/etc/homelab/vault.yml`, `/etc/homelab/backup.env`, `/etc/homelab/monitoring.env`.
   - Enforces `0700` on `/home/admin/.ssh` and `0600` on `/home/admin/.ssh/id_*` (excluding `*.pub`).
   - Enforces `0700` on `/home/admin/.gemini` and `0600` on `/home/admin/.gemini/*.json` and `/home/admin/.gemini/antigravity-cli/settings.json`.
   - When executed as `root` (`id -u == 0`) and user `admin` exists, sets `admin:users` (fallback `admin:admin`) ownership on restored `/home/admin/.ssh`, `/home/admin/.gemini`, and `/home/admin/projects`.
5. **Inventory Vault Sync**: When restoring to `/`, copies `/etc/homelab/vault.yml` to `<repo>/ansible/inventory/group_vars/all/vault.yml` for each existing repository directory in `/home/admin/projects/homelab2`, `/home/admin/homelab2`, and `/opt/homelab2`, setting mode `0600` and owner `admin`.
6. **Post-Restore Hooks**: Strictly skipped.

### 3.2 Stage 2: Bulk Data & Application Hook Restoration (`--stage data` | `--stage 2`)
1. **Mountpoint Safety Assertion**:
   - Resolves the storage mountpoint path (`STORAGE_MOUNT="/mnt/storage"` when `RESOLVED_TARGET == "/"`, otherwise `"$RESOLVED_TARGET/mnt/storage"`).
   - If `DRY_RUN != true`, executes `mountpoint -q "$STORAGE_MOUNT"`.
   - If the check fails, writes `CRITICAL: Storage mountpoint '$STORAGE_MOUNT' is not an active mountpoint. Aborting restoration to prevent root NVMe disk leakage.` to `stderr` and exits with code `1` prior to invoking `restic restore`.
2. **Path Inclusion**: Passes `--include /opt/services --include /mnt/storage/media/photos` (plus relative equivalents) to `restic restore` (and filters `restic ls` in `--dry-run` mode).
3. **Permissions & Ownership**:
   - Enforces `0700` and `1000:1000` on `/opt/services/vaultwarden/data` (if present).
   - Enforces `0600` on `/opt/services/*/.env` (if present).
   - Enforces `1000:1001` (`admin:storage`) and `2775` directory permissions on `/mnt/storage/media/photos` (if present and running as `root`).
4. **Container Startup & Post-Restore Hooks** (when `RESOLVED_TARGET == "/"`):
   - Ensures `docker.service` is started if `systemctl` and `docker.service` are present.
   - Starts installed application units (`vaultwarden.service`, `frigate.service`, `immich.service`) if present so database containers are ready to accept dumps.
   - Executes every executable `/etc/homelab/backup.d/*.sh` script with argument `post-restore`.

### 3.3 Unified Restoration (`--stage all` or omitted)
1. **Mountpoint Safety Assertion**: If `DRY_RUN != true` and bulk storage is in scope (i.e., `INCLUDE_PATH` is empty or starts with `mnt/storage` / `/mnt/storage`), enforces `mountpoint -q "$STORAGE_MOUNT"`, aborting with `CRITICAL` and exit code `1` if unmounted. (When `INCLUDE_PATH` targets a non-storage path such as `etc/homelab/vault.yml`, the `/mnt/storage` mount check is skipped so single-file restores to `/tmp` function without mounting MergerFS.)
2. **Execution**: Restores all snapshot paths (or `--include-path`), applies Stage 1 and Stage 2 permissions, syncs `vault.yml`, and runs post-restore hooks when restoring to `/`.

---

## 4. Exit Codes

| Exit Code | Meaning | Severity |
|---|---|---|
| `0` | Restoration or dry-run completed successfully. | `INFO` |
| `1` | Invalid CLI argument, missing credentials, missing `restic` binary, non-empty target directory without `--force`, repository authentication failure, or unmounted `/mnt/storage` safety assertion failure. | `CRITICAL` / `ERROR` |
| `2` | Remote SCP file upload failure (in `restore-from-b2.ps1`). | `ERROR` |
| `4` | Remote SSH connectivity failure (in `restore-from-b2.ps1`). | `ERROR` |
