# Implementation Plan: Target Host Antigravity Installation & Remote Control

**Branch**: `007-antigravity-remote-control` | **Date**: 2026-11-02 | **Spec**: [spec.md](file:///C:/Users/micro/projects/homelab2/.worktrees/007-antigravity-remote-control/specs/007-antigravity-remote-control/spec.md)

**Input**: Feature specification from `specs/007-antigravity-remote-control/spec.md`

---

## Summary

Feature 007 deploys the Google Antigravity CLI (`agy`) and configures its background Remote Control daemon on the target server (`admin@192.168.4.57`), enabling the homelab operator to remotely inspect, develop, and build out remaining homelab infrastructure phases from a mobile device or browser while away from home. The implementation installs the CLI binary under the non-root `admin` account with a system-wide symlink (`/usr/local/bin/agy`), registers `agy-remote-control.service` with instance name `homelab2-target` under systemd user supervision, enables user session lingering (`loginctl enable-linger admin`) for headless persistence across reboots, configures autonomous execution permissions (`"toolPermission": "always-proceed"`) in `settings.json`, provisions the `homelab2` workspace with dedicated GitHub SSH deploy key authentication and worktree isolation, registers authentication and configuration profiles in the encrypted offsite Restic/Backblaze B2 backup catalog while excluding transient caches, and enforces an explicit safety confirmation guard (FR-011) before live execution.

---

## Technical Context

**Language/Version**:
- CLI Engine: Upstream Google Antigravity CLI (`agy`) x86_64 ELF binary
- Automation & Scripting: Bash 5.2+, PowerShell 7+, Ansible 2.16+
- Configuration Formats: JSON, YAML, SSH Config

**Primary Dependencies**:
- CLI Binary: Google Antigravity CLI (`agy`) installed via official stream (`https://antigravity.google/cli/install.sh`)
- Process & Service Supervision: systemd user manager (`systemd --user`), `loginctl` (systemd-logind user lingering)
- Version Control: `git` 2.40+ (supporting worktrees and SSH deploy keys)
- Network Transport: Outbound HTTPS/WSS (no inbound firewall ports or router port-forwarding required)
- Cloud Storage / Backup: Restic 0.16+ targeting Backblaze B2 via existing Phase 6 backup framework

**Storage**:
- CLI Installation: `/home/admin/.local/bin/agy` (symlinked from `/usr/local/bin/agy`)
- Agent Profile & Config: `/home/admin/.gemini/antigravity-cli/settings.json` (mode `0600 admin:admin`)
- Authentication State: `/home/admin/.gemini/oauth_creds.json`, `/home/admin/.gemini/google_accounts.json` (mode `0600 admin:admin`)
- Project Workspace: `/home/admin/homelab2` (owned by `admin:admin`)
- Isolated Worktrees: `/home/admin/homelab2/.worktrees/*`
- Git SSH Key: `/home/admin/.ssh/id_ed25519_github` (mode `0600 admin:admin`), `/home/admin/.ssh/config`
- Systemd User Unit: `/home/admin/.config/systemd/user/agy-remote-control.service`
- User Linger Marker: `/var/lib/systemd/linger/admin`

**Testing**:
- Local Acceptance Runner: `scripts/verify-phase7-antigravity.sh` (8 automated assertions in [`verification-suite-contract.md`](contracts/verification-suite-contract.md))
- Workstation Orchestration: `scripts/verify-phase7-antigravity.ps1`
- Ansible Verification Playbook: `ansible/playbooks/verify-phase7-antigravity.yml` integrated into unified `verify.yml`
- Non-Destructive Restore Test: Automated assertion confirming auth files and settings recovery from Restic backup snapshot

**Target Platform & Deployment Target**:
- Target Host: `admin@192.168.4.57` (`homelab2`), Arch Linux bare-metal x86_64
- Deployment Mechanism: Ansible playbook push targeting `admin@192.168.4.57` via workstation orchestrator `scripts/apply-phase7-antigravity.ps1 -HostAddress 192.168.4.57 -User admin -ConfirmTargetReady` (and server-side `scripts/apply-phase7-antigravity.sh --confirm-target-ready`)
- Verification Mechanism: Remote acceptance verification suite executed via `scripts/verify-phase7-antigravity.ps1 -TargetHost 192.168.4.57 -User admin`

**Project Type**:
- Infrastructure automation, developer tooling deployment, and systemd user daemon supervision

**Performance Goals**:
- Daemon reconnects and appears online in Remote Control interface within 60 seconds after host reboot (SC-001)
- Re-running automation against converged host completes in under 60 seconds without service interruption (SC-003)
- Verification test suite executes all 8 assertions in under 15 seconds (SC-004)
- Disaster recovery credential restoration completes in under 2 minutes (SC-005)

**Constraints**:
- Explicit live execution gate (FR-011): Automation MUST NOT execute against `admin@192.168.4.57` without explicit `--confirm-target-ready` flag.
- Zero secrets in version control (Principle IV): OAuth tokens and SSH private keys reside strictly in gitignored paths on disk and encrypted Restic backups, never in Git.
- Unattended autonomous execution: Tool permissions configured to `"always-proceed"` so remote tasks do not deadlock on interactive prompts.
- Least privilege: CLI and background daemon run under unprivileged `admin` operator account, elevating via passwordless sudo only when executing homelab system changes.

**Scale/Scope**:
- Single-node remote development and orchestration agent managing the `homelab2` server repository and host state.

---

## Constitution Check

*GATE: Evaluated prior to Phase 0 research and re-evaluated post-design.*

| Principle / Gate | Compliance Analysis | Status |
|---|---|---|
| **I. Pragmatic Declarative-First Automation** | Installation and configuration are declared via Ansible role `ansible/roles/antigravity` managing `settings.json`, systemd user services, linger state, SSH configurations, and backup manifests. Binary download uses idempotent upstream curl installer. | **PASS** |
| **II. Strict Idempotency & Safe Convergence** | Rerunning playbooks or scripts produces no drift and leaves active daemon sessions undisturbed. Live deployment is protected by explicit `--confirm-target-ready` gate to prevent accidental execution (FR-011). | **PASS** |
| **III. Automated Verification & Acceptance Gates** | 8 automated assertions defined in [`verification-suite-contract.md`](contracts/verification-suite-contract.md) verifying binary availability, lingering, service state, registration, permissions, git workspace, backup inclusion, and zero secrets in git. | **PASS** |
| **IV. Zero Secrets in Version Control & Isolated Configuration** | OAuth credentials (`oauth_creds.json`, `google_accounts.json`) and SSH private keys (`id_ed25519_github`) are stored exclusively in gitignored directories (`~/.gemini/`, `~/.ssh/`) with mode `0600`. Real credentials are protected by client-side encrypted offsite Restic backups to Backblaze B2. | **PASS** |
| **V. Disaster Recovery & Backup by Design** | Agent configuration and credentials registered in `/etc/homelab/backup-include.txt`, ephemeral caches excluded in `/etc/homelab/backup-excludes.txt`. Disaster recovery procedure recovers credentials seamlessly without requiring re-authentication. | **PASS** |
| **VI. Modular & Decoupled Architecture** | Antigravity runs as a decoupled systemd user daemon communicating over outbound WSS/HTTPS, completely isolated from container workloads and other system services. | **PASS** |
| **VII. Stability-First & Annual Maintenance Cadence** | Leverages systemd user supervision with automatic restart on failure and structured journal logging (`journalctl --user`), requiring zero routine maintenance. | **PASS** |

**Constitution Gate Outcome**: **PASS**. 100% compliant with Constitution v1.3.0; zero principle violations; no exemptions required.

---

## Project Structure

### Documentation (this feature)

```text
specs/007-antigravity-remote-control/
├── checklists/
│   └── requirements.md                    # Requirements validation checklist
├── contracts/
│   ├── antigravity-daemon-contract.md     # Daemon lifecycle, systemd user service & lingering specification
│   ├── backup-registration-contract.md    # Backup manifests inclusion/exclusion & DR restoration specification
│   ├── host-workspace-contract.md         # Workspace directory, settings.json perms & Git SSH key specification
│   └── verification-suite-contract.md     # 8 automated acceptance assertions (AG-001 through AG-008)
├── data-model.md                          # Entity relationships, validation rules, state transitions
├── plan.md                                # This implementation plan (/speckit-plan output)
├── quickstart.md                          # Operational validation scenarios and runbook
├── research.md                            # Phase 0 architectural decisions, rationale, alternatives
└── spec.md                                # Feature specification
```

### Source Code (repository root)

```text
ansible/
├── playbooks/
│   ├── antigravity.yml                    # Standalone playbook deploying Antigravity & Remote Control
│   ├── site.yml                           # Full convergence playbook (includes antigravity.yml)
│   ├── verify-phase7-antigravity.yml      # Ansible acceptance verification playbook
│   └── verify.yml                         # Unified test runner playbook (includes verify-phase7-antigravity.yml)
└── roles/
    └── antigravity/                       # Ansible role for Antigravity & Remote Control
        ├── defaults/
        │   └── main.yml                   # Default variables (instance name, paths, model)
        ├── handlers/
        │   └── main.yml                   # Handlers (restart agy-remote-control.service)
        └── tasks/
            ├── main.yml                   # Role entrypoint coordinating task files
            ├── install.yml                # Binary installation & symlink creation
            ├── config.yml                 # settings.json autonomous configuration
            ├── auth.yml                   # Credential seeding & one-time OAuth handling
            ├── daemon.yml                 # User lingering & systemd user service registration
            ├── workspace.yml              # homelab2 git clone, worktree setup & SSH key config
            └── backup.yml                 # backup-include.txt and backup-excludes.txt integration

scripts/
├── apply-phase7-antigravity.ps1           # Workstation orchestrator (with -ConfirmTargetReady guard)
├── apply-phase7-antigravity.sh            # Server-side orchestrator (with --confirm-target-ready guard)
├── verify-phase7-antigravity.ps1          # Workstation verification orchestrator
└── verify-phase7-antigravity.sh           # Server-side acceptance verification runner (AG-001..AG-008)
```

**Structure Decision**: Infrastructure automation extending the established homelab pattern: Ansible role `ansible/roles/antigravity`, playbooks in `ansible/playbooks/`, and workstation/server orchestrators in `scripts/`.

---

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

*Zero violations. No complexity exemptions required.*
