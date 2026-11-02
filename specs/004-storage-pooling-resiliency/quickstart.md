# Quickstart & Verification Guide: Storage Pooling & Data Resiliency (Phase 4)

**Feature**: `specs/004-storage-pooling-resiliency`  
**Target Host**: `admin@192.168.4.57` (`homelab2`)  
**Status**: Ready for Implementation  

---

## 1. Prerequisites

Before running Phase 4 convergence:
1. Hardened base OS and Ansible environment converged (Phase 2 completed).
2. Remote access and mesh networking established (Phase 3 completed).
3. Physical disks connected and formatted with Ext4 or XFS, with UUIDs declared in Ansible inventory variables (`ansible/inventory/host_vars/homelab2/storage.yml` or `group_vars/all/vars.yml`).
4. SSH connectivity verified:
   ```bash
   ssh admin@192.168.4.57 "uptime"
   ```

---

## 2. Convergence Execution

Run the dedicated Phase 4 deployment orchestrator from the workstation:

### On Windows (PowerShell):
```powershell
./scripts/apply-phase4.ps1
```

### On Linux / macOS (Bash):
```bash
./scripts/apply-phase4.sh
```

### Direct Ansible Execution:
```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/storage.yml
```

---

## 3. End-to-End Validation Scenarios

### Scenario A: Storage Tiering & Mount Assertions
Verify that all storage tiers are active and correctly mounted:
```bash
ssh admin@192.168.4.57 << 'EOF'
  echo "--- Mount Status ---"
  df -h /opt/services /mnt/storage /mnt/scratch
  
  echo "--- MergerFS FUSE Mount ---"
  mount | grep mergerfs
  
  echo "--- Storage Group & Permissions ---"
  ls -ld /opt/services /mnt/storage /mnt/scratch
EOF
```
**Expected Outcome**:
- `/opt/services` is mounted on the primary NVMe.
- `/mnt/storage` shows filesystem type `fuse.mergerfs` with aggregated capacity.
- `/mnt/scratch` is independently mounted.
- Permissions show `admin:storage` and setgid `drwxrwsr-x` (`2775`) on `/mnt/storage` and `/mnt/scratch`.

---

### Scenario B: Pool Write & Underlying Member Disk Distribution
Verify that writing to `/mnt/storage` distributes files to an underlying member drive without data clobbering:
```bash
ssh admin@192.168.4.57 << 'EOF'
  TEST_FILE="/mnt/storage/test-pool-verification-$(date +%s).txt"
  echo "mergerfs-verification-data" > "$TEST_FILE"
  
  # Confirm file exists in the pool
  cat "$TEST_FILE"
  
  # Locate which physical disk received the file
  find /mnt/disks/data* -name "$(basename "$TEST_FILE")"
  
  # Clean up test file
  rm -f "$TEST_FILE"
EOF
```
**Expected Outcome**:
- File writes succeed instantly.
- The `find` command locates the file on one of the underlying `/mnt/disks/data*` drives.
- Removing the file via `/mnt/storage` deletes it from the underlying drive cleanly.

---

### Scenario C: Parity Configuration & Diff Verification
Verify SnapRAID array health and safety runner execution:
```bash
ssh admin@192.168.4.57 << 'EOF'
  echo "--- SnapRAID Status ---"
  sudo snapraid status
  
  echo "--- SnapRAID Diff Check ---"
  sudo snapraid diff
  
  echo "--- Systemd Timer Status ---"
  systemctl status snapraid-sync.timer snapraid-scrub.timer --no-pager
EOF
```
**Expected Outcome**:
- `snapraid status` reports valid parity and content files with 0 errors.
- `snapraid diff` completes without failure.
- Both timers are active and scheduled.

---

### Scenario D: Automated Phase 4 Acceptance Suite
Execute the automated test script to evaluate all 10 acceptance criteria:
```bash
# Via SSH runner
./scripts/verify-phase4.sh

# Or on Windows
./scripts/verify-phase4.ps1
```
**Expected Outcome**:
- All assertions (STO-01 through STO-10) report `[PASS]`.
- Exit code is 0.
- Telemetry events logged in `systemd-journald`.
