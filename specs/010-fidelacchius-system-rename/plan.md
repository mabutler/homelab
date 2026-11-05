# Implementation Plan: System Identity & Backup Bucket Naming (Fidelacchius)

**Branch**: `010-fidelacchius-system-rename` | **Date**: 2026-11-04 | **Spec**: [specs/010-fidelacchius-system-rename/spec.md](spec.md)

**Input**: Feature specification from `specs/010-fidelacchius-system-rename/spec.md`

## Summary

This feature establishes the official system identity "Fidelacchius (the sword of faith)" across the homelab infrastructure and migrates the offsite backup pipeline from the temporary test bucket (`homelab2-fidelachius`) to the official Backblaze B2 bucket (`fidelacchius-backups`).

The implementation covers four cohesive areas:
1. **Host Identity & Resolution**: Setting the Linux OS static and transient hostname to `fidelacchius` via `hostnamectl` and updating `/etc/hosts` for proper loopback resolution.
2. **Tailscale & Ingress**: Renaming the node on the Tailscale network mesh overlay to `fidelacchius` (claiming `fidelacchius.fable-mackarel.ts.net` following decommissioning of the legacy offline node), and updating Vaultwarden's public Funnel endpoint and `DOMAIN` environment variable.
3. **Backup Cloud Target Migration**: Reconfiguring offsite backup automation to point to `b2:fidelacchius-backups:fidelacchius`, updating B2 credentials with the newly provisioned application key (replacing the legacy key named `homelab`), initializing a clean Restic repository, creating a baseline snapshot, executing a non-destructive restore drill, and retiring the legacy test bucket and key.
4. **IaC & Inventory Alignment**: Renaming `homelab2` to `fidelacchius` in Ansible inventory (`inventory/hosts.yml`) and host variables directory (`inventory/host_vars/fidelacchius/`), and updating operator convergence and verification runner scripts.

## Technical Context

**Language/Version**: Bash 5.2+, Ansible 2.17+ (Python 3.12/3.13), Systemd 256+, Restic 0.17+  
**Primary Dependencies**: `hostnamectl`, `tailscale` CLI, `restic`, Backblaze B2, Docker Compose, Ansible core  
**Storage**: Backblaze B2 bucket `fidelacchius-backups` (`b2:fidelacchius-backups:fidelacchius`), local `/etc/hostname`, `/etc/hosts`, `/etc/homelab/backup.env`  
**Testing**: `verify-phase3.sh`, `verify-phase5-vaultwarden.sh`, `verify-phase5-backup.sh`, `ansible-playbook --check`, `hostnamectl`, `tailscale status`  
**Target Platform**: Arch Linux (Kernel 7.2.x, x86_64) on Gigabyte Z690 UD DDR4  
**Project Type**: Infrastructure as Code & System Administration / Disaster Recovery  
**Performance Goals**: Zero downtime for core OS, <15 min maintenance window for Funnel / backup cutover  
**Constraints**:
- Non-destructive cutover for backups
- Tailscale device collision handling (legacy offline node must be removed)
- Zero secrets in version control (Constitution Principle IV)
- Restore drill verification before declaring complete (Constitution Principle V)
- Internal platform paths (`/etc/homelab`, `/opt/services`, `homelab-backup.service`) preserved unchanged  
**Scale/Scope**: Single homelab node (`fidelacchius`, 192.168.4.57 / 100.120.174.15), Tailscale mesh network, B2 offsite bucket

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle / Gate | Assessment | Status |
|------------------|------------|--------|
| **I. Pragmatic Declarative-First Automation** | Ansible inventory and host variables are updated as the primary declarative definition; idempotent shell scripts are updated for operator CLI tasks. | **PASS** |
| **II. Strict Idempotency & Safe Convergence** | Hostname configuration, Tailscale preferences, and Ansible convergence are strictly idempotent. Destructive bucket operations are guarded. | **PASS** |
| **III. Automated Verification & Acceptance Gates** | Quickstart and verification suites (`verify-phase3.sh`, `verify-phase5-vaultwarden.sh`, `verify-phase5-backup.sh`) validate all network, ingress, and backup layers. | **PASS** |
| **IV. Zero Secrets in Version Control** | No real secrets or keys are committed. Real secrets remain in gitignored files (`vault.yml`, `/etc/homelab/backup.env`). Only `vault.yml.example` and documentation templates are updated. | **PASS** |
| **V. Disaster Recovery & Backup by Design** | Migration targets official Backblaze B2 bucket `fidelacchius-backups` with Restic client-side encryption. Mandatory restore verification drill confirms snapshot data integrity. | **PASS** |
| **VI. Modular & Decoupled Architecture** | Platform configuration paths (`/etc/homelab`, `/opt/services`) remain stable, avoiding ripple effects across unaffected container services. | **PASS** |
| **VII. Stability-First & Annual Maintenance Cadence** | Avoids unnecessary distro or container runtime upgrades; strictly addresses identity and backup repository alignment. | **PASS** |

## Project Structure

### Documentation (this feature)

```text
specs/010-fidelacchius-system-rename/
├── spec.md              # Feature specification
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (architectural decisions and analysis)
├── data-model.md        # Phase 1 output (entities, validation, state transitions)
├── quickstart.md        # Phase 1 output (runnable validation scenarios)
└── contracts/           # Phase 1 output (interface contracts)
    ├── system-identity-contract.md
    ├── tailscale-ingress-contract.md
    ├── backup-repository-contract.md
    └── ansible-inventory-contract.md
```

### Source Code (repository root)

```text
ansible/
├── inventory/
│   ├── hosts.yml                          # Updated: host homelab2 -> fidelacchius
│   ├── group_vars/
│   │   └── all/
│   │       ├── vars.yml                   # Updated: comments / defaults
│   │       ├── vault.yml                  # Local gitignored: updated repository target
│   │       └── vault.yml.example          # Updated: example template reference
│   └── host_vars/
│       └── fidelacchius/                  # Renamed from host_vars/homelab2/
│           └── storage.yml
├── roles/
│   ├── backup/
│   │   └── templates/
│   │       └── homelab-backup.j2          # Backup runner tags & comments
│   └── vaultwarden/
│       └── tasks/
│           └── config.yml                 # Dynamic FQDN discovery
└── playbooks/
    └── site.yml                           # Targets updated inventory

scripts/
├── restore-from-b2.sh                     # Updated default descriptions / targets
├── restore-from-b2.ps1                    # Updated default descriptions / targets
├── apply-phase3.sh / .ps1                 # Updated default target references
├── apply-phase4.sh / .ps1
├── apply-phase5.sh / .ps1
├── apply-phase7-antigravity.sh / .ps1
├── verify-phase3.sh / .ps1                # Updated assertion banners & targets
├── verify-phase4.sh / .ps1
├── verify-phase5-backup.sh / .ps1
├── verify-phase5-vaultwarden.sh / .ps1
└── verify-phase7-antigravity.sh / .ps1
```

**Structure Decision**: Infrastructure-as-Code repository layout. All changes modify existing files or rename the host-specific variable directory within standard Ansible and helper script layouts. No new microservices or architectural layers are added.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| *None* | N/A | Fully complies with all constitutional principles without exceptions. |
