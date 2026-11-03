# Tasks: Centralized Backblaze B2 Backup & Automated Disaster Recovery

**Input**: Design documents from `/specs/006-backblaze-backup-restore/`  
**Prerequisites**: [plan.md](file:///C:/Users/micro/projects/homelab2/specs/006-backblaze-backup-restore/plan.md), [spec.md](file:///C:/Users/micro/projects/homelab2/specs/006-backblaze-backup-restore/spec.md), [research.md](file:///C:/Users/micro/projects/homelab2/specs/006-backblaze-backup-restore/research.md), [data-model.md](file:///C:/Users/micro/projects/homelab2/specs/006-backblaze-backup-restore/data-model.md), [contracts/](file:///C:/Users/micro/projects/homelab2/specs/006-backblaze-backup-restore/contracts/)  

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story, followed by end-to-end rollout to `admin@192.168.4.57`.

---

## Phase 1: Setup (Shared Infrastructure & Secret Templates)

**Purpose**: Project initialization, template updates, and directory layout scaffolding.

- [X] T001 [P] Ensure Backblaze B2 credential definitions are declared in template `ansible/inventory/group_vars/all/vault.yml.example` with constraints: `vault_b2_account_id` "Non-empty alphanumeric string (25+ characters)", `vault_b2_account_key` "Non-empty alphanumeric string (31+ characters)", `vault_restic_repository` "Valid URI prefix starting with b2:", `vault_restic_password` "Minimum 16 characters, high entropy"
- [X] T002 [P] Update `.gitignore` to enforce zero secrets in version control (Constitution Principle IV) ensuring `ansible/inventory/group_vars/all/vault.yml`, `/etc/homelab/vault.yml`, and `backup.env` are strictly excluded from git
- [X] T003 [P] Define backup role defaults in `ansible/roles/backup/defaults/main.yml` with retention_policy "7d, 5w, 12m", timer schedules (`02:30` daily, `Sun 04:00` weekly), and exclude globs (`*.sqlite3`, `*.db`, `*.sqlite3-wal`, `*.sqlite3-shm`, `*.sock`, `*.log`, `*.tmp`)
- [X] T004 [P] Create backup deployment playbook in `ansible/playbooks/backup.yml` targeting `homelab_nodes` with the `backup` role

---

## Phase 2: Foundational (Core Role Tasks, Environment & Manifest Templates)

**Purpose**: Core infrastructure and configuration templates that MUST be complete before user stories can execute.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T005 [P] Implement package installation tasks in `ansible/roles/backup/tasks/packages.yml` installing `restic` (upstream restic 0.16+) and `sqlite3` CLI via pacman
- [X] T006 [P] Implement systemd notification handlers in `ansible/roles/backup/handlers/main.yml` for systemd daemon-reload, restart homelab-backup.timer, and restart homelab-backup-check.timer
- [X] T007 Implement filesystem directories and permissions in `ansible/roles/backup/tasks/config.yml` ensuring `/etc/homelab` is mode `0750 root:root` and `/etc/homelab/apps` is mode "0700 root:root"
- [X] T008 [P] Create Jinja2 credentials template in `ansible/roles/backup/templates/backup.env.j2` rendering `B2_ACCOUNT_ID`, `B2_ACCOUNT_KEY`, `RESTIC_REPOSITORY`, and `RESTIC_PASSWORD` with mode "0600 root:root"
- [X] T009 [P] Create backup inclusion manifest template in `ansible/roles/backup/templates/backup-include.txt.j2` specifying `/etc/homelab/vault.yml`, `/etc/homelab/apps`, and `/opt/services` with mode `0644 root:root`
- [X] T010 [P] Create backup exclusion manifest template in `ansible/roles/backup/templates/backup-excludes.txt.j2` specifying "Live db.sqlite3 MUST be excluded from Restic backup archives" (`*.sqlite3`, `*.db`, `*.sqlite3-wal`, `*.sqlite3-shm`, `*.sock`, `*.log`, `*.tmp`, `/opt/services/*/backups/vaultwarden-backup-*.tar.gz`)
- [X] T011 Implement host secrets deployment in `ansible/roles/backup/tasks/config.yml` deploying `/etc/homelab/vault.yml` where "Permissions on /etc/homelab/vault.yml MUST be 0600 owned by root:root" and "File MUST be captured in every Restic snapshot"
- [X] T012 Implement master role task orchestrator in `ansible/roles/backup/tasks/main.yml` importing `packages.yml`, `config.yml`, `runner.yml`, `hooks.yml`, and `service.yml`

**Checkpoint**: Core role structure, credentials templates, manifests, and foundational configuration tasks ready. User story implementation can now begin.

---

## Phase 3: User Story 1 - Continuous Automated Offsite Backups to Backblaze B2 (Priority: P1)

**Goal**: Implement the centralized backup runner script `/usr/local/bin/homelab-backup`, execute pre-backup hooks, upload client-side encrypted snapshots to Backblaze B2, exclude live databases, and supervise daily execution via systemd timer at 02:30.

**Independent Test**: Trigger `/usr/local/bin/homelab-backup run`, verify exit code 0, confirm client-side encrypted snapshot (AES-256 Poly1305) is saved in Backblaze B2 containing `/etc/homelab/vault.yml` (`0600 root:root`) and application snapshots while excluding live `db.sqlite3`.

### Tests for User Story 1

- [X] T013 [P] [US1] Create automated backup acceptance verification script in `scripts/verify-phase5-backup.sh` implementing assertions BK-001 through BK-007 (Restic installed, backup.env mode "0600 root:root", B2 repository connectivity, vault.yml included, live DB excluded, dry-run hook passes, timers active) per `contracts/backup-verification-contract.md`
- [X] T014 [P] [US1] Create workstation verification runner in `scripts/verify-phase5-backup.ps1` executing `scripts/verify-phase5-backup.sh` over SSH against `admin@192.168.4.57`

### Implementation for User Story 1

- [X] T015 [P] [US1] Create centralized backup runner script template in `ansible/roles/backup/templates/homelab-backup.j2` implementing `run`, `snapshots`, and `unlock` subcommands with flags `--dry-run`, `--verbose`, and `--config-file` per `contracts/backup-runner-contract.md`
- [X] T016 [US1] Implement pre-backup hook execution loop in `ansible/roles/backup/templates/homelab-backup.j2` discovering `/etc/homelab/backup.d/*.sh` with argument `pre-backup` where "Must accept pre-backup and post-restore arguments" and "Must return exit code 0 on success; non-zero fails the backup routine"
- [X] T017 [US1] Implement Restic backup invocation in `ansible/roles/backup/templates/homelab-backup.j2` loading `/etc/homelab/backup.env`, applying tags "homelab2, daily", and backing up with `--files-from=/etc/homelab/backup-include.txt` and `--exclude-file=/etc/homelab/backup-excludes.txt`
- [X] T018 [P] [US1] Create systemd daily backup service template in `ansible/roles/backup/templates/homelab-backup.service.j2` with `Type=oneshot`, `EnvironmentFile=/etc/homelab/backup.env`, `ExecStart=/usr/local/bin/homelab-backup run`, and `TimeoutSec=900`
- [X] T019 [P] [US1] Create systemd daily backup timer template in `ansible/roles/backup/templates/homelab-backup.timer.j2` with `OnCalendar=*-*-* 02:30:00`, `Persistent=true`, and `RandomizedDelaySec=300`
- [X] T020 [US1] Implement runner deployment task in `ansible/roles/backup/tasks/runner.yml` deploying `/usr/local/bin/homelab-backup` with mode `0755 root:root`
- [X] T021 [US1] Implement service and timer deployment tasks in `ansible/roles/backup/tasks/service.yml` enabling and starting `homelab-backup.service` and `homelab-backup.timer`

**Checkpoint**: User Story 1 is complete; daily automated offsite backup runs on schedule with journal logging and atomic pre-backup dumps.

---

## Phase 4: User Story 2 - One-Command Automated Disaster Recovery & Secret Restoration (Priority: P1) 🎯 MVP

**Goal**: Standalone disaster recovery restoration scripts (`restore-from-b2.sh` and `restore-from-b2.ps1`) capable of restoring `vault.yml` and stateful application data on clean bare metal using only the 4 bootstrap credentials with non-empty directory overwrite guards.

**Independent Test**: Run `scripts/restore-from-b2.sh --target-dir /tmp/b2-test-restore --include-path etc/homelab/vault.yml --force`; verify exit code 0, permissions `0600 root:root`, and SHA-256 match with `/etc/homelab/vault.yml`. Assert refusal without `--force` on non-empty directories.

### Tests for User Story 2

- [X] T022 [P] [US2] Add BK-008 non-destructive restore assertion to `scripts/verify-phase5-backup.sh` verifying `restore-from-b2.sh` extracts `vault.yml` to `/tmp/b2-test-restore` and matches SHA-256 checksum

### Implementation for User Story 2

- [X] T023 [P] [US2] Implement standalone Linux disaster recovery script in `scripts/restore-from-b2.sh` supporting `--account-id`, `--account-key`, `--repository`, `--password`, `--snapshot` (default `latest`), `--target-dir` (default `/`), `--include-path`, `--dry-run`, and strict overwrite guards requiring `--force` per `contracts/disaster-recovery-contract.md`
- [X] T024 [P] [US2] Implement workstation disaster recovery orchestrator in `scripts/restore-from-b2.ps1` extracting credentials from `ansible/inventory/group_vars/all/vault.yml` and orchestrating SSH execution against the target host
- [X] T025 [US2] Implement permissions restoration in `scripts/restore-from-b2.sh` restoring `/etc/homelab/vault.yml` where "Permissions on /etc/homelab/vault.yml MUST be 0600 owned by root:root" and application data `/opt/services/*/data` with owner `1000:1000` and mode `0700`
- [X] T026 [US2] Implement post-restore hook execution in `scripts/restore-from-b2.sh` invoking `/etc/homelab/backup.d/*.sh post-restore` when target is `/`
- [X] T027 [P] [US2] Create standalone Ansible verification playbook in `ansible/playbooks/verify-phase5-backup.yml` implementing assertions BK-001 through BK-008

**Checkpoint**: User Story 2 (MVP) is fully functional; node secrets and app state can be restored on clean hardware from Backblaze B2 using only the 4 bootstrap credentials.

---

## Phase 5: User Story 3 - Retention Rotation, Pruning & Snapshot Health Telemetry (Priority: P2)

**Goal**: Implement automated retention pruning (7 daily, 5 weekly, 12 monthly snapshots) and schedule weekly 5% repository data integrity verification checks via systemd timers with structured journal logging.

**Independent Test**: Run `/usr/local/bin/homelab-backup check` and `/usr/local/bin/homelab-backup prune`; verify exit code 0, check output reports complete consistency to journald, and `homelab-backup-check.timer` reports active status.

### Implementation for User Story 3

- [X] T028 [P] [US3] Implement prune subcommand in `ansible/roles/backup/templates/homelab-backup.j2` executing `restic forget --keep-daily 7 --keep-weekly 5 --keep-monthly 12 --prune` with retention_policy "7d, 5w, 12m" and exit code 4 on failure
- [X] T029 [P] [US3] Implement check subcommand in `ansible/roles/backup/templates/homelab-backup.j2` executing `restic check --read-data-subset=5%` with exit code 5 on corruption per `contracts/backup-runner-contract.md`
- [X] T030 [P] [US3] Create weekly repository integrity check systemd service template in `ansible/roles/backup/templates/homelab-backup-check.service.j2` with `Type=oneshot`, `EnvironmentFile=/etc/homelab/backup.env`, `ExecStart=/usr/local/bin/homelab-backup check`, and `TimeoutSec=1800`
- [X] T031 [P] [US3] Create weekly repository integrity check systemd timer template in `ansible/roles/backup/templates/homelab-backup-check.timer.j2` with `OnCalendar=Sun *-*-* 04:00:00` and `Persistent=true`
- [X] T032 [US3] Update systemd tasks in `ansible/roles/backup/tasks/service.yml` deploying, enabling, and starting `homelab-backup-check.service` and `homelab-backup-check.timer`

**Checkpoint**: User Story 3 is complete; retention policy is enforced on every backup run and weekly repository data integrity checks are supervised by systemd.

---

## Phase 6: User Story 4 - Standardized Per-App Backup Onboarding Contract (Priority: P2)

**Goal**: Implement the per-app backup hook contract in `/etc/homelab/backup.d/`, migrate Vaultwarden to standardized pre-backup SQLite snapshots, and document onboarding guidelines for future Phase 5 services.

**Independent Test**: Run `/etc/homelab/backup.d/10-vaultwarden.sh pre-backup`, verify that `/opt/services/vaultwarden/backups/snapshot.sqlite3` is created and passes `PRAGMA integrity_check; == "ok"`. Run `post-restore` and verify permissions are set to `1000:1000` (`0700`/`0600`).

### Implementation for User Story 4

- [X] T033 [P] [US4] Implement Vaultwarden hook template in `ansible/roles/backup/templates/10-vaultwarden.sh.j2` where executable_path is `/etc/homelab/backup.d/10-vaultwarden.sh` mode "0750 root:root", implementing `pre-backup` (quiesce with `sqlite3 VACUUM INTO` where "snapshot_path MUST pass sqlite3 '$snapshot_path' 'PRAGMA integrity_check;' == 'ok' before Restic starts") and `post-restore` (restore snapshot to `db.sqlite3` if missing, `chown 1000:1000`, `chmod 0700/0600`) per `contracts/app-backup-contract.md`
- [X] T034 [US4] Implement hook deployment tasks in `ansible/roles/backup/tasks/hooks.yml` ensuring `/etc/homelab/backup.d` directory exists (mode `0750 root:root`) and deploying `10-vaultwarden.sh` (mode `0750 root:root`)
- [X] T035 [US4] Update Vaultwarden role backup tasks in `ansible/roles/vaultwarden/tasks/backup.yml` removing legacy local backup timer/service (`vaultwarden-backup.timer`, `vaultwarden-backup.service`) and delegating entirely to `/etc/homelab/backup.d/`

**Checkpoint**: User Story 4 is complete; Vaultwarden is fully onboarded to the standardized backup contract and ready for subsequent Phase 5 services.

---

## Final Phase: Polish & Cross-Cutting Concerns

**Purpose**: System integration, deployment script updates, live target node rollout (`admin@192.168.4.57`), operational runbook validation, and linting.

- [X] T036 [P] Update master site convergence playbook in `ansible/playbooks/site.yml` to include role `backup` after `vaultwarden` under `homelab_nodes`
- [X] T037 [P] Update unified platform verification playbook in `ansible/playbooks/verify.yml` to import `playbooks/verify-phase5-backup.yml` and include BK-001 through BK-008 in the summary report
- [X] T038 [P] Update workstation deployment runner in `scripts/apply-phase5.ps1` and server runner in `scripts/apply-phase5.sh` to support deploying `playbooks/backup.yml` and default `HostAddress` to `192.168.4.57`
- [X] T039 Execute Phase 5 backup deployment to target node `admin@192.168.4.57` via `scripts/apply-phase5.ps1 -HostAddress 192.168.4.57 -User admin -Playbook playbooks/backup.yml`
- [X] T040 Verify or initialize Restic Backblaze B2 repository on `admin@192.168.4.57` via `ssh admin@192.168.4.57 "source /etc/homelab/backup.env && restic -r \$RESTIC_REPOSITORY snapshots >/dev/null 2>&1 || restic -r \$RESTIC_REPOSITORY init"`
- [X] T041 Execute initial live backup run on `admin@192.168.4.57` via `ssh admin@192.168.4.57 "sudo /usr/local/bin/homelab-backup run"` and verify snapshot creation in Backblaze B2
- [X] T042 Execute remote acceptance verification suite via `scripts/verify-phase5-backup.ps1 -TargetHost 192.168.4.57 -User admin` and confirm all 8 assertions (BK-001 through BK-008) pass
- [X] T043 Rehearse non-destructive disaster recovery on `admin@192.168.4.57` restoring `/etc/homelab/vault.yml` to `/tmp/b2-test-restore` and comparing SHA-256 checksums
- [X] T044 [P] Validate operational runbook in `specs/006-backblaze-backup-restore/quickstart.md` ensuring all commands match the finalized contracts
- [X] T045 [P] Run syntax and lint checks across `ansible/roles/backup/`, `ansible/playbooks/backup.yml`, and bash scripts in `scripts/`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately.
- **Foundational (Phase 2)**: Depends on Phase 1 — BLOCKS all user stories.
- **User Story 1 (Phase 3)**: Depends on Phase 2 completion.
- **User Story 2 (Phase 4 🎯 MVP)**: Depends on Phase 2 completion. Can proceed in parallel with User Story 1.
- **User Story 3 (Phase 5)**: Depends on User Story 1 (extends backup runner with prune and check).
- **User Story 4 (Phase 6)**: Depends on User Story 1 (integrates app hooks with backup runner).
- **Final Phase (Polish & Rollout)**: Depends on all user stories (Phases 3-6) being complete.

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2). No dependencies on other stories.
- **User Story 2 (P1 🎯 MVP)**: Can start after Foundational (Phase 2). Operates independently of scheduled backups using standalone recovery scripts.
- **User Story 3 (P2)**: Builds upon the backup runner created in US1 by adding retention pruning and weekly integrity checks.
- **User Story 4 (P2)**: Standardizes app hooks (`10-vaultwarden.sh`) consumed by the US1 backup runner.

### Within Each User Story

- Test scripts / assertions implemented and verified against failure state first.
- Configuration templates before runner integration.
- Runner implementation before systemd unit supervision.
- Story complete and independently verified before moving to next priority.

### Parallel Opportunities

- **Phase 1**: T001, T002, T003, T004 can run in parallel.
- **Phase 2**: T005, T006, T008, T009, T010 can run in parallel.
- **User Stories 1 & 2**: Once Phase 2 completes, US1 tasks (T013, T014, T015, T018, T019) and US2 tasks (T022, T023, T024, T027) can be executed in parallel.
- **Phase 5**: T028, T029, T030, T031 can run concurrently.
- **Final Phase**: T036, T037, T038 can be prepared in parallel before executing deployment on `admin@192.168.4.57` (T039).

---

## Parallel Example: User Story 1

```bash
# Launch verification test scripts in parallel:
Task: "Create automated backup acceptance verification script in scripts/verify-phase5-backup.sh"
Task: "Create workstation verification runner in scripts/verify-phase5-backup.ps1"

# Launch systemd unit templates in parallel:
Task: "Create systemd daily backup service template in ansible/roles/backup/templates/homelab-backup.service.j2"
Task: "Create systemd daily backup timer template in ansible/roles/backup/templates/homelab-backup.timer.j2"
```

## Parallel Example: User Story 2 (MVP)

```bash
# Launch recovery scripts in parallel:
Task: "Implement standalone Linux disaster recovery script in scripts/restore-from-b2.sh"
Task: "Implement workstation disaster recovery orchestrator in scripts/restore-from-b2.ps1"
Task: "Create standalone Ansible verification playbook in ansible/playbooks/verify-phase5-backup.yml"
```

---

## Implementation Strategy

### MVP First (User Story 2: Disaster Recovery & Secret Restoration)

1. Complete Phase 1: Setup (credentials template, `.gitignore`, variable defaults)
2. Complete Phase 2: Foundational (packages, environment config, manifest files)
3. Complete Phase 4: User Story 2 (standalone restore scripts `restore-from-b2.sh` and `restore-from-b2.ps1`)
4. **STOP and VALIDATE**: Verify that `restore-from-b2.sh` can authenticate using only the 4 bootstrap credentials and restore secrets to `/tmp/b2-test-restore`

### Incremental Delivery

1. Complete Phase 1 & 2 -> Foundation ready
2. Add Phase 3 (US1) -> Daily automated backups to Backblaze B2 operational
3. Add Phase 4 (US2) -> Standalone disaster recovery tested & verified (MVP!)
4. Add Phase 5 (US3) -> Retention rotation (7d/5w/12m) and weekly integrity checks active
5. Add Phase 6 (US4) -> Vaultwarden and future Phase 5 services onboarded via `/etc/homelab/backup.d/`
6. Final Phase -> Full rollout and acceptance verification on `admin@192.168.4.57`


---

## Phase 7: Convergence

- [X] T046 Remove or update obsolete `vaultwarden-backup.timer` assertion (VW-09) in `ansible/playbooks/verify.yml` per T035 and T037 (contradicts)
- [X] T047 Align default target host IP from 192.168.4.58 to 192.168.4.57 in `scripts/verify-phase5-backup.ps1` and `scripts/restore-from-b2.ps1` per plan target platform (partial)
- [X] T048 Address unused `APP_NAME` in `ansible/roles/backup/templates/10-vaultwarden.sh.j2` to pass Shellcheck SC2034 cleanly per T045 (partial)
- [X] T049 Refactor eval invocation and restore function in `scripts/verify-phase5-backup.sh` to eliminate Shellcheck SC2294 and SC2329 warnings per T045 (partial)

---

## Phase 8: Convergence

- [X] T050 Update ansible/roles/backup/tasks/config.yml to configure /etc/homelab/apps with mode 0700 and converge target host per T007 / plan: host secrets storage (partial)
- [X] T051 Refactor failed_when condition in ansible/playbooks/verify-phase5-backup.yml to use logical OR across all permission assertions per T027 / BK-002 (partial)

