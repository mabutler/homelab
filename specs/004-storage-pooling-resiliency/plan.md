# Implementation Plan: Storage Pooling & Data Resiliency Layer (Phase 4)

**Branch**: `004-storage-pooling-resiliency` | **Date**: 2026-11-01 | **Spec**: [`specs/004-storage-pooling-resiliency/spec.md`](file:///C:/Users/micro/projects/homelab2/specs/004-storage-pooling-resiliency/spec.md)

**Input**: Feature specification from [`specs/004-storage-pooling-resiliency/spec.md`](file:///C:/Users/micro/projects/homelab2/specs/004-storage-pooling-resiliency/spec.md) targeting bare-metal host `admin@192.168.4.57`.

---

## Summary

Deploy the storage pooling, tiering, and data resiliency subsystem for `homelab2` on bare-metal Arch Linux. This phase establishes a high-performance fast application tier on primary NVMe (`/opt/services`), aggregates disparate physical bulk hard drives into a single unified virtual filesystem at `/mnt/storage` using MergerFS with per-drive spin-down and balanced write policies, isolates high-wear CCTV and torrent downloads onto a dedicated scratch volume (`/mnt/scratch`), and configures snapshot-based parity protection and bit-rot scrubbing across bulk drives using SnapRAID with automated daily diff/sync and weekly scrub systemd timers. An automated safety runner guards against accidental mass deletions, and structured telemetry is routed to `systemd-journald` in compliance with Constitution Principles I, II, III, and V.

---

## Technical Context

**Language/Version**: Python 3.10+ (Ansible Core runtime on control node & host `/usr/local/bin/python3`), POSIX Shell / Bash 5.2+ (safety runner & verification scripts), PowerShell 7+ (Windows orchestrators)

**Primary Dependencies**:
- Storage Pooling: `mergerfs` (v2.33+, FUSE filesystem, system package)
- Parity & Data Resiliency: `snapraid` (v12.x+, system package)
- Base Filesystems: `e2fsprogs` / `xfsprogs`
- Automation: Ansible Core (playbooks, roles, handlers, templates)
- System Daemons: `systemd` (fstab mounts, timer units, service units, journald logging)

**Production Target Host**:
- Network Address: `192.168.4.57` (management LAN: `192.168.4.0/24`)
- Administrative User: `admin` (passwordless sudo privileges active)
- Storage Group: `storage` (GID 1001)

**Storage & Tiering Hierarchy**:
- Tier 0 (Fast NVMe App State): `/opt/services` (`admin:storage`, `0775`)
- Tier 1 (Bulk Storage Pool): `/mnt/storage` (MergerFS pooling `/mnt/disks/data*`, `admin:storage`, `2775`)
- Tier 1 (Physical Member Mounts): `/mnt/disks/data1`, `/mnt/disks/data2`, `/mnt/disks/parity1` (UUID mounts in `/etc/fstab`)
- Tier 2 (Scratch & CCTV Buffer): `/mnt/scratch` (Ext4 dedicated mount, `admin:storage`, `2775`, excluded from SnapRAID)
- Parity State Files: `/var/snapraid.content`, `/mnt/disks/data*/snapraid.content`, `/mnt/disks/parity1/snapraid.parity`

**Testing & Orchestration**:
- Production convergence runners:
  - Phase 4 dedicated playbook: `ansible/playbooks/storage.yml`
  - Cross-platform orchestrators: `scripts/apply-phase4.ps1` and `scripts/apply-phase4.sh`
- Acceptance verification suite:
  - Automated test script: `scripts/verify-phase4.sh`
  - Playbook verification: `ansible/playbooks/verify-phase4.yml` and unified `ansible/playbooks/verify.yml`
  - 10 automated acceptance assertions in [`verification-suite.md`](file:///C:/Users/micro/projects/homelab2/specs/004-storage-pooling-resiliency/contracts/verification-suite.md)

**Performance Goals**:
- Full Phase 4 convergence executes in under 5 minutes
- Unified pool reflects 100% of underlying member files with zero cataloging delay (SC-001)
- Read operations spin up only the single underlying disk containing the requested file (SC-002)
- Automated verification suite validates all mount points, permissions, and parity syntax in under 10 seconds (SC-005)
- Disaster recovery convergence restores complete storage layout from repo in under 15 minutes (SC-006)
- 100% of transient writes directed to `/mnt/scratch` produce 0 blocks of SnapRAID parity sync churn (SC-007)

**Constraints & Safeguards**:
- Administrative & boot safeguard: All disk mounts in `/etc/fstab` declare `nofail` and `x-systemd.device-timeout=10s` to prevent boot hangs.
- Deletion safety threshold: Parity safety runner (`snapraid-runner.sh`) halts `snapraid sync` and alerts journald if more than 50 files are marked for removal.
- Group permission consistency: Setgid bit (`2775`) strictly enforced on `/mnt/storage` and `/mnt/scratch` to guarantee multi-container read/write interoperability.

**Scale/Scope**: Multi-drive storage array supporting bulk household archives, Immich photo libraries, Frigate NVR CCTV feeds, and containerized microservices on `homelab2`.

---

## Constitution Check

*GATE: Evaluated prior to Phase 0 research and re-evaluated post-design.*

| Principle / Gate | Compliance Analysis | Status |
|---|---|---|
| **I. Pragmatic Declarative-First Automation** | Storage layout, MergerFS configuration, SnapRAID setup, and systemd timers are declared in Ansible roles (`storage_layout`, `mergerfs`, `snapraid`). The deletion threshold check uses a clean, self-contained shell runner (`snapraid-runner.sh`) in compliance with the pragmatic scripting fallback clause. | **PASS** |
| **II. Strict Idempotency & Safe Convergence** | All tasks use idempotent Ansible modules (`mount`, `template`, `systemd`, `file`). Destructive formatting operations are never executed silently; disks are mounted by pre-existing filesystem UUIDs. Reruns produce 0 unintended state changes. | **PASS** |
| **III. Automated Verification & Acceptance Gates** | 10 automated assertions defined in [`verification-suite.md`](file:///C:/Users/micro/projects/homelab2/specs/004-storage-pooling-resiliency/contracts/verification-suite.md) and runnable via `verify-phase4.sh`. Storage mount accessibility and SnapRAID sync/diff/scrub status are actively asserted and reported to `systemd-journald`. | **PASS** |
| **IV. Zero Cleartext Secrets & Isolated Configuration** | No plaintext credentials required for storage pooling or local parity. Any hardware-specific UUIDs are decoupled into inventory variables. | **PASS** |
| **V. Disaster Recovery & Backup by Design** | Drive UUID fstab entries, MergerFS configurations, SnapRAID definitions, and runner scripts are committed to version control. Parity synchronization protects against single disk loss, and scratch isolation prevents backing up transient churn. Ready for offsite Restic integration in Phase 7. | **PASS** |
| **VI. Modular & Decoupled Architecture** | Decomposed into three independent Ansible roles (`storage_layout`, `mergerfs`, `snapraid`). Storage tiers (`/opt/services`, `/mnt/storage`, `/mnt/scratch`) have decoupled paths and distinct lifecycle policies. | **PASS** |
| **VII. Stability-First & Annual Maintenance** | Uses mature, battle-tested utilities (`mergerfs`, `snapraid`, standard Ext4/XFS filesystems). Avoids fragile in-kernel RAID arrays or complex distributed filesystems. Independent disk filesystems remain directly readable on any Linux machine. | **PASS** |

**Constitution Gate Outcome**: **PASS**. Zero principle violations; no exemptions or overrides required.

---

## Project Structure

### Documentation (this feature)

```text
specs/004-storage-pooling-resiliency/
├── checklists/
│   └── requirements.md           # Specification quality checklist
├── contracts/
│   ├── mergerfs-contract.md      # MergerFS mount syntax, options, write policies
│   ├── snapraid-contract.md      # SnapRAID config, safety runner script, systemd units
│   ├── storage-layout-contract.md# Mount paths, UUID standards, permissions, storage group
│   └── verification-suite.md     # 10 automated acceptance assertions and test protocol
├── data-model.md                 # StorageDisk, StoragePool, ParityConfig, SnapRaidJob entities
├── plan.md                       # This implementation plan
├── quickstart.md                 # Step-by-step convergence and validation guide
├── research.md                   # Phase 0 architectural decisions, rationale, alternatives
└── spec.md                       # Feature specification
```

### Source Code (repository root)

```text
ansible/
├── inventory/
│   ├── group_vars/all/
│   │   └── vars.yml              # Storage defaults, group GID, diff threshold
│   └── host_vars/homelab2/
│       └── storage.yml           # Host-specific drive UUIDs and mount mapping
├── playbooks/
│   ├── site.yml                  # Unified platform playbook (includes storage.yml)
│   ├── storage.yml               # Dedicated Phase 4 storage convergence playbook
│   ├── verify-phase4.yml         # Dedicated Phase 4 verification playbook
│   └── verify.yml                # Unified verification playbook
└── roles/
    ├── mergerfs/
    │   ├── defaults/main.yml     # MergerFS mount options and branch patterns
    │   ├── handlers/main.yml     # Systemd daemon-reload & remount handlers
    │   └── tasks/main.yml        # Package install, fstab entry, mount assertion
    ├── snapraid/
    │   ├── defaults/main.yml     # Parity disks, content paths, exclude list
    │   ├── handlers/main.yml     # Systemd timer reload handlers
    │   ├── tasks/main.yml        # Package install, config template, runner script, timers
    │   └── templates/
    │       ├── snapraid-runner.sh.j2
    │       ├── snapraid-scrub.service.j2
    │       ├── snapraid-scrub.timer.j2
    │       ├── snapraid-sync.service.j2
    │       ├── snapraid-sync.timer.j2
    │       └── snapraid.conf.j2
    └── storage_layout/
        ├── defaults/main.yml     # Default directory paths, group ownership
        └── tasks/main.yml        # Storage group creation, directory hierarchy, physical fstab mounts

scripts/
├── apply-phase4.ps1              # Windows orchestration runner for storage convergence
├── apply-phase4.sh               # Linux/macOS orchestration runner for storage convergence
├── verify-phase4.ps1             # Windows verification runner
└── verify-phase4.sh              # Host-side automated test script evaluating STO-01 to STO-10
```

---

## Complexity Tracking

> **Constitution Check passed with zero violations. No complexity overrides required.**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| *None* | *N/A* | *N/A* |
