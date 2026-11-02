# Phase 0 Research: Storage Pooling & Data Resiliency Layer (Phase 4)

**Feature**: `specs/004-storage-pooling-resiliency`  
**Date**: 2026-11-01  
**Status**: Completed  

---

## 1. Storage Pooling Engine & Options (MergerFS)

### Context & Requirements
The homelab requires pooling multiple disparate-sized bulk HDDs into a unified mount (`/mnt/storage`) while retaining individual disk filesystems (Ext4/XFS), enabling independent disk spin-down for power/noise savings, and providing transparent file placement.

### Decision
Use **MergerFS** (v2.33+) mounted via `/etc/fstab` as a FUSE filesystem aggregating underlying member mount points (`/mnt/disks/data*`).

**Key Mount Options**:
- `cache.files=partial`: Enables mmap support (required by databases/SQLite) while avoiding aggressive kernel RAM caching that could cause OOM.
- `category.create=mfs` (Most Free Space): Routes new file writes to the member drive with the most available free capacity.
- `minfreespace=50G`: If a drive has less than 50GB free, it is skipped for new file creation, preventing drive exhaustion.
- `func.mkdir=pmfs`: Preserves existing directory path hierarchies where possible while using most free space.
- `atomic_rename=true`: Converts intra-drive renames into atomic OS operations, essential for downstream Arr/torrent hardlinks and file moves without data copying.
- `dropcacheonclose=true`: Frees page cache on file close to keep memory usage minimal on the host.
- `x-systemd.requires-mounts-for=/mnt/disks/data1 /mnt/disks/data2`: Guarantees underlying member drives are mounted before systemd mounts the MergerFS pool.
- `nofail`: Ensures the host boots even if a disk is missing or slow to respond.

### Rationale
- Unlike ZFS or hardware RAID, MergerFS does not stripe data across drives. Each file lives entirely on a single physical disk. If two disks fail in an array, data on the remaining disks remains 100% accessible and readable on any standard Linux system.
- Idle disks remain in low-power standby; only the physical disk containing the accessed file spins up.
- Easily accommodates mixed drive capacities without rebuilding the pool.

### Alternatives Considered
- **ZFS / Btrfs RAID**: Requires uniform drive sizing (or inefficient partition matching), prevents per-drive spin-down (all drives spin up on any read), and introduces high rebuild stress on failure. Rejected in accordance with Constitution Principle VII (Stability & Low Toil).
- **Unraid**: Proprietary OS / licensing, non-standard Arch Linux integration.
- **mhddfs**: Deprecated, unmaintained, known deadlock bugs.

---

## 2. Parity Protection & Integrity Scrubbing (SnapRAID)

### Context & Requirements
Bulk data stored on `/mnt/storage` requires protection against drive failure and silent bit rot, while excluding high-churn, temporary workloads (CCTV footage, active downloads).

### Decision
Use **SnapRAID** (v12.x+) with at least one dedicated parity drive (`/mnt/disks/parity1`) protecting all bulk data disks (`/mnt/disks/data*`).

**Key Configuration Patterns**:
- **Content Files**: Store at least 1 copy on the OS NVMe drive (`/var/snapraid.content`) and 1 copy on the root of each data drive (`/mnt/disks/data*/snapraid.content`). SnapRAID requires multiple identical content files for redundancy; if one drive fails, the content file survives elsewhere.
- **Parity Storage**: Parity drive capacity MUST be equal to or greater than the largest data drive.
- **Exclusion Rules**:
  - Exclude `/mnt/scratch/**` (high-churn Frigate CCTV, torrent staging)
  - Exclude transient cache files: `*.tmp`, `*.part`, `*Thumbs.db`, `.DS_Store`, `.Trash-*`
  - Exclude database write-ahead logs if any reside outside `/opt/services`.
- **Scheduled Timers**:
  - `snapraid-sync.timer`: Runs daily at 03:00 to synchronize parity blocks.
  - `snapraid-scrub.timer`: Runs weekly on Sunday at 04:00 to verify 8% of data blocks for bit rot.

### Parity Safety Runner Script (Diff Threshold Check)
To guard against accidental mass file deletion (which could cause `snapraid sync` to overwrite valid parity data with empty parity), a wrapper script (`snapraid-runner.sh`) runs prior to `snapraid sync`:
1. Executes `snapraid diff` and parses added, removed, and modified counts.
2. If `deleted_files > DEL_THRESHOLD` (default: 50 files), the script aborts with an exit code of 2, logs an alert to `systemd-journald`, and skips the sync until an operator inspects the change.
3. Automatically triggers `snapraid touch` to handle timestamp discrepancies without full re-hashing.

### Rationale
- Snapshot parity matches homelab media and archive access patterns (95% read, infrequent writes).
- Real-time RAID parity parity calculations waste CPU and spin up all disks; snapshot parity runs once per day off-peak.
- Bit rot detection via file hashes protects personal photo collections and long-term archives.

### Alternatives Considered
- **SnapRAID without safety threshold**: Risks catastrophic loss if a script erroneously deletes files and the scheduled sync immediately wipes the parity data. Safety runner is mandatory.
- **Software RAID5/6 (mdadm)**: Unsuitable for disparate drives; entire array spins up on every write; catastrophic rebuild risks.

---

## 3. Storage Tiering & Mount Hierarchy

### Context & Requirements
The architecture requires strict isolation between three operational tiers:
1. Fast application state / databases (Tier 0)
2. Bulk resilient storage (Tier 1)
3. Transient high-churn scratch buffer (Tier 2)

### Decision

| Tier | Target Path | Backing Hardware | Filesystem | Role / Workload | Parity / Backup Policy |
|---|---|---|---|---|---|
| **Tier 0: Fast App State** | `/opt/services` | Host OS NVMe | Ext4 | Postgres, SQLite, Redis, Home Assistant, Vaultwarden, Immich indices | Excluded from SnapRAID; backed up daily via Restic |
| **Tier 1: Bulk Storage Pool** | `/mnt/storage` | Pooled Data Disks (`/mnt/disks/data*`) | MergerFS over Ext4 | Photo library, documents, archives, finalized media | Protected by SnapRAID parity; critical datasets backed up offsite |
| **Tier 1 Physical Mounts** | `/mnt/disks/data*`, `/mnt/disks/parity*` | Individual Disks | Ext4 (UUID mount) | Underlying physical drives | Managed via `/etc/fstab` with `nofail` |
| **Tier 2: Scratch & CCTV** | `/mnt/scratch` | Dedicated Scratch Disk / Partition | Ext4 | Frigate continuous CCTV video buffers, active torrents | **Strictly excluded** from SnapRAID parity and backups |

### Directory & Mount Hierarchy:
```text
/
├── opt/
│   └── services/                 # Fast NVMe application configs & databases
└── mnt/
    ├── disks/
    │   ├── data1/                # Physical bulk drive 1 (Ext4, UUID mount)
    │   ├── data2/                # Physical bulk drive 2 (Ext4, UUID mount)
    │   └── parity1/              # Physical parity drive 1 (Ext4, UUID mount)
    ├── storage/                  # MergerFS pooled virtual filesystem (/mnt/disks/data*)
    └── scratch/                  # Isolated high-churn CCTV / torrent scratch volume
```

### Rationale
- Mounting underlying drives under `/mnt/disks/` creates a clean separation between raw member disks and pooled/virtual filesystems under `/mnt/`.
- MergerFS globs `/mnt/disks/data*` easily without accidentally including parity or scratch volumes.
- Prevents container stacks from inadvertently writing directly to an unmounted underlying disk mount point if the disk is detached (using `x-systemd.requires-mounts-for`).

---

## 4. Permissions, Ownership & Storage Group Model

### Context & Requirements
In Phase 5, multiple containerized services (Immich, FileBrowser, Frigate, Arr stack) will run under distinct non-root user IDs but need shared read/write access to `/mnt/storage` and `/mnt/scratch` without permission conflicts or root-owned file locks.

### Decision
Establish a dedicated system group:
- Group Name: `storage`
- GID: `1001` (stable, deterministic GID)
- Administrative user (`admin`) added to `storage` group.
- Container runtimes configure `PUID=1000` (admin) and `PGID=1001` (`storage`).
- Mount permissions: `/mnt/storage` and `/mnt/scratch` directories configure `chmod 2775` (setgid bit enabled) and ownership `admin:storage`.
- With the setgid bit set (`2775`), any new file or subfolder created inside the pool automatically inherits group `storage`, ensuring multi-container read/write interoperability.

### Rationale
Eliminates the common homelab permission bug where one service writes a file with `0644` or root ownership, causing other services to fail with permission denied.

---

## 5. Telemetry & Automated Verification

### Context & Requirements
Constitution Principles III (Verification Gates) and V (Disaster Recovery) mandate that storage components must provide observable telemetry and automated acceptance verification.

### Decision
1. **Journald Logging**:
   - `snapraid-runner.sh` sends structured status summaries to `systemd-cat -t snapraid` or logs directly with syslog levels.
   - MergerFS mount errors and fstab status logged to system journal.
2. **Automated Verification Script (`scripts/verify-phase4.sh`)**:
   - Asserts all configured disk UUIDs are mounted and reachable.
   - Asserts `/mnt/storage` is mounted as MergerFS FUSE filesystem.
   - Performs read/write/delete test on `/mnt/storage` and verifies file creation on member disk.
   - Asserts `/mnt/scratch` is mounted and isolated.
   - Verifies `snapraid.conf` syntax with `snapraid status`.
   - Asserts systemd timer units (`snapraid-sync.timer`, `snapraid-scrub.timer`) are active and enabled.
   - Exits 0 on complete health; exits > 0 with actionable diagnostic output on failure.

---

## Research Summary & Readiness
All architectural decisions, technical choices, and safety parameters are resolved. No open `NEEDS CLARIFICATION` items remain. Proceeding to Phase 1 Design and Contracts.
