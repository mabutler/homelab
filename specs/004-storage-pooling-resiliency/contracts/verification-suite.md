# Contract: Storage Verification Suite & Acceptance Assertions

**Feature**: `specs/004-storage-pooling-resiliency`  
**File**: `contracts/verification-suite.md`  
**Status**: Active  

---

## 1. Automated Acceptance Assertions Matrix

Every assertion MUST be implemented and evaluated in `scripts/verify-phase4.sh` and `ansible/playbooks/verify-phase4.yml`.

| Check ID | Target Component | Verification Assertion | Success Condition |
|---|---|---|---|
| **STO-01** | Physical Disk Mounts | Verify that all configured bulk data, parity, and scratch disks are mounted persistently via UUID in `/etc/fstab` and active in `/proc/mounts`. | All declared UUIDs present in `/etc/fstab` and mounted under `/mnt/disks/` or `/mnt/scratch`. |
| **STO-02** | MergerFS Pool Mount | Verify that `/mnt/storage` is mounted with FUSE type `fuse.mergerfs`. | `mountpoint -q /mnt/storage` succeeds and filesystem type matches `fuse.mergerfs`. |
| **STO-03** | Pool Read/Write/Delete | Execute an automated read, write, and delete lifecycle on `/mnt/storage`. | File writes succeed; file is confirmed present on an underlying `/mnt/disks/data*` disk; deletion leaves no orphaned blocks. |
| **STO-04** | Scratch Tier Isolation | Verify that `/mnt/scratch` is active, writable, and resides outside the MergerFS pool hierarchy. | `/mnt/scratch` is independently mounted and not included in MergerFS member branch globs. |
| **STO-05** | NVMe App Tier Setup | Verify that `/opt/services` exists with proper ownership and permissions for container stacks. | Directory exists, owned by `admin:storage` with mode `0775` or `0755`. |
| **STO-06** | Storage Group & Setgid | Verify group `storage` (GID 1001) exists, `admin` is a member, and setgid bit (`2775`) is active on `/mnt/storage` and `/mnt/scratch`. | `getent group storage` succeeds; permissions mode shows setgid `2775`. |
| **STO-07** | SnapRAID Configuration | Execute `snapraid status` or configuration parse check against `/etc/snapraid.conf`. | SnapRAID parses configuration without syntax errors and reports healthy array state. |
| **STO-08** | Parity Safety Runner | Verify `/usr/local/bin/snapraid-runner.sh` exists, is executable, and enforces the deletion threshold. | Script executes dry-run diff successfully and logs to journald. |
| **STO-09** | Systemd Timers | Verify that `snapraid-sync.timer` and `snapraid-scrub.timer` are enabled and active. | `systemctl is-active` returns `active` for both timer units. |
| **STO-10** | Journald Telemetry | Confirm that SnapRAID and storage mount events are visible in system logs. | `journalctl -u snapraid-sync -n 5` or `journalctl -t snapraid -n 5` returns structured log output without errors. |

---

## 2. Execution Protocol

```bash
# Production verification execution
./scripts/verify-phase4.sh
```

- **Exit Code 0**: All 10 assertions pass; Phase 4 meets Definition of Done and Constitution Principles III & V.
- **Exit Code > 0**: At least one assertion failed; outputs failing Check ID and actionable remediation message to stderr.
