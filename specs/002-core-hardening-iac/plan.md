# Implementation Plan: Core Hardening & Configuration Management Foundation

**Branch**: `002-core-hardening-iac` | **Date**: 2026-11-01 | **Spec**: [`specs/002-core-hardening-iac/spec.md`](file:///C:/Users/micro/projects/homelab2/specs/002-core-hardening-iac/spec.md)

**Input**: Feature specification from [`specs/002-core-hardening-iac/spec.md`](file:///C:/Users/micro/projects/homelab2/specs/002-core-hardening-iac/spec.md) with production target machine `admin@192.168.4.57` (SSH key authentication configured).

---

## Summary

Establish an Infrastructure-as-Code foundation using Ansible and SOPS with age asymmetric key encryption, applying base system hardening, operational telemetry, and peripheral device rules to the production Arch Linux host at `admin@192.168.4.57`. This feature configures strict SSH hardening (public key only, zero passwords, brute-force rate limiting via fail2ban with local subnet protection), preserves administrative privilege escalation with passwordless sudo for automation, enables core system health daemons (`chrony` time synchronization, `smartd` drive diagnostic telemetry, `systemd-oomd` memory safeguards, persistent `journald` quotas), installs persistent udev rules for connected peripherals (Z-Wave controller, Google Coral TPU), and verifies the live production environment against Constitution Phase 2 quality and local telemetry gates.

---

## Technical Context

**Language/Version**: Python 3.10+ (Ansible Core 2.15+ / 2.16+ runtime), YAML 1.2, POSIX Shell / Bash 5.2+, PowerShell 7+ (Windows operator orchestration)

**Primary Dependencies**:
- Automation Engine: `ansible-core`, `ansible-lint`, `community.sops` collection
- Cryptographic Secrets Tooling: `sops` (v3.8+), `age` (v1.1+)
- Hardening & Security: OpenSSH (`sshd`), `fail2ban` (with systemd backend), `sudo`
- Core Health Daemons: `chrony` (NTP sync), `smartmontools` (`smartd`), `systemd-oomd`, `systemd-journald`
- Peripheral Management: `udev` (`systemd-udevd`)

**Production Target Host**:
- Network Address: `192.168.4.57`
- Administrative User: `admin`
- Host Authentication: Existing SSH public key authentication pre-configured and operational
- Privilege Escalation: Non-interactive `sudo` configured for `admin`
- Target Environment: x86-64 bare-metal host running Arch Linux (kernel 7.2.11-arch1-1), Python 3.14.9 runtime

**Storage**:
- Local host root filesystem (`/`) and boot partition (`/boot`) provisioned in Phase 1
- Persistent journal logging bounded to 2.0 GiB on disk (`/var/log/journal`)

**Testing & Orchestration**:
- Static analysis & linting: `ansible-lint`, `yamllint`, `ansible-playbook --syntax-check`
- Production convergence runners:
  - Standard Ansible controller push: `ansible-playbook -i inventory/hosts.yml playbooks/site.yml`
  - Cross-platform orchestrator: `scripts/apply-phase2.ps1` (PowerShell for Windows workstation -> SSH sync & converge) and `scripts/apply-phase2.sh` (POSIX)
- Idempotency testing: consecutive playbook runs asserting `changed=0`
- Acceptance verification suite: [`contracts/verification-suite.md`](file:///C:/Users/micro/projects/homelab2/specs/002-core-hardening-iac/contracts/verification-suite.md) and [`scripts/verify-phase2.sh`](file:///C:/Users/micro/projects/homelab2/scripts/verify-phase2.sh)
- Runnable verification scenarios in [`quickstart.md`](file:///C:/Users/micro/projects/homelab2/specs/002-core-hardening-iac/quickstart.md)

**Performance Goals**:
- Full clean-slate site convergence against `192.168.4.57` completes in under 10 minutes (SC-001)
- Re-run idempotency completes in under 60 seconds with 0 changed tasks (SC-002)
- Key-based administrative SSH login connects in under 3 seconds (SC-004)
- System time offset remains within 50 milliseconds of upstream NTP (SC-005)

**Constraints & Safeguards**:
- Headless safety: SSH drop-ins and sudoers drop-ins must pass syntax validation (`sshd -t` and `visudo -cf`) before reload/write to prevent operator lockout from `admin@192.168.4.57` (Edge Cases)
- Fail2ban subnet protection: Fail2ban `ignoreip` must include `127.0.0.1/8` and the local management subnet `192.168.4.0/24` to prevent inadvertent lockout of the administration workstation
- Zero cleartext passwords or secret keys in version control or filesystem (FR-002, SC-003)
- Missing peripherals (Coral TPU or Z-Wave dongle) must not break playbook execution (Edge Cases)

**Scale/Scope**: Production bare-metal host `homelab2` (`admin@192.168.4.57`), establishing the platform foundation for Phase 3 (Network) through Phase 8 (Telemetry).

---

## Constitution Check

*GATE: Evaluated prior to Phase 0 research and re-evaluated post-design.*

| Principle / Gate | Compliance Analysis | Status |
|---|---|---|
| **I. Pragmatic Declarative-First Automation** | Uses Ansible as primary declarative IaC engine for all host configurations, roles, and daemons on `192.168.4.57`. Modular roles with clear boundaries; any edge script fallbacks live in designated script modules with explicit contracts. | **PASS** |
| **II. Strict Idempotency & Safe Convergence** | All roles and tasks designed to produce 0 changes on re-run against production. No destructive disk or credential operations run unconfirmed. Idempotency is explicitly verified via `changed=0`. | **PASS** |
| **III. Automated Verification & Acceptance Gates** | 10 automated health checks defined in verification contract and runnable via `verify.yml` and `scripts/verify-phase2.sh` against `192.168.4.57`. Conforms to v1.2.0 amendment: Phase 2 is an early local hardening phase prior to full network overlay setup, so verification is focused on local health assertions (`sshd`, `chronyd`, `smartd`, `systemd-oomd`, persistent journald) and exit codes. | **PASS** |
| **IV. Zero Cleartext Secrets & Isolated Configuration** | Secrets encrypted at rest via SOPS using age asymmetric encryption (`vault.sops.yml`). Cleartext secrets never committed. Decrypted in memory during convergence using operator's age private key. | **PASS** |
| **V. Disaster Recovery & Backup by Design** | Conforms to v1.2.0 amendment: Early standalone phase exempt from off-host backup pipelines; Phase 2 backup readiness satisfied by version-controlled encrypted vault, committed inventory, and documented out-of-band age key backup. | **PASS** |
| **VI. Modular & Decoupled Architecture** | Decomposed into discrete, self-contained Ansible roles (`ssh_hardening`, `admin_user`, `time_sync`, `disk_health`, `system_safeguards`, `udev_rules`), tagged for independent execution against production. | **PASS** |
| **VII. Stability-First & Annual Maintenance** | Employs battle-tested system components (`sshd`, `chrony`, `smartd`, `systemd-oomd`) with stable defaults. Avoids speculative abstractions and ephemeral packages. | **PASS** |

**Constitution Gate Outcome**: **PASS**. Zero principle violations; no exemptions or complexity overrides required.

---

## Project Structure

### Documentation (this feature)

```text
specs/002-core-hardening-iac/
├── checklists/
│   └── requirements.md       # Checklist for Phase 2 spec requirements
├── contracts/
│   ├── ansible-orchestration.md # Ansible CLI invocation syntax, tags, and exit codes
│   ├── secrets-schema.md     # SOPS vault schema, age key standards, and variables
│   └── verification-suite.md # Acceptance test matrix, assertions, and check IDs
├── data-model.md             # Logical entities, attributes, and relationships
├── plan.md                   # This implementation plan
├── quickstart.md             # Step-by-step operator convergence and verification guide
├── research.md               # Phase 0 architectural decisions, rationale, alternatives
├── spec.md                   # Feature specification
└── tasks.md                  # Implementation tasks breakdown
```

### Source Code (repository root)

```text
ansible/
├── ansible.cfg                          # Standard Ansible configuration
├── requirements.yml                     # Ansible collections (community.sops)
├── inventory/
│   ├── hosts.yml                        # Production host definition (homelab2 -> 192.168.4.57)
│   └── group_vars/
│       └── all/
│           ├── vars.yml                 # Non-sensitive variables (ports, limits, fail2ban whitelist)
│           └── vault.sops.yml           # Encrypted secrets (admin credentials, tokens)
├── playbooks/
│   ├── site.yml                         # Main convergence orchestrator playbook
│   ├── harden.yml                       # Hardening and security-only playbook
│   └── verify.yml                       # Health assertions & acceptance verification playbook
└── roles/
    ├── common_packages/                 # Base operational utilities and tools
    │   └── tasks/main.yml
    ├── admin_user/                      # Operator user, groups, authorized keys, sudoers drop-in
    │   ├── tasks/main.yml
    │   └── templates/sudoers_wheel.j2
    ├── ssh_hardening/                   # Drop-in sshd configuration and fail2ban intrusion prevention
    │   ├── tasks/main.yml
    │   ├── templates/sshd_hardening.conf.j2
    │   └── templates/jail.local.j2
    ├── time_sync/                       # Chrony NTP service and hardware RTC sync
    │   ├── tasks/main.yml
    │   └── templates/chrony.conf.j2
    ├── disk_health/                     # Smartmontools (smartd) continuous disk diagnostics
    │   ├── tasks/main.yml
    │   └── templates/smartd.conf.j2
    ├── system_safeguards/               # systemd-oomd memory protection and journald retention quotas
    │   ├── tasks/main.yml
    │   ├── templates/oomd.conf.j2
    │   └── templates/journald.conf.j2
    └── udev_rules/                      # Persistent hardware symlinks (Z-Wave, Coral TPU, uinput)
        ├── tasks/main.yml
        └── templates/99-homelab-peripherals.rules.j2

scripts/
├── apply-phase2.ps1                     # Windows operator orchestrator: sync & run Ansible against 192.168.4.57
├── apply-phase2.sh                      # POSIX operator orchestrator: sync & run Ansible against 192.168.4.57
└── verify-phase2.sh                     # Automated CLI acceptance assertion script for Phase 2
```

**Structure Decision**:
An `ansible/` root directory separates declarative configuration management from Phase 1 bootstrap scripts (`scripts/install/`). The inventory explicitly binds `homelab2` to production address `192.168.4.57`. Orchestration helper scripts in `scripts/` provide seamless execution from both Windows workstations (via PowerShell SSH remoting) and standard Linux/macOS controllers.

---

## Complexity Tracking

> Zero constitutional violations; table empty by design.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| None | N/A | N/A |
