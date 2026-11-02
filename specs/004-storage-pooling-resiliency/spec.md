# Feature Specification: Storage Pooling & Data Resiliency Layer

**Feature Branch**: `004-storage-pooling-resiliency`

**Created**: 2026-11-01

**Status**: Draft

**Input**: User description: "next phase" (Mapped to Phase 4 from repository Roadmap: Storage Pooling & Data Resiliency Layer)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Unified Storage Pooling & Transparent File Access (Priority: P1)

As a homelab operator and household user, I want multiple disparate storage disks combined into a single unified mount point (`/mnt/storage`) with transparent file placement and standard filesystem semantics, so that applications and users can store and access data across all drives without needing to track individual disk boundaries, while keeping spinning disks spun down when inactive.

**Why this priority**: A unified storage namespace is the foundational prerequisite for self-hosted applications (Immich, FileBrowser, media archives) planned in subsequent phases. Without storage pooling, applications must manage individual drive mount points manually, creating operational fragility and imbalanced capacity utilization.

**Independent Test**: Can be tested independently by creating test directories and files on `/mnt/storage`, verifying that writes are automatically distributed to underlying member drives based on available capacity policies, that directory structures are seamlessly merged, and that files can be read, updated, and deleted with full POSIX permission consistency.

**Acceptance Scenarios**:

1. **Given** multiple formatted data disks mounted to the host, **When** the storage pooling service initializes, **Then** all member disks are presented as a single unified directory tree at `/mnt/storage`.
2. **Given** a new write operation targeting `/mnt/storage`, **When** data is written, **Then** the file is placed on the underlying member disk satisfying the configured free-space policy while appearing instantly in the unified namespace.
3. **Given** files existing across different member disks within identically named parent folders, **When** listing the directory at `/mnt/storage`, **Then** the contents are presented as a single merged view.
4. **Given** an application performing atomic file renames or cross-directory moves within the pool, **When** the rename operation executes, **Then** the operation completes atomically without duplicate disk consumption or data corruption.
5. **Given** a query or read operation targeting a file located on a specific physical disk, **When** that file is accessed, **Then** only the specific disk hosting the file needs to spin up, while idle disks in the pool remain in power-saving standby.

---

### User Story 2 - Snapshot-Based Parity Protection & Integrity Scrubbing (Priority: P1)

As a homelab administrator, I want dedicated parity protection and scheduled data scrubbing across bulk data drives, so that stored data is protected against physical disk failure and silent bit rot without requiring constant real-time striping overhead.

**Why this priority**: Data stored in the bulk pool (family photos, documents, system backups) requires local redundancy against drive failure. Snapshot parity provides resilience without the high write overhead, rebuild fragility, or matched-disk constraints of traditional RAID arrays.

**Independent Test**: Can be tested independently by calculating parity across sample data on member drives, simulating the loss or corruption of a file on a data drive, and successfully verifying and recovering the lost/corrupted file using the parity data.

**Acceptance Scenarios**:

1. **Given** data disks and dedicated parity disk(s) configured in the resiliency layout, **When** a parity synchronization operation runs, **Then** parity information is calculated and updated across all bulk data drives.
2. **Given** an accidental file corruption or bit rot occurrence on an underlying data disk, **When** a scrub verification routine runs, **Then** the corrupted block is detected, identified, and reported with actionable diagnostics.
3. **Given** a simulated single drive failure, **When** a restoration command is executed targeting a replacement drive, **Then** all files originally present on the failed disk are reconstructed bit-for-bit from parity.
4. **Given** an automated scheduled timer (daily sync, weekly scrub), **When** triggered by the system, **Then** the parity operation runs headlessly, logs its status to the system journal, and exits cleanly without operator intervention.
5. **Given** an abnormal deletion threshold (e.g., more than a configured percentage or number of files deleted since the last sync), **When** the automated parity sync executes, **Then** the sync aborts safely and logs an alert to prevent overwriting valid parity with accidental mass deletions.

---

### User Story 3 - Storage Tiering & Scratch Space Isolation (Priority: P2)

As a homelab operator, I want distinct storage tiers separating high-I/O application state (`/opt/services`), bulk resilient data (`/mnt/storage`), and high-wear transient data (`/mnt/scratch`), so that heavy disk-write churn does not degrade pool performance or cause unnecessary parity synchronization overhead.

**Why this priority**: Applications like Frigate NVR (continuous video recording) and torrent downloads generate continuous, high-volume write churn. Isolating transient writes to a dedicated scratch volume prevents premature SSD wear and stops parity sync jobs from calculating parity on temporary data that does not require redundancy.

**Independent Test**: Can be tested independently by mounting `/mnt/scratch` on dedicated transient storage, running heavy write workloads into `/mnt/scratch`, and confirming that `/mnt/scratch` operations do not trigger parity calculations or consume space in `/mnt/storage`.

**Acceptance Scenarios**:

1. **Given** the storage tier layout, **When** high-I/O service configuration and database paths are established, **Then** `/opt/services` provides dedicated high-speed SSD/NVMe access for application runtimes.
2. **Given** continuous CCTV recording buffers or staging download directories, **When** writing to `/mnt/scratch`, **Then** writes are isolated from the bulk storage pool and member disks.
3. **Given** the parity protection configuration, **When** inspecting protected paths, **Then** `/mnt/scratch` and transient temporary paths are explicitly excluded from parity tracking.
4. **Given** a full disk condition on the scratch filesystem, **When** scratch capacity is exhausted, **Then** bulk storage pool operations at `/mnt/storage` and critical service data at `/opt/services` remain completely unaffected.

---

### User Story 4 - Automated Verification, Telemetry & Mount Recovery (Priority: P2)

As a homelab administrator, I want automated verification tests, health assertions, and structured telemetry integrated into the storage subsystem, so that mount failures, disk disconnects, or parity sync errors are immediately observable and the entire storage layout can be recreated declaratively in a disaster recovery scenario.

**Why this priority**: In accordance with Constitution Principles III (Acceptance Gates) and V (Backup by Design), storage configuration must not fail silently. All mounts and automated tasks must provide verifiable health assertions and recover cleanly after reboot or hardware swap.

**Independent Test**: Can be tested independently by running the Phase 4 verification suite, which validates drive mount statuses, permissions, pooling visibility, parity synchronization exit codes, and journal telemetry logging.

**Acceptance Scenarios**:

1. **Given** the host boots or reboots, **When** storage services initialize, **Then** all underlying drives are mounted persistently via stable filesystem UUIDs or device serials without relying on volatile `/dev/sdX` letters.
2. **Given** the automated health verification suite, **When** executed, **Then** it tests read/write access to `/mnt/storage`, confirms `/mnt/scratch` availability, verifies `/opt/services` permissions, and asserts that SnapRAID parity status is clean.
3. **Given** a failure during automated parity sync (e.g., disk I/O error or abnormal threshold exceeded), **When** the error occurs, **Then** a structured error event is recorded to the system journal with an elevated log level for administrative notification.
4. **Given** a disaster recovery rebuild from bare metal, **When** applying configuration management with the repository's declarative storage definitions, **Then** the exact drive mounts, pool configuration, and timer units are reconstituted and verified in under 15 minutes.

---

### Edge Cases

- **Missing or Disconnected Drive on Boot**: If an underlying member drive fails to spin up or is disconnected, the system must not hang the boot process indefinitely; remaining available drives and services must boot with appropriate degraded-mount warnings logged.
- **Member Disk Nearing Exhaustion**: When an individual data disk reaches full capacity, the pooling layer must route subsequent new file writes to remaining member disks with available space without dropping writes or throwing I/O errors.
- **Simultaneous Writes to Same Directory**: If two concurrent tasks write files to the same directory path, the pooling engine must maintain atomic operations without file clobbering or permission races.
- **Accidental Mass Deletion Protection**: If a script or user erroneously deletes a major directory tree, the automated parity sync must detect that the change threshold is breached, halt immediately without syncing, and alert the administrator before parity blocks are overwritten.
- **System Reboot Mid-Sync**: If the host is power-cycled or rebooted during an active parity sync, the parity engine must detect the interrupted state on the next run, resume or clean up safely, and complete synchronization without data corruption.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST identify and mount all underlying data and parity drives using persistent, immutable device identifiers (UUIDs) in `/etc/fstab`.
- **FR-002**: System MUST configure a unified storage pool using MergerFS mounted at `/mnt/storage`, aggregating all underlying bulk data drives into a single unified directory hierarchy.
- **FR-003**: System MUST configure MergerFS with balanced write policies (such as most free space or existing path) and enable support for POSIX file permissions and atomic file renames across directories.
- **FR-004**: System MUST maintain standard non-root group ownership and permissions (e.g., dedicated storage group with write access) across `/mnt/storage` so that containerized services and local users can access files predictably.
- **FR-005**: System MUST configure SnapRAID parity protection for all bulk data disks comprising the `/mnt/storage` pool, utilizing at least one dedicated parity drive of equal or greater capacity than the largest single data drive.
- **FR-006**: System MUST explicitly exclude transient and non-critical paths—specifically `/mnt/scratch`, download staging caches, and temporary buffers—from SnapRAID parity tracking.
- **FR-007**: System MUST configure a dedicated scratch filesystem and directory at `/mnt/scratch` for Frigate CCTV continuous recording and temporary downloads.
- **FR-008**: System MUST configure the high-performance application state directory hierarchy at `/opt/services` on the primary NVMe tier with appropriate ownership for container stacks.
- **FR-009**: System MUST deploy automated systemd service and timer units for daily SnapRAID parity synchronization (`snapraid sync`) and weekly scrubbing (`snapraid scrub`).
- **FR-010**: System MUST configure a pre-sync safety check (e.g., diff threshold script) that halts automated parity synchronization if deleted or modified files exceed a defined safety threshold, logging an alert to prevent destructive parity updates.
- **FR-011**: System MUST capture and log all storage pooling mount operations, disk health notifications, and SnapRAID sync/scrub execution summaries directly to `systemd-journald`.
- **FR-012**: System MUST provide an automated health verification script that asserts all storage tiers (`/mnt/storage`, `/mnt/scratch`, `/opt/services`) are mounted, readable, writable, and have valid parity status.
- **FR-013**: System MUST declare all filesystem mount options, pooling parameters, and parity configurations within version-controlled configuration management (Ansible / shell fallback modules) in compliance with Constitution Principles I, II, and IV.

### Key Entities *(include if feature involves data)*

- **Member Data Disk**: An individual physical storage disk formatted with a standard native Linux filesystem (Ext4 or XFS) containing a subset of bulk user files.
- **Parity Disk**: A dedicated physical disk dedicated entirely to storing SnapRAID parity calculation blocks.
- **Storage Pool (`/mnt/storage`)**: The unified virtual filesystem presentation provided by MergerFS that aggregates member data disks into a single coherent namespace.
- **Scratch Tier (`/mnt/scratch`)**: An isolated high-churn filesystem dedicated to ephemeral data, CCTV continuous buffers, and download staging, deliberately untracked by parity.
- **Application Fast Tier (`/opt/services`)**: Fast NVMe directory tree hosting persistent container configuration, SQLite/PostgreSQL databases, and real-time state files.
- **Parity State & Content Files**: SnapRAID metadata tracking file inodes, hashes, and parity block alignments, stored redundantly across multiple physical drives.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A single unified directory tree at `/mnt/storage` successfully reflects 100% of files stored across all underlying member data disks.
- **SC-002**: A file written to `/mnt/storage` is successfully placed on an underlying member disk with adequate free space, and reading that file spins up only the single drive holding that file.
- **SC-003**: Parity calculation (`snapraid sync`) executes headlessly via systemd timer and completes with exit status 0 when data disks are in a clean state.
- **SC-004**: Simulated single-file corruption on an underlying data disk is detected by `snapraid scrub` and can be reconstructed using `snapraid fix`.
- **SC-005**: Automated verification script validates all mount points, write permissions, and parity status in under 10 seconds.
- **SC-006**: In the event of a total system re-provisioning, the entire storage tiering and pooling configuration can be applied and verified on bare metal in under 15 minutes.
- **SC-007**: 100% of high-wear CCTV and transient download writes are directed to `/mnt/scratch` and produce 0 blocks of SnapRAID parity sync churn.

## Assumptions

- **Target Disks**: Physical data and parity drives are pre-installed in the homelab chassis, formatted with standard Linux filesystems (Ext4 or XFS), and labeled or identifiable by UUID.
- **Drive Sizing**: The dedicated parity drive has capacity equal to or greater than the largest single data drive in the pool.
- **Filesystem Choice**: Underlying member drives use standard native Linux filesystems (Ext4 or XFS) to ensure that in the event of catastrophic pool software failure, each individual disk remains directly mountable and readable on any standard Linux machine.
- **Operating Environment**: Arch Linux bare-metal host running hardened base configuration from Phase 2 and remote access from Phase 3.
- **Offsite Backup Separation**: Offsite cloud backups (Restic to Backblaze B2) for critical data in `/opt/services` and `/mnt/storage` will be centralized and orchestrated in Phase 7; Phase 4 establishes the local storage tiering, local parity redundancy, and data organization required for those backup pipelines.
