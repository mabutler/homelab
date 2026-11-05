# homelab2 Coding Standards

<!--
Template Resolution Hierarchy Specification:
This template is resolved by agent skills using the native 4-tier template resolution hierarchy:
- Tier 1 (Overrides): .specify/templates/overrides/coding-standards-template.md
- Tier 2 (Presets): .specify/presets/<preset-id>/templates/coding-standards-template.md (evaluated per .specify/presets/.registry sorted ascending by priority; strategy: replace, prepend, append, wrap)
- Tier 3 (Extensions): .specify/extensions/<ext-id>/templates/coding-standards-template.md (evaluated per .specify/extensions/.registry sorted ascending by priority)
- Tier 4 (Core Fallback): .specify/templates/coding-standards-template.md

Invariant: If a requested template is not found in any of the 4 tiers, the agent MUST fail closed and emit an error per Principle II.
-->

## Constitutional Authority & Precedence

This document operationalizes the universal engineering principles established in the **homelab2 Constitution** into concrete, stack-specific implementation conventions for this repository.

- **Authority Link**: Governed by `.specify/memory/constitution.md` (or `constitution.md`). Universal rules defined in the Constitution (epistemic authority, two-tier failure semantics, behavioral testing, single authoritative state, supply-chain protection, bounded resources, and code hygiene) are not repeated here.
- **Precedence Declaration**: The Constitution ranks highest in authority. In any conflict between this Coding Standards document and the Core Principles of the Constitution, the Constitution strictly prevails.
- **Scope**: Applies to all production code, internal libraries, build scripts, and automated test harnesses maintained in this repository.

---

## Language, Runtime & Toolchain

Operationalizes Constitutional Principles V (*Centralized Dependencies & Protected Toolchain Gate*) and VII (*Zero Warnings & Read-Only Vendored Code*):

- **Target Platform**: Ansible Core (YAML / Jinja2) for declarative Infrastructure-as-Code; Bash 5.x (POSIX/Linux) and PowerShell 7+ (Windows Operator Workstation) for modular orchestration, bootstrap, and verification runners; Docker Engine & Docker Compose ( supervised via `systemd`) on bare-metal Arch Linux (`fidelacchius`).
- **Build, Linter & Zero-Warning Gates**: `ansible-lint` (configured via `.ansible-lint` with `profile: production`), `shellcheck` (configured via `.shellcheckrc` with `shell=bash`), and `bash -n` syntax validation across `scripts/**/*.sh`. All playbooks, roles, and scripts MUST pass with zero warnings before convergence or merge.
- **Dependency & Lockfile Conventions**: Ansible collections are pinned centrally in `ansible/requirements.yml` (`community.sops >=1.9.0`, `ansible.posix`, `community.general`); base OS packages are declared centrally in `ansible/inventory/group_vars/all/vars.yml` (`common_packages`); containerized workloads pin explicit upstream stable/LTS image tags in their role defaults and Docker Compose templates.

---

## Architecture, Module Layout & Compile-Time Boundaries

Operationalizes Constitutional Principle IV (*Structurally Enforced Boundaries*):

- **Project Structure & Layer Organization**:
  - `ansible/inventory/`: Single authoritative state for host topology (`hosts.yml`), global defaults (`group_vars/all/vars.yml`), drive topology (`host_vars/homelab2/storage.yml`), and gitignored secrets (`group_vars/all/vault.yml`).
  - `ansible/roles/<role>/`: Self-contained, modular infrastructure and application roles (`tasks/`, `defaults/`, `templates/`, `handlers/`, `files/`).
  - `ansible/playbooks/`: Top-level convergence entry points (`site.yml`, `harden.yml`, `storage.yml`, `backup.yml`, `<app>.yml`).
  - `scripts/`: Modular operator convergence runners (`apply-phase*.{sh,ps1}`), acceptance verification suites (`verify-phase*.{sh,ps1}`), disaster recovery scripts (`restore-from-b2.{sh,ps1}`), and live OS bootstrap modules (`scripts/install/`).
  - `docs/` & `ROADMAP.md`: Reconciled architecture, phase roadmap, operational runbooks, and recovery documentation.
- **Compile-Time Boundary & I/O Seam Enforcement**: Declarative Ansible roles MUST NOT embed ad-hoc imperative shell workarounds where native idempotent Ansible modules exist. When shell fallbacks are required (e.g., storage partitioning, MergerFS/SnapRAID orchestration, transactional SQLite/PostgreSQL dumps, or live verification probes), they MUST be isolated into standalone, contract-documented scripts with `set -euo pipefail`. Application containers bind strictly to loopback (`127.0.0.1:<port>`) or isolated Docker networks behind the Caddy reverse proxy and Tailscale overlay, and never touch raw host partitions outside their explicitly mounted NVMe (`/opt/services/<app>`) or MergerFS (`/mnt/storage`) directories.

---

## Error Handling & Failure Idioms

Operationalizes Constitutional Principle II (*Two-Tier Failure Model & Fail Closed on Required State*):

- **Canonical Result Types for Rejected Operations**: Distinct non-zero exit codes (e.g., exit codes `1..N` mapped to specific verification assertions such as `VW-01` through `VW-09` or `MON-01` through `MON-10`) accompanied by structured JSON results (`--json`) or actionable `WARN`/`ERROR` messages written to `stderr`. In Ansible tasks, expected boundary checks use `register` + explicit `failed_when` / `assert` conditions with descriptive `fail_msg` diagnostics.
- **Defect Invariant & Fail-Closed Mechanism**: All Bash scripts enforce `set -euo pipefail` (and PowerShell scripts enforce `$ErrorActionPreference = "Stop"`). Playbooks and scripts validate required preconditions (SSH reachability, required secret keys in `/etc/homelab/vault.yml` or `.env`, mount point presence, and explicit `--confirm-target-ready` safety flags for destructive or sensitive actions) before mutating state, halting immediately at `CRITICAL` on any violated precondition.

---

## State, Concurrency & Identifier Idioms

Operationalizes Constitutional Principle IV (*Safe Concurrency & Disambiguated Colliding Identifiers*):

- **Immutable Snapshots & Disambiguated ID Types**: Stateful service backups capture consistent, immutable point-in-time snapshots (e.g., SQLite `VACUUM INTO` online backup + `PRAGMA integrity_check` prior to Restic encrypted upload to Backblaze B2) rather than reading live mutated database files without locks. Systemd maintenance units and alert hooks enforce concurrency protection and recursion guards (e.g., `flock` lockfiles and cooldown state files in `/run/homelab-monitoring/`) so concurrent triggers cannot corrupt state or cause alert storms. Hardware devices and storage mounts are referenced exclusively by deterministic, disambiguated identifiers (`UUID=` in `/etc/fstab`, `/dev/disk/by-id/`, and `/dev/serial/by-id/` udev symlinks—never volatile `/dev/sdX` or `/dev/ttyUSBX` kernel names).

---

## Testing Framework & Conventions

Operationalizes Constitutional Principle III (*Behavioral, Value-Driven Testing & Deterministic Execution*):

- **Test Framework, Determinism & Naming**: Every infrastructure phase and application deployment is guarded by an automated acceptance verification suite (`scripts/verify-phase*.sh` and `.ps1`) implementing a numbered Assertion Matrix (`NET-01..08`, `STO-01..10`, `BK-01..08`, `VW-01..09`, `AG-001..008`, `MON-01..10`). Verification scripts support both `--local` execution and remote SSH execution, emit deterministic exit codes per assertion, and support `--json` structured reporting. Ansible playbooks additionally support `--check` (dry-run idempotency verification) to prove zero unintended state drift.

---

## Naming, Formatting & Code Style

Operationalizes Constitutional Principle VII (*Code Hygiene & Ubiquitous Language*):

- **Identifier & Code Style Conventions**:
  - **Ansible Variables & Role Names**: `snake_case` prefixed with the owning role or domain (e.g., `vaultwarden_internal_port`, `frigate_http_port`, `monitoring_cooldown_sec`).
  - **Scripts & Skill Directories**: `kebab-case` (e.g., `apply-phase5.sh`, `verify-phase8-monitoring.sh`, `homelab-hc-run`).
  - **Shell Constants & Environment Variables**: `UPPER_SNAKE_CASE` (e.g., `TARGET_HOST`, `LOCAL_MODE`, `REPO_ROOT`).
  - **Comments**: Present-tense, high-signal comments explaining *why* a configuration or guard exists and referencing the contract assertion it enforces, never narrating git history.

---

## Human-Facing Documentation & README Conventions

Operationalizes Constitutional Principle VII (*Code Hygiene, Ubiquitous Language & Safe Logging*):

- **Human-Facing Documentation & README Structure**: The repository root `README.md` (complemented by `ROADMAP.md` and `docs/operations.md`) serves as the primary human-facing onboarding and operational entry point and MUST maintain four canonical sections: (1) Project Overview & Phase Architecture, (2) Getting Started / Convergence Quickstart (`scripts/apply-phase*.{sh,ps1}`), (3) CLI / Skill / Acceptance Verification Reference (`scripts/verify-phase*.{sh,ps1}`), and (4) Configuration & Governance Verification. Any change classified as `USER_FACING` in `plan.md` (adding or modifying deployed services, operator CLI flags, recovery runbooks, agent skills, or governance rules) MUST update `README.md`, `ROADMAP.md`, and relevant `docs/` guides in the same change. Purely internal changes (`INTERNAL_ONLY` refactors or lint fixes) are exempt from artificial `README.md` edits.
