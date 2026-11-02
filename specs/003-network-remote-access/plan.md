# Implementation Plan: Network & Remote Access Overlay (Phase 3)

**Branch**: `003-network-remote-access` | **Date**: 2026-11-01 | **Spec**: [`specs/003-network-remote-access/spec.md`](file:///C:/Users/micro/projects/homelab2/specs/003-network-remote-access/spec.md)

**Input**: Feature specification from [`specs/003-network-remote-access/spec.md`](file:///C:/Users/micro/projects/homelab2/specs/003-network-remote-access/spec.md) with production target machine `admin@192.168.4.57` (SSH key authentication configured).

---

## Summary

Deploy the network and remote access overlay on the bare-metal Arch Linux host at `admin@192.168.4.57`. This layer establishes an encrypted mesh virtual private network (`tailscaled`) for secure remote access without WAN port forwarding, institutes a declarative, dual-stack host-level packet filter (`nftables`) with a default-drop policy on external interfaces, and provisions a modern reverse proxy (`caddy`) listening on HTTP/HTTPS with automatic ACME TLS issuance and WebSocket upgrade support. The plan establishes automated health telemetry, acceptance testing ([`verification-suite.md`](file:///C:/Users/micro/projects/homelab2/specs/003-network-remote-access/contracts/verification-suite.md)), and backup posture in compliance with Constitution Principles III and V.

---

## Technical Context

**Language/Version**: Python 3.10+ (Ansible Core runtime), POSIX Shell / Bash 5.2+, PowerShell 7+ (Windows orchestration)

**Primary Dependencies**:
- Mesh VPN: `tailscale` (systemd unit `tailscaled.service`)
- Packet Filter: `nftables` (systemd unit `nftables.service`, rule file `/etc/nftables.conf`)
- Ingress Reverse Proxy: `caddy` (systemd unit `caddy.service`, configuration `/etc/caddy/Caddyfile` and modular drop-in directory `/etc/caddy/conf.d/`)
- Automation & Secrets: Ansible Core, `community.sops` collection, `sops` (v3.8+), `age` (v1.1+)

**Production Target Host**:
- Network Address: `192.168.4.57` (management LAN: `192.168.4.0/24`)
- Administrative User: `admin` (passwordless sudo privileges active from Phase 2)
- Target OS: Arch Linux (kernel 7.2.11-arch1-1, x86_64)

**Storage & Paths**:
- Firewall Rules: `/etc/nftables.conf`
- Caddy Configuration: `/etc/caddy/Caddyfile` and `/etc/caddy/conf.d/*.caddy`
- Caddy Data/Certificates: `/var/lib/caddy`
- Tailscale State: `/var/lib/tailscale`

**Testing & Orchestration**:
- Production convergence runners:
  - Phase 3 dedicated playbook: `ansible/playbooks/network.yml`
  - Cross-platform orchestrators: `scripts/apply-phase3.ps1` and `scripts/apply-phase3.sh`
- Acceptance verification suite:
  - Automated test script: `scripts/verify-phase3.sh`
  - Playbook verification: `ansible/playbooks/verify-phase3.yml` and unified `ansible/playbooks/verify.yml`
  - Runnable verification scenarios in [`quickstart.md`](file:///C:/Users/micro/projects/homelab2/specs/003-network-remote-access/quickstart.md)

**Performance Goals**:
- Full Phase 3 convergence executes in under 5 minutes
- Remote mesh connection established in under 15 seconds (SC-001)
- 100% compliance with default-deny inbound firewall policy (SC-002)
- HTTP to HTTPS redirection latency under 100 milliseconds (SC-004)
- Verification test suite completes in under 60 seconds (SC-007)

**Constraints & Safeguards**:
- Administrative lockout safeguard: `nftables` syntax check `nft -c -f /etc/nftables.conf` MUST pass before service reload; loopback and established connections are accepted before any port filtering.
- Local subnet `192.168.4.0/24` SSH access preserved regardless of mesh status.
- Zero plaintext credentials: Tailscale auth key stored exclusively in SOPS encrypted vault.

**Scale/Scope**: Production bare-metal host `homelab2` (`admin@192.168.4.57`), bridging Phase 2 host hardening to Phase 4 storage and Phase 5 application stacks.

---

## Constitution Check

*GATE: Evaluated prior to Phase 0 research and re-evaluated post-design.*

| Principle / Gate | Compliance Analysis | Status |
|---|---|---|
| **I. Pragmatic Declarative-First Automation** | Uses Ansible as primary declarative IaC engine for all host network components, roles (`tailscale`, `firewall`, `reverse_proxy`), and daemons on `192.168.4.57`. | **PASS** |
| **II. Strict Idempotency & Safe Convergence** | All roles and tasks designed to produce 0 changes on re-run against production. Safe syntax verification guards prevent firewall and proxy misconfiguration. | **PASS** |
| **III. Automated Verification & Acceptance Gates** | 8 automated assertions defined in [`verification-suite.md`](file:///C:/Users/micro/projects/homelab2/specs/003-network-remote-access/contracts/verification-suite.md) and runnable via `verify-phase3.sh`. Conforms to v1.2.0 amendment: Phase 3 establishes full network connectivity, so telemetry and automated health assertions are strictly enforced. | **PASS** |
| **IV. Zero Cleartext Secrets & Isolated Configuration** | Tailscale registration key and any DNS API tokens are encrypted at rest via SOPS using age asymmetric encryption (`vault.sops.yml`). Cleartext secrets never committed. Decrypted in memory during convergence using operator's age private key. | **PASS** |
| **V. Disaster Recovery & Backup by Design** | Conforms to v1.2.0 amendment: Phase 3 backup readiness is satisfied by version-controlled declarative configurations (`nftables.conf`, `Caddyfile`, Ansible roles), encrypted vault secrets, and disposable/auto-renewing ACME certificate architecture. | **PASS** |
| **VI. Modular & Decoupled Architecture** | Decomposed into discrete Ansible roles (`tailscale`, `firewall`, `caddy`) with independent tags. Reverse proxy features modular `/etc/caddy/conf.d/*.caddy` drop-in architecture for clean decoupling from future Phase 5 services. | **PASS** |
| **VII. Stability-First & Annual Maintenance** | Employs battle-tested system components (`tailscaled`, native `nftables`, official Arch Linux `caddy`) with stable defaults. Avoids speculative abstractions. | **PASS** |

**Constitution Gate Outcome**: **PASS**. Zero principle violations; no exemptions or complexity overrides required.

---

## Project Structure

### Documentation (this feature)

```text
specs/003-network-remote-access/
├── checklists/
│   └── requirements.md       # Checklist for Phase 3 spec requirements
├── contracts/
│   ├── caddy-ingress-contract.md # Caddyfile schema, drop-in pattern, WebSocket and health endpoints
│   ├── firewall-contract.md  # nftables table/chain schema, port whitelist matrix, default drop rules
│   ├── secrets-schema.md     # SOPS vault schema, age key standards, and variables
│   └── verification-suite.md # Acceptance test matrix, assertions, and check IDs
├── data-model.md             # Logical entities, attributes, and relationships
├── plan.md                   # This implementation plan
├── quickstart.md             # Step-by-step operator convergence and verification guide
├── research.md               # Phase 0 architectural decisions, rationale, alternatives
└── spec.md                   # Feature specification
```

### Source Code (repository root)

```text
ansible/
├── inventory/
│   ├── group_vars/
│   │   └── all/
│   │       ├── vars.yml       # Network defaults (ports, subnets, caddy paths)
│   │       └── vault.sops.yml # Encrypted secrets (tailscale auth key)
│   └── hosts.yml
├── playbooks/
│   ├── network.yml            # Phase 3 convergence playbook (tailscale, firewall, caddy)
│   ├── site.yml               # Complete end-to-end homelab site playbook
│   ├── verify-phase3.yml      # Dedicated Phase 3 verification playbook
│   └── verify.yml             # Unified platform verification playbook
└── roles/
    ├── tailscale/             # Tailscale package, daemon, and auth key convergence
    ├── firewall/              # nftables template, syntax validation, and atomic reload
    └── caddy/                 # Caddy package, Caddyfile, drop-in directory, health endpoint

scripts/
├── apply-phase3.ps1           # Windows PowerShell orchestrator for Phase 3
├── apply-phase3.sh            # POSIX Bash orchestrator for Phase 3
└── verify-phase3.sh           # Automated acceptance test runner (NET-01 through NET-08)
```

**Structure Decision**: Infrastructure-as-Code automation repository following Ansible standard multi-role structure with accompanying PowerShell and Bash orchestrator scripts.

---

## Complexity Tracking

> Zero Constitution principle violations detected. No complexity overrides required.
