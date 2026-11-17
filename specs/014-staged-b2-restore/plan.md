# Implementation Plan: Staged Backblaze B2 Disaster Recovery Restoration

**Branch**: `014-staged-b2-restore` | **Date**: 2026-11-10 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/014-staged-b2-restore/spec.md`

<!--
Template Resolution Hierarchy & FeatureContext Specification:
This template is resolved by agent skills using the native 4-tier template resolution hierarchy:
- Tier 1 (Overrides): .specify/templates/overrides/plan-template.md
- Tier 2 (Presets): .specify/presets/<preset-id>/templates/plan-template.md (evaluated per .specify/presets/.registry sorted ascending by priority; strategy: replace, prepend, append, wrap)
- Tier 3 (Extensions): .specify/extensions/<ext-id>/templates/plan-template.md (evaluated per .specify/extensions/.registry sorted ascending by priority)
- Tier 4 (Core Fallback): .specify/templates/plan-template.md

Invariant: If a requested template is not found in any of the 4 tiers, the agent MUST fail closed and emit an error per Principle II

FeatureContext Resolution:
feature_directory MUST NOT be empty and ${FEATURE_DIR} MUST exist for downstream skills.
Context is discovered via SPECIFY_FEATURE_DIRECTORY env variable or .specify/feature.json.
-->

## Summary

Refactor the standalone Backblaze B2 / Restic disaster recovery tooling (`scripts/restore-from-b2.sh`, `ansible/roles/backup/files/restore-from-b2.sh`, and workstation wrapper `scripts/restore-from-b2.ps1`) to support a multi-stage bare-metal restoration workflow via `--stage <config|1|data|2|all>` (and `-Stage` in PowerShell).

- **Stage 1 (`--stage config` or `--stage 1`)**: Executes on a clean OS installation prior to Ansible convergence. Restores only `/etc/homelab`, `/home/admin/.ssh`, `/home/admin/.gemini`, and `/home/admin/projects`, enforces restrictive `0600`/`0700` permissions and `admin:users` ownership, synchronizes `/etc/homelab/vault.yml` to `ansible/inventory/group_vars/all/vault.yml`, explicitly excludes `/mnt/storage` bulk data, and skips post-restore database hooks (`backup.d/*.sh`).
- **Inter-Stage (`ansible-playbook playbooks/site.yml`)**: Installs Docker, configures networking/firewall/Caddy, partitions/mounts the MergerFS storage pool at `/mnt/storage`, configures SnapRAID, and deploys application systemd units.
- **Stage 2 (`--stage data` or `--stage 2`)**: Enforces a mandatory pre-extraction mountpoint assertion (`mountpoint -q /mnt/storage`)—halting immediately with exit code `1` and a `CRITICAL` error to `stderr` if `/mnt/storage` is unmounted to prevent root NVMe disk exhaustion—then extracts `/opt/services` and `/mnt/storage/media/photos`, ensures container services are running, and executes all executable `/etc/homelab/backup.d/*.sh post-restore` database hooks.

---

## Technical Context

**Language/Version**:
- Automation & Scripting: POSIX / Bash 5.2+ (`scripts/restore-from-b2.sh`, `scripts/verify-phase5-backup.sh`), PowerShell 7+ (`scripts/restore-from-b2.ps1`, `scripts/verify-phase5-backup.ps1`), Ansible Core 2.16+ (`ansible/roles/backup/`, `ansible/playbooks/verify-phase5-backup.yml`)
- Backup CLI: Go (`restic` 0.16+)

**Primary Dependencies**:
- `restic` (Backblaze B2 client-side encrypted snapshot extraction and listing)
- `util-linux` (`mountpoint -q` kernel mount table verification)
- `systemd` (`systemctl` for verifying/starting `docker.service` and application units during Stage 2 hook execution)
- `sqlite3` and `docker compose` (`pg_restore` inside `immich_postgres`) invoked by `/etc/homelab/backup.d/*.sh post-restore`

**Storage**:
- Root / Fast NVMe Tier (`/dev/nvme0n1p2`): `/etc/homelab`, `/home/admin/{.ssh,.gemini,projects}`, and `/opt/services`
- Pooled Bulk Storage Tier (MergerFS `storage_pool` mounted at `/mnt/storage`): `/mnt/storage/media/photos` (`library`, `upload`, `profile`)
- Offsite Backup Store: Backblaze B2 (`b2:fidelacchius-backups:fidelacchius`)

**Testing**:
- In strict compliance with Constitution Principle III, ZERO automated unit test files, test directories, or mock frameworks are created.
- Static Analysis & Syntax Verification: `bash -n`, `shellcheck`, and `ansible-lint` across all modified scripts and playbooks.
- Live Acceptance Verification Gate: `scripts/verify-phase5-backup.sh`, `scripts/verify-phase5-backup.ps1`, and `ansible/playbooks/verify-phase5-backup.yml` extended from 8 assertions (`BK-001`–`BK-008`) to 12 assertions (`BK-001`–`BK-012`) covering Stage 1 path filtering, Stage 2 unmounted storage abort, invalid stage rejection, and Stage 1 non-destructive restore rehearsal.

**Target Platform**:
- Bare-metal Arch Linux x86_64 server `fidelacchius` (`admin@192.168.4.57`) and Windows/Linux operator workstations.

**Project Type**:
- Infrastructure disaster recovery CLI tooling, Ansible backup role synchronization, automated verification harness, and operational runbook documentation.

**Performance Goals**:
- Stage 1 (`--stage config` / `--stage 1`) bootstrap restoration completes in `< 2 minutes` over standard broadband (SC-001).
- Unmounted `/mnt/storage` check executes in `< 50ms` and aborts prior to any network payload download (SC-002, SC-003).

**Constraints**:
- Root NVMe drive MUST experience `0 bytes` of bulk media leakage if `/mnt/storage` is unmounted (SC-002, FR-005, FR-006).
- Zero secrets committed to Git; `vault.yml` is restored from encrypted Backblaze B2 and synchronized directly to gitignored `ansible/inventory/group_vars/all/vault.yml` with mode `0600` (Principle IV, FR-004).
- Full backward compatibility when `--stage` is omitted or set to `all` (FR-012).

**Scale/Scope**:
- Single bare-metal node (`fidelacchius`) with multi-terabyte MergerFS storage pool (`/mnt/storage`) and containerized service stacks (`/opt/services/{vaultwarden,frigate,immich}`).

**Documentation Impact**:
- `USER_FACING`: Modifies operator-visible CLI flags (`--stage` on `scripts/restore-from-b2.sh` and `-Stage` on `scripts/restore-from-b2.ps1`) and disaster recovery operational workflows. Updates `docs/full-restore-runbook.md`, `docs/disaster-recovery-phase3.md`, `docs/operations.md`, `README.md`, and `ROADMAP.md` in the same change per `.specify/memory/coding-standards.md` and Principle VII.

---

## Constitution Check

*GATE: Evaluated prior to Phase 0 research and re-verified after Phase 1 design.*

| Principle / Gate | Compliance Analysis | Status |
|---|---|---|
| **I. Evidence Over Invention, Bounded Investigation & Pragmatic Declarative-First Automation** | All restoration paths (`/etc/homelab`, `/home/admin/.ssh`, `/home/admin/.gemini`, `/home/admin/projects`, `/opt/services`, `/mnt/storage/media/photos`) trace directly to `ansible/roles/backup/defaults/main.yml` and `docs/full-restore-runbook.md`. Script updates maintain synchronization between `scripts/restore-from-b2.sh` and `ansible/roles/backup/files/restore-from-b2.sh` deployed to `/usr/local/bin/restore-from-b2.sh`. | **PASS** |
| **II. Two-Tier Failure Model, Fail Closed on Required State & Strict Idempotency** | Invalid `--stage` arguments fail closed with exit code `1` during CLI parsing. Missing `/mnt/storage` mountpoint during Stage 2 (`data`/`2`) logs `CRITICAL:` to `stderr` and exits with code `1` before `restic restore` runs. All scripts enforce `set -euo pipefail` (and `$ErrorActionPreference = "Stop"`). | **PASS** |
| **III. Behavioral, Value-Driven Testing, Deterministic Execution & Live Acceptance Gates** | Zero unit test suites or mock harnesses are added (Skip Allowlist #5: provisioning/recovery scripts verified by linters and live acceptance gates). Verification is enforced via `bash -n`, `shellcheck`, `ansible-lint`, and live assertions `BK-001` through `BK-012` in `scripts/verify-phase5-backup.sh` and `ansible/playbooks/verify-phase5-backup.yml`. | **PASS** |
| **IV. Single Authoritative State, Enforced Boundaries, Safe Concurrency & Zero Secrets in Git** | `scripts/restore-from-b2.sh` and `ansible/roles/backup/files/restore-from-b2.sh` remain identical and deployed to `/usr/local/bin/restore-from-b2.sh`. Restored secrets (`/etc/homelab/vault.yml`, `.ssh/id_ed25519_github`, `.gemini/oauth_creds.json`) enforce `0600` permissions and remain strictly gitignored. | **PASS** |
| **V. Centralized Dependencies, Protected Toolchain Gate & Disaster Recovery by Design** | No new third-party dependencies or packages are added (`mountpoint` is part of core `util-linux` on Arch Linux). Directly strengthens Principle V by eliminating the bare-metal bootstrap dependency loop between Restic restoration and Ansible storage/Docker convergence. | **PASS** |
| **VI. Bounded Resources & Verify-Before-Destroy** | Enforces non-empty directory guard (`--force` required) and active mountpoint verification (`mountpoint -q`) prior to extracting multi-gigabyte media archives, preventing root NVMe capacity exhaustion. | **PASS** |
| **VII. Code Hygiene, Ubiquitous Language & Safe Logging** | Logs use structured severity prefixes (`CRITICAL`, `WARN`, `INFO`) on appropriate streams (`stderr` for errors/warnings, `stdout` for milestones) with zero credential exposure. Human-facing documentation (`docs/full-restore-runbook.md`, `docs/disaster-recovery-phase3.md`, `docs/operations.md`, `README.md`, `ROADMAP.md`) is updated in tandem. | **PASS** |

**Gate Evaluation (Pre-Phase 0 & Post-Phase 1)**: **PASS**. Zero constitutional violations.

---

## Project Structure

### Documentation (this feature)

```text
specs/014-staged-b2-restore/
├── spec.md                                # Feature specification
├── plan.md                                # This implementation plan (/speckit-plan output)
├── research.md                            # Phase 0 architectural decisions & research findings
├── data-model.md                          # Phase 1 stage definitions, entities & state transitions
├── quickstart.md                          # Phase 1 operator validation & staged recovery guide
├── contracts/                             # Phase 1 interface & verification contracts
│   ├── staged-restore-contract.md         # CLI contract for restore-from-b2.sh & restore-from-b2.ps1
│   └── verification-contract.md           # Acceptance assertions BK-001 through BK-012
├── checklists/
│   └── requirements.md                    # Specification quality checklist
└── tasks.md                               # Phase 2 output (/speckit-tasks command - created in next stage)
```

### Source Code (repository root)

```text
scripts/
├── restore-from-b2.sh                     # Updated with --stage (config|1|data|2|all), mountpoint guard, permission sync & container startup
├── restore-from-b2.ps1                    # Updated with -Stage parameter and SSH propagation
├── verify-phase5-backup.sh                # Extended with BK-009..BK-012 staged restore assertions
└── verify-phase5-backup.ps1               # Workstation wrapper for backup acceptance verification

ansible/
├── playbooks/
│   └── verify-phase5-backup.yml           # Extended with BK-009..BK-012 Ansible verification tasks
└── roles/
    └── backup/
        ├── files/
        │   └── restore-from-b2.sh         # Synchronized copy deployed to /usr/local/bin/restore-from-b2.sh
        └── tasks/
            └── runner.yml                 # Deploys restore-from-b2.sh to /usr/local/bin/restore-from-b2.sh

docs/
├── full-restore-runbook.md                # Updated to 3-phase staged restore (Stage 1 -> site.yml -> Stage 2)
├── disaster-recovery-phase3.md            # Updated with staged B2 bootstrap cross-reference and Stage 1 secrets recovery
└── operations.md                          # Updated backup & recovery sections to reflect --stage config and --stage data

README.md                                  # Updated governance & disaster recovery documentation references
ROADMAP.md                                 # Updated Phase 5 Backblaze B2 & Restic pipeline entry with staged DR support
```

**Structure Decision**:
Modifies existing disaster recovery scripts (`scripts/restore-from-b2.{sh,ps1}`), the Ansible backup role's deployed script (`ansible/roles/backup/files/restore-from-b2.sh`), the backup acceptance suite (`scripts/verify-phase5-backup.sh` and `ansible/playbooks/verify-phase5-backup.yml`), and the canonical operational documentation (`docs/full-restore-runbook.md`, `docs/disaster-recovery-phase3.md`, `docs/operations.md`, `README.md`, `ROADMAP.md`). Zero new directories or dependencies are introduced outside `specs/014-staged-b2-restore/`.

---

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

*No constitutional violations identified. Zero complexity exemptions required.*
