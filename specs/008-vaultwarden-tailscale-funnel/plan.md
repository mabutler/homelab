# Implementation Plan: Vaultwarden Public Access via Tailscale Funnel

**Branch**: `008-vaultwarden-tailscale-funnel` | **Date**: 2026-11-03 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/008-vaultwarden-tailscale-funnel/spec.md`

## Summary

Expose the Vaultwarden password manager directly to the public internet using Tailscale Funnel on standard HTTPS (port 443), terminating TLS with automated Let's Encrypt certificates managed by Tailscale. Dynamically discover the Tailscale node FQDN (`<node-name>.<tailnet>.ts.net`) at deployment time via `tailscale status --json` to configure Vaultwarden's canonical `DOMAIN` setting without committing secrets or domain metadata to git. Decommission Caddy's Vaultwarden ingress drop-in and resolve wildcard port 443 contention, allowing Funnel to proxy traffic directly to `127.0.0.1:8088`. Validate real-time WebSocket synchronization, signup restrictions, and automated reboot persistence.

## Technical Context

**Language/Version**: Ansible 2.16+, Jinja2, POSIX Shell / Bash  
**Primary Dependencies**: Tailscale (1.50+ with Funnel; 1.102.2 detected), Vaultwarden (`vaultwarden/server:1.32.7-alpine`), Docker CE & Compose v2, systemd, Caddy 2.x  
**Storage**: SQLite 3 with Write-Ahead Logging (WAL) on persistent host storage (`/opt/services/vaultwarden/data/db.sqlite3` / `/mnt/storage/appdata/vaultwarden`)  
**Testing**: `ansible-lint`, check-mode verification, automated health assertions (`verify-phase5.yml`, `verify.yml`), HTTPS/WebSocket handshake validation via `curl`  
**Target Platform**: Arch Linux x86_64 host (`homelab2`) running systemd  
**Project Type**: Infrastructure-as-Code (Ansible playbooks, roles, system configuration)  
**Performance Goals**: Public ingress response < 500ms p95; WebSocket notification propagation < 5s; zero background daemon CPU overhead  
**Constraints**:
- Strict adherence to Constitution Principle IV: Zero real domains, node hostnames, or secrets in git; dynamic runtime discovery via `tailscale status --json` with generic placeholders (`<node-name>.<tailnet>.ts.net`) in committed files.
- Strict adherence to Principle I & II: Declarative-first, idempotent automation with clean convergence.
- Strict adherence to Principle III: Automated verification of Funnel status, public HTTPS endpoint, and WebSocket upgrades.
- Strict adherence to Principle V: Existing Restic / Backblaze B2 backup and restore capabilities remain operational.
**Scale/Scope**: Exposing a single password manager instance to household members across corporate/school devices and personal clients without requiring VPN installation.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Requirement | Design Status | Gate Evaluation |
|---|---|---|---|
| **I. Pragmatic Declarative-First** | IaC via Ansible playbooks and roles; modular shell scripts where necessary | All tasks declared in `ansible/roles/vaultwarden`, `ansible/roles/caddy`, and `verify-phase5.yml` | **PASS** |
| **II. Strict Idempotency & Safe Convergence** | Playbooks re-runnable without state drift or disruption | Funnel status checked before running `tailscale funnel --bg`; Caddy route removal is idempotent | **PASS** |
| **III. Automated Verification & Acceptance Gates** | Every deployment has automated assertions; fail fast with actionable error messages | `verify-phase5.yml` and `verify.yml` updated with VW-06 (Funnel HTTPS probe) and VW-07 (WebSocket handshake) | **PASS** |
| **IV. Zero Secrets & Isolated Configuration** | No secrets or real hostnames committed; example templates only; dynamic discovery | FQDN dynamically resolved at runtime from `tailscale status --json`; committed files use generic placeholders | **PASS** |
| **V. Disaster Recovery & Backup by Design** | Stateful datasets protected by automated backups and restore verification | Existing SQLite WAL backup hook and systemd timer maintained and verified | **PASS** |
| **VI. Modular & Decoupled Architecture** | Services loosely coupled; standard protocols | Ingress decoupling: Tailscale Funnel terminates TLS and proxies to `127.0.0.1:8088`; Caddy bypassed | **PASS** |
| **VII. Stability-First & Annual Maintenance** | Stable/pinned versions; zero routine toil | Pinned container image `vaultwarden/server:1.32.7-alpine`; native Tailscale daemon state persistence | **PASS** |

## Project Structure

### Documentation (this feature)

```text
specs/008-vaultwarden-tailscale-funnel/
├── spec.md              # Feature specification
├── plan.md              # This implementation plan
├── research.md          # Phase 0 technical decisions and research findings
├── data-model.md        # Phase 1 entities, schemas, and state transitions
├── quickstart.md        # Phase 1 validation scenarios and run guide
├── contracts/           # Phase 1 interface contracts
│   ├── tailscale-funnel-cli.md
│   ├── vaultwarden-ingress-endpoints.md
│   └── ansible-role-vars.md
├── checklists/
│   └── requirements.md  # Quality checklist
└── tasks.md             # Phase 2 output (/speckit-tasks command)
```

### Source Code (repository root)

```text
ansible/
├── playbooks/
│   ├── site.yml                          # Main orchestration playbook
│   ├── vaultwarden.yml                   # Vaultwarden application playbook
│   ├── verify-phase5.yml                 # Phase 5 Vaultwarden verification playbook
│   └── verify.yml                        # Comprehensive verification playbook
├── roles/
│   ├── caddy/
│   │   ├── tasks/
│   │   │   └── main.yml                  # Ensure 20-vaultwarden.caddy is absent
│   │   └── templates/
│   │       ├── 00-health.caddy.j2        # Adjust wildcard :443 binding to avoid port conflict
│   │       └── 20-vaultwarden.caddy.j2   # (Decommissioned / removed)
│   └── vaultwarden/
│       ├── defaults/
│       │   └── main.yml                  # Defaults (vaultwarden_domain: "", funnel settings)
│       ├── tasks/
│       │   ├── main.yml                  # Include layout, config, service, funnel, backup
│       │   ├── config.yml                # Dynamic FQDN resolution + env template deployment
│       │   ├── funnel.yml                # Declarative Tailscale Funnel orchestration
│       │   └── service.yml               # Docker Compose and systemd management
│       └── templates/
│           └── env.j2                    # Deployed .env with dynamic DOMAIN and SIGNUPS_ALLOWED=false
```

**Structure Decision**: Infrastructure automation changes are placed inside existing Ansible roles (`ansible/roles/vaultwarden`, `ansible/roles/caddy`) and playbooks (`vaultwarden.yml`, `verify-phase5.yml`, `verify.yml`). No new monolithic repositories or external dependencies are introduced.

## Complexity Tracking

*No constitutional violations identified. Design simplifies topology by eliminating intermediate Caddy proxying for Vaultwarden.*

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| None | N/A | N/A |

---

## Phases & Execution Workflow

### Phase 0: Research & Resolution
- [x] Resolve dynamic FQDN discovery via `tailscale status --json`
- [x] Clarify Tailscale Funnel CLI persistence mechanism (`--bg`) and idempotency
- [x] Document resolution of port 443 contention with Caddy
- [x] Verify WebSocket handshake requirements for `/notifications/hub`
- [x] Confirm strict signup controls (`SIGNUPS_ALLOWED=false`) and non-root execution

### Phase 1: Design & Contracts
- [x] Data Model: `data-model.md` specifying entities, configuration schemas, and state transitions
- [x] Interface Contracts:
  - `contracts/tailscale-funnel-cli.md`: Schema for Funnel invocation and status JSON
  - `contracts/vaultwarden-ingress-endpoints.md`: Public HTTPS, WebSocket, and health check endpoints
  - `contracts/ansible-role-vars.md`: Role variables for Vaultwarden and Caddy
- [x] Validation Guide: `quickstart.md` defining step-by-step verification scenarios
- [x] Constitutional post-design audit completed

### Phase 2: Implementation Tasks (Next Step via `/speckit-tasks`)
- Tasks will be generated into `tasks.md` in dependency order:
  1. Caddy role update: Remove `20-vaultwarden.caddy` and prevent wildcard `:443` port contention.
  2. Vaultwarden role update: Add dynamic FQDN resolution and declarative Tailscale Funnel management (`tasks/funnel.yml`).
  3. Playbooks update: Adjust `vaultwarden.yml`, `verify-phase5.yml`, and `verify.yml` to assert Funnel ingress, TLS validity, and WebSocket communication.
  4. Execution and live verification on target node.
