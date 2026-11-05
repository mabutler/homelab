# Implementation Plan: Automated Platform Monitoring & Alerting (`ntfy` & `Healthchecks`)

**Branch**: `011-monitoring-ntfy-healthchecks` | **Date**: 2026-11-05 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/011-monitoring-ntfy-healthchecks/spec.md`

---

## Summary

Deploy zero-toil, cloud-backed platform monitoring and alerting for `fidelacchius` integrating hosted `ntfy.sh` (real-time push notifications) and `healthchecks.io` (dead-man's-switch heartbeat monitoring) without hosting local monitoring containers on the server (so power or WAN outages are still detected externally). Using a minimal set of operator credentials in `vault.yml` (`vault_ntfy_topic` and `vault_healthchecks_api_key`), an isolated Ansible role (`ansible/roles/monitoring`) renders `/etc/homelab/monitoring.env` (`0600`), automatically reconciles all 6 canonical `healthchecks.io` checks via API v3 (`"unique": ["name", "slug"]`, `"channels": "*"`), installs global catch-all systemd failure hooks (`/etc/systemd/system/service.d/99-homelab-failure-alert.conf` and `/etc/systemd/user/service.d/99-homelab-failure-alert.conf` with recursion guards), instruments all 5 scheduled maintenance jobs via modular systemd drop-ins (`10-healthchecks.conf`) and a reusable CLI wrapper (`/usr/local/bin/homelab-hc-run`), wires `smartd` physical disk alerts (`/usr/local/bin/homelab-smartd-alert`), and runs a 5-minute composite health sweep (`homelab-heartbeat.timer`) covering all system/user daemons, dynamic Docker container discovery (current and future), HTTP readiness endpoints, and storage tier capacity thresholds with per-component alert deduplication and recovery notifications.

---

## Technical Context

**Language/Version**:
- Automation & Tooling: Ansible 2.16+, POSIX Shell / Bash 5.2+, PowerShell 7+
- Host Utilities: `systemd 262`, `curl`, `jq`, `flock` (`util-linux`), `smartmontools` (`smartd`), `docker` CLI

**Primary Dependencies**:
- External Cloud SaaS Endpoints: `https://ntfy.sh` (push notifications) & `https://healthchecks.io/api/v3` / `https://hc-ping.com` (heartbeat management & ping API)
- Process & Timer Supervision: `systemd` system and user managers (`service.d/` global drop-ins, `homelab-alert@.service`, `homelab-heartbeat.timer`)
- Existing Platform Roles: `disk_health` (`smartd`), `backup` (Restic B2 backup manifest), `snapraid`, `vaultwarden`, `frigate`, `caddy`, `tailscale`, `antigravity`

**Storage**:
- Configuration & Isolated Secrets: `/etc/homelab/monitoring.env` (`0600 root:root`), `/etc/homelab/monitoring.env.example` (`0644`), `/etc/homelab/monitoring/checks-catalog.json` (`0644`)
- Local State & Cache: `/var/lib/homelab/monitoring/checks.json` (`0600 root:root`, cached `slug -> ping_url` map) and `/var/lib/homelab/monitoring/state/*.json` (per-component alert deduplication and cooldown state files)

**Testing**:
- Static Analysis & Linting: `ansible-lint`, `shellcheck`, `jq` JSON validation, `bash -n` syntax checks
- Automated Acceptance Suite: `scripts/verify-phase8-monitoring.sh` (`MON-01` through `MON-10`), `scripts/verify-phase8-monitoring.ps1`, and `ansible/playbooks/verify-phase8-monitoring.yml` (imported into `ansible/playbooks/verify.yml`)

**Target Platform**:
- Arch Linux x86_64 bare-metal server (`fidelacchius`, `systemd 262`)

**Project Type**:
- Infrastructure-as-Code (Ansible roles, playbooks, modular shell helpers, systemd global/service drop-ins, and automated verification scripts)

**Performance Goals**:
- Service failure, SMART disk alert, or health sweep failure notification delivered to `ntfy.sh` within `< 30` seconds of detection (SC-003)
- 5-minute composite health sweep (`/usr/local/bin/homelab-health-sweep`) executes in `< 3` seconds with zero background daemon memory overhead between runs
- Alert deduplication suppresses 100% of duplicate crash-loop notifications within the 15-minute (`900`s) cooldown window while delivering 1 initial failure alert and 1 recovery alert upon resolution (SC-004)

**Constraints**:
- Zero self-hosted monitoring containers (`ntfy` or `healthchecks`) deployed on `fidelacchius` (FR-001)
- Zero manual UI configuration required in `healthchecks.io` or `ntfy.sh` when deploying or adding new systemd services, Docker containers, or scheduled jobs (FR-002, SC-001, SC-002)
- Silent-when-healthy policy: zero `ntfy.sh` push notifications sent during normal healthy operation; notifications fire strictly on failures, threshold warnings, missed heartbeats, and recoveries (FR-005)
- Zero plaintext or encrypted secrets in Git; all real credentials reside in gitignored `vault.yml` and `/etc/homelab/monitoring.env` (`0600`) and are backed up via Restic to Backblaze B2 (FR-003, FR-014, Principle IV & V)

**Scale/Scope**:
- Covers 100% of existing continuous services (`sshd`, `chronyd`, `smartd`, `systemd-oomd`, `nftables`, `tailscaled`, `caddy`, `docker`, `vaultwarden`, `frigate`, `agy-remote-control`), all 5 scheduled maintenance timers (`homelab-backup`, `homelab-backup-check`, `vaultwarden-backup`, `snapraid-sync`, `snapraid-scrub`), all 7 storage mount paths (`/` + Tier 0/1/2 disks), all physical SMART drives, and any future systemd service or Docker container added to `fidelacchius`.

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked and confirmed post-Phase 1 design.*

| Principle / Gate | Compliance Analysis | Status |
|---|---|---|
| **I. Pragmatic Declarative-First Automation** | All monitoring configuration, systemd global drop-ins, scheduled job bindings, `smartd` integration, and backup manifest updates are managed declaratively via Ansible (`ansible/roles/monitoring`, `disk_health`, `backup`). Runtime API reconciliation, notification deduplication, and health sweeps are implemented as modular, contract-backed scripts under `/usr/local/bin/homelab-*`. | **PASS** |
| **II. Strict Idempotency & Safe Convergence** | `homelab-hc-reconcile` uses `healthchecks.io` API v3 `"unique": ["name", "slug"]` upsert semantics, guaranteeing zero duplicate checks across repeated playbook runs. All Ansible tasks are strictly idempotent (`changed=0` on second run). | **PASS** |
| **III. Automated Verification & Acceptance Gates** | 10 automated verification checks (`MON-01` through `MON-10` in [verification-contract.md](./contracts/verification-contract.md)) verify secret isolation, global systemd failure hooks, recursion guards, `healthchecks.io` check registration, scheduled job drop-ins, `smartd` hooks, alert deduplication/recovery state machine, live `ntfy.sh` & `healthchecks.io` connectivity, Restic backup coverage, and clean logs. | **PASS** |
| **IV. Zero Secrets in Version Control & Isolated Configuration** | `vault_ntfy_topic`, `vault_ntfy_token`, `vault_healthchecks_api_key`, and `vault_healthchecks_ping_key` reside exclusively in gitignored `ansible/inventory/group_vars/all/vault.yml` and `/etc/homelab/monitoring.env` (`0600`). Only sanitized placeholders are committed in `vault.yml.example` and `monitoring.env.example`. | **PASS** |
| **V. Disaster Recovery & Backup by Design** | `/etc/homelab/monitoring.env`, `/etc/homelab/monitoring/checks-catalog.json`, and `/var/lib/homelab/monitoring/checks.json` are included in the nightly Restic backup to Backblaze B2 (`backup_include_paths`). Even on a clean restore without `checks.json`, running `monitoring.yml` automatically re-reconciles all checks via API v3. | **PASS** |
| **VI. Modular & Decoupled Architecture** | Scheduled jobs (`homelab-backup`, `homelab-backup-check`, `vaultwarden-backup`, `snapraid-sync`, `snapraid-scrub`) and global unit failure hooks are attached via systemd drop-in directories (`*.service.d/10-healthchecks.conf` and `service.d/99-homelab-failure-alert.conf`), leaving existing application and backup roles decoupled. | **PASS** |
| **VII. Stability-First & Annual Maintenance Cadence** | Uses native `systemd` timers/drop-ins, `curl`, and `jq` with zero extra background daemons or third-party agent binaries, and enforces a silent-when-healthy alerting policy with 15-minute cooldown deduplication. | **PASS** |

**Gate Evaluation**: **PASS** (Pre-Phase 0 and Post-Phase 1). Zero constitutional violations.

---

## Project Structure

### Documentation (this feature)

```text
specs/011-monitoring-ntfy-healthchecks/
├── spec.md                                              # Feature specification
├── plan.md                                              # This implementation plan
├── research.md                                          # Phase 0 architectural decisions & research findings
├── data-model.md                                        # Phase 1 entity schemas, check catalog & state machine
├── quickstart.md                                        # Phase 1 bootstrap, deployment & validation guide
├── contracts/                                           # Phase 1 explicit interface & verification contracts
│   ├── ntfy-dispatcher-contract.md                      # homelab-ntfy CLI, deduplication & systemd failure hook contract
│   ├── healthchecks-reconcile-and-wrapper-contract.md   # API v3 reconciler, ping helper & job drop-in contract
│   ├── health-sweep-and-storage-contract.md             # Composite health sweep, container discovery & smartd contract
│   └── verification-contract.md                         # Automated acceptance assertions MON-01 through MON-10
├── checklists/
│   └── requirements.md                                  # Specification quality checklist
└── tasks.md                                             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
ansible/
├── inventory/
│   └── group_vars/
│       └── all/
│           ├── vars.yml                                 # Non-sensitive monitoring defaults (thresholds, cooldown, schedules)
│           └── vault.yml.example                        # Sanitized ntfy.sh & healthchecks.io secret placeholders
├── playbooks/
│   ├── site.yml                                         # Master convergence playbook (includes monitoring role)
│   ├── monitoring.yml                                   # Dedicated Phase 8 monitoring deployment playbook
│   ├── verify-phase8-monitoring.yml                     # Dedicated Phase 8 monitoring acceptance verification playbook
│   └── verify.yml                                       # Master platform verification playbook (imports verify-phase8-monitoring.yml)
└── roles/
    ├── monitoring/
    │   ├── defaults/
    │   │   └── main.yml                                 # Default URLs, thresholds, cooldown, check catalog, monitored units/mounts
    │   ├── files/
    │   │   ├── monitoring.env.example                   # Committed sanitized template for /etc/homelab/monitoring.env.example
    │   │   ├── homelab-ntfy                             # Outbound ntfy.sh dispatcher with flock deduplication & recovery state
    │   │   ├── homelab-unit-alert                       # Systemd system/user unit failure diagnostic collector & alert sender
    │   │   ├── homelab-hc-reconcile                     # Zero-touch healthchecks.io API v3 check reconciler
    │   │   ├── homelab-hc-ping                          # Slug-based healthchecks.io ping & ExecStopPost handler
    │   │   ├── homelab-hc-run                           # Reusable command wrapper for scheduled/ad-hoc jobs
    │   │   └── homelab-smartd-alert                     # smartd -M exec handler forwarding disk warnings to homelab-ntfy
    │   ├── handlers/
    │   │   └── main.yml                                 # Systemd system & user daemon-reload and timer restart handlers
    │   ├── tasks/
    │   │   ├── main.yml                                 # Role task orchestrator
    │   │   ├── preflight.yml                            # Validate required monitoring variables and tools (curl, jq, flock)
    │   │   ├── config.yml                               # Create /etc/homelab/monitoring*, /var/lib/homelab/monitoring/*, monitoring.env
    │   │   ├── scripts.yml                              # Install /usr/local/bin/homelab-* scripts & homelab-health-sweep
    │   │   ├── systemd_hooks.yml                        # Deploy global service.d failure hooks, recursion guards & job drop-ins
    │   │   ├── reconcile.yml                            # Run homelab-hc-reconcile to provision/update all checks in healthchecks.io
    │   │   └── heartbeat.yml                            # Enable & start homelab-heartbeat.timer and run initial health sweep
    │   └── templates/
    │       ├── monitoring.env.j2                        # Runtime secret environment file (/etc/homelab/monitoring.env, 0600)
    │       ├── checks-catalog.json.j2                   # Declarative JSON catalog of canonical healthchecks.io checks
    │       ├── homelab-health-sweep.j2                  # 5-minute composite health sweep script (/usr/local/bin/homelab-health-sweep)
    │       ├── homelab-alert-system.service.j2          # /etc/systemd/system/homelab-alert@.service
    │       ├── homelab-alert-user.service.j2            # /etc/systemd/user/homelab-alert@.service
    │       ├── 99-homelab-failure-alert.conf.j2         # Global service.d OnFailure drop-in for system & user managers
    │       ├── 99-zz-no-recursion.conf.j2               # Recursion guard clearing OnFailure for homelab-alert@.service
    │       ├── 10-healthchecks.conf.j2                  # Scheduled maintenance job ExecStartPre/ExecStopPost drop-in
    │       ├── homelab-heartbeat.service.j2             # Composite health sweep oneshot service
    │       └── homelab-heartbeat.timer.j2               # 5-minute composite health sweep timer
    ├── disk_health/
    │   ├── defaults/
    │   │   └── main.yml                                 # Default smartd_scan_options with -m <nomailer> -M exec /usr/local/bin/homelab-smartd-alert
    │   └── templates/
    │       └── smartd.conf.j2                           # Updated smartd configuration invoking homelab-smartd-alert
    └── backup/
        └── defaults/
            └── main.yml                                 # Include /etc/homelab/monitoring.env, /etc/homelab/monitoring, and /var/lib/homelab/monitoring/checks.json

scripts/
├── apply-phase8-monitoring.sh                           # Bash convergence wrapper for monitoring deployment
├── apply-phase8-monitoring.ps1                          # PowerShell convergence wrapper for monitoring deployment
├── verify-phase8-monitoring.sh                          # Target host acceptance test suite (MON-01 to MON-10)
└── verify-phase8-monitoring.ps1                         # Workstation acceptance test wrapper
```

**Structure Decision**:
- Follows the established `homelab2` role and phase convention (`ansible/roles/monitoring`, `ansible/playbooks/monitoring.yml`, `ansible/playbooks/verify-phase8-monitoring.yml`, and `scripts/*-phase8-monitoring.*` corresponding to Phase 8 in `docs/roadmap.md`).
- Keeps all monitoring executables in `/usr/local/bin/homelab-*`, runtime secrets in `/etc/homelab/monitoring.env` (`0600`), declarative catalog in `/etc/homelab/monitoring/checks-catalog.json`, and state/cache in `/var/lib/homelab/monitoring/`.

---

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| *(None)* | All 7 Constitutional Principles pass unconditionally. | N/A |
