# Phase 1 Data Model: Constitution v2.0.0 Codebase Audit and Alignment

**Feature**: `012-constitution-codebase-audit`  
**Date**: 2026-11-05

---

## 1. Domain Entities

### 1.1 `AuditFinding`
Represents a verified constitutional or linter non-compliance item in the repository.

| Field | Type | Constraints / Validation Rules |
|---|---|---|
| `finding_id` | `string` (`AUD-001`..`AUD-013`) | Unique identifier mapping 1:1 with `FR-001`..`FR-013`. |
| `category` | `enum` (`LINTER_CONFIG`, `ANSIBLE_VAR_PREFIX`, `ANSIBLE_SHELL_PIPE`, `ANSIBLE_MODULE_IDIOM`, `ANSIBLE_ERROR_HANDLING`, `YAML_FORMATTING`, `SHELLCHECK`, `DOC_RELATIVE_LINKS`, `DOC_GOV_VERSION`, `OPEN_QUESTIONS_REGISTRY`, `SPEC_DECOUPLING`, `README_CANONICAL_SECTIONS`) | Must map to a ratified Constitutional Principle (I, II, IV, V, or VII). |
| `file_path` | `string` | Repository-relative file path outside `specs/` and `.specify/`. |
| `line_range` | `string` | Exact line numbers verified during static audit. |
| `rule_id` | `string` | Linter rule (`var-naming[no-role-prefix]`, `risky-shell-pipe`, `SC2329`, etc.) or Constitutional section. |
| `remediation_status` | `enum` (`OPEN`, `REMEDIATED`, `VERIFIED`) | Transitions `OPEN -> REMEDIATED -> VERIFIED` upon passing `VerificationGate`. |

---

### 1.2 `LinterConfiguration`
Represents the declarative static analysis configuration files at the repository root.

| File | Key | Target Value | Constitutional Purpose |
|---|---|---|---|
| `.ansible-lint` | `profile` | `production` | Enforces full production-grade Ansible rules (Principle VII). |
| `.ansible-lint` | `exclude_paths` | `.git/`, `.specify/`, `.worktrees/`, `specs/`, `scripts/` | Prevents local git worktrees from polluting repository-level lint scans (FR-001). |
| `ansible.cfg` / `.ansible-lint` | `roles_path` / `ANSIBLE_ROLES_PATH` | `ansible/roles:roles` | Resolves `syntax-check[specific]` when running `ansible-lint` from repository root (FR-001). |
| `.shellcheckrc` | `shell` | `bash` | Enforces Bash 5.x static analysis across all `.sh` files without weakening warnings (Principle V & VII). |

---

### 1.3 `RoleVariableMapping`
Defines the exact variable rename transformations required across `ansible/roles/` and `ansible/inventory/` to satisfy `var-naming[no-role-prefix]` (FR-002):

| Owning Role | Legacy Variable / Register | Compliant Prefixed Identifier | Files Impacted |
|---|---|---|---|
| `antigravity` | `target_oauth_creds`, `local_oauth_stat`, `available_local_oauth`, `local_accounts_stat`, `available_local_accounts`, `post_oauth_stat` | `antigravity_target_oauth_creds`, `antigravity_local_oauth_stat`, `antigravity_available_local_oauth`, `antigravity_local_accounts_stat`, `antigravity_available_local_accounts`, `antigravity_post_oauth_stat` | `ansible/roles/antigravity/tasks/auth.yml` |
| `antigravity` | `linger_stat`, `verify_linger`, `oauth_check`, `operator_uid_cmd`, `agy_remote_start` | `antigravity_linger_stat`, `antigravity_verify_linger`, `antigravity_oauth_check`, `antigravity_operator_uid_cmd`, `antigravity_agy_remote_start` | `ansible/roles/antigravity/tasks/daemon.yml` |
| `antigravity` | `agy_check` | `antigravity_agy_check` | `ansible/roles/antigravity/tasks/install.yml` |
| `antigravity` | `target_ssh_key`, `local_ssh_stat`, `available_local_ssh_key`, `git_repo_check` | `antigravity_target_ssh_key`, `antigravity_local_ssh_stat`, `antigravity_available_local_ssh_key`, `antigravity_git_repo_check` | `ansible/roles/antigravity/tasks/workspace.yml` |
| `backup` | `local_vault_stat` | `backup_local_vault_stat` | `ansible/roles/backup/tasks/config.yml` |
| `common_packages` | `pkg_install` | `common_packages_pkg_install` | `ansible/roles/common_packages/tasks/main.yml` |
| `disk_health` | `smartd_scan_options`, `smartmontools_install` | `disk_health_smartd_scan_options`, `disk_health_smartmontools_install` | `ansible/roles/disk_health/defaults/main.yml`, `ansible/roles/disk_health/tasks/main.yml`, `ansible/roles/disk_health/templates/smartd.conf.j2`, `ansible/inventory/group_vars/all/vars.yml` |
| `ssh_hardening` | `fail2ban_install` | `ssh_hardening_fail2ban_install` | `ansible/roles/ssh_hardening/tasks/main.yml` |
| `storage_layout` | `storage_group`, `storage_gid`, `storage_admin_user`, `storage_base_directories`, `storage_foundational_packages` | `storage_layout_group`, `storage_layout_gid`, `storage_layout_admin_user`, `storage_layout_base_directories`, `storage_layout_foundational_packages` | `ansible/roles/storage_layout/defaults/main.yml`, `ansible/roles/storage_layout/tasks/main.yml`, `ansible/roles/frigate/tasks/layout.yml`, `ansible/inventory/group_vars/all/vars.yml` |
| `time_sync` | `chrony_install` | `time_sync_chrony_install` | `ansible/roles/time_sync/tasks/main.yml` |
| `vaultwarden` | `tailscale_status_raw`, `tailscale_status`, `tailscale_funnel_status_cmd`, `tailscale_funnel_json`, `tailscale_funnel_enable_cmd`, `tailscale_funnel_verification_cmd`, `sqlite_pkg_install` | `vaultwarden_tailscale_status_raw`, `vaultwarden_tailscale_status`, `vaultwarden_tailscale_funnel_status_cmd`, `vaultwarden_tailscale_funnel_json`, `vaultwarden_tailscale_funnel_enable_cmd`, `vaultwarden_tailscale_funnel_verification_cmd`, `vaultwarden_sqlite_pkg_install` | `ansible/roles/vaultwarden/tasks/config.yml`, `ansible/roles/vaultwarden/tasks/funnel.yml`, `ansible/roles/vaultwarden/tasks/layout.yml` |

---

### 1.4 `OpenQuestionEntry` (`reference/open-questions.md`)
Represents a centralized epistemic tracking entry per Constitutional Principle I (*Centralized Open Questions*).

| Field | Description |
|---|---|
| `ID` | Sequential identifier (`OQ-001`, `OQ-002`, ...). |
| `Status` | `OPEN`, `DEFERRED`, or `RESOLVED`. |
| `Phase / Component` | Affected architectural phase or role (e.g., Phase 6 Game Streaming, Phase 7 Local Backup Server). |
| `Question / Ambiguity` | Clear statement of the unresolved technical decision or parameter. |
| `Sources Checked` | Exact files/sections inspected per the Authority Hierarchy (`file:line`). |
| `Owning Authority` | Human role or external dependency responsible for resolution. |
| `Temporary Working Assumption` | Safe, fail-closed assumption currently governing the codebase. |

---

### 1.5 `GovernanceDocument`
Represents human-facing and architectural documentation subject to Principle VII and Ephemeral Spec Decoupling:

1. `README.md` — Must expose the 4 canonical headings (`## 1. Project Overview & Phase Architecture`, `## 2. Getting Started / Convergence Quickstart`, `## 3. CLI / Skill / Acceptance Verification Reference`, `## 4. Configuration & Governance Verification`) with zero links to `specs/NNN-*/`.
2. `ROADMAP.md` & `docs/roadmap.md` — Must use repository-relative links (zero `file:///C:` URIs), cite Constitution `v2.0.0` and companion standards (`coding-standards.md`, `logging-standards.md`), and remove links to `specs/001-*` and `specs/002-*`.
3. `docs/operations.md` & `docs/disaster-recovery-phase3.md` — Must use repository-relative links and replace `FR-011` with permanent safety-guard / `AG-001..008` contract terminology.
