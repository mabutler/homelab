---
description: "Task list for Vaultwarden Public Access via Tailscale Funnel"
---

# Tasks: Vaultwarden Public Access via Tailscale Funnel

**Input**: Design documents from `/specs/008-vaultwarden-tailscale-funnel/`  
**Prerequisites**: `plan.md`, `spec.md`, `data-model.md`, `contracts/`, `research.md`, `quickstart.md`, `.specify/memory/constitution.md`  
**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `- [ ] [TaskID] [P?] [Story?] Description with file path`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., `[US1]`, `[US2]`, `[US3]`, `[US4]`)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure & Variables)

**Purpose**: Define configurable parameters and defaults for Tailscale Funnel and Caddy coordination without committing secrets or domain metadata to version control.

- [X] T001 [P] Define Tailscale Funnel role defaults in `ansible/roles/vaultwarden/defaults/main.yml` including `vaultwarden_domain: ""`, `vaultwarden_domain_default: "https://<node-name>.<tailnet>.ts.net"`, `vaultwarden_enable_funnel: true`, `vaultwarden_funnel_port: 443`, and `vaultwarden_internal_port: 8088` conforming to Invariant "Neither NodeFQDN, Tailscale auth keys, nor admin tokens may appear in version control"
- [X] T002 [P] Define Caddy ingress control variables in `ansible/roles/caddy/defaults/main.yml` including `caddy_manage_vaultwarden: false` and `caddy_enable_wildcard_443: false` to govern drop-in retirement and prevent port contention

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Eliminate Caddy port 443 binding contention and decommission conflicting legacy routes so Tailscale Funnel can bind port 443 without collision.

**⚠️ CRITICAL**: Tailscale Funnel cannot terminate port 443 if Caddy or another service is listening on port 443. This phase MUST be complete before any user story can activate Funnel.

- [X] T003 Eliminate wildcard `:443` binding in `ansible/roles/caddy/templates/00-health.caddy.j2`, conditioning wildcard `:443` block on `caddy_enable_wildcard_443 | default(false)` while retaining port 80 health checks (`/health`) and HTTPS redirection
- [X] T004 Update `ansible/roles/caddy/tasks/main.yml` to conditionally deploy or remove `/etc/caddy/conf.d/20-vaultwarden.caddy` based on `caddy_manage_vaultwarden` (ensuring `state: absent` and triggering Caddy reload when false)
- [X] T005 Remove deprecated template `ansible/roles/caddy/templates/20-vaultwarden.caddy.j2` to decommission legacy Caddy ingress route for Vaultwarden
- [X] T006 Validate Caddy syntax and reload service to verify port 443 is unblocked using `caddy validate` in `ansible/roles/caddy/tasks/main.yml`

**Checkpoint**: Foundation ready — Caddy port 443 released and legacy route decommissioned. User story implementation can now begin.

---

## Phase 3: User Story 1 - Frictionless Credential Access from Any Device and Network (Priority: P1) 🎯 MVP

**Goal**: Homelab and household members on external networks and unmanaged devices (work laptops, school computers) without Tailscale installed can securely access the web vault over public HTTPS with valid Let's Encrypt TLS termination.

**Independent Test**: Connect from an external machine or curl `https://<node-name>.<tailnet>.ts.net/alive` without VPN and verify HTTP 200 with valid TLS certificate and no browser security warnings.

- [X] T007 [US1] Create declarative Tailscale Funnel management task file `ansible/roles/vaultwarden/tasks/funnel.yml` querying `tailscale funnel status --json` and executing `tailscale funnel --bg --yes 8088` when inactive on port 443
- [X] T008 [US1] Include `funnel.yml` orchestration in `ansible/roles/vaultwarden/tasks/main.yml` gated by `vaultwarden_enable_funnel | default(true)`
- [X] T009 [US1] Update backend and public HTTPS ingress probe assertions in `ansible/playbooks/verify-phase5.yml` replacing legacy Caddy host header probe with dynamic public Funnel endpoint `/alive` check asserting HTTP 200 (VW-06)

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently over public HTTPS.

---

## Phase 4: User Story 2 - Bitwarden Client Integration & Real-Time Sync (Priority: P1)

**Goal**: Official Bitwarden mobile apps and browser extensions connect to the public domain with live WebSocket synchronization enabled, propagating credential changes across devices in real time.

**Independent Test**: Perform WebSocket upgrade handshake against `https://<discovered_fqdn>/notifications/hub` with `Upgrade: websocket` headers and verify `101 Switching Protocols` (or 401 Unauthorized handshake ack) response.

- [X] T010 [US2] Ensure `WEBSOCKET_ENABLED={{ vaultwarden_websocket_enabled | lower }}` in `ansible/roles/vaultwarden/templates/env.j2` conforming to constraint "MUST be true for real-time sync"
- [X] T011 [US2] Update WebSocket upgrade verification task VW-07 in `ansible/playbooks/verify-phase5.yml` to probe `https://<discovered_fqdn>/notifications/hub` over Tailscale Funnel using `curl` with `Upgrade: websocket` and assert `101 Switching Protocols` or protocol upgrade response

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently with full WebSocket real-time synchronization.

---

## Phase 5: User Story 3 - Automated Ingress Routing & Direct TLS Termination (Priority: P2)

**Goal**: Public HTTPS traffic terminates TLS directly at Tailscale's edge and proxies directly to the backend container port (8088) without intermediate proxy hops, persisting automatically across system reboots.

**Independent Test**: Query `tailscale funnel status --json` to verify port 443 maps directly to `http://127.0.0.1:8088`, confirm Caddy has no active routes for Vaultwarden, and verify native persistence across daemon restarts.

- [X] T012 [P] [US3] Configure direct reverse-proxy mapping to `127.0.0.1:8088` in `ansible/roles/vaultwarden/tasks/funnel.yml` ensuring conformance with Invariant "Vaultwarden container continues binding exclusively to 127.0.0.1:8088. It MUST NOT bind to 0.0.0.0:8088"
- [X] T013 [P] [US3] Update execution order in `ansible/playbooks/vaultwarden.yml` to run `caddy` role prior to `vaultwarden` role to guarantee port 443 release before Funnel activation
- [X] T014 [US3] Add automated assertion in `ansible/playbooks/verify-phase5.yml` verifying `tailscale funnel status --json` confirms background Funnel persistence and direct routing to port 8088

**Checkpoint**: At this point, ingress topology is decoupled, Caddy is cleanly bypassed, and Funnel persistence is verified.

---

## Phase 6: User Story 4 - Public Ingress Hardening & Domain Configuration Alignment (Priority: P2)

**Goal**: Dynamically discover node FQDN at deployment time, align Vaultwarden's canonical `DOMAIN` to match the public HTTPS endpoint, enforce signups disabled, and ensure WebCrypto origin integrity without committing private domain metadata to git.

**Independent Test**: Query `/api/config` on the public HTTPS endpoint and confirm `signupsAllowed: false` and `domain: "https://<discovered_fqdn>"`, and verify `/opt/services/vaultwarden/.env` file permissions are `0600`.

- [X] T015 [US4] Implement dynamic FQDN resolution in `ansible/roles/vaultwarden/tasks/config.yml` querying `tailscale status --json` to extract `.CertDomains[0]` or `.Self.DNSName` with fallback to `vaultwarden_domain_default`
- [X] T016 [US4] Update `ansible/roles/vaultwarden/templates/env.j2` to set `DOMAIN={{ vaultwarden_domain }}` with constraint "Must start with 'https://', no trailing slash" and Invariant "DOMAIN MUST match https://{{ tailscale_discovered_fqdn }} exactly. Mismatches will trigger client-side WebCrypto failures and cross-origin security warnings"
- [X] T017 [US4] Enforce `SIGNUPS_ALLOWED={{ vaultwarden_signups_allowed | lower }}` in `ansible/roles/vaultwarden/templates/env.j2` conforming to constraint "MUST be false (FR-005)" and Invariant "SIGNUPS_ALLOWED MUST strictly equal false. Any configuration where SIGNUPS_ALLOWED=true fails pre-flight verification"
- [X] T018 [US4] Enforce `ENABLE_DB_WAL={{ vaultwarden_enable_db_wal | lower }}` in `ansible/roles/vaultwarden/templates/env.j2` conforming to constraint "MUST be true for transactional integrity"
- [X] T019 [US4] Enforce strict secret file permissions (mode `0600`, owner `root:root`) for `/opt/services/vaultwarden/.env` in `ansible/roles/vaultwarden/tasks/config.yml` (VW-04)
- [X] T020 [US4] Add automated verification task in `ansible/playbooks/verify-phase5.yml` querying `https://<discovered_fqdn>/api/config` and asserting `signupsAllowed` is `false` and `domain` matches discovered FQDN

**Checkpoint**: All user stories functional, hardened against unauthorized registration, aligned with public origin, and compliant with zero-secrets principle.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: End-to-end integration, documentation updates, syntax validation, and platform verification.

- [X] T021 [P] Synchronize Phase 5 verification assertions (VW-06 Funnel HTTPS probe, VW-07 WebSocket upgrade, and `/api/config` validation) into platform master verification playbook `ansible/playbooks/verify.yml`
- [X] T022 [P] Validate all modified Ansible roles and playbooks with `ansible-lint` in `ansible/.ansible-lint`
- [X] T023 Run end-to-end deployment playbook `ansible/playbooks/vaultwarden.yml` against target node to verify clean convergence
- [X] T024 Execute full acceptance suite via `ansible/playbooks/verify-phase5.yml` and validate against `specs/008-vaultwarden-tailscale-funnel/quickstart.md` scenarios

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion — **BLOCKS** all user stories (port 443 must be freed from Caddy before Funnel can start)
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - User Story 1 (P1): Core Funnel activation & public HTTPS probe (MVP)
  - User Story 2 (P1): WebSocket sync & upgrade verification
  - User Story 3 (P2): Direct proxying & persistence assertion
  - User Story 4 (P2): Dynamic FQDN discovery, domain origin alignment, & signup hardening
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start immediately after Foundational (Phase 2). No dependency on subsequent stories.
- **User Story 2 (P1)**: Can start after Foundational; enhances US1 with WebSocket notification hub support.
- **User Story 3 (P2)**: Can start after Foundational; ensures direct routing topology and persistence.
- **User Story 4 (P2)**: Can start after Foundational; dynamic FQDN resolution in `config.yml` can be developed in parallel with Funnel tasks, but deployment converges in Vaultwarden service restart.

### Parallel Opportunities

- In Phase 1: `T001` and `T002` (defaults for vaultwarden and caddy) can run in parallel.
- In Phase 2: `T003`, `T004`, and `T005` can be edited in parallel across Caddy templates and tasks.
- In Phase 5: `T012` and `T013` can run in parallel.
- In Phase 7: `T021` and `T022` (verify.yml sync and ansible-lint) can run in parallel.

---

## Parallel Example: User Story 1 & Foundational

```bash
# Parallel variable setup:
Task: "Define Tailscale Funnel role defaults in ansible/roles/vaultwarden/defaults/main.yml"
Task: "Define Caddy ingress control variables in ansible/roles/caddy/defaults/main.yml"

# Parallel Caddy configuration adjustments:
Task: "Eliminate wildcard :443 binding in ansible/roles/caddy/templates/00-health.caddy.j2"
Task: "Update ansible/roles/caddy/tasks/main.yml to conditionally deploy or remove 20-vaultwarden.caddy"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (`T001`, `T002`)
2. Complete Phase 2: Foundational (`T003` - `T006`) — releases port 443
3. Complete Phase 3: User Story 1 (`T007` - `T009`) — activates Tailscale Funnel
4. **STOP and VALIDATE**: Probe `https://<node-name>.<tailnet>.ts.net/alive` independently
5. Public MVP is working and accessible!

### Incremental Delivery

1. Complete Setup + Foundational → Caddy port 443 contention eliminated
2. Add User Story 1 → Test independently → Public web vault accessible (MVP!)
3. Add User Story 2 → Test independently → Real-time push synchronization verified
4. Add User Story 3 → Test independently → Direct proxy routing and reboot persistence verified
5. Add User Story 4 → Test independently → Dynamic FQDN discovery and signup restrictions verified
6. Complete Polish → Full `verify.yml` and `ansible-lint` green

---

## Notes

- `[P]` tasks = different files, no dependencies
- `[Story]` label maps task to specific user story for traceability
- Every task includes an explicit file path
- Verbatim constraints from `data-model.md` are quoted in relevant task descriptions
- Zero secrets or real domain hostnames committed to git
