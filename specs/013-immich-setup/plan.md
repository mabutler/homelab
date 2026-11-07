# Implementation Plan: Immich Photo Management Platform Deployment

**Branch**: `013-immich-setup` | **Date**: 2026-11-06 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/013-immich-setup/spec.md`

---

## Summary

Deploy the Immich photo and video management platform (`ghcr.io/immich-app/immich-server:v1.118.2`) on `fidelacchius` to establish a high-performance, private, self-hosted family photo library (Phase 5 of the repository Roadmap). The technical approach uses a dedicated Ansible role (`ansible/roles/immich`) managing a multi-container Docker Compose stack supervised by systemd (`immich.service`), consisting of four pinned services: `immich-server`, `immich-machine-learning`, `immich-database` (`pgvecto-rs:pg16-v0.2.1`), and `immich-redis` (`redis:6.2-alpine`).

The deployment enforces a strict two-tier storage topology: high-IOPS metadata, PostgreSQL database files, vector search embeddings, thumbnails, and ML models reside on NVMe storage at `/opt/services/immich`, while original full-resolution media files reside on pooled MergerFS storage at `/mnt/storage/media/photos` with consistent `PUID=1000`/`PGID=1001` permissions. Hardware video decoding and transcoding bind the host's integrated Intel UHD Graphics 770 iGPU (`00:02.0`) via stable PCI paths (`/dev/dri/by-path/pci-0000:00:02.0-render`) while leaving the discrete AMD Radeon RX 6700 XT untouched. Web and mobile ingress routes through Caddy (`/etc/caddy/conf.d/30-immich.caddy`) terminating TLS with 50GB streaming upload buffers. Continuous disaster recovery integrates an automated transactional `pg_dump` hook (`/etc/homelab/backup.d/30-immich.sh`) into the host Restic and Backblaze B2 pipeline, verified by an automated 9-assertion acceptance suite (`scripts/verify-phase5-immich.sh`).

---

## Technical Context

**Language/Version**:
- Container Workloads: Immich Server & Machine Learning `v1.118.2` (Node.js 20 / Python 3.11 runtimes inside upstream containers)
- Database: PostgreSQL 16 with `pgvector` (`tensorchord/pgvecto-rs:pg16-v0.2.1`)
- Cache: Redis `6.2-alpine`
- Automation & Tooling: Ansible 2.16+, POSIX Bash 5.2+, PowerShell 7+

**Primary Dependencies**:
- Container Runtime: Docker Engine & Docker Compose v2 (`ansible/roles/docker`)
- Hardware Acceleration: Intel Media Driver (`LIBVA_DRIVER_NAME=iHD`, VAAPI / QuickSync) on Intel Alder Lake-S UHD Graphics 770 (`pci-0000:00:02.0`)
- Process Supervision: systemd (`immich.service`)
- Reverse Proxy & Ingress: Caddy 2 (`/etc/caddy/conf.d/30-immich.caddy`)
- Backup Pipeline: Restic + Backblaze B2 (`/etc/homelab/backup.d/30-immich.sh`)

**Storage**:
- Tier 0 Fast NVMe App Storage (`/opt/services/immich` on `/dev/nvme0n1p2`, 1.8TB free): `compose.yml`, `.env` (`0600`), `.env.example`, `data/postgres` (PostgreSQL + pgvector cluster), `data/thumbs`, `data/model-cache`, `data/profile`, and transactional backup staging `backups/immich_db_backup.dump`
- Tier 1 Pooled Bulk Storage (`/mnt/storage/media/photos` on MergerFS `storage_pool`, 3.6TB free): `library/` (original full-resolution photos and videos), `upload/` (transient upload chunks), and `encoded-video/` (transcoded MP4s), protected by SnapRAID parity

**Testing**:
- In strict adherence to Constitution Principle III, ZERO automated unit test suites, test runners, or mock frameworks are created.
- Static Analysis & Linting: `ansible-lint`, `shellcheck`, and `bash -n` syntax checks across all scripts and playbooks.
- Automated Acceptance Suite: `scripts/verify-phase5-immich.sh` and `scripts/verify-phase5-immich.ps1` enforcing the 9-point assertion matrix `IMM-01` through `IMM-09`, integrated into `ansible/playbooks/verify-phase5-immich.yml` and `ansible/playbooks/verify.yml`.

**Target Platform**:
- Arch Linux x86_64 host (`fidelacchius`) with Intel Alder Lake-S UHD Graphics 770 iGPU (`00:02.0`) and discrete AMD Radeon RX 6700 XT (`03:00.0`).

**Project Type**:
- Infrastructure-as-Code (Ansible role, playbooks, Caddy drop-in configuration, backup hook, and operator verification scripts) for a containerized application stack.

**Performance Goals**:
- Immich web UI and API ping (`/api/server/ping`) respond with HTTP 200 in `< 500ms` (SC-004).
- Timeline rendering and thumbnail browsing load within `< 500ms` per viewport scroll (SC-002).
- Video streaming begins playback within `< 2s` via hardware transcoding (SC-003).
- Single-stream video transcode maintains host CPU utilization `< 50%` via Intel iGPU offload (SC-007).

**Constraints**:
- Discrete AMD Radeon RX 6700 XT GPU (`03:00.0`) must remain completely isolated and untouched by Immich containers (Principle IV).
- Zero cleartext secrets, database passwords, or cryptographic keys committed to version control; real secrets reside exclusively in gitignored `vault.yml` and `/opt/services/immich/.env` (`0600`) (Principle IV, SC-008).
- Service ingress bound strictly to loopback `127.0.0.1:2283` behind Caddy reverse proxy; zero ports published directly to `0.0.0.0` (FR-006, Principle IV).
- Transient thumbnail files, model caches, and transcoded videos must be excluded from offsite Backblaze B2 backups to conserve bandwidth and storage (Principle V).

**Scale/Scope**:
- Multi-user photo library supporting multi-terabyte collections (up to 3.6TB on current pool), multi-gigabyte video uploads (up to 50GB batches), and continuous background mobile synchronization.

**Documentation Impact**:
- `USER_FACING`: Updates repository root `README.md` (adding Immich to deployed applications, ports, and acceptance scripts), `ROADMAP.md` (marking Phase 5 Immich completed), `docs/roadmap.md` (reconciling operational state), and `docs/operations.md` (documenting initial onboarding and backup procedures).

---

## Constitution Check

*GATE: Evaluated prior to Phase 0 research. Re-evaluated and confirmed post-Phase 1 design.*

| Principle / Gate | Compliance Analysis | Status |
|---|---|---|
| **I. Evidence Over Invention, Bounded Investigation & Pragmatic Declarative-First Automation** | Immich configuration, directory structure, compose manifest, systemd unit, Caddy drop-in, and backup hook are declared via Ansible (`ansible/roles/immich`). All hardware paths (`00:02.0`), storage mount paths (`/mnt/storage`, `/opt/services`), and user IDs (`PUID=1000`, `PGID=1001`) are verified against host evidence (`lspci`, `df`, `id`). Verification uses contract-backed modular shell scripts (`verify-phase5-immich.sh`). | **PASS** |
| **II. Two-Tier Failure Model, Fail Closed on Required State & Strict Idempotency** | All Ansible tasks use idempotent modules (`file`, `template`, `systemd`, `assert`). Re-running `immich.yml` against a converged host produces `changed=0` without restarting healthy containers. Shell scripts enforce `set -euo pipefail`. `immich.service` asserts `RequiresMountsFor=/opt/services /mnt/storage`, failing closed if storage pools are unmounted. | **PASS** |
| **III. Behavioral, Value-Driven Testing, Deterministic Execution & Live Acceptance Gates** | In strict accordance with Principle III, zero unit tests or mocks are generated. Comprehensive live acceptance is guarded by 9 automated assertions (`IMM-01` through `IMM-09`) in `scripts/verify-phase5-immich.sh`, testing systemd state, HTTP ping, GPU device binding, storage mounts, secret permissions, Caddy syntax, storage group ownership, backup hook dump generation, and journald telemetry. | **PASS** |
| **IV. Single Authoritative State, Enforced Boundaries, Safe Concurrency & Zero Secrets in Git** | Database credentials are kept exclusively in gitignored `ansible/inventory/group_vars/all/vault.yml` and rendered to `/opt/services/immich/.env` (`0600`). Version control commits only `.env.example`. Immich server binds exclusively to `127.0.0.1:2283` behind Caddy. The discrete AMD GPU (`03:00.0`) is strictly unreferenced. | **PASS** |
| **V. Centralized Dependencies, Protected Toolchain Gate & Disaster Recovery by Design** | Container versions (`v1.118.2`, `pg16-v0.2.1`, `6.2-alpine`) are centrally declared in Ansible role defaults. Disaster recovery is guaranteed via `/etc/homelab/backup.d/30-immich.sh` executing transactional `pg_dump` into `/opt/services/immich/backups/`, captured by Restic into Backblaze B2, while transient caches (`thumbs`, `model-cache`, `encoded-video`) are excluded. | **PASS** |
| **VI. Bounded Resources & Verify-Before-Destroy** | Caddy enforces explicit request streaming limits (`50GB`) without unbounded memory buffering. Host resource consumption is bounded by `systemd-oomd` and journald storage ceilings (`2G`). Hardware transcoding prevents CPU starvation. Destruction of existing photo assets is prohibited. | **PASS** |
| **VII. Code Hygiene, Ubiquitous Language & Safe Logging** | All playbooks and scripts pass `ansible-lint`, `shellcheck`, and `bash -n` with zero warnings. Consistent ubiquitous terminology (`immich-server`, `immich-database`, `PUID`, `PGID`, `Tier 0`, `Tier 1`) is used across IaC, contracts, and documentation. Container and service logs route to `journald` with zero credential or token leakage. Human documentation (`README.md`, `ROADMAP.md`, `docs/`) will be updated in the same change. | **PASS** |

**Gate Evaluation**: **PASS** (Pre-Phase 0 and Post-Phase 1). Zero constitutional violations.

---

## Project Structure

### Documentation (this feature)

```text
specs/013-immich-setup/
├── spec.md                              # Feature specification
├── plan.md                              # This implementation plan (/speckit-plan output)
├── research.md                          # Phase 0 architectural decisions & technical research
├── data-model.md                        # Phase 1 storage topology, schemas & lifecycle state models
├── quickstart.md                        # Phase 1 deployment, onboarding & verification runbook
├── contracts/                           # Phase 1 explicit interface & verification contracts
│   ├── immich-service-contract.md       # Compose stack, systemd unit, iGPU device & storage contract
│   ├── backup-restore-contract.md       # 30-immich.sh pg_dump backup hook & Restic exclusion contract
│   ├── caddy-ingress-contract.md        # Caddy reverse proxy drop-in, upload buffering & TLS contract
│   └── verification-contract.md         # Automated acceptance matrix assertions IMM-01 through IMM-09
├── checklists/
│   └── requirements.md                  # Specification quality checklist
└── tasks.md                             # Phase 2 output (/speckit-tasks command - created in next stage)
```

### Source Code (repository root)

```text
ansible/
├── inventory/
│   └── group_vars/
│       └── all/
│           ├── vars.yml                 # Non-sensitive Immich configuration defaults (ports, versions, paths)
│           └── vault.yml.example        # Sanitized placeholder for immich_db_password
├── playbooks/
│   ├── site.yml                         # Master convergence playbook (includes immich role)
│   ├── immich.yml                       # Dedicated Phase 5 Immich deployment playbook
│   ├── verify-phase5-immich.yml         # Dedicated Phase 5 Immich acceptance verification playbook
│   └── verify.yml                       # Master platform verification playbook (imports verify-phase5-immich.yml)
└── roles/
    ├── immich/
    │   ├── defaults/
    │   │   └── main.yml                 # Pinned container images, ports, paths, and user/group IDs
    │   ├── files/
    │   │   └── env.example              # Committed .env.example template
    │   ├── handlers/
    │   │   └── main.yml                 # Systemd daemon-reload and Immich restart handlers
    │   ├── tasks/
    │   │   ├── main.yml                 # Task orchestrator (includes preflight, layout, config, service, backup, caddy)
    │   │   ├── preflight.yml            # Assertion of Docker, storage mounts, and iGPU device existence
    │   │   ├── layout.yml               # Creation of NVMe and MergerFS directory structures and permissions
    │   │   ├── config.yml               # Rendering of .env and compose.yml templates
    │   │   ├── service.yml              # Deployment of immich.service systemd unit and service activation
    │   │   ├── backup.yml               # Deployment of /etc/homelab/backup.d/30-immich.sh backup hook
    │   │   └── caddy.yml                # Deployment of /etc/caddy/conf.d/30-immich.caddy ingress drop-in
    │   └── templates/
    │       ├── 30-immich.sh.j2          # Transactional PostgreSQL dump and restore hook template
    │       ├── 30-immich.caddy.j2       # Caddy reverse proxy drop-in template
    │       ├── compose.yml.j2           # Docker Compose manifest template
    │       ├── env.j2                   # Environment file template (.env)
    │       └── immich.service.j2        # Systemd unit template
    └── backup/
        └── templates/
            ├── backup-include.txt.j2    # Updated to include /mnt/storage/media/photos/library
            └── backup-excludes.txt.j2   # Updated to exclude transient thumbnails, caches, and live DB files

scripts/
├── apply-phase5-immich.sh               # POSIX operator convergence runner for Immich
├── apply-phase5-immich.ps1              # PowerShell operator convergence runner for Immich
├── verify-phase5-immich.sh              # POSIX automated acceptance suite (IMM-01 through IMM-09)
└── verify-phase5-immich.ps1             # PowerShell automated acceptance suite

docs/
├── roadmap.md                           # Updated Phase 5 Immich completion and operational records
└── operations.md                        # Updated Immich runbook, user onboarding, and backup restore procedures

README.md                                # Root README updated with Immich service, ports, and acceptance runner
ROADMAP.md                               # Strategic roadmap updated marking Phase 5 Immich completed
```

**Structure Decision**:
Follows the established homelab2 architecture patterns seen in `ansible/roles/frigate` and `ansible/roles/vaultwarden`. Infrastructure is declared via modular Ansible roles, orchestrated via dedicated POSIX/PowerShell runner scripts (`apply-phase5-immich.{sh,ps1}`), and validated via dedicated acceptance verification suites (`verify-phase5-immich.{sh,ps1}`).

---

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

*Zero constitutional violations identified. No complexity exceptions required.*
