# Tasks: Constitution v2.0.0 Codebase Audit and Alignment

**Input**: Design documents from `/specs/012-constitution-codebase-audit/` (`plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/verification-gate-contract.md`, `quickstart.md`)  
**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/verification-gate-contract.md`  
**Documentation Impact**: `USER_FACING` — Updates root `README.md` (4 canonical sections), `ROADMAP.md`, `docs/roadmap.md`, `docs/disaster-recovery-phase3.md`, `docs/operations.md`, and creates `reference/open-questions.md`.  
**Tests**: ZERO automated test files or test suites generated, in strict accordance with Constitutional Principle III (Exemption Category 5: declarative IaC and shell automation verified via static analysis `bash -n`, `shellcheck`, `ansible-lint` and live acceptance runners).  
**Organization**: Tasks are grouped by user story in priority order to enable independent implementation and static verification.

---

## Format: `[ID] [P?] [Story] Description with exact file path`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (`[US1]`, `[US2]`, `[US3]`, `[US4]`, `[US5]`)
- Every task includes an exact repository-relative file path in its description.

---

## Phase 1: Setup (Shared Infrastructure & Linter Tooling)

**Purpose**: Configure repository-root static analysis tooling and runners to ensure consistent lint execution and exclude auxiliary git worktrees.

- [ ] T001 Configure `profile: production`, `exclude_paths: [.git/, .specify/, .worktrees/, specs/, scripts/]`, and role search paths in `.ansible-lint`
- [ ] T002 [P] Configure root `ansible.cfg` resolving `roles_path = ansible/roles:roles` and inventory for repository-root execution in `ansible.cfg`
- [ ] T003 [P] Configure centrally declared `shell = bash` without disabling global warning rules in `.shellcheckrc`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core inventory variable alignment required across multiple roles before user story implementations.

**⚠️ CRITICAL**: Foundational inventory updates establish shared variable standards across `disk_health`, `storage_layout`, and dependent consumer roles (`frigate`).

- [ ] T004 Standardize global role variables `storage_layout_group: "storage"`, `storage_layout_gid: 1001`, and `disk_health_smartd_scan_options` in `ansible/inventory/group_vars/all/vars.yml`
- [ ] T005 [P] Verify baseline toolchain execution and root role resolution across `ansible.cfg` and `.ansible-lint` using `ansible-lint --version`

**Checkpoint**: Foundation ready — user story implementation can now begin.

---

## Phase 3: User Story 1 - Clean Static Verification & Pre-PR Gate Enforcement (Priority: P1) 🎯 MVP

**Goal**: Remediate all ShellCheck warnings across automation scripts and standardize role prefixes across all 8 Ansible roles to satisfy AUD-01 and core static verification.

**Independent Test**: Execute `bash -n scripts/*.sh bootstrap-speckit.sh && shellcheck scripts/*.sh bootstrap-speckit.sh` asserting exit code 0 with zero warnings, and verify role variable naming compliance.

### Implementation for User Story 1

- [ ] T006 [P] [US1] Annotate dynamic function dispatch with `# shellcheck disable=SC2329` and clarifying comment in `scripts/verify-phase2.sh`
- [ ] T007 [P] [US1] Remediate SC2004 array arithmetic subscripts (`CHECK_STATUS[idx]="$status"`) in `scripts/verify-phase5-vaultwarden.sh`
- [ ] T008 [P] [US1] Remediate SC2004 array arithmetic subscripts (`ASSERTION_STATUS[idx]="$status"`) in `scripts/verify-phase8-monitoring.sh`
- [ ] T009 [P] [US1] Annotate caller-expanded SSH command with `# shellcheck disable=SC2029` and clarifying comment in `scripts/verify-phase7-antigravity.sh`
- [ ] T010 [P] [US1] Group consecutive echo statements into a single redirection block `{ ...; } >> "$GITIGNORE"` to resolve SC2129 in `bootstrap-speckit.sh`
- [ ] T011 [P] [US1] Prefix registered facts (`target_oauth_creds -> antigravity_target_oauth_creds`, `local_oauth_stat -> antigravity_local_oauth_stat`, `available_local_oauth -> antigravity_available_local_oauth`, `local_accounts_stat -> antigravity_local_accounts_stat`, `available_local_accounts -> antigravity_available_local_accounts`, `post_oauth_stat -> antigravity_post_oauth_stat`) in `ansible/roles/antigravity/tasks/auth.yml`
- [ ] T012 [P] [US1] Prefix registered facts (`linger_stat -> antigravity_linger_stat`, `verify_linger -> antigravity_verify_linger`, `oauth_check -> antigravity_oauth_check`, `operator_uid_cmd -> antigravity_operator_uid_cmd`, `agy_remote_start -> antigravity_agy_remote_start`) in `ansible/roles/antigravity/tasks/daemon.yml`
- [ ] T013 [P] [US1] Prefix registered fact `agy_check -> antigravity_agy_check` in `ansible/roles/antigravity/tasks/install.yml`
- [ ] T014 [P] [US1] Prefix registered facts (`target_ssh_key -> antigravity_target_ssh_key`, `local_ssh_stat -> antigravity_local_ssh_stat`, `available_local_ssh_key -> antigravity_available_local_ssh_key`, `git_repo_check -> antigravity_git_repo_check`) in `ansible/roles/antigravity/tasks/workspace.yml`
- [ ] T015 [P] [US1] Prefix registered fact `local_vault_stat -> backup_local_vault_stat` in `ansible/roles/backup/tasks/config.yml`
- [ ] T016 [P] [US1] Prefix registered fact `pkg_install -> common_packages_pkg_install` in `ansible/roles/common_packages/tasks/main.yml`
- [ ] T017 [P] [US1] Standardize `smartd_scan_options -> disk_health_smartd_scan_options` and `smartmontools_install -> disk_health_smartmontools_install` in `ansible/roles/disk_health/defaults/main.yml`, `ansible/roles/disk_health/tasks/main.yml`, and `ansible/roles/disk_health/templates/smartd.conf.j2`
- [ ] T018 [P] [US1] Prefix registered fact `fail2ban_install -> ssh_hardening_fail2ban_install` in `ansible/roles/ssh_hardening/tasks/main.yml`
- [ ] T019 [P] [US1] Standardize `storage_layout_group`, `storage_layout_gid`, `storage_layout_admin_user`, `storage_layout_base_directories`, and `storage_layout_foundational_packages` in `ansible/roles/storage_layout/defaults/main.yml` and `ansible/roles/storage_layout/tasks/main.yml`
- [ ] T020 [P] [US1] Update referenced storage variables to `storage_layout_group` and `storage_layout_gid` in `ansible/roles/frigate/tasks/layout.yml`
- [ ] T021 [P] [US1] Prefix registered fact `chrony_install -> time_sync_chrony_install` in `ansible/roles/time_sync/tasks/main.yml`
- [ ] T022 [P] [US1] Standardize `tailscale_status_raw`, `tailscale_status`, `tailscale_funnel_status_cmd`, `tailscale_funnel_json`, `tailscale_funnel_enable_cmd`, `tailscale_funnel_verification_cmd`, and `sqlite_pkg_install` with `vaultwarden_` prefix in `ansible/roles/vaultwarden/tasks/config.yml`, `ansible/roles/vaultwarden/tasks/funnel.yml`, and `ansible/roles/vaultwarden/tasks/layout.yml`
- [ ] T023 [US1] Execute static syntax validation and shellcheck assertions (`AUD-01`) via `bash -n scripts/*.sh bootstrap-speckit.sh && shellcheck scripts/*.sh bootstrap-speckit.sh`

**Checkpoint**: ShellCheck passes with exit code 0 and zero warnings; all 34 role variable naming violations remediated across 8 roles.

---

## Phase 4: User Story 2 - Epistemic Authority, Path Normalization & Constitution Version Alignment (Priority: P1)

**Goal**: Replace machine-specific `file:///C:` URIs with repository-relative Markdown links, align governance citations to Constitution v2.0.0, and initialize `reference/open-questions.md`.

**Independent Test**: Verify zero occurrences of `file:///C:` via `! grep -rn "file:///C:" README.md ROADMAP.md docs/ reference/`, verify version citations via `! grep -rn "v1\.1\.0" README.md ROADMAP.md docs/` and `grep -q "v2.0.0" ROADMAP.md docs/roadmap.md`, and verify non-empty `test -s reference/open-questions.md`.

### Implementation for User Story 2

- [ ] T024 [P] [US2] Replace all `file:///C:` URIs with repository-relative Markdown links and update governance citations from v1.1.0 to Constitution v2.0.0 in `ROADMAP.md`
- [ ] T025 [P] [US2] Replace all `file:///C:` URIs with repository-relative links, update governance citations to Constitution v2.0.0, and update Constitutional Compliance Matrix to reflect Core Principles I–VII in `docs/roadmap.md`
- [ ] T026 [P] [US2] Replace all `file:///C:` URIs with repository-relative Markdown links in `docs/disaster-recovery-phase3.md`
- [ ] T027 [US2] Initialize centralized open questions registry conforming to Principle I schema (table with columns `ID` (`OQ-001`..), `Status` (`OPEN`|`DEFERRED`|`RESOLVED`), `Phase / Component`, `Question / Ambiguity`, `Sources Checked`, `Owning Authority`, `Temporary Working Assumption`) in `reference/open-questions.md`
- [ ] T028 [US2] Verify epistemic authority assertions (`AUD-03`, `AUD-05`, `AUD-06`) across `ROADMAP.md`, `docs/roadmap.md`, `docs/disaster-recovery-phase3.md`, and `reference/open-questions.md`

**Checkpoint**: All documentation links are repository-relative; governance citations reference Constitution v2.0.0; `reference/open-questions.md` is initialized.

---

## Phase 5: User Story 3 - Strict Ephemeral Spec Decoupling & Spec Citation Hygiene (Priority: P2)

**Goal**: Decouple production scripts and operational runbooks from ephemeral feature spec directories (`specs/NNN-*/`) and `FR-XXX` identifiers, citing permanent contracts and verification assertions (`AG-001..008`, Principle VI safety guard) instead.

**Independent Test**: Verify zero occurrences of `FR-XXX` or `specs/NNN-*` outside `specs/` via `! grep -rnE "FR-[0-9]{3}|specs/[0-9]{3}-" docs/operations.md scripts/apply-phase7-antigravity.* scripts/install/install.conf.example`.

### Implementation for User Story 3

- [ ] T029 [P] [US3] Replace `FR-011` citation with Constitutional Principle VI target-readiness safety guard and `AG-001..008` contract references while preserving `--confirm-target-ready` and exit code 3 in `scripts/apply-phase7-antigravity.sh`
- [ ] T030 [P] [US3] Replace `FR-011` citation with Constitutional Principle VI target-readiness safety guard and `AG-001..008` contract references while preserving `-ConfirmTargetReady` and exit code 3 in `scripts/apply-phase7-antigravity.ps1`
- [ ] T031 [P] [US3] Purge `FR-006` spec citations and replace with permanent contract references in `scripts/install/install.conf.example`
- [ ] T032 [P] [US3] Replace `FR-011` and `specs/005-vaultwarden-app/` citations with permanent operational and architectural links in `docs/operations.md`
- [ ] T033 [US3] Verify spec decoupling assertions (`AUD-04`) across production scripts and operational documentation using `! grep -rnE "FR-[0-9]{3}|specs/[0-9]{3}-" docs/operations.md scripts/`

**Checkpoint**: Production scripts and operational guides outside `specs/` are completely decoupled from ephemeral specs and requirement tags.

---

## Phase 6: User Story 4 - Canonical Human-Facing Documentation Structure (Priority: P2)

**Goal**: Reorganize root `README.md` into the four canonical sections mandated by Constitutional Principle VII and `coding-standards.md`, updating phase coverage through Phase 8 and purging ephemeral spec links.

**Independent Test**: Verify presence of all four canonical headings (`## 1. Project Overview & Phase Architecture`, `## 2. Getting Started / Convergence Quickstart`, `## 3. CLI / Skill / Acceptance Verification Reference`, `## 4. Configuration & Governance Verification`) and documented status for Phases 1–8 in `README.md` (`AUD-07`).

### Implementation for User Story 4

- [ ] T034 [US4] Restructure `## 1. Project Overview & Phase Architecture` in `README.md` documenting architecture, hardware profile (`fidelacchius`), and completed Phases 1 through 8 (including Phase 7 Antigravity Remote Control and Phase 8 Monitoring & Alerting)
- [ ] T035 [US4] Restructure `## 2. Getting Started / Convergence Quickstart` in `README.md` documenting prerequisite keys and execution commands for operator runners `scripts/apply-phase*.{sh,ps1}`
- [ ] T036 [US4] Restructure `## 3. CLI / Skill / Acceptance Verification Reference` in `README.md` documenting acceptance suites `scripts/verify-phase*.{sh,ps1}`, assertion matrices, and agent skill commands
- [ ] T037 [US4] Restructure `## 4. Configuration & Governance Verification` in `README.md` linking to `.specify/memory/constitution.md` (v2.0.0), `coding-standards.md`, `logging-standards.md`, `ROADMAP.md`, `reference/open-questions.md`, and documenting the pre-PR verification gate command
- [ ] T038 [US4] Verify canonical structure, relative links, and spec decoupling assertions (`AUD-07`, `AUD-03`, `AUD-04`) in `README.md`

**Checkpoint**: `README.md` strictly implements the 4 canonical sections, documents all phases through Phase 8, and contains zero links to ephemeral `specs/`.

---

## Phase 7: User Story 5 - Failure Idiom & Idempotent Playbook Hygiene (Priority: P3)

**Goal**: Remediate all `ansible-lint` failure idioms (`risky-shell-pipe`, `command-instead-of-module`, `ignore_errors`, missing `changed_when`) and YAML formatting defects across playbooks and roles.

**Independent Test**: `ansible-lint` passes with zero violations (`0 failure(s), 0 warning(s)`) under the `production` profile.

### Implementation for User Story 5

- [ ] T039 [P] [US5] Add `pipefail: true` / `set -o pipefail` (with `args: { executable: /bin/bash }`) to shell tasks in `ansible/playbooks/verify-phase4.yml`
- [ ] T040 [P] [US5] Add `pipefail: true`, wrap lines exceeding 160 characters, and strip trailing whitespace in `ansible/playbooks/verify-phase5-backup.yml`
- [ ] T041 [P] [US5] Add `pipefail: true` and replace imperative systemctl commands with `ansible.builtin.systemd` in `ansible/playbooks/verify-phase7-antigravity.yml`
- [ ] T042 [P] [US5] Add `pipefail: true`, replace commands with `ansible.builtin.systemd`, and wrap lines in `ansible/playbooks/verify-phase8-monitoring.yml`
- [ ] T043 [P] [US5] Add `pipefail: true` and clean excessive blank lines in `ansible/playbooks/verify.yml`
- [ ] T044 [P] [US5] Add `set -o pipefail` to curl/pipeline shell task in `ansible/roles/antigravity/tasks/install.yml`
- [ ] T045 [P] [US5] Replace `ignore_errors: true` with explicit `failed_when: false` or `stat`-guarded conditional checks and wrap lines >160 chars in `ansible/roles/antigravity/tasks/auth.yml`
- [ ] T046 [P] [US5] Replace `ignore_errors: true` with `failed_when: false`, add explicit `changed_when: false`, and pin `ansible.builtin.git` (`update: false`) in `ansible/roles/antigravity/tasks/workspace.yml`
- [ ] T047 [P] [US5] Add explicit `changed_when` triggers to linger and daemon command tasks in `ansible/roles/antigravity/tasks/daemon.yml`
- [ ] T048 [P] [US5] Replace imperative systemctl restart command with `ansible.builtin.systemd` in `ansible/roles/monitoring/handlers/main.yml`
- [ ] T049 [P] [US5] Wrap lines exceeding 160 characters (`smartd_scan_options` / `disk_health_smartd_scan_options`) and strip trailing whitespace in `ansible/inventory/group_vars/all/vars.yml`
- [ ] T050 [US5] Execute `ansible-lint` production profile check (`AUD-02`) to verify `0 failure(s), 0 warning(s)` across `ansible/playbooks/` and `ansible/roles/`

**Checkpoint**: `ansible-lint` exits 0 with zero warnings under production profile across the entire repository.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: End-to-end repository-wide verification gate and runbook validation.

- [ ] T051 Run quickstart validation sequence (`AUD-03` through `AUD-07`) in `specs/012-constitution-codebase-audit/quickstart.md`
- [ ] T052 Execute unified constitutional pre-PR verification gate (`AUD-08`) via `bash -n scripts/*.sh && shellcheck scripts/*.sh && ansible-lint`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately. Configures `.ansible-lint`, `ansible.cfg`, and `.shellcheckrc`.
- **Foundational (Phase 2)**: Depends on Setup completion — updates shared inventory variables in `group_vars/all/vars.yml` before role tasks are modified.
- **User Story 1 (Phase 3, P1)**: Depends on Foundational completion. Fixes ShellCheck warnings and standardizes role variable prefixes.
- **User Story 2 (Phase 4, P1)**: Depends on Foundational completion. Can run in parallel with User Story 1 (markdown and documentation files only).
- **User Story 3 (Phase 5, P2)**: Depends on Phase 4 completion (documentation links normalized). Decouples scripts and operational guides from ephemeral specs.
- **User Story 4 (Phase 6, P2)**: Depends on Phase 4 and Phase 5 completion (canonical README structure incorporates normalized relative links and Phase 1–8 references).
- **User Story 5 (Phase 7, P3)**: Depends on User Story 1 completion (role variables already prefixed). Remediates playbooks and task failure idioms to achieve clean `ansible-lint`.
- **Polish (Phase 8)**: Depends on all user stories being complete. Executes end-to-end verification gate.

### User Story Dependencies

```
Phase 1: Setup (T001..T003)
      │
      ▼
Phase 2: Foundational (T004..T005)
      │
      ├───────────────────────────────┐
      ▼                               ▼
Phase 3: US1 - Static / Vars (P1)   Phase 4: US2 - Epistemic / Links (P1)
(T006..T023)                        (T024..T028)
      │                               │
      │                               ▼
      │                             Phase 5: US3 - Spec Decoupling (P2)
      │                             (T029..T033)
      │                               │
      │                               ▼
      │                             Phase 6: US4 - Canonical README (P2)
      │                             (T034..T038)
      ▼                               │
Phase 7: US5 - Playbook Idioms (P3) ◄─┘
(T039..T050)
      │
      ▼
Phase 8: Polish & Gate (T051..T052)
```

### Parallel Opportunities

- **Phase 1 Setup**: `T002` (`ansible.cfg`) and `T003` (`.shellcheckrc`) can run in parallel.
- **Phase 3 User Story 1**:
  - All shell script fixes (`T006`, `T007`, `T008`, `T009`, `T010`) can run in parallel.
  - Role variable prefix tasks (`T011`, `T012`, `T013`, `T014`, `T015`, `T016`, `T017`, `T018`, `T019`, `T020`, `T021`, `T022`) touch distinct role directories and can run in parallel.
- **Phase 4 User Story 2**:
  - Documentation link normalizations (`T024`, `T025`, `T026`) can run in parallel.
- **Phase 5 User Story 3**:
  - Script spec decoupling tasks (`T029`, `T030`, `T031`, `T032`) touch distinct files and can run in parallel.
- **Phase 7 User Story 5**:
  - Playbook idiom tasks (`T039`, `T040`, `T041`, `T042`, `T043`) and role idiom tasks (`T044`, `T045`, `T046`, `T047`, `T048`, `T049`) touch distinct files and can run in parallel.

---

## Parallel Execution Examples

### Parallel Example: User Story 1 ShellCheck Remediations
```bash
# Launch independent shell script warning fixes concurrently:
Task: "Annotate dynamic function dispatch with SC2329 comment in scripts/verify-phase2.sh"
Task: "Remediate SC2004 array arithmetic subscripts in scripts/verify-phase5-vaultwarden.sh"
Task: "Remediate SC2004 array arithmetic subscripts in scripts/verify-phase8-monitoring.sh"
Task: "Annotate caller-expanded SSH command with SC2029 comment in scripts/verify-phase7-antigravity.sh"
Task: "Group redirection into single block to resolve SC2129 in bootstrap-speckit.sh"
```

### Parallel Example: User Story 1 Role Variable Standardization
```bash
# Launch independent role variable updates concurrently across distinct roles:
Task: "Prefix registered facts with antigravity_* in ansible/roles/antigravity/tasks/auth.yml"
Task: "Prefix local_vault_stat with backup_local_vault_stat in ansible/roles/backup/tasks/config.yml"
Task: "Prefix pkg_install with common_packages_pkg_install in ansible/roles/common_packages/tasks/main.yml"
Task: "Standardize disk_health_* in ansible/roles/disk_health/defaults/main.yml"
Task: "Prefix fail2ban_install with ssh_hardening_fail2ban_install in ansible/roles/ssh_hardening/tasks/main.yml"
Task: "Standardize storage_layout_* in ansible/roles/storage_layout/defaults/main.yml"
Task: "Prefix chrony_install with time_sync_chrony_install in ansible/roles/time_sync/tasks/main.yml"
Task: "Standardize vaultwarden_* in ansible/roles/vaultwarden/tasks/config.yml"
```

---

## Implementation Strategy

### MVP First (Phases 1, 2, and 3 - User Story 1 Only)

1. Complete Phase 1: Setup (`.ansible-lint`, `ansible.cfg`, `.shellcheckrc`).
2. Complete Phase 2: Foundational (`group_vars/all/vars.yml`).
3. Complete Phase 3: User Story 1 (ShellCheck fixes and 8 Ansible role variable renames).
4. **STOP and VALIDATE**: Run `bash -n scripts/*.sh bootstrap-speckit.sh && shellcheck scripts/*.sh bootstrap-speckit.sh` to confirm 100% clean shell syntax and zero warnings.

### Incremental Delivery

1. **Increment 1 (MVP)**: Setup + Foundational + User Story 1 -> Zero ShellCheck warnings, standardized role variable prefixes (`AUD-01`).
2. **Increment 2**: User Story 2 -> Relative links, Constitution v2.0.0 alignment, and `reference/open-questions.md` (`AUD-03`, `AUD-05`, `AUD-06`).
3. **Increment 3**: User Story 3 -> Production scripts and operational guides decoupled from ephemeral specs (`AUD-04`).
4. **Increment 4**: User Story 4 -> Canonical 4-section `README.md` documenting Phases 1–8 (`AUD-07`).
5. **Increment 5**: User Story 5 -> `pipefail: true`, native modules, `changed_when`, `failed_when`, clean YAML formatting, passing `ansible-lint` (`AUD-02`).
6. **Increment 6 (Polish)**: End-to-end pre-PR gate (`AUD-08`) passing with exit code 0 and zero warnings.

---

## Notes

- **[P] marker**: Indicates different files and no cross-task dependencies.
- **[Story] label**: Traceability marker linking each task to its user story in `spec.md`.
- **Constitutional Principle III**: Zero automated test files generated; all verification relies on static analysis and existing live acceptance runners.
- **No linter suppression**: Toolchain strictness is preserved; no rules are added to `skip_list`.
