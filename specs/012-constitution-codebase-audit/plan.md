# Implementation Plan: Constitution v2.0.0 Codebase Audit and Alignment

**Branch**: `012-constitution-codebase-audit` | **Date**: 2026-11-05 | **Spec**: [spec.md](file:///home/admin/projects/homelab2/specs/012-constitution-codebase-audit/spec.md)

**Input**: Feature specification from `/specs/012-constitution-codebase-audit/spec.md`

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

Conduct a comprehensive repository-wide audit and alignment against the newly ratified Constitution v2.0.0 and companion standards (`.specify/memory/coding-standards.md` and `.specify/memory/logging-standards.md`). The implementation will:
1. Configure root-level static analysis tooling (`.ansible-lint`, `ansible.cfg`, `.shellcheckrc`) to exclude local `.worktrees/` and properly resolve Ansible roles from the repository root.
2. Resolve all 34 `var-naming[no-role-prefix]` violations across 8 Ansible roles by standardizing role-prefixed variables and registered task facts.
3. Remediate all Ansible task hygiene violations under `ansible-lint` `production` profile, including 17 `risky-shell-pipe` instances (adding `pipefail: true`), replacing imperative command/shell calls with native idempotent modules (`systemd`, `command`), eliminating `ignore_errors: true` in favor of explicit `failed_when` conditions, and cleaning up YAML formatting.
4. Remediate all 17 ShellCheck warnings (`SC2329`, `SC2004`, `SC2029`, `SC2129`) across shell automation scripts (`scripts/*.sh` and `bootstrap-speckit.sh`).
5. Normalize all repository documentation (`ROADMAP.md`, `docs/roadmap.md`, `docs/disaster-recovery-phase3.md`) by replacing machine-specific `file:///C:` URIs with repository-relative Markdown links and aligning governance version references to Constitution v2.0.0.
6. Establish `reference/open-questions.md` conforming to Constitutional Principle I to track open technical ambiguities and deferred architectural decisions.
7. Decouple production scripts (`scripts/apply-phase7-antigravity.sh`, `scripts/apply-phase7-antigravity.ps1`, `scripts/install/install.conf.example`) and operational guides (`docs/operations.md`, `README.md`) from ephemeral feature spec paths (`specs/NNN-*/`) and `FR-XXX` identifiers, citing permanent contracts and verification assertions (`AG-001..008`, Principle VI safety guard) instead.
8. Restructure root `README.md` into the four canonical sections mandated by Constitutional Principle VII and `coding-standards.md`, updating phase coverage to include Phase 7 (Antigravity Remote Control) and Phase 8 (Platform Monitoring & Alerting).

## Technical Context

**Language/Version**: Ansible Core 2.21+ (YAML / Jinja2), Bash 5.x (POSIX/Linux automation scripts), PowerShell 7+ (Windows operator runners), Markdown (CommonMark / GFM).

**Primary Dependencies**: `ansible-lint` (26.10.x, production profile), `shellcheck` (0.10.x, shell=bash), `bash -n`, POSIX coreutils (`grep`, `test`), `ansible-core` (with collections `ansible.builtin`, `ansible.posix`, `community.general`, `community.sops`).

**Storage**: N/A (configuration files, IaC playbooks, shell scripts, and Markdown documentation files on local disk; no runtime persistent storage or database modifications).

**Testing**: ZERO automated unit test files, mock frameworks, or test directories per Constitutional Principle III. Verification is executed exclusively via static analyzers (`bash -n scripts/*.sh bootstrap-speckit.sh`, `shellcheck scripts/*.sh bootstrap-speckit.sh`, `ansible-lint` under `production` profile) and static assertions (`AUD-01` through `AUD-08` in `contracts/verification-gate-contract.md`), supplemented by existing live acceptance verification suites (`scripts/verify-phase*.sh`).

**Target Platform**: Bare-metal Arch Linux server (`fidelacchius`, x86_64) and local operator workstation (Linux / Windows PowerShell).

**Project Type**: Infrastructure-as-Code (IaC) configuration management, orchestration shell scripts, and architectural governance documentation.

**Performance Goals**: Static linting and pre-PR gate execution (`bash -n scripts/*.sh && shellcheck scripts/*.sh && ansible-lint`) completing within <30 seconds locally.

**Constraints**:
- Constitutional Principle III: ZERO automated test files, test suites, or mock frameworks anywhere in the repository.
- Constitutional Principle V: Zero external dependency additions, toolchain modifications, or linter strictness downgrades (no adding rules to `skip_list`).
- Constitutional Principle VII: Zero linter warnings (`ansible-lint` production profile, `shellcheck`).
- Recorded Deviation 001: Historical specs `specs/001-*` through `specs/011-*` are retained on disk as archival records, but all production code and active operational documentation outside `specs/` must decouple from them.
- Zero secrets in version control (Principle IV).

**Scale/Scope**: Repository-wide audit covering ~15 shell scripts, 9 Ansible playbooks, 8 Ansible roles, 4 root documentation/markdown files (`README.md`, `ROADMAP.md`, `docs/roadmap.md`, `docs/operations.md`, `docs/disaster-recovery-phase3.md`), and establishing `reference/open-questions.md`.

**Documentation Impact**: `USER_FACING` — Root `README.md` must be updated to establish the four canonical sections mandated by Principle VII and `coding-standards.md` (`## 1. Project Overview & Phase Architecture`, `## 2. Getting Started / Convergence Quickstart`, `## 3. CLI / Skill / Acceptance Verification Reference`, `## 4. Configuration & Governance Verification`), documenting all completed phases (including Phase 7 Antigravity Remote Control and Phase 8 Monitoring/Alerting) and replacing links to ephemeral spec files; `ROADMAP.md` and `docs/roadmap.md` must be updated with relative links and Constitution v2.0.0 citations; and `reference/open-questions.md` must be created.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle I: Evidence Over Invention, Bounded Investigation & Pragmatic Declarative-First Automation
- **Compliance Status**: PASS
- **Analysis**: All audit findings in `research.md` and `spec.md` trace directly to line-numbered diagnostics from `shellcheck`, `ansible-lint`, and grep scans across the repository. No unverified assumptions or speculative additions are made.
- **Centralized Open Questions**: All unresolved questions and deferred architectural decisions outliving a single task are captured in `reference/open-questions.md` citing checked sources, owning authority, and temporary working assumptions.
- **Pragmatic Declarative Automation**: Declarative Ansible tasks are prioritized for system configuration; where shell tasks are necessary (e.g., dynamic verification probes or package installation wrappers), they are made strictly idempotent and fail-safe with explicit contracts.

### Principle II: Two-Tier Failure Model, Fail Closed on Required State & Strict Idempotency
- **Compliance Status**: PASS
- **Analysis**:
  - `ignore_errors: true` is eliminated from `ansible/roles/antigravity/tasks/{auth,workspace}.yml` and replaced with explicit `failed_when` conditions or `stat`-guarded conditional checks.
  - All commands define explicit `changed_when` triggers to guarantee safe convergence and eliminate false change indicators.
  - All shell tasks using pipes enforce `pipefail: true` (`set -o pipefail`) so pipeline failures abort execution rather than silently passing.
  - Script safety guards (such as `--confirm-target-ready` in `scripts/apply-phase7-antigravity.sh`) fail closed with exit code 3 when preconditions are not met.

### Principle III: Behavioral, Value-Driven Testing, Deterministic Execution & Live Acceptance Gates
- **Compliance Status**: PASS (Exemption Justified under Skip Allowlist Category 5)
- **Analysis**:
  - **ZERO Automated Tests**: In strict accordance with Constitutional Principle III and the subagent persona instructions, NO unit test files, mock frameworks, or test directories (`tests/`) are generated anywhere in the workspace.
  - **Plan Justification & Skip Allowlist**: Infrastructure code, build scripts, and IaC roles in this repository fall under skip allowlist category 5: *"One-off build/provisioning scripts and declarative infrastructure roles verified by automated linters (`ansible-lint`, `shellcheck`) and live acceptance gates (`scripts/verify-*.sh`)"*.
  - Verification is performed exclusively via declarative static analyzers (`bash -n`, `shellcheck`, `ansible-lint`), the deterministic assertion matrix (`AUD-01` through `AUD-08` in `contracts/verification-gate-contract.md`), and existing live acceptance suites.

### Principle IV: Single Authoritative State, Enforced Boundaries, Safe Concurrency & Zero Secrets in Git
- **Compliance Status**: PASS
- **Analysis**:
  - Documentation links are normalized to repository-relative paths, eliminating conflicting machine-specific paths (`file:///C:/...`).
  - Production code and operational documentation decouple from ephemeral feature specs (`specs/NNN-*/`), pointing exclusively to permanent architectural models (`ROADMAP.md`, `docs/`) and invariant assertion IDs.
  - Zero plaintext credentials, private keys, or encrypted vault secrets are modified or tracked in version control during this audit.

### Principle V: Centralized Dependencies, Protected Toolchain Gate & Disaster Recovery by Design
- **Compliance Status**: PASS
- **Analysis**:
  - NO external dependencies, package versions, or Ansible collections are added or mutated.
  - The toolchain strictness is strictly protected: `.ansible-lint` retains `profile: production` and `.shellcheckrc` retains `shell=bash`. No rules are weakened or added to `skip_list` to bypass linting checks.
  - Disaster recovery documentation (`docs/disaster-recovery-phase3.md`) is maintained with relative links.

### Principle VI: Bounded Resources & Verify-Before-Destroy
- **Compliance Status**: PASS
- **Analysis**:
  - `.ansible-lint` excludes `.worktrees/` to prevent unbounded recursion and execution over auxiliary git worktrees.
  - Destructive/target-readiness confirmation guards in `scripts/apply-phase7-antigravity.sh` and `scripts/apply-phase7-antigravity.ps1` are preserved, updating only diagnostic citations from `FR-011` to permanent safety contracts.

### Principle VII: Code Hygiene, Ubiquitous Language & Safe Logging
- **Compliance Status**: PASS
- **Analysis**:
  - Zero warnings enforced across `ansible-lint` and `shellcheck`.
  - Variable naming across 8 roles standardizes on role-prefixed `snake_case` per `coding-standards.md`.
  - Repository root `README.md` is updated to include the four canonical sections mandated by Principle VII and `coding-standards.md`, documenting Phases 1–8.
  - Logging statements retain structured severity prefixes (`INFO`, `WARN`, `CRITICAL`, `DEBUG`) with zero credential exposure.

*Gate Evaluation*: **PASS** (Zero constitutional violations; all items strictly align with Principles I–VII and companion standards).

## Project Structure

### Documentation (this feature)

```text
specs/012-constitution-codebase-audit/
├── spec.md                     # Feature specification (scenarios, requirements FR-001..013, success criteria)
├── plan.md                     # This implementation plan (/speckit-plan output)
├── research.md                 # Phase 0 research decisions and audit root cause analysis
├── data-model.md               # Phase 1 domain entities, linter mappings, and variable renames
├── quickstart.md               # Phase 1 quickstart validation runbook
├── contracts/
│   └── verification-gate-contract.md # Verification assertion matrix (AUD-01..08)
└── checklists/
    └── requirements.md         # Requirements validation checklist
```

### Source Code (repository root)

```text
.ansible-lint                   # Linter configuration (profile: production, exclude .worktrees/, roles_path)
.shellcheckrc                   # Shellcheck configuration (shell=bash)
ansible.cfg                     # Root Ansible configuration resolving roles_path and inventory for root execution

ansible/
├── inventory/
│   └── group_vars/all/vars.yml # Formatting fixes, line wraps, and updated storage/smartd role variables
├── playbooks/
│   ├── antigravity.yml         # Phase 7 convergence playbook
│   ├── backup.yml              # Phase 5 backup playbook
│   ├── verify-phase4.yml       # Pipefail additions on shell tasks
│   ├── verify-phase5-backup.yml# Pipefail additions, line length, and trailing space fixes
│   ├── verify-phase7-antigravity.yml # Pipefail, systemd module, and command-instead-of-shell fixes
│   ├── verify-phase8-monitoring.yml  # Pipefail, systemd module, and line length fixes
│   └── verify.yml              # Pipefail additions and empty lines cleanup
└── roles/
    ├── antigravity/tasks/      # Prefix variables with antigravity_*, add pipefail, changed_when, failed_when
    ├── backup/tasks/           # Prefix local_vault_stat -> backup_local_vault_stat
    ├── common_packages/tasks/  # Prefix pkg_install -> common_packages_pkg_install
    ├── disk_health/            # Prefix smartd_scan_options & smartmontools_install -> disk_health_*
    ├── monitoring/handlers/    # Module-instead-of-command (systemd)
    ├── ssh_hardening/tasks/    # Prefix fail2ban_install -> ssh_hardening_fail2ban_install
    ├── storage_layout/         # Prefix storage_* defaults -> storage_layout_*
    ├── time_sync/tasks/        # Prefix chrony_install -> time_sync_chrony_install
    └── vaultwarden/tasks/      # Prefix tailscale_* & sqlite_pkg_install -> vaultwarden_*

scripts/
├── apply-phase7-antigravity.sh # Decouple from FR-011, retain target readiness safety guard
├── apply-phase7-antigravity.ps1# Decouple from FR-011, retain target readiness safety guard
├── bootstrap-speckit.sh        # Fix SC2129 redirection grouping
├── verify-phase2.sh            # Fix SC2329 dynamic dispatch annotation
├── verify-phase5-vaultwarden.sh# Fix SC2004 array arithmetic subscripts
├── verify-phase7-antigravity.sh# Fix SC2029 SSH command expansion annotation
└── verify-phase8-monitoring.sh # Fix SC2004 array arithmetic subscripts

README.md                       # Canonical 4-section layout, Phase 1-8 status, spec decoupling
ROADMAP.md                      # Relative links, Constitution v2.0.0, spec link decoupling
docs/
├── roadmap.md                  # Relative links, Constitution v2.0.0 compliance matrix, spec decoupling
├── operations.md               # Decouple from FR-011 and specs/005-vaultwarden-app/
└── disaster-recovery-phase3.md # Fix relative links
reference/
└── open-questions.md           # Centralized open questions registry (Principle I)
```

**Structure Decision**: Multi-tier Infrastructure-as-Code (IaC) and documentation layout. Root configuration files (`.ansible-lint`, `ansible.cfg`, `.shellcheckrc`) govern repository-level static analysis without requiring directory navigation; `ansible/` manages declarative playbooks and modular roles; `scripts/` contains modular operator runners and live verification suites; `docs/` and root Markdown files host permanent architecture and human-facing operational guides; `reference/` hosts the centralized open questions registry; and `specs/` maintains feature specifications and design contracts.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| None | None | All implementation items strictly comply with Principles I–VII and governance standards. |
