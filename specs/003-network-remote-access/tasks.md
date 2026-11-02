# Tasks: Network & Remote Access Overlay (Phase 3 Rollout)

**Input**: Design documents from [`specs/003-network-remote-access/`](file:///C:/Users/micro/projects/homelab2/specs/003-network-remote-access/)
- **Plan**: [`plan.md`](file:///C:/Users/micro/projects/homelab2/specs/003-network-remote-access/plan.md)
- **Specification**: [`spec.md`](file:///C:/Users/micro/projects/homelab2/specs/003-network-remote-access/spec.md)
- **Data Model**: [`data-model.md`](file:///C:/Users/micro/projects/homelab2/specs/003-network-remote-access/data-model.md)
- **Contracts**: [`contracts/`](file:///C:/Users/micro/projects/homelab2/specs/003-network-remote-access/contracts/)
  - [`caddy-ingress-contract.md`](file:///C:/Users/micro/projects/homelab2/specs/003-network-remote-access/contracts/caddy-ingress-contract.md)
  - [`firewall-contract.md`](file:///C:/Users/micro/projects/homelab2/specs/003-network-remote-access/contracts/firewall-contract.md)
  - [`secrets-schema.md`](file:///C:/Users/micro/projects/homelab2/specs/003-network-remote-access/contracts/secrets-schema.md)
  - [`verification-suite.md`](file:///C:/Users/micro/projects/homelab2/specs/003-network-remote-access/contracts/verification-suite.md)
- **Research**: [`research.md`](file:///C:/Users/micro/projects/homelab2/specs/003-network-remote-access/research.md)
- **Quickstart**: [`quickstart.md`](file:///C:/Users/micro/projects/homelab2/specs/003-network-remote-access/quickstart.md)
- **Constitution**: [`.specify/memory/constitution.md`](file:///C:/Users/micro/projects/homelab2/.specify/memory/constitution.md)

**Rollout Target**: `admin@192.168.4.57` (homelab2 bare-metal Arch Linux host)

---

## Format: `- [ ] [ID] [P?] [Story?] Description with file path`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to ([US1], [US2], [US3], [US4])
- Exact file paths included in all descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization, directory tree scaffolding for network roles, and base configuration templates.

- [X] T001 Initialize Ansible role directory trees (`tasks/`, `handlers/`, `templates/`, `defaults/`) for `tailscale`, `firewall`, and `caddy` in `ansible/roles/`
- [X] T002 [P] Create Caddy configuration drop-in layout directory structure for `/etc/caddy/conf.d` in `ansible/roles/caddy/templates/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Global network variables, encrypted SOPS secrets schema, and orchestration runner scripts that MUST be complete before ANY user story role can execute.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T003 Declare network variables (`tailscale_enabled: true`, `tailscale_accept_routes: true`, `tailscale_advertise_exit_node: false`, `firewall_enabled: true`, `firewall_allowed_subnets: ['192.168.4.0/24']`, `firewall_allowed_tcp_ports: [22, 80, 443]`, `firewall_allowed_udp_ports: [41641]`, `caddy_enabled: true`, `caddy_conf_dir: '/etc/caddy/conf.d'`) in `ansible/inventory/group_vars/all/vars.yml`
- [X] T004 [P] Declare encrypted secrets schema template with placeholders (`vault_tailscale_auth_key: 'tskey-auth-placeholder'`, `vault_cloudflare_api_token: 'placeholder'`) in `ansible/inventory/group_vars/all/vault.sops.yml`
- [X] T005 [P] Implement cross-platform PowerShell runner `scripts/apply-phase3.ps1` for Windows workstation orchestration to push and execute playbooks against `admin@192.168.4.57`
- [X] T006 [P] Implement cross-platform POSIX runner `scripts/apply-phase3.sh` for Linux/macOS orchestration to push and execute playbooks against `admin@192.168.4.57`
- [X] T007 Validate SSH connectivity and prerequisite tools (`ansible-core`, `sops`, `age`, `python-yaml`) on target host `admin@192.168.4.57` using `scripts/apply-phase3.ps1`

**Checkpoint**: Foundation ready - inventory variables, encrypted secrets schema, and orchestrator scripts established; target host connectivity verified; user stories can begin.

---

## Phase 3: User Story 1 - Secure Mesh Networking & Remote Administration (Priority: P1) 🎯 MVP

**Goal**: Integrate the host into the Tailscale encrypted mesh virtual private network with automated daemon startup and non-interactive authentication, enabling secure remote administration without public port forwarding.

**Independent Test**: Roll out Tailscale to `admin@192.168.4.57`; authenticate host into mesh network; verify `tailscale status --json` reports `.BackendState == "Running"`; verify remote client can connect via SSH using mesh IP in `100.64.0.0/10` range or node name `homelab2` without router port forwarding.

### Implementation for User Story 1

- [X] T008 [P] [US1] Define Tailscale role default variables (`tailscale_args: '--accept-routes=true'`, `tailscale_auth_key: "{{ vault_tailscale_auth_key | default('') }}"`) in `ansible/roles/tailscale/defaults/main.yml`
- [X] T009 [P] [US1] Define Tailscale service handlers for restarting daemon (`systemctl restart tailscaled`) in `ansible/roles/tailscale/handlers/main.yml`
- [X] T010 [US1] Implement Tailscale installation and service activation tasks (install `tailscale` package from Arch Linux official repositories, enable and start `tailscaled.service`) in `ansible/roles/tailscale/tasks/main.yml`
- [X] T011 [US1] Implement Tailscale mesh authentication tasks checking current status (`tailscale status --json`) and executing `tailscale up --authkey={{ vault_tailscale_auth_key }}` with verbatim `no_log: true` when status is not `Running` in `ansible/roles/tailscale/tasks/main.yml`
- [X] T012 [US1] Create dedicated Phase 3 network convergence playbook `ansible/playbooks/network.yml` importing `tailscale` role with secret loading and age key validation
- [X] T013 [US1] Execute Tailscale rollout to `admin@192.168.4.57` using `scripts/apply-phase3.ps1 -Tags tailscale`
- [X] T014 [US1] Verify Tailscale service status and mesh authentication state on `admin@192.168.4.57` using `scripts/verify-phase3.ps1`

**Checkpoint**: User Story 1 functional - Host is registered on Tailnet, `tailscaled.service` is active, and remote SSH administration over encrypted mesh network is operational.

---

## Phase 4: User Story 2 - Host-Level Firewall & Boundary Protection (Priority: P1)

**Goal**: Enforce declarative host-level packet filtering via Linux `nftables` across all interfaces with a default-drop policy on external interfaces, while explicitly whitelisting local management LAN (`192.168.4.0/24`), mesh VPN encapsulation (UDP 41641), mesh interface (`tailscale0`), and web ingress (80/443).

**Independent Test**: Apply firewall rules; verify `nft list table inet filter` shows `type filter hook input priority filter; policy drop;`; confirm allowed ports (22 from `192.168.4.0/24`, 80, 443, 41641/udp, and interface `tailscale0`) accept connections while unapproved ports drop packets silently.

### Implementation for User Story 2

- [X] T015 [P] [US2] Define firewall role default variables (`firewall_allowed_subnets: ['192.168.4.0/24']`, `firewall_allowed_tcp_ports: [22, 80, 443]`, `firewall_allowed_udp_ports: [41641]`) in `ansible/roles/firewall/defaults/main.yml`
- [X] T016 [P] [US2] Define firewall service reload handler executing `systemctl reload-or-restart nftables.service` in `ansible/roles/firewall/handlers/main.yml`
- [X] T017 [P] [US2] Create dual-stack `nftables` template enforcing table `inet filter`, verbatim `policy drop;` on input and forward chains, `ct state established,related accept`, `ct state invalid drop`, `iifname "lo" accept`, `ip protocol icmp accept`, `ip6 nexthdr ipv6-icmp accept`, `iifname "tailscale0" accept`, `udp dport 41641 accept`, `ip saddr 192.168.4.0/24 tcp dport 22 accept`, and `tcp dport { 80, 443 } accept` in `ansible/roles/firewall/templates/nftables.conf.j2`
- [X] T018 [US2] Implement firewall tasks deploying `/etc/nftables.conf` with syntax check `validate: '/usr/bin/nft -c -f %s'`, enabling and starting `nftables.service` in `ansible/roles/firewall/tasks/main.yml`
- [X] T019 [US2] Wire `firewall` role into Phase 3 network playbook `ansible/playbooks/network.yml`
- [X] T020 [US2] Execute firewall rollout to `admin@192.168.4.57` using `scripts/apply-phase3.ps1 -Tags firewall`
- [X] T021 [US2] Verify `nftables.service` active state and rule policy drop enforcement on `admin@192.168.4.57` without administrative lockout

**Checkpoint**: User Stories 1 AND 2 complete - Host is protected by default-drop `nftables` firewall while retaining mesh VPN and management LAN administrative reachability.

---

## Phase 5: User Story 3 - Automated Ingress Reverse Proxy & ACME TLS Termination (Priority: P2)

**Goal**: Deploy Caddy ingress reverse proxy listening on ports 80 and 443 with modular `/etc/caddy/conf.d/*.caddy` drop-in architecture, automated HTTP-to-HTTPS redirection, WebSocket upgrades, and core `/health` check endpoint.

**Independent Test**: Query `http://192.168.4.57:80/health` and verify HTTP 200 `OK`; query `http://192.168.4.57:80/` and verify HTTP 301/308 redirect to HTTPS; verify `/etc/caddy/conf.d/*.caddy` files load dynamically.

### Implementation for User Story 3

- [X] T022 [P] [US3] Define Caddy role default variables (`caddy_conf_dir: '/etc/caddy/conf.d'`, `caddy_log_level: 'INFO'`) in `ansible/roles/caddy/defaults/main.yml`
- [X] T023 [P] [US3] Define Caddy service reload handler executing `systemctl reload caddy.service` in `ansible/roles/caddy/handlers/main.yml`
- [X] T024 [P] [US3] Create main Caddyfile template enforcing structured logging (`output stderr`, `format console`, `level INFO`), verbatim `admin off`, and verbatim `import /etc/caddy/conf.d/*.caddy` in `ansible/roles/caddy/templates/Caddyfile.j2`
- [X] T025 [P] [US3] Create health check drop-in template providing `:80 { handle /health { respond "OK" 200 } handle { redir https://{host}{uri} permanent } }` in `ansible/roles/caddy/templates/00-health.caddy.j2`
- [X] T026 [US3] Implement Caddy deployment tasks installing `caddy` package, creating `/etc/caddy/conf.d` directory, deploying `/etc/caddy/Caddyfile` with syntax check `validate: '/usr/bin/caddy validate --config %s'`, deploying `00-health.caddy`, and enabling `caddy.service` in `ansible/roles/caddy/tasks/main.yml`
- [X] T027 [US3] Wire `caddy` role into Phase 3 network playbook `ansible/playbooks/network.yml`
- [X] T028 [US3] Execute Caddy rollout to `admin@192.168.4.57` using `scripts/apply-phase3.ps1 -Tags caddy`
- [X] T029 [US3] Verify `caddy.service` active state, `/health` endpoint returning 200, and HTTP->HTTPS redirection on `admin@192.168.4.57`

**Checkpoint**: User Stories 1, 2, AND 3 complete - Ingress reverse proxy is listening on ports 80/443, serving `/health`, redirecting insecure HTTP to HTTPS, and ready for Phase 5 application drop-ins.

---

## Phase 6: User Story 4 - Verification, Telemetry & Configuration Recovery (Priority: P2)

**Goal**: Implement automated verification test suite (assertions NET-01 through NET-08), structured journal logging telemetry, and disaster recovery validation in compliance with Constitution Principles III and V.

**Independent Test**: Run `scripts/verify-phase3.sh` and verify all 8 assertion tests pass with exit code 0; test with a forced failure and verify script exits with non-zero exit code corresponding to failing check ID (NET-01 through NET-08) and emits error to stderr.

### Implementation for User Story 4

- [X] T030 [P] [US4] Implement automated acceptance test runner `scripts/verify-phase3.sh` evaluating NET-01 through NET-08 with individual check functions, diagnostic stderr outputs, and exact exit code mapping (1: nftables service, 2: nftables rules, 3: tailscale service, 4: tailscale status, 5: caddy service, 6: health endpoint 200, 7: http redirect 301/308, 8: listening ports 22/80/443/41641)
- [X] T031 [P] [US4] Implement PowerShell companion acceptance test runner `scripts/verify-phase3.ps1` for workstation orchestration executing verification over SSH against `admin@192.168.4.57`
- [X] T032 [P] [US4] Create dedicated Phase 3 Ansible verification playbook asserting NET-01 through NET-08 assertions in `ansible/playbooks/verify-phase3.yml`
- [X] T033 [US4] Integrate Phase 3 verification tasks (`tailscale`, `firewall`, `caddy`) into unified platform verification playbook `ansible/playbooks/verify.yml`
- [X] T034 [US4] Wire `tailscale`, `firewall`, and `caddy` roles into master homelab playbook `ansible/playbooks/site.yml`
- [X] T035 [P] [US4] Create disaster recovery documentation detailing 5-minute host reconstitution procedure and secret recovery from `vault.sops.yml` in `docs/disaster-recovery-phase3.md`
- [X] T036 [US4] Execute full automated verification suite `scripts/verify-phase3.ps1` against `admin@192.168.4.57` confirming all checks NET-01 through NET-08 pass with exit code 0

**Checkpoint**: All user stories complete - Network stack is rolled out to `admin@192.168.4.57`, protected, remotely accessible, serving ingress routes, and continuously observable with automated verification and verified recovery posture.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Validation, linting, end-to-end integration, and documentation updates across all user stories.

- [X] T037 [P] Run `ansible-lint` against all playbooks and roles in `ansible/`
- [X] T038 [P] Run `shellcheck` against `scripts/apply-phase3.sh` and `scripts/verify-phase3.sh`
- [X] T039 Execute idempotency verification by running `scripts/apply-phase3.ps1 -TargetHost "192.168.4.57"` and verifying clean zero-change convergence
- [X] T040 [P] Update platform implementation roadmap tracking Phase 3 Network & Remote Access completion in `ROADMAP.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately.
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories.
- **User Stories (Phase 3+)**: All depend on Foundational phase completion.
  - **User Story 1 (P1)**: Can start after Foundational (Phase 2). Establishes remote mesh access.
  - **User Story 2 (P1)**: Can start after Foundational (Phase 2). Establishes host packet filtering.
  - **User Story 3 (P2)**: Can start after User Story 2 (firewall must allow ports 80 and 443).
  - **User Story 4 (P2)**: Can start after User Stories 1, 2, and 3 are in place (verifies entire network stack).
- **Polish (Phase 7)**: Depends on all user stories being implemented and deployed.

### User Story Dependencies

```mermaid
flowchart TD
    Setup["Phase 1: Setup"] --> Foundation["Phase 2: Foundational"]
    Foundation --> US1["Phase 3: User Story 1 (Tailscale Mesh - P1)"]
    Foundation --> US2["Phase 4: User Story 2 (nftables Firewall - P1)"]
    US2 --> US3["Phase 5: User Story 3 (Caddy Ingress - P2)"]
    US1 --> US4["Phase 6: User Story 4 (Verification & Telemetry - P2)"]
    US2 --> US4
    US3 --> US4
    US4 --> Polish["Phase 7: Polish & Cross-Cutting"]
```

### Within Each User Story

- Default variables and handlers before tasks.
- Jinja2 templates before role tasks referencing them.
- Role tasks complete before playbook integration.
- Rollout execution task after playbook integration.
- Independent test verified on `admin@192.168.4.57` before moving to subsequent user story checkpoint.

---

## Parallel Execution Examples

### Parallel Example: User Story 1 & 2 Setup & Templates

```bash
# Launch defaults and handlers across roles concurrently:
Task: "T008 [P] [US1] Define Tailscale role default variables in ansible/roles/tailscale/defaults/main.yml"
Task: "T009 [P] [US1] Define Tailscale service handlers in ansible/roles/tailscale/handlers/main.yml"
Task: "T015 [P] [US2] Define firewall role default variables in ansible/roles/firewall/defaults/main.yml"
Task: "T016 [P] [US2] Define firewall service reload handler in ansible/roles/firewall/handlers/main.yml"
Task: "T017 [P] [US2] Create dual-stack nftables template in ansible/roles/firewall/templates/nftables.conf.j2"
```

### Parallel Example: User Story 3 Templates

```bash
# Launch Caddy configuration templates concurrently:
Task: "T022 [P] [US3] Define Caddy role default variables in ansible/roles/caddy/defaults/main.yml"
Task: "T023 [P] [US3] Define Caddy service reload handler in ansible/roles/caddy/handlers/main.yml"
Task: "T024 [P] [US3] Create main Caddyfile template in ansible/roles/caddy/templates/Caddyfile.j2"
Task: "T025 [P] [US3] Create health check drop-in template in ansible/roles/caddy/templates/00-health.caddy.j2"
```

### Parallel Example: User Story 4 Verification Runners

```bash
# Launch verification runners and documentation concurrently:
Task: "T030 [P] [US4] Implement automated acceptance test runner scripts/verify-phase3.sh"
Task: "T031 [P] [US4] Implement PowerShell companion acceptance test runner scripts/verify-phase3.ps1"
Task: "T032 [P] [US4] Create dedicated Phase 3 Ansible verification playbook ansible/playbooks/verify-phase3.yml"
Task: "T035 [P] [US4] Create disaster recovery documentation in docs/disaster-recovery-phase3.md"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (`ansible/roles/` structure).
2. Complete Phase 2: Foundational (`vars.yml`, `vault.sops.yml`, orchestrator scripts, pre-flight target check).
3. Complete Phase 3: User Story 1 (Tailscale package, daemon, authentication, rollout to `admin@192.168.4.57`).
4. **STOP and VALIDATE**: Verify host appears online on Tailnet and SSH connects via mesh IP without LAN routing.

### Incremental Delivery

1. Foundation ready (Phases 1 & 2).
2. Deliver User Story 1 (Tailscale mesh VPN) -> Rollout & test remote connectivity (MVP achieved).
3. Deliver User Story 2 (nftables firewall) -> Rollout & test boundary drops & port whitelists.
4. Deliver User Story 3 (Caddy reverse proxy) -> Rollout & test HTTP->HTTPS redirect and `/health` 200 OK.
5. Deliver User Story 4 (Automated verification & telemetry) -> Execute `scripts/verify-phase3.ps1` (NET-01 through NET-08).
6. Polish & validation (linting, idempotency run with 0 changes, roadmap update).
