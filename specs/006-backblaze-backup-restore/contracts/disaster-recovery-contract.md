# Contract: Standalone Disaster Recovery Restoration

**Contract Identifier**: `DISASTER-RECOVERY-V1`  
**Target Scripts**: `scripts/restore-from-b2.sh` (Linux), `scripts/restore-from-b2.ps1` (Workstation Orchestration)  
**Applicability**: Clean bare-metal rebuilds, disaster recovery rehearsals, staging verification  

---

## 1. Specification

The disaster recovery script MUST operate with only the git repository and 4 bootstrap credentials. It MUST NOT require pre-existing Ansible installations on the target host or active container states.

### CLI Synopsis
```bash
# Direct on Linux host:
./scripts/restore-from-b2.sh [OPTIONS]

# Remote workstation orchestration:
./scripts/restore-from-b2.ps1 -HostAddress <IP> -User <user> [OPTIONS]
```

### Bootstrap Credentials Inputs
Credentials can be supplied via environment variables or explicit flags:

| Environment Variable | CLI Option | Description | Mandatory |
|---|---|---|---|
| `B2_ACCOUNT_ID` | `--account-id` | Backblaze B2 Application Key ID | Yes |
| `B2_ACCOUNT_KEY` | `--account-key` | Backblaze B2 Application Key | Yes |
| `RESTIC_REPOSITORY` | `--repository` | Target repository URI (`b2:...`) | Yes |
| `RESTIC_PASSWORD` | `--password` | Client-side Restic encryption password | Yes |

*Note*: If `ansible/inventory/group_vars/all/vault.yml` exists locally on the workstation running `restore-from-b2.ps1`, the PowerShell script automatically extracts these variables if omitted from CLI arguments.

### CLI Flags

| Flag | Argument | Default | Description |
|---|---|---|---|
| `--snapshot` | ID / `latest` | `latest` | Specific snapshot ID to restore. |
| `--target-dir` | path | `/` | Target destination directory for extraction. |
| `--include-path` | path | All | Filter restoration to a specific subpath (e.g. `etc/homelab/vault.yml`). |
| `--force` | none | `false` | Required to overwrite existing non-empty destination directories. |
| `--dry-run` | none | `false` | Verify connectivity and list snapshot contents without restoring files. |

---

## 2. Execution Safeguards

1. **Non-Empty Directory Guard**:
   - If `--target-dir` contains existing files or directories that would be overwritten, the script MUST refuse to proceed unless `--force` is explicitly provided.
2. **Pre-flight Dependency Check**:
   - Verifies `restic` binary is installed. If missing on bare metal, prints command to install (`pacman -S restic`, `apt install restic`, or curl standalone binary).
3. **Repository Connectivity Test**:
   - Executes `restic snapshots` to verify credentials and key unlocking before attempting any extraction.
4. **Permissions Restoration**:
   - Restores `/etc/homelab/vault.yml` with mode `0600` and owner `root:root`.
   - Restores `/opt/services/<app>/data` with owner `1000:1000` and mode `0700`.
   - Invokes all `/etc/homelab/backup.d/*.sh post-restore` scripts if target is `/`.

---

## 3. Standard Recovery Flow

```bash
# Step 1: Clone repo on bare metal
git clone https://github.com/myorg/homelab2.git /opt/homelab2
cd /opt/homelab2

# Step 2: Restore secrets and application state
export B2_ACCOUNT_ID="00xxxxxxxxxxxxxxx"
export B2_ACCOUNT_KEY="K00xxxxxxxxxxxxxxxxxxxx"
export RESTIC_REPOSITORY="b2:my-bucket:homelab2"
export RESTIC_PASSWORD="my-restic-password"

sudo ./scripts/restore-from-b2.sh --force

# Step 3: Run Phase 5 deployment to converge services
./scripts/apply-phase5.sh
```
