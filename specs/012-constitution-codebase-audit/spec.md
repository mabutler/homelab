# Feature Specification: Constitution v2.0.0 Codebase Audit and Alignment

**Feature Branch**: `012-constitution-codebase-audit`

**Created**: 2026-11-05

**Status**: Ready for Planning

**Input**: User description: "With the recent constitution updates, scan the codebase and see what changes we need"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Clean Static Verification & Pre-PR Gate Enforcement (Priority: P1)

As a homelab operator or autonomous agent submitting changes, I need all automation scripts, configuration management playbooks, and syntax validators to pass cleanly with zero warnings, so that the constitutional pre-PR verification gate (`bash -n scripts/*.sh && shellcheck scripts/*.sh && ansible-lint`) executes with deterministic exit code 0 and protects repository stability.

**Why this priority**: Constitutional Principle VII (*Zero Warnings & Read-Only Vendored Code*) and the Development Workflow mandate that `main` must always build and lint cleanly. Currently, `shellcheck` fails across multiple scripts and `ansible-lint` fails with dozens of violations under the production profile.

**Independent Test**: Can be fully tested by executing `bash -n scripts/*.sh && shellcheck scripts/*.sh && ansible-lint` from repository root and asserting exit code 0 with zero warnings.

**Acceptance Scenarios**:

1. **Given** the repository root checkout, **When** `shellcheck scripts/*.sh bootstrap-speckit.sh` is executed, **Then** all scripts exit with code 0 and zero diagnostic warnings.
2. **Given** the repository root checkout, **When** `ansible-lint` is executed under the production profile, **Then** zero fatal violations, syntax check errors, or formatting defects are reported.
3. **Given** the presence of local `.worktrees/` development branches, **When** linters run, **Then** isolated worktrees are excluded from repository-level linting scans.

---

### User Story 2 - Epistemic Authority, Path Normalization & Constitution Version Alignment (Priority: P1)

As an operator or agent navigating repository architecture, I need all documentation and links to reference the ratified Constitution v2.0.0, use repository-relative Markdown links rather than machine-specific paths (`file:///C:/...`), and provide an authoritative location for unresolved questions (`reference/open-questions.md`), so that all engineering decisions trace to authoritative sources.

**Why this priority**: Constitutional Principle I (*Evidence Over Invention, Bounded Investigation*) and Principle IV (*Single Authoritative State*) require unambiguous epistemic traceability. Machine-specific paths break navigation across platforms, and outdated version citations create governance confusion.

**Independent Test**: Can be tested by scanning all `.md` files for `file:///C:` and verifying that governance references cite Constitution v2.0.0 and that `reference/open-questions.md` exists.

**Acceptance Scenarios**:

1. **Given** the documentation files (`ROADMAP.md`, `docs/roadmap.md`, `docs/disaster-recovery-phase3.md`), **When** inspected for link URIs, **Then** zero `file:///C:` or machine-specific absolute file URLs exist, and all links use valid relative paths.
2. **Given** governance references across `ROADMAP.md` and `docs/roadmap.md`, **When** inspected for version numbers, **Then** all references cite Constitution v2.0.0 and companion standards (`coding-standards.md`, `logging-standards.md`).
3. **Given** the repository structure, **When** checked for open questions tracking, **Then** `reference/open-questions.md` exists with clear guidelines for logging unresolved ambiguities.

---

### User Story 3 - Strict Ephemeral Spec Decoupling & Spec Citation Hygiene (Priority: P2)

As a platform maintainer, I need production scripts, configuration templates, and operational runbooks outside `specs/` to be completely decoupled from ephemeral feature specs (`specs/NNN-*/`) and transient requirement IDs (`FR-XXX`), referencing permanent contracts or assertion IDs instead.

**Why this priority**: Constitutional Principle VII and the Development Workflow explicitly state: "Production code, comments, documentation, and commit messages outside `specs/` MUST NOT cite spec folders or `FR-XXX` identifiers." Multiple operational runbooks and scripts currently cite `FR-011`, `FR-006`, and `specs/005-vaultwarden-app/`.

**Independent Test**: Can be tested by searching for `specs/` and `FR-` outside the `specs/` directory (excluding Spec Kit agent internals and tooling) and asserting zero occurrences in production code, scripts, or operational docs.

**Acceptance Scenarios**:

1. **Given** production scripts (`scripts/apply-phase7-antigravity.sh`, `scripts/apply-phase7-antigravity.ps1`, `scripts/install/install.conf.example`), **When** inspected for spec markers, **Then** all citations of `FR-011` and `FR-006` are replaced with behavioral contract descriptions or assertion references (e.g., target readiness safety guard, `AG-001..008`).
2. **Given** operational documentation (`docs/operations.md`, `README.md`, `docs/roadmap.md`), **When** inspected for spec citations, **Then** all links to ephemeral `specs/NNN-*/` files are replaced with permanent architectural or contract references.

---

### User Story 4 - Canonical Human-Facing Documentation Structure (Priority: P2)

As a new homelab operator or external collaborator, I need `README.md` to maintain the four canonical sections required by Constitutional Principle VII and `coding-standards.md` and accurately reflect all completed phases (including Antigravity Remote Control and Platform Monitoring/Alerting) with accurate quickstart commands.

**Why this priority**: The root `README.md` is the primary human-facing entry point. It currently lacks the mandatory canonical section layout, omits recent completed phases (Phase 7 and Phase 8), and contains links to ephemeral spec folders.

**Independent Test**: Can be tested by inspecting `README.md` for the four canonical headings and verifying all listed verification commands execute or describe existing scripts.

**Acceptance Scenarios**:

1. **Given** `README.md`, **When** reviewed against `coding-standards.md`, **Then** it contains the four canonical sections: (1) Project Overview & Phase Architecture, (2) Getting Started / Convergence Quickstart, (3) CLI / Skill / Acceptance Verification Reference, and (4) Configuration & Governance Verification.
2. **Given** the Phase Architecture summary in `README.md`, **When** compared against repository state, **Then** it documents Phase 1 through Phase 5, Phase 7 (Antigravity Remote Control), and Phase 8 (Monitoring, Alerting & Healthchecks).

---

### User Story 5 - Failure Idiom & Idempotent Playbook Hygiene (Priority: P3)

As a system reliability engineer, I need Ansible tasks and shell scripts to adhere to strict failure idioms: native modules over shell workarounds, explicit `changed_when` conditions, `set -o pipefail` in pipelines, and `failed_when` assertions rather than `ignore_errors: true`.

**Why this priority**: Constitutional Principle II (*Strict Idempotency & Safe Convergence*) and `coding-standards.md` require automation routines to be safely re-runnable with predictable failure semantics and zero unintended state divergence.

**Independent Test**: Can be tested by running `ansible-lint` against all roles and playbooks and verifying that rule tags `command-shell`, `idempotency`, and `unpredictability` have zero violations.

**Acceptance Scenarios**:

1. **Given** Ansible tasks using shell pipes, **When** evaluated, **Then** each task sets `pipefail: true` or incorporates explicit pipeline error handling.
2. **Given** Ansible tasks executing commands, **When** evaluated, **Then** each task defines an explicit `changed_when` condition or uses a native idempotent module.
3. **Given** Ansible tasks with potential error states, **When** evaluated, **Then** `ignore_errors: true` is replaced with controlled `failed_when` conditions that document allowable non-fatal states.

---

### Edge Cases

- **What happens when `.worktrees/` directory exists locally during `ansible-lint` execution?**
  `.ansible-lint` must explicitly list `.worktrees/` in `exclude_paths` so temporary git worktrees are never traversed by linting tasks on the main branch.
- **What happens when a shell script invokes test functions dynamically?**
  In `scripts/verify-phase2.sh`, dynamic function calls flagged by ShellCheck SC2329 must be either directly invoked or annotated with `# shellcheck disable=SC2329` with a clarifying comment explaining the dispatch mechanism.
- **How does documentation handle historical specs given Recorded Deviation 001?**
  Recorded Deviation 001 in the Constitution ratifies retaining historical specs `specs/001-*` through `specs/011-*` on disk as archival audit records. However, active production code, runbooks, and `README.md` must not link to them as operational documentation.
- **What happens when open questions are identified during an audit?**
  Unresolved questions must be formally recorded in `reference/open-questions.md` with cited evidence, owning authority, and working assumptions rather than left as inline code comments or undocumented gaps.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Linter configuration (`.ansible-lint`) MUST explicitly exclude `.worktrees/` from directory expansion and ensure root-level execution cleanly locates Ansible roles in `ansible/roles`.
- **FR-002**: Ansible role variables and registered task results in `ansible/roles/` MUST strictly comply with role prefix naming conventions (`var-naming`), eliminating all 34 `no-role-prefix` violations.
- **FR-003**: Ansible playbooks and role tasks MUST eliminate all 17 `risky-shell-pipe` violations by setting `pipefail: true` or explicitly handling pipe failures in shell tasks.
- **FR-004**: Ansible playbooks and role tasks MUST replace imperative `command` and `shell` invocations with native idempotent Ansible modules (`systemd`, `git`, `get_url`) where available, resolving all 10 `command-instead-of-module` and `command-instead-of-shell` violations.
- **FR-005**: Ansible playbooks and tasks MUST eliminate `ignore_errors: true` in favor of explicit, typed `failed_when` conditions and define explicit `changed_when` triggers on all command tasks.
- **FR-006**: Ansible inventory and playbook YAML files MUST resolve all 12 formatting violations (lines exceeding 160 characters, trailing whitespace, and excessive blank lines) to achieve clean production profile compliance.
- **FR-007**: Shell automation scripts (`scripts/*.sh` and `bootstrap-speckit.sh`) MUST resolve all ShellCheck warnings (SC2329 in `verify-phase2.sh`, SC2004 in `verify-phase5-vaultwarden.sh` and `verify-phase8-monitoring.sh`, SC2029 in `verify-phase7-antigravity.sh`, and SC2129 in `bootstrap-speckit.sh`), ensuring `shellcheck` passes with exit code 0.
- **FR-008**: All repository documentation files (`ROADMAP.md`, `docs/roadmap.md`, `docs/disaster-recovery-phase3.md`) MUST purge machine-specific absolute file URIs (`file:///C:/Users/micro/...`) and replace them with repository-relative Markdown links.
- **FR-009**: All governance references across `ROADMAP.md` and `docs/roadmap.md` MUST be updated from outdated "v1.1.0" citations to ratified "v2.0.0" and link directly to `.specify/memory/constitution.md`.
- **FR-010**: The repository MUST establish `reference/open-questions.md` conforming to Constitutional Principle I to track open questions, ambiguities, and deferred decisions.
- **FR-011**: Production scripts and operational documentation outside `specs/` (`docs/operations.md`, `scripts/apply-phase7-antigravity.sh`, `scripts/apply-phase7-antigravity.ps1`, `scripts/install/install.conf.example`, and `README.md`) MUST purge ephemeral `specs/NNN-*/` paths and `FR-XXX` identifiers, replacing them with permanent contract assertion IDs (e.g., `AG-001..008`) or permanent architectural documents.
- **FR-012**: The repository root `README.md` MUST be structured with the four mandatory canonical sections defined in Principle VII and `coding-standards.md`: (1) Project Overview & Phase Architecture, (2) Getting Started / Convergence Quickstart, (3) CLI / Skill / Acceptance Verification Reference, and (4) Configuration & Governance Verification, updated to reflect all completed phases (Phase 1 through Phase 5, Phase 7, and Phase 8).
- **FR-013**: The constitutional pre-PR verification command (`bash -n scripts/*.sh && shellcheck scripts/*.sh && ansible-lint`) MUST execute cleanly with exit code 0 and zero warnings.

### Key Entities

- **GovernanceDocument**: Architectural specification or standard (`constitution.md`, `coding-standards.md`, `logging-standards.md`, `ROADMAP.md`, `README.md`) establishing authoritative policies.
- **AuditFinding**: Concrete gap or non-compliance item identified in the codebase with file location, violated principle, severity, and remediation action.
- **LinterConfiguration**: Tool configuration file (`.ansible-lint`, `.shellcheckrc`) enforcing static verification gates without runtime test files.
- **VerificationGate**: Pre-PR automated command sequence ensuring zero warnings, strict syntax validation, and live acceptance readiness.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of shell scripts in `scripts/` and root pass `bash -n` and `shellcheck` with zero errors and zero warnings (exit code 0).
- **SC-002**: 100% of Ansible playbooks and roles in `ansible/` pass `ansible-lint` under the `production` profile with zero violations (exit code 0).
- **SC-003**: 0 machine-specific absolute file paths (`file:///C:...`) remain in repository markdown documents.
- **SC-004**: 0 citations of ephemeral `specs/NNN-*/` directories or `FR-XXX` requirement identifiers exist in production code, scripts, or operational documentation outside `specs/`.
- **SC-005**: 100% of governance citations across documentation reference Constitution v2.0.0 and its companion standards.
- **SC-006**: Root `README.md` contains all four mandatory canonical sections and accurately reflects Phase 1 through Phase 8 status.
- **SC-007**: Centralized open questions registry `reference/open-questions.md` is initialized and referenced by documentation.
- **SC-008**: The unified pre-PR verification command completes with exit code 0.

## Assumptions

- **Archival Specs**: Historical feature specifications `specs/001-*` through `specs/011-*` remain preserved on disk per Recorded Deviation 001 as archival audit artifacts, but active documentation and code must decouple from them.
- **Static Verification Only**: No automated unit test files, mock frameworks, or test suites are to be created, strictly observing Constitutional Principle III. All verification is performed via static analysis (`shellcheck`, `ansible-lint`, `bash -n`) and existing live acceptance runners (`verify-phase*.sh`).
- **Platform Portability**: Shell scripts target Bash 5.x on Linux and PowerShell 7+ on Windows operator workstations.
- **Zero Secret Exposure**: No plaintext secrets or live credential material will be touched, logged, or altered during the audit and alignment.
