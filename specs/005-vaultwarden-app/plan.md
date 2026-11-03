# Implementation Plan: Vaultwarden Application Deployment & Resiliency

**Branch**: `005-vaultwarden-app` | **Date**: 2026-11-01 | **Spec**: [spec.md](file:///C:/Users/micro/projects/homelab2/specs/005-vaultwarden-app/spec.md)

**Input**: Feature specification from `/specs/005-vaultwarden-app/spec.md`

---

## Summary

Phase 5 inaugurates the application platform layer of `homelab2` by deploying Vaultwarden as the primary, self-hosted password and credential management service directly to the production host `admin@192.168.4.57`. The technical approach utilizes Docker CE with Docker Compose managed via a native systemd unit (`vaultwarden.service`), stores persistent application state and SQLite in WAL mode on the Tier 0 Fast NVMe App tier (`/opt/services/vaultwarden`), routes HTTPS and WebSockets through a modular Caddy reverse proxy drop-in, executes automated transactional backups (`VACUUM INTO` + `PRAGMA integrity_check;`) with 30-day retention pruning, and guarantees zero cleartext secrets in version control via SOPS/age encryption.

---

## Technical Context

**Language/Version**:
- Container: Rust (upstream `vaultwarden/server:1.32.7-alpine`)
- Automation & Tooling: Ansible 2.16+, Bash 5.2+, PowerShell 7+, SQLite 3.45+

**Primary Dependencies**:
- Container Engine: Docker CE & Docker Compose plugin (`docker-compose-plugin`)
- Reverse Proxy: Caddy 2.8+ (managing internal TLS and WebSocket reverse proxying)
- Secret Management: SOPS with age encryption (`vault.sops.yml`)
- Init & Process Supervision: systemd (service units and timer units)

**Storage**:
- NVMe App State: `/opt/services/vaultwarden/data` (persistent database `db.sqlite3`, RSA keys, encrypted attachments)
- Local Backup Staging: `/opt/services/vaultwarden/backups` (point-in-time gzip archives with 30-day retention)
- Database Engine: SQLite 3 with Write-Ahead Logging (`ENABLE_DB_WAL=true`) and synchronous mode

**Testing**:
- Local Acceptance Runner: `scripts/verify-phase5-vaultwarden.sh` (9 automated checks in [`verification-contract.md`](file:///C:/Users/micro/projects/homelab2/specs/005-vaultwarden-app/contracts/verification-contract.md))
- Workstation Orchestration: `scripts/verify-phase5-vaultwarden.ps1`
- Ansible Verification Playbook: `ansible/playbooks/verify-phase5.yml` integrated into unified `verify.yml`

**Target Platform & Deployment Target**:
- Target Host: `admin@192.168.4.57` (`homelab2`), Arch Linux bare-metal on x86_64 architecture
- Deployment Mechanism: Ansible playbook push targeting `admin@192.168.4.57` via `ansible/inventory/hosts.yml` and workstation orchestrator `scripts/apply-phase5.ps1 -HostAddress 192.168.4.57 -User admin` (with `scripts/apply-phase5.sh` for local/SSH execution)
- Verification Mechanism: Remote acceptance verification suite executed against `admin@192.168.4.57` via `scripts/verify-phase5-vaultwarden.ps1 -TargetHost 192.168.4.57 -User admin` (or local `scripts/verify-phase5-vaultwarden.sh`)

**Project Type**:
- Containerized Web Application & Secret Management Service

**Performance Goals**:
- Service health endpoint (`/alive`) responds with HTTP 200 within 500ms (SC-001)
- WebSocket push sync across connected Bitwarden clients propagates within 2 seconds (SC-002)
- Online transactional backup executes in under 30 seconds with 0 downtime (SC-004)
- Automated verification suite runs all 9 assertions in under 15 seconds (SC-006)
- Full disaster recovery restore from raw archive completes in under 5 minutes (SC-005)

**Constraints**:
- Zero cleartext credentials in git: Argon2id-hashed `ADMIN_TOKEN` encrypted at rest using SOPS with age
- Non-root process execution: Container runs with non-root UID/GID (1000:1000)
- Loopback-only binding: Backend container port maps exclusively to `127.0.0.1:8088`
- Durability: SQLite WAL mode enabled to ensure crash consistency
- Registration: Open registration disabled (`SIGNUPS_ALLOWED=false`), admin invitations enabled

**Scale/Scope**:
- Household and homelab credential storage (1–10 active users, multi-device browser, mobile, and CLI clients)

---

## Constitution Check

*GATE: Evaluated prior to Phase 0 research and re-evaluated post-design.*

| Principle / Gate | Compliance Analysis | Status |
|---|---|---|
| **I. Pragmatic Declarative-First Automation** | Container installation, directory permissions, Compose definition, Caddy ingress, systemd unit, and backup timer are declared via Ansible roles (`docker`, `vaultwarden`, `caddy`). Transactional SQLite snapshotting and disaster recovery restoration use modular, self-contained shell scripts (`backup.sh`, `restore.sh`) with documented contracts. | **PASS** |
| **II. Strict Idempotency & Safe Convergence** | All Ansible tasks use idempotent modules (`template`, `systemd`, `file`, `package`). Rerunning playbooks does not restart healthy containers unless configuration files change. Destructive restore operations require explicit opt-in confirmation guards (`--force`). | **PASS** |
| **III. Automated Verification & Acceptance Gates** | 9 automated assertions defined in [`verification-contract.md`](file:///C:/Users/micro/projects/homelab2/specs/005-vaultwarden-app/contracts/verification-contract.md). Both host health assertions (`/alive`, container status, WebSocket handshake) and structured systemd journal logging are verified before declaring the phase complete. | **PASS** |
| **IV. Zero Cleartext Secrets & Isolated Configuration** | The administrative portal secret (`ADMIN_TOKEN`) is encrypted with SOPS and age inside `ansible/inventory/group_vars/all/vault.sops.yml`. The rendered `.env` file is generated with `0600` permissions. No plaintext secrets exist in git. | **PASS** |
| **V. Disaster Recovery & Backup by Design** | Adheres directly to the Phase 5 mandatory per-application backup gate: an automated daily transactional backup (`VACUUM INTO`) runs without stopping the container, verifies SQLite data integrity via `PRAGMA integrity_check;`, bundles attachments, prunes expired backups (> 30 days), and documents a tested < 5 minute recovery procedure. | **PASS** |
| **VI. Modular & Decoupled Architecture** | Vaultwarden runs in its own isolated Compose stack under `/opt/services/vaultwarden`, bound to loopback `127.0.0.1:8088`. Ingress is loosely coupled via Caddy drop-in (`/etc/caddy/conf.d/20-vaultwarden.caddy`). Vaultwarden can be stopped or restarted without impacting other services. | **PASS** |
| **VII. Stability-First & Annual Maintenance** | Image is pinned to a battle-tested stable release (`vaultwarden/server:1.32.7-alpine`). SQLite requires zero external daemon maintenance. Daily operations require zero manual toil. | **PASS** |

**Constitution Gate Outcome**: **PASS**. 100% compliant with Constitution v1.2.0; zero principle violations; no exemptions required.

---

## Project Structure

### Documentation (this feature)

```text
specs/005-vaultwarden-app/
├── checklists/
│   └── requirements.md                # Feature requirement verification checklist
├── contracts/
│   ├── backup-restore-contract.md     # Transactional backup & disaster recovery CLI specification
│   ├── caddy-ingress-contract.md      # Ingress drop-in, TLS parameters, and WebSocket upgrade spec
│   ├── vaultwarden-service-contract.md# Compose manifest, systemd service unit, and volume contract
│   └── verification-contract.md       # 9 acceptance test assertions and JSON test schema
├── data-model.md                      # Service, environment, database, backup, and ingress entities
├── plan.md                            # This implementation plan
├── quickstart.md                      # Step-by-step validation guide and operational runbook
├── research.md                        # Phase 0 architectural decisions, rationale, alternatives
└── spec.md                            # Feature specification
```

### Source Code (repository root)

```text
ansible/
├── inventory/
│   └── group_vars/
│       └── all/
│           ├── vars.yml               # Non-sensitive Vaultwarden configuration defaults
│           └── vault.sops.yml         # Encrypted admin token (Argon2id hashed)
├── playbooks/
│   ├── site.yml                       # Master convergence playbook (includes docker & vaultwarden)
│   ├── vaultwarden.yml                # Dedicated Phase 5 Vaultwarden playbook
│   ├── verify-phase5.yml              # Phase 5 acceptance verification playbook
│   └── verify.yml                     # Master acceptance verification playbook
└── roles/
    ├── caddy/
    │   └── templates/
    │       └── 20-vaultwarden.caddy.j2# Caddy reverse proxy drop-in template
    ├── docker/
    │   ├── defaults/main.yml          # Docker package and daemon defaults
    │   ├── handlers/main.yml          # Docker service restart handlers
    │   └── tasks/main.yml             # Docker CE & docker-compose installation & service enabling
    └── vaultwarden/
        ├── defaults/main.yml          # Vaultwarden image tag, ports, paths, retention defaults
        ├── handlers/main.yml          # Container restart and systemd reload handlers
        ├── tasks/
        │   ├── main.yml               # Task orchestrator for vaultwarden
        │   ├── layout.yml             # Directory creation under /opt/services/vaultwarden
        │   ├── config.yml             # Render .env and compose.yml
        │   ├── service.yml            # Systemd service unit definition and start
        │   └── backup.yml             # Backup script, restore script, and systemd backup timer
        └── templates/
            ├── backup.sh.j2           # Transactional backup and pruning runner
            ├── compose.yml.j2         # Declarative compose specification
            ├── env.j2                 # Environment configuration template
            ├── restore.sh.j2          # Disaster recovery restore runner
            ├── vaultwarden-backup.service.j2 # Systemd backup service
            ├── vaultwarden-backup.timer.j2   # Systemd backup timer
            └── vaultwarden.service.j2 # Systemd container lifecycle service

scripts/
├── apply-phase5.ps1                   # Phase 5 PowerShell convergence orchestrator
├── apply-phase5.sh                    # Phase 5 Bash convergence orchestrator
├── verify-phase5-vaultwarden.ps1      # Workstation acceptance test runner
└── verify-phase5-vaultwarden.sh       # Target host acceptance test suite (VW-01 to VW-09)
```

**Structure Decision**:
- Reusable `docker` role installed so subsequent Phase 5 applications (Home Assistant, Immich, Frigate) reuse the shared container engine.
- Dedicated `vaultwarden` role encapsulating application layout, configuration, secrets, Compose manifest, systemd service, backup automation, and restore tooling.
- Caddy reverse proxy integration updated via `templates/20-vaultwarden.caddy.j2` deployed into `/etc/caddy/conf.d/`.
- Cross-platform convergence orchestrators (`apply-phase5.ps1`/`.sh`) and acceptance verification runners (`verify-phase5-vaultwarden.ps1`/`.sh`) following the established repository standards.

---

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| *(None)* | All constitutional gates pass unconditionally. | N/A |
