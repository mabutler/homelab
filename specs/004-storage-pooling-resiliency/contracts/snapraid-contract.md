# Contract: SnapRAID Parity & Safety Runner Specification

**Feature**: `specs/004-storage-pooling-resiliency`  
**File**: `contracts/snapraid-contract.md`  
**Status**: Active  

---

## 1. SnapRAID Configuration Contract (`/etc/snapraid.conf`)

The SnapRAID configuration MUST strictly adhere to the following schema:

```ini
# Parity Disk Location(s)
parity /mnt/disks/parity1/snapraid.parity

# Redundant Content Files (at least 1 on OS drive, 1 on each data drive)
content /var/snapraid.content
content /mnt/disks/data1/snapraid.content
content /mnt/disks/data2/snapraid.content

# Monitored Data Disks
data d1 /mnt/disks/data1
data d2 /mnt/disks/data2

# Excluded Files and Folders
exclude *.bak
exclude *.tmp
exclude *.part
exclude *Thumbs.db
exclude .DS_Store
exclude .Trash-*
exclude /mnt/scratch/
exclude *.unrecoverable
```

### Safety Constraints:
- Parity files MUST reside on a drive of equal or greater size than any individual data drive.
- Content files MUST be distributed across at least two independent physical disks.
- High-churn directories (`/mnt/scratch`) MUST be explicitly excluded.

---

## 2. Parity Safety Runner Script Contract (`/usr/local/bin/snapraid-runner.sh`)

To protect valid parity against accidental mass deletions, scheduled sync jobs MUST execute via a protective wrapper script:

```bash
#!/usr/bin/env bash
set -euo pipefail

DEL_THRESHOLD="${SNAPRAID_DEL_THRESHOLD:-50}"

echo "Starting SnapRAID pre-sync evaluation..."

# 1. Update file timestamps to prevent unnecessary hashing
snapraid touch

# 2. Check changes using diff
DIFF_OUTPUT=$(snapraid diff 2>&1 || true)
DELETED_COUNT=$(echo "$DIFF_OUTPUT" | grep -E '^([0-9]+)\s+removed' | awk '{print $1}' || echo "0")

if [ -z "$DELETED_COUNT" ]; then
    DELETED_COUNT=0
fi

echo "SnapRAID diff: $DELETED_COUNT files marked for deletion (threshold: $DEL_THRESHOLD)."

# 3. Guard against mass deletions
if [ "$DELETED_COUNT" -gt "$DEL_THRESHOLD" ]; then
    logger -p user.err -t snapraid "SnapRAID safety guard triggered: $DELETED_COUNT files removed exceeds threshold of $DEL_THRESHOLD. Parity sync aborted to prevent data loss."
    echo "ERROR: Deletion threshold exceeded ($DELETED_COUNT > $DEL_THRESHOLD). Aborting sync." >&2
    exit 2
fi

# 4. Execute sync
echo "Executing SnapRAID sync..."
if snapraid sync; then
    logger -p user.notice -t snapraid "SnapRAID sync completed successfully."
else
    EXIT_CODE=$?
    logger -p user.err -t snapraid "SnapRAID sync failed with exit code $EXIT_CODE."
    exit "$EXIT_CODE"
fi
```

---

## 3. Systemd Unit Contracts

### 3.1 SnapRAID Sync (`snapraid-sync.service` & `snapraid-sync.timer`)
- **Service Type**: `oneshot`
- **ExecStart**: `/usr/local/bin/snapraid-runner.sh`
- **Schedule**: Daily at `03:00`
- **Unit Options**: `ConditionACPower=true`

### 3.2 SnapRAID Scrub (`snapraid-scrub.service` & `snapraid-scrub.timer`)
- **Service Type**: `oneshot`
- **ExecStart**: `/usr/bin/snapraid scrub -p 8 -o 10` (scrubs 8% of array, older than 10 days)
- **Schedule**: Weekly on Sunday at `04:00`
- **Logging**: StandardOutput and StandardError sent to `journal`
