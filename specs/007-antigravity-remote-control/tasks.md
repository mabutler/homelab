---
description: "Task list for Target Host Antigravity Installation & Remote Control"
---

# Tasks: Target Host Antigravity Installation & Remote Control

**Input**: Design documents from `/specs/007-antigravity-remote-control/`  
**Prerequisites**: [plan.md](file:///C:/Users/micro/projects/homelab2/.worktrees/007-antigravity-remote-control/specs/007-antigravity-remote-control/plan.md), [spec.md](file:///C:/Users/micro/projects/homelab2/.worktrees/007-antigravity-remote-control/specs/007-antigravity-remote-control/spec.md), [research.md](file:///C:/Users/micro/projects/homelab2/.worktrees/007-antigravity-remote-control/specs/007-antigravity-remote-control/research.md), [data-model.md](file:///C:/Users/micro/projects/homelab2/.worktrees/007-antigravity-remote-control/specs/007-antigravity-remote-control/data-model.md), [contracts/](file:///C:/Users/micro/projects/homelab2/.worktrees/007-antigravity-remote-control/specs/007-antigravity-remote-control/contracts/)  

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story, followed by end-to-end verification and gated rollout to `admin@192.168.4.57`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure & Role Scaffolding)

**Purpose**: Project initialization, directory structure scaffolding, and default configurations.

- [X] T001 [P] Initialize role directory structure for `ansible/roles/antigravity/{defaults,handlers,tasks,templates}/`
- [X] T002 [P] Define role default variables in `ansible/roles/antigravity/defaults/main.yml` with constraints: `instance_name`: "Default: homelab2-target; alphanumeric and hyphens", `service_unit`: "Fixed: agy-remote-control.service", `model`: 'Default: "Gemini 3.8 Flash (Medium)"', and paths
- [X] T003 [P] Update `.gitignore` in repo root to enforce zero secrets in version control (Constitution Principle IV) ensuring `secrets/antigravity/oauth_creds.json`, `secrets/ssh/id_ed25519_github`, and `ansible/inventory/group_vars/all/vault.yml` are strictly excluded from git
- [X] T004 [P] Create standalone Antigravity deployment playbook in `ansible/playbooks/antigravity.yml` targeting `homelab_nodes` with the `antigravity` role

---

## Phase 2: Foundational (Blocking Prerequisites & Environment Scaffolding)

**Purpose**: Core infrastructure and configuration templates that MUST be complete before ANY user story can be implemented.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T005 [P] Implement prerequisite packages installation tasks in `ansible/roles/antigravity/tasks/install.yml` ensuring `curl`, `jq`, `git`, and `openssh` are installed via pacman
- [X] T006 [P] Implement systemd notification handlers in `ansible/roles/antigravity/handlers/main.yml` for user daemon-reload and restart `agy-remote-control.service`
- [X] T007 [P] Implement operator directory structure creation in `ansible/roles/antigravity/tasks/config.yml` ensuring `/home/admin/.local/bin` mode `0755 admin:admin`, `/home/admin/.gemini` with constraint "perms 0700 admin:admin", `/home/admin/.gemini/antigravity-cli` with constraint "perms 0700 admin:admin", and `/home/admin/.ssh` with constraint "perms 0700 admin:admin"
- [X] T008 Implement master role task orchestrator in `ansible/roles/antigravity/tasks/main.yml` importing `install.yml`, `config.yml`, `auth.yml`, `daemon.yml`, `workspace.yml`, and `backup.yml` in sequential order

**Checkpoint**: Foundation ready - user story implementation can now begin.

---

## Phase 3: User Story 1 - Persistent Remote-Controlled Agent on Target Host (Priority: P1) 🎯 MVP

**Goal**: Deploy the Antigravity CLI binary, configure autonomous settings (`toolPermission: always-proceed`), register user session lingering (`loginctl enable-linger admin`), seed/authenticate Google account credentials, and supervise `agy-remote-control.service` with instance name `homelab2-target` under systemd user management so the remote agent stays online across reboots.

**Independent Test**: Verify `agy --version` succeeds, `/var/lib/systemd/linger/admin` exists, `systemctl --user is-active agy-remote-control.service` returns `active`, `agy remote-control status` displays `homelab2-target`, and the daemon re-establishes connection within 60 seconds of reboot without requiring an interactive SSH session.

### Implementation for User Story 1

- [X] T009 [P] [US1] Implement CLI installation and symlink tasks in `ansible/roles/antigravity/tasks/install.yml` downloading upstream installer via `curl -fsSL https://antigravity.google/cli/install.sh | bash` with constraints: `binary_path` "/home/admin/.local/bin/agy and symlinked to /usr/local/bin/agy", skipping when `command -v agy` returns 0
- [X] T010 [P] [US1] Create autonomous settings configuration task in `ansible/roles/antigravity/tasks/config.yml` deploying `/home/admin/.gemini/antigravity-cli/settings.json` with constraints: "perms 0600 admin:admin", `tool_permission` 'MUST be "always-proceed" (autonomous mode)', `agent_mode` 'MUST be "auto"', `trusted_workspaces` 'MUST contain "/home/admin/homelab2"', and `model` 'Default: "Gemini 3.8 Flash (Medium)"'
- [X] T011 [US1] Implement credential seeding and interactive fallback in `ansible/roles/antigravity/tasks/auth.yml` deploying `/home/admin/.gemini/oauth_creds.json` and `/home/admin/.gemini/google_accounts.json` with constraint "perms 0600 admin:admin" when available, or prompting with one-time browser OAuth URL
- [X] T012 [P] [US1] Implement user session lingering tasks in `ansible/roles/antigravity/tasks/daemon.yml` executing `loginctl enable-linger admin` with constraint `linger_enabled` "MUST be true (/var/lib/systemd/linger/admin exists)"
- [X] T013 [US1] Implement systemd user service registration and startup in `ansible/roles/antigravity/tasks/daemon.yml` configuring `agy-remote-control.service` under user manager scope `user` with instance name "Default: homelab2-target; alphanumeric and hyphens", `Restart=always`, and `RestartSec=5`

**Checkpoint**: User Story 1 (MVP) is fully functional; Antigravity runs persistently as a background daemon with autonomous permissions, online in the Remote Control interface across reboots.

---

## Phase 4: User Story 2 - Host Project Workspace Readiness for Autonomous Build-Out (Priority: P1)

**Goal**: Provision the `homelab2` git repository checkout at `/home/admin/homelab2`, configure dedicated GitHub SSH deploy key authentication, establish the `.worktrees/` directory for isolated branch execution, and grant passwordless sudo for `admin` to allow unattended build-out tasks to execute hands-free.

**Independent Test**: Verify `/home/admin/homelab2` is a valid git repository, `ssh -T git@github.com` succeeds using `/home/admin/.ssh/id_ed25519_github`, worktree creation under `/home/admin/homelab2/.worktrees/` succeeds, and passwordless sudo executes without terminal prompts.

### Implementation for User Story 2

- [X] T014 [P] [US2] Implement dedicated GitHub SSH deploy key deployment in `ansible/roles/antigravity/tasks/workspace.yml` deploying `/home/admin/.ssh/id_ed25519_github` with constraint "perms 0600 admin:admin" and `/home/admin/.ssh/id_ed25519_github.pub` with constraint "perms 0644 admin:admin"
- [X] T015 [P] [US2] Implement SSH client config in `ansible/roles/antigravity/tasks/workspace.yml` deploying `/home/admin/.ssh/config` containing constraint `ssh_config_path` "/home/admin/.ssh/config containing Host github.com stanza"
- [X] T016 [US2] Implement Git global identity configuration in `ansible/roles/antigravity/tasks/workspace.yml` configuring `git_user_name` and `git_user_email` in `/home/admin/.gitconfig`
- [X] T017 [US2] Implement repository checkout and worktree directory setup in `ansible/roles/antigravity/tasks/workspace.yml` cloning repository to `/home/admin/homelab2` with constraint `workspace_root` "/home/admin/homelab2 (owned by admin:admin)" and creating `worktrees_dir` "/home/admin/homelab2/.worktrees"
- [X] T018 [US2] Implement passwordless sudo configuration for `admin` operator in `ansible/roles/antigravity/tasks/workspace.yml` creating `/etc/sudoers.d/99-homelab-admin` to enable unattended remote execution of homelab automation

**Checkpoint**: User Story 2 is complete; the remote agent can create isolated worktrees, pull/push from GitHub, and execute administrative homelab automation on the host without terminal prompts.

---

## Phase 5: User Story 3 - Credential Isolation, Backup Coverage & Health Verification (Priority: P2)

**Goal**: Integrate Antigravity and Git credentials into the centralized Backblaze B2 / Restic backup catalog while excluding transient caches, enforce zero secrets in version control, and implement automated acceptance verification scripts (AG-001 through AG-008) and Ansible verification playbooks.

**Independent Test**: Run `scripts/verify-phase7-antigravity.sh` on the host (or via `scripts/verify-phase7-antigravity.ps1`), confirming all 8 assertions pass with exit code 0 (`[PASS] AG-001` through `[PASS] AG-008`), verify backup inclusion/exclusion manifests, and assert zero credentials tracked in git.

### Implementation for User Story 3

- [X] T019 [P] [US3] Implement backup manifest registration tasks in `ansible/roles/antigravity/tasks/backup.yml` appending inclusions to `/etc/homelab/backup-include.txt` (`/home/admin/.gemini/oauth_creds.json`, `/home/admin/.gemini/google_accounts.json`, `/home/admin/.gemini/antigravity-cli/settings.json`, `/home/admin/.ssh/id_ed25519_github`, `/home/admin/.ssh/id_ed25519_github.pub`)
- [X] T020 [P] [US3] Implement backup exclusions registration tasks in `ansible/roles/antigravity/tasks/backup.yml` appending exclusions to `/etc/homelab/backup-excludes.txt` (`/home/admin/.gemini/antigravity-cli/cache/**`, `/home/admin/.gemini/antigravity-cli/crashes/**`, `/home/admin/.gemini/antigravity-cli/log/**`, `/home/admin/.gemini/antigravity-cli/updater/**`, `/home/admin/.gemini/antigravity-cli/brain/**`, `/home/admin/.gemini/tmp/**`, `/home/admin/homelab2/.git/**`)
- [X] T021 [P] [US3] Implement server-side acceptance verification script in `scripts/verify-phase7-antigravity.sh` implementing assertions AG-001 through AG-008 per `contracts/verification-suite-contract.md` supporting `--json` output
- [X] T022 [P] [US3] Implement workstation verification runner in `scripts/verify-phase7-antigravity.ps1` executing `scripts/verify-phase7-antigravity.sh` over SSH against `admin@192.168.4.57`
- [X] T023 [P] [US3] Implement Ansible verification playbook in `ansible/playbooks/verify-phase7-antigravity.yml` asserting AG-001 through AG-008 with structured check output

**Checkpoint**: User Story 3 is complete; automated verification confirms healthy daemon status, backup coverage is locked in, and secrets are strictly isolated from git.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Workstation orchestrators with safety confirmation guards (FR-011), playbook integration, documentation, and operational runbook rehearsal.

- [X] T024 [P] Implement workstation deployment orchestrator in `scripts/apply-phase7-antigravity.ps1` with mandatory `-ConfirmTargetReady` guard enforcing FR-011 before invoking Ansible against `admin@192.168.4.57`
- [X] T025 [P] Implement server-side deployment orchestrator in `scripts/apply-phase7-antigravity.sh` with mandatory `--confirm-target-ready` guard enforcing FR-011
- [X] T026 Integrate `antigravity.yml` into master deployment playbook in `ansible/playbooks/site.yml`
- [X] T027 Integrate `verify-phase7-antigravity.yml` into unified verification playbook in `ansible/playbooks/verify.yml`
- [X] T028 [P] Update documentation and operational runbook in `docs/operations.md` and `ROADMAP.md` reflecting Feature 007 remote control capabilities
- [X] T029 Execute operational validation scenarios per `specs/007-antigravity-remote-control/quickstart.md` (live deployment only after explicit operator confirmation)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately.
- **Foundational (Phase 2)**: Depends on Phase 1 completion - BLOCKS all user stories.
- **User Story 1 (Phase 3)**: Depends on Phase 2 completion. Delivers the core persistent daemon (MVP).
- **User Story 2 (Phase 4)**: Depends on Phase 2 completion. Can proceed in parallel with US1 or immediately following US1.
- **User Story 3 (Phase 5)**: Depends on US1 and US2 definitions for paths and assertions.
- **Polish (Phase 6)**: Depends on completion of all user story implementations.

### User Story Dependencies

- **User Story 1 (P1)**: Independent of US2 and US3. Installs CLI and establishes background daemon.
- **User Story 2 (P1)**: Sets up git repository and deploy keys; references workspace paths used in US1 settings.
- **User Story 3 (P2)**: Validates US1 and US2 components, registers backup manifests, and verifies git hygiene.

### Parallel Opportunities

- Within Phase 1: T001, T002, T003, T004 can run in parallel.
- Within Phase 2: T005, T006, T007 can run in parallel.
- Within Phase 3 (US1): T009, T010, T012 can run in parallel.
- Within Phase 4 (US2): T014, T015 can run in parallel.
- Within Phase 5 (US3): T019, T020, T021, T022, T023 can run in parallel.
- Within Phase 6: T024, T025, T028 can run in parallel.

---

## Parallel Example: User Story 1 & User Story 2

```bash
# Launch parallel implementation tasks across roles:
Task: "Implement CLI installation and symlink tasks in ansible/roles/antigravity/tasks/install.yml"
Task: "Create autonomous settings configuration task in ansible/roles/antigravity/tasks/config.yml"
Task: "Implement dedicated GitHub SSH deploy key deployment in ansible/roles/antigravity/tasks/workspace.yml"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (`ansible/roles/antigravity/defaults/main.yml`, `.gitignore`, `ansible/playbooks/antigravity.yml`)
2. Complete Phase 2: Foundational (prerequisite packages, directory scaffolding, task orchestrator)
3. Complete Phase 3: User Story 1 (CLI installation, autonomous settings, user lingering, systemd user service)
4. **STOP and VALIDATE**: Verify that `agy --version` works, user lingering is enabled, and `agy remote-control status` registers `homelab2-target`.

### Incremental Delivery

1. Setup + Foundational -> Scaffolding ready.
2. User Story 1 -> Persistent daemon active (MVP).
3. User Story 2 -> Git repository, deploy key, and worktrees operational.
4. User Story 3 -> Backup registration and 8-assertion automated verification suite operational.
5. Polish -> Workstation orchestrators, master playbooks updated, and operational runbook validated.

---

## Notes

- `[P]` tasks operate on different files with no inter-task blocking dependencies.
- `[Story]` labels track task traceability directly to User Stories in `spec.md`.
- All credentials (OAuth tokens, private keys) are strictly gitignored and backed up offsite to Backblaze B2.
- The live host `admin@192.168.4.57` MUST NOT be modified until explicit user confirmation is provided (FR-011).
