# Tasks: System Identity & Backup Bucket Naming (Fidelacchius)

**Input**: Design documents from `specs/010-fidelacchius-system-rename/`  
**Prerequisites**: [plan.md](plan.md) (required), [spec.md](spec.md) (required), [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md), [.specify/memory/constitution.md](../../.specify/memory/constitution.md)

**Tests**: Includes automated system verification suites (`scripts/verify-*.sh` / `scripts/verify-*.ps1`) and non-destructive disaster recovery restore tests mandated by the feature specification and Constitution Principles III & V.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (`[US1]`, `[US2]`, `[US3]`)
- Include exact file paths in descriptions
- Quoted constraints from data-model.md included verbatim

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Pre-flight environment preparation, scratch space setup, and toolchain readiness

- [X] T001 Verify pre-flight operator environment, active git branch `010-fidelacchius-system-rename`, and required CLI tooling (`hostnamectl`, `tailscale`, `restic`, `ansible`, `jq`) in the local terminal
- [X] T002 [P] Create non-destructive test restore scratch directory at `/tmp/b2-test-restore` for backup verification drills

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: External account checks and prerequisites that MUST be verified before user stories can execute

**⚠️ CRITICAL**: Confirm legacy Tailscale state and B2 bucket readiness before altering active system configuration

- [X] T003 Verify legacy offline node `fidelacchius` (`100.109.1.87`) is decommissioned/deleted from the Tailscale Admin Console to satisfy the Tailscale MagicDNS No-Collision Rule: "Node name in `tailscale status` MUST NOT end with `-<number>` (e.g., `-1`)"
- [X] T004 [P] Validate that official Backblaze B2 bucket `fidelacchius-backups` exists or operator application credentials have permissions to create it under constraint "Must be `fidelacchius-backups` (S3/B2 DNS naming rules: lowercase, numbers, hyphens)"

**Checkpoint**: Foundation ready - user story implementation can now begin.

---

## Phase 3: User Story 1 - System Hostname & Network Identity as Fidelacchius (Priority: P1) 🎯 MVP

**Goal**: Establish the server's canonical OS hostname (`fidelacchius`), loopback resolution, Tailscale node identity (`fidelacchius.fable-mackarel.ts.net`), and update Vaultwarden public Funnel routing.

**Independent Test**: Verify hostname via `hostnamectl status` and `uname -n` returning `fidelacchius`, `/etc/hosts` resolving `fidelacchius`, `tailscale status --json` reporting node name `fidelacchius` without `-1`, and `scripts/verify-phase3.sh` and `scripts/verify-phase5-vaultwarden.sh` passing cleanly.

### Tests & Verification Suites for User Story 1

- [X] T005 [P] [US1] Update network verification scripts in `scripts/verify-phase3.sh` and `scripts/verify-phase3.ps1` to assert static/transient hostname `fidelacchius` and Tailscale FQDN `fidelacchius.fable-mackarel.ts.net.`
- [X] T006 [P] [US1] Update Vaultwarden verification scripts in `scripts/verify-phase5-vaultwarden.sh` and `scripts/verify-phase5-vaultwarden.ps1` to assert endpoint domain `https://fidelacchius.fable-mackarel.ts.net`

### Implementation for User Story 1

- [X] T007 [US1] Set system static and transient hostname to `fidelacchius` in `/etc/hostname` via `sudo hostnamectl set-hostname fidelacchius` and set pretty hostname `"Fidelacchius (the sword of faith)" (optional display label)` in `/etc/machine-info` verifying constraint "Must be `fidelacchius` (RFC 1123 compliant: lowercase alphanumeric and hyphens, 1-63 chars)"
- [X] T008 [US1] Update local loopback resolution in `/etc/hosts` to satisfy constraint "Must map `127.0.0.1` and `127.0.1.1` to `fidelacchius` / `fidelacchius.localdomain`"
- [X] T009 [US1] Update Tailscale node machine name via `sudo tailscale set --hostname=fidelacchius` verifying constraint "Node name in `tailscale status` MUST NOT end with `-<number>` (e.g., `-1`)" and asserting DNSName resolves to `fidelacchius.fable-mackarel.ts.net.`
- [X] T010 [US1] Update Vaultwarden service configuration in `/opt/services/vaultwarden/.env` setting `DOMAIN="https://fidelacchius.fable-mackarel.ts.net"` to satisfy constraint "Public Tailscale Funnel ingress URL: `https://fidelacchius.fable-mackarel.ts.net`"
- [X] T011 [US1] Re-assert Tailscale Funnel public forwarding on HTTPS port 443 to internal container port 8088 via `tailscale funnel 8088 on` for `https://fidelacchius.fable-mackarel.ts.net`
- [X] T012 [US1] Restart the Vaultwarden container service via `docker compose up -d --force-recreate` in `/opt/services/vaultwarden/docker-compose.yml`
- [X] T013 [US1] Update dynamic FQDN discovery task in `ansible/roles/vaultwarden/tasks/config.yml` ensuring discovery resolves `fidelacchius.fable-mackarel.ts.net`
- [X] T014 [US1] Execute automated verification suites `scripts/verify-phase3.sh` and `scripts/verify-phase5-vaultwarden.sh` to confirm OS identity and Funnel ingress

**Checkpoint**: User Story 1 is fully functional and testable independently.

---

## Phase 4: User Story 2 - Official Backblaze B2 Backup Bucket & Repository Migration (Priority: P1)

**Goal**: Configure the offsite backup pipeline with the official Backblaze B2 bucket `fidelacchius-backups`, initialize the Restic repository (`b2:fidelacchius-backups:fidelacchius`), create a fresh baseline snapshot, and verify disaster recovery readiness with a non-destructive restore drill.

**Independent Test**: Connect to `b2:fidelacchius-backups:fidelacchius`, run a full backup via `/usr/local/bin/homelab-backup run`, restore `/etc/homelab/vault.yml` to `/tmp/b2-test-restore` using `/usr/local/bin/restore-from-b2.sh`, verify identical SHA256 checksums, and pass `scripts/verify-phase5-backup.sh`.

### Tests & Verification Suites for User Story 2

- [X] T015 [P] [US2] Update backup verification scripts in `scripts/verify-phase5-backup.sh` and `scripts/verify-phase5-backup.ps1` to assert repository URI `b2:fidelacchius-backups:fidelacchius` and bucket `fidelacchius-backups`
- [X] T016 [P] [US2] Update disaster recovery restore scripts in `scripts/restore-from-b2.sh` and `scripts/restore-from-b2.ps1` with default repository target `b2:fidelacchius-backups:fidelacchius` and updated header documentation

### Implementation for User Story 2

- [X] T017 [P] [US2] Update committed template `ansible/inventory/group_vars/all/vault.yml.example` with placeholder `b2:fidelacchius-backups:fidelacchius` adhering to constraint "Git status MUST NOT show modifications adding plaintext or encrypted secrets to versioned files"
- [X] T018 [US2] Update gitignored secret files `ansible/inventory/group_vars/all/vault.yml` and `/etc/homelab/backup.env` (permissions `0600 root:root`) with newly provisioned B2 Application Key credentials and target `RESTIC_REPOSITORY="b2:fidelacchius-backups:fidelacchius"` matching pattern `^b2:fidelacchius-backups:fidelacchius$`
- [X] T019 [US2] Initialize the Restic cloud repository in the official bucket via `source /etc/homelab/backup.env && restic -r "$RESTIC_REPOSITORY" init`
- [X] T020 [US2] Update Ansible backup runner template in `ansible/roles/backup/templates/homelab-backup.j2` with updated tag comments (`--tag fidelacchius --tag daily`)
- [X] T021 [US2] Deploy updated backup runner script `/usr/local/bin/homelab-backup` and systemd environment file `/etc/homelab/backup.env` via Ansible backup role playbook convergence or template deploy
- [X] T022 [US2] Trigger an immediate baseline backup run via `sudo /usr/local/bin/homelab-backup run` ensuring `/etc/homelab/vault.yml` and `/opt/services/vaultwarden/backups/` snapshots are committed to `b2:fidelacchius-backups:fidelacchius`
- [X] T023 [US2] Execute non-destructive disaster recovery restore drill using `/usr/local/bin/restore-from-b2.sh --target-dir /tmp/b2-test-restore --include-path etc/homelab/vault.yml --force` and assert SHA256 checksum equality against live `/etc/homelab/vault.yml` per Constitution Principle V
- [X] T024 [US2] Execute automated verification suite `scripts/verify-phase5-backup.sh` to validate live backup environment, snapshot catalog, and systemd timer state
- [X] T025 [US2] Document retirement steps and safely decommission legacy test bucket `homelab2-fidelachius` and old B2 application key `homelab` in the Backblaze B2 Admin Console

**Checkpoint**: User Stories 1 AND 2 are both fully functional and independently verified.

---

## Phase 5: User Story 3 - Declarative Infrastructure & Inventory Identity Alignment (Priority: P2)

**Goal**: Align Ansible inventory definitions, host variables hierarchy, and operator helper scripts from `homelab2` to `fidelacchius`, ensuring clean IaC convergence.

**Independent Test**: Inspect inventory graph via `ansible-inventory -i inventory/hosts.yml --graph`, verify host variables with `ansible-inventory -i inventory/hosts.yml --host fidelacchius`, and execute dry-run check `ansible-playbook -i inventory/hosts.yml playbooks/site.yml --limit fidelacchius --check` with 0 errors.

### Implementation for User Story 3

- [X] T026 [P] [US3] Rename target host from `homelab2` to `fidelacchius` under `homelab_nodes` and `arch_linux` groups in `ansible/inventory/hosts.yml` satisfying constraint "Canonical inventory name in `hosts.yml`: `fidelacchius`"
- [X] T027 [P] [US3] Rename host variables directory from `ansible/inventory/host_vars/homelab2/` to `ansible/inventory/host_vars/fidelacchius/` preserving `storage.yml` satisfying constraint "Directory containing host-specific vars: `ansible/inventory/host_vars/fidelacchius/`"
- [X] T028 [P] [US3] Update documentation comments and default variable references in `ansible/inventory/group_vars/all/vars.yml`
- [X] T029 [P] [US3] Update operator execution scripts `scripts/apply-phase2.sh`, `scripts/apply-phase2.ps1`, `scripts/apply-phase3.sh`, `scripts/apply-phase3.ps1` to default target host to `fidelacchius`
- [X] T030 [P] [US3] Update operator execution scripts `scripts/apply-phase4.sh`, `scripts/apply-phase4.ps1`, `scripts/apply-phase5.sh`, `scripts/apply-phase5.ps1`, `scripts/apply-phase7-antigravity.sh`, `scripts/apply-phase7-antigravity.ps1` to default target host to `fidelacchius`
- [X] T031 [P] [US3] Update operator verification scripts `scripts/verify-phase2.sh`, `scripts/verify-phase4.sh`, `scripts/verify-phase4.ps1`, `scripts/verify-phase7-antigravity.sh`, `scripts/verify-phase7-antigravity.ps1` assertion banners and target host references to `fidelacchius`
- [X] T032 [US3] Verify inventory resolution and variable binding via `ansible-inventory -i ansible/inventory/hosts.yml --host fidelacchius` confirming storage layout and group memberships `[homelab_nodes, arch_linux]`
- [X] T033 [US3] Execute dry-run convergence check via `ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml --limit fidelacchius --check` to verify end-to-end declarative configuration with 0 unreachable hosts and 0 syntax errors

**Checkpoint**: All user stories are complete and declarative IaC is aligned.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation updates, final security audit, end-to-end validation, and workspace cleanup

- [X] T034 [P] Update architecture documentation in `docs/` and root `README.md` reflecting official hostname `fidelacchius` and bucket `fidelacchius-backups`
- [X] T035 [P] Audit git working tree and git log via `git diff --cached` and `git status` to verify zero credentials or encryption keys were committed per Constitution Principle IV
- [X] T036 Execute complete end-to-end validation scenarios described in `specs/010-fidelacchius-system-rename/quickstart.md`
- [X] T037 Clean up temporary test restore scratchpad files in `/tmp/b2-test-restore`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 - BLOCKS all user stories (validates legacy Tailscale node deletion and B2 bucket existence)
- **User Story 1 (Phase 3)**: Depends on Phase 2 - Can proceed immediately once foundational prerequisites are verified
- **User Story 2 (Phase 4)**: Depends on Phase 2 - Can proceed in parallel with US1 or immediately following US1
- **User Story 3 (Phase 5)**: Depends on Phase 3 and Phase 4 completion so that IaC inventory and operator scripts match live host state and repository targets
- **Polish (Phase 6)**: Depends on all user stories (US1, US2, US3) being completed

### User Story Dependencies

- **User Story 1 (P1)**: Independent of US2; establishes network and OS identity `fidelacchius`
- **User Story 2 (P1)**: Independent of US1; establishes cloud backup repository `b2:fidelacchius-backups:fidelacchius`
- **User Story 3 (P2)**: Integrates US1 hostname and US2 backup targets into Ansible inventory and operator scripts

### Within Each User Story

- Test and verification script updates [P] prepared before running system alterations
- Configuration files updated before restarting services
- Manual backup and non-destructive restore drill executed before retiring legacy bucket
- Inventory and host_vars renamed before running Ansible check playbooks

### Parallel Opportunities

- **Setup Tasks**: T001 and T002 can run in parallel
- **Foundational Tasks**: T003 and T004 can run in parallel
- **User Story 1 Tasks**: Verification script updates T005 and T006 can run in parallel
- **User Story 2 Tasks**: Verification script updates T015, T016, and example template T017 can run in parallel
- **User Story 3 Tasks**: Inventory rename T026, host_vars rename T027, vars update T028, and runner script updates T029, T030, T031 can all run in parallel
- **Polish Tasks**: Documentation update T034 and security audit T035 can run in parallel

---

## Parallel Example: User Story 1

```bash
# Update verification suites for User Story 1 in parallel:
Task T005: "scripts/verify-phase3.sh" & "scripts/verify-phase3.ps1"
Task T006: "scripts/verify-phase5-vaultwarden.sh" & "scripts/verify-phase5-vaultwarden.ps1"
```

## Parallel Example: User Story 2

```bash
# Update verification and documentation artifacts for User Story 2 in parallel:
Task T015: "scripts/verify-phase5-backup.sh" & "scripts/verify-phase5-backup.ps1"
Task T016: "scripts/restore-from-b2.sh" & "scripts/restore-from-b2.ps1"
Task T017: "ansible/inventory/group_vars/all/vault.yml.example"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001 - T002)
2. Complete Phase 2: Foundational (T003 - T004)
3. Complete Phase 3: User Story 1 (T005 - T014)
4. **STOP and VALIDATE**: Verify OS hostname `fidelacchius`, MagicDNS, and Vaultwarden Funnel endpoint independently
5. Host identity is officially established (MVP achieved!)

### Incremental Delivery

1. **Increment 1 (MVP)**: Hostname, Tailscale node identity, and Vaultwarden Funnel routing active as `fidelacchius` (Phase 3)
2. **Increment 2**: Offsite backup pipeline migrated to `fidelacchius-backups` with verified restore drill (Phase 4)
3. **Increment 3**: Declarative IaC inventory, `host_vars/fidelacchius/`, and operator scripts aligned (Phase 5)
4. **Increment 4**: Documentation, security audits, and quickstart end-to-end acceptance verified (Phase 6)

---

## Notes

- All tasks follow strict format: `- [ ] [TaskID] [P?] [Story?] Description with file path`
- Every task includes an explicit file path or unambiguous CLI target
- Constraints and validation rules from `data-model.md` are quoted verbatim
- Zero secrets in version control (Constitution Principle IV) strictly maintained throughout
- Disaster recovery restore verified (Constitution Principle V) prior to retiring test bucket
