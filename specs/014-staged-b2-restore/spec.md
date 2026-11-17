# Feature Specification: Staged Backblaze B2 Disaster Recovery Restoration

**Feature Branch**: `014-staged-b2-restore`

**Created**: 2026-11-10

**Status**: Draft

**Input**: User description:
```text
Stage 1: System Bootstrap & Secrets (restore-from-b2.sh --stage config or --stage 1)

Restores only:
/etc/homelab (vault.yml, monitoring.env, app configurations)
/home/admin/.ssh (GitHub deploy key, authorized keys)
/home/admin/.gemini (OAuth credentials)
/home/admin/projects
Syncs vault.yml to repo inventory.
Skips all bulk data (/mnt/storage) and skips post-restore hooks (since Docker is not yet installed).

Inter-Stage: Run Ansible (ansible-playbook ... playbooks/site.yml)

Sets up Docker, system users, network, firewall, and Caddy.
Partitions/formats any missing mounts, installs and mounts MergerFS to /mnt/storage, and sets up SnapRAID.

Stage 2: Bulk Data & Application Hook Restoration (restore-from-b2.sh --stage data or --stage 2)

Asserts /mnt/storage is an active mountpoint (mountpoint -q /mnt/storage) to prevent NVMe leakage.
Restores /opt/services (service state) and /mnt/storage/media/photos (directly into MergerFS).
Executes post-restore database hooks (/etc/homelab/backup.d/*.sh) and brings containers up.
```

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - System Bootstrap & Secrets Restoration (Stage 1) (Priority: P1)

As a homelab systems administrator recovering from total hardware loss or a freshly installed operating system, I want to execute an initial bootstrap restoration stage from offsite cloud backups that extracts only sensitive configurations, credentials, SSH authentication keys, and project repositories while excluding bulk media and skipping application database hooks, so that the host is immediately prepared for automated configuration management without writing bulk files to unpartitioned storage or failing on missing container engines.

**Why this priority**: System recovery on bare metal is fundamentally blocked without administrative credentials, inventory secrets, and SSH keys. Decoupling the secrets restoration from bulk datasets solves the bootstrapping dependency loop while keeping initial recovery quick and lightweight.

**Independent Test**: Can be tested independently on a minimal fresh operating system installation with no container engine or storage pool present: execute the configuration restoration stage, verify that system secrets, SSH keys, application configurations, and repository checkouts are restored with restricted permissions, confirm that repository inventory secrets are synchronized, and verify that no bulk media files are downloaded and no post-restore database hooks are invoked.

**Acceptance Scenarios**:

1. **Given** a clean system installation with offsite backup credentials, **When** the operator invokes the configuration restoration stage, **Then** configuration secrets, administrative SSH keys, OAuth tokens, and project repositories are restored to their expected filesystem paths with restrictive access permissions.
2. **Given** restored configuration secrets including the primary vault file, **When** the configuration restoration finishes, **Then** the primary vault secrets file is automatically synchronized to the repository configuration management inventory path.
3. **Given** an environment where the container runtime and bulk storage array are not yet installed or mounted, **When** the configuration restoration stage runs, **Then** all bulk storage paths are excluded and no post-restore database hooks are executed.
4. **Given** an existing destination directory containing preexisting files, **When** the operator invokes the configuration restoration with an overwrite confirmation flag, **Then** files are restored without failing the non-empty directory check.

---

### User Story 2 - Storage Mountpoint Assertion & NVMe Leakage Prevention (Priority: P1)

As a storage administrator, I want the restoration system to verify and assert that the pooled mass-storage path is an active, mounted filesystem before initiating bulk data extraction, so that catastrophic leakage of hundreds of gigabytes into the host's root NVMe solid-state partition is strictly prevented if the pooled storage pool failed to mount.

**Why this priority**: Writing bulk media directly into an unmounted mountpoint directory writes files directly into the root filesystem. This quickly exhausts root drive capacity, risks filesystem corruption, and produces silent state divergence. Enforcing an active mountpoint assertion is a non-negotiable safety guard.

**Independent Test**: Can be tested independently by attempting a bulk data restoration while the pooled mass-storage path is unmounted: verify that the restoration tool immediately halts with a critical diagnostic failure and non-zero exit code before transferring any files or modifying disk contents.

**Acceptance Scenarios**:

1. **Given** a target system where the mass-storage pool is unmounted or missing from active mounts, **When** the bulk restoration stage is invoked, **Then** the system immediately aborts with an actionable error message indicating an unmounted storage target, exiting with a non-zero exit code before performing any file extraction.
2. **Given** a target system where the mass-storage pool is actively mounted and accessible, **When** the bulk restoration stage is invoked, **Then** the mount validation passes and file extraction proceeds into the mounted filesystem pool.

---

### User Story 3 - Bulk Data & Media Restoration into Storage Pool (Stage 2) (Priority: P1)

As a homelab administrator who has completed base system configuration and storage pool assembly, I want to execute a secondary bulk restoration stage that restores application service directories and bulk photo media directly into the active pooled storage array, so that persistent service data and family photo collections are accurately reconstituted.

**Why this priority**: Once infrastructure and storage pools are established by configuration management, restoring persistent application volumes and media collections completes the reconstitution of user-facing services.

**Independent Test**: Can be tested independently following configuration management: execute the bulk restoration stage, verify that service state and database dumps are restored to high-speed service storage, and verify that full-resolution photos and media are restored directly into the pooled storage tier with proper ownership.

**Acceptance Scenarios**:

1. **Given** a converged host with active storage pooling, **When** the bulk restoration stage executes, **Then** application service states, configuration manifests, and database dump archives are restored to the application service directory.
2. **Given** active storage pooling, **When** the bulk restoration stage restores media assets, **Then** photo and video files are extracted directly into the pooled storage media directory with correct group access permissions.
3. **Given** bulk data restoration options, **When** the operator specifies a dry-run flag, **Then** candidate snapshot files are cataloged and listed to standard output without downloading payload data or modifying the target filesystems.

---

### User Story 4 - Application Container Startup & Database Hook Execution (Priority: P2)

As a systems operator, I want the bulk restoration process to ensure required container runtimes and application services are active, and then automatically trigger post-restore database hooks, so that application databases are reconstituted from restored transactional backups without manual administrative intervention.

**Why this priority**: Having database dump files on disk is insufficient; the database management systems within application containers must import the dump to restore services to a functional state. Automating hook execution after services are running guarantees zero-to-functional recovery.

**Independent Test**: Can be tested independently by running Stage 2 on a system with restored database dumps: verify that application containers are started and each executable post-restore hook in the backup hooks directory is executed, validating successful database table population.

**Acceptance Scenarios**:

1. **Given** restored application states containing transactional database dumps, **When** the bulk data restoration concludes its file extraction, **Then** application container services are initiated or confirmed active.
2. **Given** active container database engines, **When** post-restore hooks are invoked, **Then** database restoration hooks execute with the post-restore action and restore relational tables from the restored dump archives.
3. **Given** an individual post-restore hook that encounters a non-fatal warning or already converged state, **When** execution completes, **Then** clear diagnostic status is output and the overall recovery procedure reports comprehensive completion.

---

### User Story 5 - Workstation Remote Disaster Recovery Orchestration (Priority: P2)

As an operator seated at a desktop workstation, I want to drive both restoration stages remotely over SSH using unified parameter flags, so that I can perform bare-metal recovery without requiring interactive keyboard or monitor connections to the server chassis.

**Why this priority**: The homelab server operates headlessly in a server rack or closet. Complete remote orchestration from a primary workstation minimizes operational toil during disaster recovery events.

**Independent Test**: Can be tested independently by executing the workstation orchestration wrapper with explicit stage flags targeting a remote host over SSH, verifying that the appropriate remote commands are dispatched and executed with expected parameters.

**Acceptance Scenarios**:

1. **Given** an administrative workstation with backup credentials and network reachability to the server, **When** the operator executes the workstation orchestrator specifying the configuration stage, **Then** the script executes the Stage 1 restoration on the remote target and syncs credentials.
2. **Given** successful configuration management execution, **When** the operator executes the workstation orchestrator specifying the bulk data stage, **Then** the script executes the Stage 2 restoration remotely with mount assertions and hook execution.
3. **Given** a requirement for unattended execution, **When** the workstation orchestrator connects over SSH, **Then** authentication and script transfer occur non-interactively using batch credentials.

---

### Edge Cases

- **Target storage pool not mounted**: When `--stage data` or `--stage 2` runs and `/mnt/storage` is not reported as an active mountpoint by `mountpoint -q /mnt/storage`, the process MUST fail closed immediately with exit code 1 and log an actionable error message explaining that continuing would corrupt or fill the root NVMe drive.
- **Preexisting non-empty destination directories**: If the target directory contains preexisting files and `--force` is not specified, the restoration MUST abort with an explanatory error to avoid unintentional overwrite. When `--force` is supplied, files are restored over existing contents.
- **Docker engine not running during Stage 2 hooks**: If container runtimes are stopped or failing when post-restore hooks execute, the restoration runner MUST attempt to start or restart the service stacks, or emit a clear diagnostic failure identifying which hook failed and how to rerun it manually.
- **Partial or missing snapshot paths**: If a specific path requested in a stage filter is not found in the target snapshot, the restoration runner logs a warning for optional paths, while failing closed if core configuration paths are entirely absent.
- **Invalid stage argument**: If an unrecognized stage name is provided (e.g. `--stage invalid`), the command parser MUST reject the input immediately, display valid stage options (`config`, `1`, `data`, `2`, `all`), and exit with code 1.
- **Credential absence or failure**: If offsite backup credentials or repository decryption keys are missing, invalid, or fail decryption, the script MUST fail closed during preflight checks before any target directory creation or disk modification.
- **Disaster recovery on unified / single-pass invocation**: When invoked with `--stage all` or without a `--stage` argument (preserving legacy behavior), the script performs both configuration and bulk restorations, but MUST enforce the active mountpoint assertion if bulk storage paths are targeted.

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The disaster recovery restore script (`scripts/restore-from-b2.sh`) MUST support a `--stage` parameter accepting `config`, `1`, `data`, `2`, and `all` (case-insensitive).
- **FR-002**: When invoked with `--stage config` or `--stage 1`, the system MUST restrict file restoration to the following paths:
  - `/etc/homelab` (host configuration, `vault.yml`, `monitoring.env`, application configuration definitions, backup scripts)
  - `/home/admin/.ssh` (GitHub deploy key, authorized keys)
  - `/home/admin/.gemini` (OAuth credentials)
  - `/home/admin/projects` (project source repositories)
- **FR-003**: When invoked with `--stage config` or `--stage 1`, the system MUST explicitly exclude bulk storage paths (`/mnt/storage` and all subpaths) and MUST skip the execution of post-restore hooks in `/etc/homelab/backup.d/`.
- **FR-004**: When invoked with `--stage config` or `--stage 1`, the system MUST enforce secure permissions (`0600` on secret files, `0700` on `.ssh` directories) and MUST synchronize the restored `/etc/homelab/vault.yml` to the repository configuration inventory at `ansible/inventory/group_vars/all/vault.yml`.
- **FR-005**: When invoked with `--stage data` or `--stage 2`, the system MUST perform an active mountpoint check asserting that `/mnt/storage` is an active mountpoint (`mountpoint -q /mnt/storage`) prior to initiating file extraction.
- **FR-006**: If `/mnt/storage` is not an active mountpoint when `--stage data` or `--stage 2` is invoked, the system MUST abort immediately with an exit code of 1 and print a `CRITICAL` error message to standard error explaining that restoration was halted to prevent root NVMe disk leakage.
- **FR-007**: When invoked with `--stage data` or `--stage 2`, the system MUST restore application service state (`/opt/services`) and bulk media assets (`/mnt/storage/media/photos`).
- **FR-008**: When invoked with `--stage data` or `--stage 2`, the system MUST ensure application container runtimes are running and MUST execute all executable post-restore hooks in `/etc/homelab/backup.d/*.sh` with the argument `post-restore`.
- **FR-009**: The workstation disaster recovery orchestrator (`scripts/restore-from-b2.ps1`) MUST accept a `-Stage` parameter accepting `config`, `1`, `data`, `2`, and `all`, and MUST propagate the corresponding `--stage` argument to `restore-from-b2.sh` during remote SSH execution.
- **FR-010**: The disaster recovery procedures in `docs/disaster-recovery-phase3.md` and `docs/operations.md` MUST be updated to document the staged recovery workflow, detailing Stage 1 execution, inter-stage Ansible execution (`site.yml`), and Stage 2 execution.
- **FR-011**: Both stages MUST support a `--dry-run` flag that lists the candidate snapshot contents matching that stage's path filters without downloading files or modifying filesystems.
- **FR-012**: The system MUST maintain backward compatibility when `--stage` is omitted or specified as `all`, executing a complete restoration while retaining the storage mountpoint assertion if bulk paths are restored.

### Key Entities

- **Disaster Recovery Staged Workflow**: The multi-phase operational process dividing bare-metal recovery into Stage 1 (System Bootstrap & Secrets), Inter-Stage Configuration Management (`ansible-playbook ... playbooks/site.yml`), and Stage 2 (Bulk Data & Application Services).
- **Stage 1 Bootstrap Payload**: The bounded subset of offsite backup data containing `/etc/homelab`, `/home/admin/.ssh`, `/home/admin/.gemini`, and `/home/admin/projects`.
- **Stage 2 Bulk Payload**: The high-capacity subset of offsite backup data containing `/opt/services` (service definitions, SQLite/PostgreSQL dumps, configuration data) and `/mnt/storage/media/photos` (pooled photo and video libraries).
- **Storage Mount Assertion**: The mandatory runtime check verifying that `/mnt/storage` is an active filesystem mountpoint before bulk data restoration is permitted.
- **Database Restoration Hook**: An executable shell script residing in `/etc/homelab/backup.d/*.sh` that accepts `post-restore` to load database dumps into running containers.

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Stage 1 configuration restoration completes within 2 minutes under standard broadband network connectivity.
- **SC-002**: Root NVMe storage experiences 0 bytes of bulk media data leakage during disaster recovery restoration.
- **SC-003**: 100% of bulk restoration attempts against an unmounted storage pool abort prior to downloading files or modifying disk state.
- **SC-004**: Configuration management playbook (`site.yml`) executes cleanly after Stage 1 with zero missing secret or missing repository errors.
- **SC-005**: All registered database restoration hooks execute with 100% success following Stage 2 bulk data extraction.
- **SC-006**: Remote workstation execution achieves full feature parity with local script execution across all supported stages.

---

## Assumptions

- A bare-metal or virtual host is running a clean Arch Linux base installation with user `admin` and network access prior to running Stage 1.
- The operator possesses the 4 Backblaze B2 bootstrap credentials (`B2_ACCOUNT_ID`, `B2_ACCOUNT_KEY`, `RESTIC_REPOSITORY`, `RESTIC_PASSWORD`) either as environment variables, command-line arguments, or stored in workstation configuration.
- The configuration management playbook (`site.yml`) handles drive partitioning, formatting, filesystem mounting, MergerFS pool setup at `/mnt/storage`, SnapRAID configuration, and Docker container engine installation during the inter-stage phase.
- Application container definitions under `/opt/services/*/compose.yml` and post-restore hooks under `/etc/homelab/backup.d/*.sh` are self-contained and idempotent.
- Restoring directly to `/` is the primary operational disaster recovery target; custom `--target-dir` invocations remain supported for inspection and non-root drills.
