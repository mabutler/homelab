# Tasks: Immich Photo Management Platform Deployment

**Input**: Design documents from `/specs/013-immich-setup/`  
**Prerequisites**: [plan.md](./plan.md) (required), [spec.md](./spec.md) (required), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)  
**Documentation Impact**: `USER_FACING` - Updates repository root `README.md`, `ROADMAP.md`, `docs/roadmap.md`, and `docs/operations.md`.  
**Tests**: In strict accordance with Constitution Principle III, ZERO automated unit test suites, test runners, or mock frameworks are created. All verification is performed exclusively via static analysis (`bash -n`, `shellcheck`, `ansible-lint`) and live acceptance suites (`scripts/verify-phase5-immich.sh`, `scripts/verify-phase5-immich.ps1`, `ansible/playbooks/verify-phase5-immich.yml`).  
**Organization**: Tasks are grouped by user story in priority order (P1 stories first, then P2) to enable independent implementation, testing, and MVP delivery.

---

## Format: `- [ ] [ID] [P?] [Story] Description with file path`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Maps to user story from spec.md (`[US1]`, `[US2]`, `[US4]`, `[US3]`, `[US5]`, `[US6]`). Setup, Foundational, and Polish phases omit story labels.
- Include exact file paths and quoted verbatim constraints in task descriptions.

---

## Phase 1: Setup (Shared Infrastructure & Inventory Definitions)

**Purpose**: Establish configuration defaults, variable schemas, directory placeholders, and Ansible role scaffolding.

- [x] T001 [P] Configure global Immich variables, port definitions (`immich_port: 2283`), and paths in `ansible/inventory/group_vars/all/vars.yml`
- [x] T002 [P] Add sanitized vault secret placeholder `immich_db_password: "CHANGE_ME_IN_VAULT"` to `ansible/inventory/group_vars/all/vault.yml.example`
- [x] T003 [P] Define default role parameters, image versions (`ghcr.io/immich-app/immich-server:v1.118.2`, `docker.io/tensorchord/pgvecto-rs:pg16-v0.2.1`, `docker.io/redis:6.2-alpine`), and user IDs (`PUID=1000`, `PGID=1001`) in `ansible/roles/immich/defaults/main.yml`
- [x] T004 [P] Create sanitized reference environment template `ansible/roles/immich/files/env.example`
- [x] T005 [P] Implement systemd reload and Immich restart notification handlers in `ansible/roles/immich/handlers/main.yml`

---

## Phase 2: Foundational (Blocking Prerequisites & Execution Framework)

**Purpose**: Core validation and runner infrastructure that MUST be complete before ANY user story can be implemented.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [x] T006 Implement host preflight checks asserting Docker daemon active, storage mount accessibility (`/opt/services` and `/mnt/storage`), and iGPU render node existence in `ansible/roles/immich/tasks/preflight.yml`
- [x] T007 Create role task orchestrator integrating preflight, layout, config, service, backup, and caddy tasks in `ansible/roles/immich/tasks/main.yml`
- [x] T008 [P] Implement dedicated Phase 5 Immich deployment playbook in `ansible/playbooks/immich.yml`
- [x] T009 Integrate immich playbook into master platform convergence playbook `ansible/playbooks/site.yml`
- [x] T010 [P] Create POSIX convergence runner script with `--tags` support, root privilege checks, and error traps in `scripts/apply-phase5-immich.sh`
- [x] T011 [P] Create PowerShell convergence runner script with SSH remote execution support for Windows operator workstation in `scripts/apply-phase5-immich.ps1`

**Checkpoint**: Foundation ready - user story implementation can now begin.

---

## Phase 3: User Story 2 - Resilient Multi-Tier Storage Architecture (Priority: P1)

**Goal**: Partition Immich storage between Tier 0 fast NVMe (`/opt/services/immich`) for metadata, PostgreSQL DB, thumbnails, model cache, and backup staging, and Tier 1 pooled MergerFS storage (`/mnt/storage/media/photos`) for original libraries, uploads, and encoded video with `admin:storage` (`PUID=1000`/`PGID=1001`) ownership and `2775` permissions.

**Independent Test**: Verify directory creation, ownership `admin:storage`, mode `2775` on MergerFS paths, and mode `0700` with owner `999:999` on `/opt/services/immich/data/postgres`, confirming volume targets match the Tier 0 / Tier 1 specification (Assertions `IMM-04`, `IMM-07`).

### Implementation for User Story 2

- [x] T012 [US2] Implement filesystem provisioning tasks creating Tier 0 NVMe directories (`/opt/services/immich/{data/postgres,data/thumbs,data/model-cache,data/profile,backups}`) with modes `0700`/`0750`/`0755` and Tier 1 MergerFS directories (`/mnt/storage/media/photos/{library,upload,encoded-video}`) with owner `admin:storage` (`PUID=1000`/`PGID=1001`) and mode `2775` in `ansible/roles/immich/tasks/layout.yml`
- [x] T013 [US2] Enforce Tier 0 NVMe and Tier 1 MergerFS volume mount path separation parameters and directory mappings in `ansible/roles/immich/defaults/main.yml` and `ansible/roles/immich/templates/compose.yml.j2` ensuring `library`, `upload`, and `encoded-video` bind to `/mnt/storage/media/photos` and `thumbs`, `profile`, `model-cache`, and `postgres` bind to `/opt/services/immich/data`

**Checkpoint**: Multi-tier storage boundaries are established; media files write to pooled bulk storage while metadata and caches remain on NVMe.

---

## Phase 4: User Story 1 - Self-Hosted Photo and Video Management & Seamless Ingest (Priority: P1) 🎯 MVP

**Goal**: Deploy the core Immich multi-container stack (`immich_server`, `immich_database`, `immich_redis`, `immich_machine_learning`) supervised by systemd (`immich.service`), providing the primary photo/video ingest, timeline browsing, and API on `127.0.0.1:2283` utilizing provisioned storage tiers.

**Independent Test**: Verify systemd unit `immich.service` starts the stack, containers report healthy state, and HTTP ping probe `curl -fsS -m 2 http://127.0.0.1:2283/api/server/ping` returns `{"res":"pong"}` within 500ms (Assertion `IMM-02`).

### Implementation for User Story 1

- [x] T014 [P] [US1] Create Jinja2 environment file template with mode `0600` containing database credentials, Redis connection, and node production environment in `ansible/roles/immich/templates/env.j2`
- [x] T015 [P] [US1] Create Docker Compose manifest template defining `immich-server`, `immich-machine-learning`, `redis`, and `database` services with healthchecks and dependencies in `ansible/roles/immich/templates/compose.yml.j2`
- [x] T016 [P] [US1] Create systemd service unit template with `RequiresMountsFor=/opt/services /mnt/storage`, `Type=oneshot`, and `RemainAfterExit=yes` in `ansible/roles/immich/templates/immich.service.j2`
- [x] T017 [US1] Implement configuration deployment tasks rendering `.env` (mode `0600`) and `compose.yml` (mode `0644`) into `/opt/services/immich/` in `ansible/roles/immich/tasks/config.yml`
- [x] T018 [US1] Implement service activation tasks deploying `immich.service`, running `systemctl daemon-reload`, and enabling/starting `immich.service` in `ansible/roles/immich/tasks/service.yml`

**Checkpoint**: Immich container stack is operational and responds to API ping requests on loopback port 2283.

---

## Phase 5: User Story 4 - Continuous Disaster Recovery & Atomic Database Backups (Priority: P1)

**Goal**: Automate disaster recovery through a transactional PostgreSQL dump hook (`/etc/homelab/backup.d/30-immich.sh`) integrated into the host Restic and Backblaze B2 backup pipeline, while excluding transient thumbnails, caches, and live DB files.

**Independent Test**: Run `/etc/homelab/backup.d/30-immich.sh pre-backup`, verify a non-empty `immich_db_backup.dump` is created in `/opt/services/immich/backups/`, and verify Restic inclusion and exclusion filters (Assertion `IMM-08`).

### Implementation for User Story 4

- [x] T019 [P] [US4] Create transactional PostgreSQL database dump and restore hook template (`pre-backup` and `post-restore` actions executing `pg_dump` with custom format) in `ansible/roles/immich/templates/30-immich.sh.j2`
- [x] T020 [US4] Implement backup task deploying executable hook to `/etc/homelab/backup.d/30-immich.sh` with mode `0755` in `ansible/roles/immich/tasks/backup.yml`
- [x] T021 [P] [US4] Update centralized Restic backup inclusion list template to capture `/mnt/storage/media/photos/library` in `ansible/roles/backup/templates/backup-include.txt.j2`
- [x] T022 [P] [US4] Update centralized Restic backup exclusion list template to exclude live DB files (`/opt/services/immich/data/postgres/**`), pre-generated thumbnails (`/opt/services/immich/data/thumbs/**`), model cache (`/opt/services/immich/data/model-cache/**`), transient uploads (`/mnt/storage/media/photos/upload/**`), and transcoded video (`/mnt/storage/media/photos/encoded-video/**`) in `ansible/roles/backup/templates/backup-excludes.txt.j2`

**Checkpoint**: Backup hook generates verified database dumps; Restic backup rules protect library and metadata while excluding regenerable caches.

---

## Phase 6: User Story 3 - Hardware-Accelerated Video Transcoding & Machine Learning (Priority: P2)

**Goal**: Configure Intel UHD Graphics 770 iGPU (`00:02.0`) device passthrough (`/dev/dri/by-path/pci-0000:00:02.0-render`) with `LIBVA_DRIVER_NAME=iHD` into `immich-server` for hardware video transcoding while strictly isolating the discrete AMD Radeon RX 6700 XT GPU (`03:00.0`), and configure machine learning model caching.

**Independent Test**: Inspect `/opt/services/immich/compose.yml` to verify render node `pci-0000:00:02.0-render` is mounted as `/dev/dri/renderD128` and discrete AMD GPU `03:00.0` is completely unreferenced (Assertion `IMM-03`).

### Implementation for User Story 3

- [x] T023 [US3] Configure explicit Intel UHD 770 iGPU device passthrough (`/dev/dri/by-path/pci-0000:00:02.0-render:/dev/dri/renderD128` and `/dev/dri/by-path/pci-0000:00:02.0-card:/dev/dri/card0`) with `LIBVA_DRIVER_NAME=iHD` while strictly isolating discrete AMD GPU `03:00.0` in `ansible/roles/immich/templates/compose.yml.j2`
- [x] T024 [US3] Add preflight assertion validating presence of Intel iGPU render node `/dev/dri/by-path/pci-0000:00:02.0-render` on target host in `ansible/roles/immich/tasks/preflight.yml`

**Checkpoint**: Intel iGPU hardware acceleration is mapped into Immich server; discrete AMD GPU remains isolated.

---

## Phase 7: User Story 5 - Automated Health Telemetry & Service Observability (Priority: P2)

**Goal**: Implement comprehensive automated acceptance verification scripts (`scripts/verify-phase5-immich.sh` and `ps1`) enforcing assertions `IMM-01` through `IMM-09`, journald telemetry verification, and integration into Ansible playbooks `verify-phase5-immich.yml` and `verify.yml`.

**Independent Test**: Execute `scripts/verify-phase5-immich.sh --local` and verify all 9 assertions pass with exit code 0 and structured output (Assertions `IMM-01` through `IMM-09`).

### Implementation for User Story 5

- [x] T025 [P] [US5] Implement POSIX acceptance verification script executing assertions `IMM-01` through `IMM-09` with structured error reporting, exit codes 1-9, and `--json` support in `scripts/verify-phase5-immich.sh`
- [x] T026 [P] [US5] Implement PowerShell acceptance verification script executing assertions `IMM-01` through `IMM-09` for Windows operator workstation in `scripts/verify-phase5-immich.ps1`
- [x] T027 [US5] Create dedicated Phase 5 Immich acceptance verification playbook running assertions via script or Ansible tasks in `ansible/playbooks/verify-phase5-immich.yml`
- [x] T028 [US5] Import Phase 5 Immich verification playbook into master verification suite in `ansible/playbooks/verify.yml`

**Checkpoint**: Automated verification harness is operational across POSIX, PowerShell, and Ansible interfaces.

---

## Phase 8: User Story 6 - Reverse Proxy Ingress & Network Security (Priority: P2)

**Goal**: Configure Caddy reverse proxy drop-in (`/etc/caddy/conf.d/30-immich.caddy`) for HTTPS ingress at `photos.{$HOMELAB_DOMAIN:lan}` and `photos.fidelacchius.ts.net`, terminating TLS, supporting up to 50GB request bodies, WebSockets, and loopback forwarding to `127.0.0.1:2283`.

**Independent Test**: Run `caddy validate --config /etc/caddy/Caddyfile` and verify drop-in syntax and proxy target (Assertion `IMM-06`).

### Implementation for User Story 6

- [x] T029 [P] [US6] Create Caddy reverse proxy drop-in template for `photos.{$HOMELAB_DOMAIN:lan}` and Tailscale domain with `max_size 50GB` request body and loopback upstream `127.0.0.1:2283` in `ansible/roles/immich/templates/30-immich.caddy.j2`
- [x] T030 [US6] Implement Caddy deployment tasks installing drop-in to `/etc/caddy/conf.d/30-immich.caddy` and triggering Caddy reload handler in `ansible/roles/immich/tasks/caddy.yml`

**Checkpoint**: Ingress routing is established; Immich is reachable via secure Caddy endpoints with 50GB streaming upload buffers.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Documentation updates, governance alignment, and static analysis verification across all created files.

- [x] T031 [P] Update repository root `README.md` adding Immich to deployed applications, port table (`2283`), and verification script reference
- [x] T032 [P] Update repository root `ROADMAP.md` marking Phase 5 Immich photo management platform as completed
- [x] T033 [P] Update operational roadmap status in `docs/roadmap.md` with Immich deployment details and architectural records
- [x] T034 [P] Document operator onboarding, mobile application configuration, and backup restoration procedures in `docs/operations.md`
- [x] T035 Execute static analysis and syntax validation across shell scripts and Ansible configurations (`bash -n scripts/apply-phase5-immich.sh scripts/verify-phase5-immich.sh`, `shellcheck scripts/apply-phase5-immich.sh scripts/verify-phase5-immich.sh`, and `ansible-lint`)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately.
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories.
- **User Story 2 (Phase 3 - P1)**: Depends on Foundational completion. Provisions the host directory layout and multi-tier storage paths with strict permissions before configuration deployment or service startup.
- **User Story 1 (Phase 4 - P1)**: Depends on US2 storage layout. Deploys environment, compose manifest, and activates the operational service stack (MVP).
- **User Story 4 (Phase 5 - P1)**: Depends on US1 (running database) and US2 (storage layout) to verify transactional dumps.
- **User Story 3 (Phase 6 - P2)**: Depends on US1 (compose manifest) to configure iGPU hardware bindings.
- **User Story 5 (Phase 7 - P2)**: Depends on US1, US2, US3, US4 to execute complete 9-assertion acceptance matrix.
- **User Story 6 (Phase 8 - P2)**: Depends on US1 (operational backend on port 2283) to validate reverse proxy ingress.
- **Polish (Phase 9)**: Depends on all user story implementations being complete.

### User Story Dependencies

- **User Story 2 (P1)**: Independent of other user stories; requires only Phase 1 & 2 to establish directory structure and permissions.
- **User Story 1 (P1)**: Depends on US2 directory layout to safely deploy configuration and activate services without root-owned bind mounts.
- **User Story 4 (P1)**: Connects to database deployed in US1 and backs up library configured in US2.
- **User Story 3 (P2)**: Augments compose manifest from US1 with hardware acceleration devices.
- **User Story 5 (P2)**: Asserts operational state across US1, US2, US3, US4, US6.
- **User Story 6 (P2)**: Exposes US1 service to local network and Tailscale via Caddy.

### Parallel Opportunities

- In **Phase 1 (Setup)**: T001, T002, T003, T004, T005 can all execute concurrently.
- In **Phase 2 (Foundational)**: T008, T010, T011 can run in parallel while orchestrator tasks are prepared.
- In **Phase 3 (User Story 2)**: T012 and T013 establish host directory topology and volume mapping definitions.
- In **Phase 4 (User Story 1)**: T014, T015, T016 can be authored in parallel before assembling tasks T017 and T018.
- In **Phase 5 (User Story 4)**: T019, T021, T022 can run in parallel.
- In **Phase 7 (User Story 5)**: T025 and T026 can be authored in parallel.
- In **Phase 9 (Polish)**: T031, T032, T033, T034 can be edited concurrently.

---

## Parallel Example: User Story 1 & Setup

```bash
# Author setup defaults and templates in parallel:
Task: "Configure global Immich variables in ansible/inventory/group_vars/all/vars.yml"
Task: "Add vault secret placeholder in ansible/inventory/group_vars/all/vault.yml.example"
Task: "Define default role parameters in ansible/roles/immich/defaults/main.yml"
Task: "Create env.example template in ansible/roles/immich/files/env.example"

# Author core US1 templates in parallel:
Task: "Create Jinja2 environment file template in ansible/roles/immich/templates/env.j2"
Task: "Create Docker Compose manifest template in ansible/roles/immich/templates/compose.yml.j2"
Task: "Create systemd service unit template in ansible/roles/immich/templates/immich.service.j2"
```

---

## Implementation Strategy

### MVP First (User Stories 2 & 1)

1. Complete Phase 1: Setup (role skeleton, variables, handlers).
2. Complete Phase 2: Foundational (preflight checks, runners).
3. Complete Phase 3: User Story 2 (directory structure, permissions, mount paths).
4. Complete Phase 4: User Story 1 (compose stack, environment, systemd unit, service activation).
5. **STOP and VALIDATE**: Test User Story 1 independently by starting `immich.service` and verifying HTTP 200 from `http://127.0.0.1:2283/api/server/ping`.

### Incremental Delivery

1. Setup + Foundational -> Scaffolding ready.
2. User Story 2 -> NVMe vs MergerFS multi-tier storage isolated and permissions verified (`PUID=1000`/`PGID=1001`).
3. User Story 1 (MVP) -> Core container stack operational on loopback with pre-provisioned directories.
4. User Story 4 -> Automated PostgreSQL `pg_dump` hook created and Restic offsite backup rules configured.
5. User Story 3 -> Intel UHD 770 iGPU acceleration enabled; discrete AMD GPU verified unreferenced.
6. User Story 5 -> Acceptance suite (`scripts/verify-phase5-immich.sh`) validating assertions `IMM-01` through `IMM-09`.
7. User Story 6 -> Caddy reverse proxy drop-in deployed; TLS and 50GB streaming ingress operational.
8. Polish -> Documentation and static analysis clean.

---

## Notes

- Strict adherence to Constitution Principle III: Zero automated unit test files are generated anywhere in the workspace.
- Live acceptance testing is handled exclusively by `scripts/verify-phase5-immich.sh` and `ansible/playbooks/verify-phase5-immich.yml`.
- All credentials remain isolated in gitignored vault files and `.env` (mode `0600`).
