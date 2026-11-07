# Phase 0 Research: Constitution v2.0.0 Codebase Audit and Alignment

**Feature**: `012-constitution-codebase-audit`  
**Date**: 2026-11-05  
**Authority**: `.specify/memory/constitution.md` (v2.0.0), `.specify/memory/coding-standards.md`, `.specify/memory/logging-standards.md`

---

## 1. Root-Level `ansible-lint` Role Resolution & Worktree Exclusion (FR-001)

- **Decision**: Configure `.ansible-lint` at the repository root to add `.worktrees/` to `exclude_paths` and set `ANSIBLE_ROLES_PATH: "ansible/roles"` under `extra_vars` / environment or root `ansible.cfg` pointer so `ansible-lint` invoked from repository root resolves `ansible/roles/` cleanly without `syntax-check[specific]` failures.
- **Rationale**:
  - Currently, running `ansible-lint` from `/home/admin/projects/homelab2` traverses `.worktrees/007-*` and `.worktrees/008-*` (generating 100+ duplicate violations and Python 3.14 subprocess syntax errors on stale worktrees).
  - Additionally, because `ansible/ansible.cfg` is nested in `ansible/`, root-level `ansible-lint` checks `ansible/playbooks/*.yml` with search path `ansible/playbooks/roles:~/.ansible/roles:...`, failing with `syntax-check[specific]: The role '<role>' was not found` across all 9 playbooks (`antigravity.yml`, `backup.yml`, `frigate.yml`, `harden.yml`, `monitoring.yml`, `network.yml`, `site.yml`, `storage.yml`, `vaultwarden.yml`).
  - Adding `.worktrees/` to `exclude_paths` in `.ansible-lint` and configuring root-level role resolution (via root `ansible.cfg` or `.ansible-lint` `mock_roles` / environment configuration pointing `roles_path = ansible/roles:roles`) satisfies Constitutional Principle VII and the pre-PR gate `bash -n scripts/*.sh && shellcheck scripts/*.sh && ansible-lint`.
- **Alternatives Considered**:
  - *Changing the pre-PR gate command to `cd ansible && ansible-lint`*: Rejected because Constitutional Development Workflow explicitly specifies running `ansible-lint` from the repository root (`bash -n scripts/*.sh && shellcheck scripts/*.sh && ansible-lint`).
  - *Symlinking `ansible/playbooks/roles -> ../roles`*: Rejected as less clean than declarative configuration in `.ansible-lint` / `ansible.cfg`, though a root `ansible.cfg` or `.ansible-lint` configuration is standard and self-contained.

---

## 2. Ansible Role Variable & Register Prefix Alignment (`var-naming[no-role-prefix]`) (FR-002)

- **Decision**: Rename all unprefixed role `register`, `set_fact`, and `defaults/main.yml` variables across `ansible/roles/` to use their owning role prefix (`antigravity_`, `backup_`, `common_packages_`, `disk_health_`, `ssh_hardening_`, `storage_layout_`, `time_sync_`, `vaultwarden_`), and update any downstream references in tasks, templates, or playbooks.
- **Rationale**:
  - `coding-standards.md` (Section *Naming, Formatting & Code Style*) and `ansible-lint` `production` profile mandate `snake_case` prefixed with the owning role name.
  - Audit identified 34 `var-naming[no-role-prefix]` violations across 8 roles:
    - `ansible/roles/antigravity/tasks/{auth,daemon,install,workspace}.yml`: 17 registered/fact variables (`target_oauth_creds`, `local_oauth_stat`, `available_local_oauth`, `local_accounts_stat`, `available_local_accounts`, `post_oauth_stat`, `linger_stat`, `verify_linger`, `oauth_check`, `operator_uid_cmd`, `agy_remote_start`, `agy_check`, `target_ssh_key`, `local_ssh_stat`, `available_local_ssh_key`, `git_repo_check`).
    - `ansible/roles/backup/tasks/config.yml`: `local_vault_stat` -> `backup_local_vault_stat`.
    - `ansible/roles/common_packages/tasks/main.yml`: `pkg_install` -> `common_packages_install`.
    - `ansible/roles/disk_health/defaults/main.yml` & `tasks/main.yml`: `smartd_scan_options` -> `disk_health_smartd_scan_options` (updating `templates/smartd.conf.j2` and `ansible/inventory/group_vars/all/vars.yml` if referenced), `smartmontools_install` -> `disk_health_smartmontools_install`.
    - `ansible/roles/ssh_hardening/tasks/main.yml`: `fail2ban_install` -> `ssh_hardening_fail2ban_install`.
    - `ansible/roles/storage_layout/defaults/main.yml`: `storage_group`, `storage_gid`, `storage_admin_user`, `storage_base_directories`, `storage_foundational_packages` -> prefix with `storage_layout_` (updating `ansible/roles/storage_layout/tasks/*.yml` and `ansible/inventory/host_vars/homelab2/storage.yml` / `vars.yml` if referenced).
    - `ansible/roles/time_sync/tasks/main.yml`: `chrony_install` -> `time_sync_chrony_install`.
    - `ansible/roles/vaultwarden/tasks/{config,funnel,layout}.yml`: `tailscale_status_raw`, `tailscale_status`, `tailscale_funnel_status_cmd`, `tailscale_funnel_json`, `tailscale_funnel_enable_cmd`, `tailscale_funnel_verification_cmd`, `sqlite_pkg_install` -> prefix with `vaultwarden_`.
- **Alternatives Considered**:
  - *Adding `var-naming[no-role-prefix]` to `.ansible-lint` `skip_list`*: Strictly forbidden by Constitutional Principle V (*Human-Only Toolchain & Security Gate*: "AI agents MUST NOT... weaken compiler/linter warning or strictness flags") and `coding-standards.md`.

---

## 3. Ansible Shell Pipe Safety, Module Idioms & Error Handling (FR-003, FR-004, FR-005, FR-006)

- **Decision**:
  1. Add `set -o pipefail` (with `args: { executable: /bin/bash }` where needed) to all 17 `ansible.builtin.shell` tasks using pipes across `ansible/playbooks/verify*.yml` and `ansible/roles/antigravity/tasks/install.yml`.
  2. Replace imperative `command`/`shell` calls with native `ansible.builtin.systemd`, `ansible.builtin.command` (when shell features are unused), or structured module equivalents across `verify-phase7-antigravity.yml`, `verify-phase8-monitoring.yml`, `roles/antigravity/`, and `roles/monitoring/handlers/main.yml`. Where `git` or `curl | bash` or `systemctl --user` is required for specific inspection/bootstrap semantics that native modules do not directly support in check/assertion context, use the canonical module or scope-appropriate invocation that satisfies `ansible-lint` idioms without weakening checks.
  3. Replace `ignore_errors: true` in `ansible/roles/antigravity/tasks/auth.yml:90` and `workspace.yml:55` with explicit `failed_when: false` or `stat`-guarded conditional execution, and add `changed_when` to `daemon.yml:14` and `workspace.yml:42`. Also pin or guard `ansible.builtin.git` in `workspace.yml:126` (`update: false` when cloning only if not present) to resolve `latest[git]`.
  4. Wrap lines exceeding 160 characters and strip trailing spaces / extra blank lines across `ansible/inventory/group_vars/all/vars.yml`, `ansible/playbooks/verify*.yml`, `ansible/roles/antigravity/tasks/{auth,workspace}.yml`, and `ansible/roles/disk_health/defaults/main.yml`.
- **Rationale**:
  - Enforces Constitutional Principle II (*Two-Tier Failure Model & Strict Idempotency*) and Principle VII (*Zero Warnings*).
- **Alternatives Considered**:
  - *Inline `# noqa` comments*: Avoided wherever a native module, `set -o pipefail`, or `changed_when` directly resolves the root cause.

---

## 4. ShellCheck Zero-Warning Remediation Across `scripts/*.sh` & `bootstrap-speckit.sh` (FR-007)

- **Decision**:
  1. `scripts/verify-phase2.sh` (lines 117–195, `SC2329`): Add `# shellcheck disable=SC2329` above the dynamically dispatched `check_01`..`check_10` functions with an explanatory comment documenting that `run_check` invokes them indirectly by name, or invoke them directly.
  2. `scripts/verify-phase5-vaultwarden.sh` (lines 147–148, `SC2004`) and `scripts/verify-phase8-monitoring.sh` (lines 157–159, `SC2004`): Remove unnecessary `$` inside array arithmetic subscripts (`CHECK_STATUS[idx]="$status"`, `ASSERTION_STATUS[idx]="$status"`, etc.).
  3. `scripts/verify-phase7-antigravity.sh` (line 103, `SC2029`): Annotate `# shellcheck disable=SC2029` with a comment explaining that `$cmd` is intentionally expanded by the caller into a self-contained remote command string prior to SSH invocation.
  4. `bootstrap-speckit.sh` (line 110, `SC2129`): Group the consecutive `echo ... >> "$GITIGNORE"` statements into a single `{ ...; } >> "$GITIGNORE"` block.
- **Rationale**:
  - Eliminates all 17 ShellCheck warnings across `scripts/*.sh` and `bootstrap-speckit.sh` with zero behavioral regressions.
- **Alternatives Considered**:
  - *Global `.shellcheckrc` exclusions*: Rejected per Constitutional Principle V (never weaken global linter strictness flags).

---

## 5. Epistemic Hygiene: Relative Links, Constitution v2.0.0 Citations, Open Questions Registry & Spec Decoupling (FR-008..FR-012)

- **Decision**:
  1. Replace all 19 `file:///C:/Users/micro/projects/homelab2/...` URIs across `ROADMAP.md`, `docs/roadmap.md`, and `docs/disaster-recovery-phase3.md` with clean repository-relative paths.
  2. Update all governance version references in `ROADMAP.md` and `docs/roadmap.md` from `v1.1.0` to `v2.0.0`, referencing `.specify/memory/constitution.md`, `.specify/memory/coding-standards.md`, and `.specify/memory/logging-standards.md`, and updating the Constitutional Compliance Matrix in `docs/roadmap.md` to reflect the 7 merged Core Principles (I–VII) of Constitution v2.0.0.
  3. Create `reference/open-questions.md` with a structured schema (Question ID, Status, Context & Checked Sources, Owning Authority, Temporary Working Assumption, Resolution) per Constitutional Principle I.
  4. Purge ephemeral `specs/NNN-*/` links and `FR-XXX` citations from `README.md`, `ROADMAP.md`, `docs/roadmap.md`, `docs/operations.md`, `scripts/apply-phase7-antigravity.sh`, `scripts/apply-phase7-antigravity.ps1`, and `scripts/install/install.conf.example`, replacing them with permanent documentation links (`docs/roadmap.md`, `docs/operations.md`, `docs/disaster-recovery-phase3.md`) and contract assertion identifiers (`AG-001..008`, Constitutional Principle VI verify-before-mutate safety guard).
  5. Restructure root `README.md` into the 4 mandatory canonical sections required by `coding-standards.md`:
     - `## 1. Project Overview & Phase Architecture` (covering Phases 1–8 including Phase 5 Vaultwarden & B2 Backups, Phase 7 Antigravity Remote Control, and Phase 8 Monitoring & Alerting)
     - `## 2. Getting Started / Convergence Quickstart` (`scripts/apply-phase*.{sh,ps1}`)
     - `## 3. CLI / Skill / Acceptance Verification Reference` (`scripts/verify-phase*.{sh,ps1}` and assertion matrices)
     - `## 4. Configuration & Governance Verification` (links to `.specify/memory/constitution.md`, `coding-standards.md`, `logging-standards.md`, `ROADMAP.md`, `docs/`, `reference/open-questions.md`, and the pre-PR verification command).
- **Rationale**:
  - Satisfies Constitutional Principles I, IV, VII, and Development Workflow & Quality Gates.
- **Alternatives Considered**:
  - *Deleting `specs/001-*` through `specs/011-*`*: Rejected because Recorded Deviation 001 explicitly preserves historical specs on disk as archival audit records while requiring production code and operational documentation outside `specs/` to decouple from them.
