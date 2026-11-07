# Research & Architectural Decisions: Immich Photo Management Platform Deployment

**Feature**: `013-immich-setup`  
**Date**: 2026-11-06  
**Status**: Completed  
**Governing Documents**: `.specify/memory/constitution.md`, `.specify/memory/coding-standards.md`, `.specify/memory/logging-standards.md`, `specs/013-immich-setup/spec.md`

---

## 1. Container Workload Architecture & Image Tag Pinning

### Question / Unknown
What container images, topologies, and pinned tags should be selected for Immich to provide maximum stability, security, and low operational toil in compliance with Constitution Principle V (*Centralized Dependencies, Stability-First & Annual Maintenance Cadence*)?

### Decision
Deploy the official multi-container Immich stack consisting of four pinned container images:
1. **Application Server (`immich-server`)**: `ghcr.io/immich-app/immich-server:v1.118.2`
   - Handles web UI, REST API, client authentication, timeline generation, background job queues, and video transcode coordination.
   - Note: Since Immich v1.106.0, `immich-microservices` was unified directly into `immich-server`.
2. **Machine Learning Engine (`immich-machine-learning`)**: `ghcr.io/immich-app/immich-machine-learning:v1.118.2`
   - Provides on-demand facial recognition, object detection, and CLIP multilingual semantic search embeddings over an internal HTTP API.
3. **Relational & Vector Database (`immich-database`)**: `docker.io/tensorchord/pgvecto-rs:pg16-v0.2.1`
   - PostgreSQL 16 database pre-configured with the `vectors` (`pgvecto.rs`) extension required for high-dimensional vector similarity indexing.
4. **Task Queue & In-Memory Cache (`immich-redis`)**: `docker.io/redis:6.2-alpine`
   - High-throughput volatile queue for background processing pipelines (thumbnail extraction, metadata parsing, transcode tasks).

### Rationale
- Using pinned upstream release tags (`v1.118.2`, `pg16-v0.2.1`, `6.2-alpine`) prevents sudden container drift or breaking database migrations on host restarts.
- Unifying the microservices into `immich-server` reduces container overhead from 5 containers down to 4, matching current upstream best practices.
- The `pgvecto-rs` image is the upstream-mandated vector store for Immich v1.90+ ensuring native hardware vector acceleration.

### Alternatives Considered
- `ghcr.io/immich-app/immich-server:latest` / `:release`: Rejected because floating tags violate Constitution Principle V and create non-deterministic convergence states.
- Running PostgreSQL directly on the Arch host: Rejected to avoid contaminating host package state and simplify backup/restore boundary isolation.
- Single all-in-one container: Immich does not support an official monolithic single-binary container; multi-container Compose is the canonical distribution.

---

## 2. Multi-Tier Storage Topology & Permissions

### Question / Unknown
How should persistent storage be partitioned between fast NVMe storage and pooled mass storage to guarantee low visual latency while accommodating terabytes of family media without permission contention?

### Decision
Implement a strict two-tier storage layout:
1. **Tier 0 Fast NVMe Storage (`/opt/services/immich`)**:
   - Resides on the 2TB NVMe SSD filesystem (`/dev/nvme0n1p2`).
   - Stores all high-I/O metadata:
     - PostgreSQL database cluster: `/opt/services/immich/data/postgres`
     - Machine learning model cache: `/opt/services/immich/data/model-cache`
     - Generated thumbnails & previews: `/opt/services/immich/data/thumbs`
     - User profile avatars: `/opt/services/immich/data/profile`
     - Transactional database backup staging: `/opt/services/immich/backups`
   - Docker Compose and secrets: `/opt/services/immich/compose.yml` (`0644`), `/opt/services/immich/.env` (`0600`).
2. **Tier 1 Pooled Bulk Storage (`/mnt/storage/media/photos`)**:
   - Resides on the MergerFS storage pool (`/mnt/storage`) backed by SnapRAID parity protection.
   - Stores immutable, full-resolution original media assets:
     - Primary user library: `/mnt/storage/media/photos/library`
     - Ingestion upload staging: `/mnt/storage/media/photos/upload`
     - Adaptive transcoded video streams: `/mnt/storage/media/photos/encoded-video`
3. **Process UID/GID & File Permissions**:
   - Containers execute under host user `admin` (`PUID=1000`) and group `storage` (`PGID=1001`).
   - Host directories are pre-created with mode `2775` (setgid) on storage paths and `0755`/`0750` on application paths, ensuring any file written by Immich or other homelab tools remains readable and writable across services.

### Rationale
- Database queries, vector similarity searches, and thumbnail rendering require microsecond random I/O that would thrash mechanical hard drives. Placing them on NVMe guarantees `<500ms` viewport rendering.
- High-capacity original photos and videos (often multi-terabyte collections) must reside on the expandable, parity-protected MergerFS pool.
- Standardizing on `PUID=1000` / `PGID=1001` eliminates Docker root-squash permission mismatches with host backup and administration tools.

### Alternatives Considered
- Storing everything in `/opt/services/immich`: Rejected because NVMe storage is cost-constrained (1.8TB available) and cannot scale to large raw video libraries.
- Storing database and thumbnails on `/mnt/storage`: Rejected because SQLite/Postgres I/O against MergerFS FUSE layers incurs unacceptable query latency and potential file-locking quirks.

---

## 3. Hardware Video Decoding & Machine Learning Acceleration

### Question / Unknown
How should GPU hardware acceleration be exposed to Immich containers on `fidelacchius` while preserving isolation and avoiding interference with discrete graphics or other services?

### Decision
- Bind host Intel Alder Lake-S UHD Graphics 770 iGPU (`00:02.0`) to `immich-server` and `immich-machine-learning` using deterministic udev PCI device paths:
  - Render node: `/dev/dri/by-path/pci-0000:00:02.0-render` (mapped to `/dev/dri/renderD128`)
  - Card node: `/dev/dri/by-path/pci-0000:00:02.0-card` (mapped to `/dev/dri/card0`)
- Set environment variable `LIBVA_DRIVER_NAME=iHD` for Intel Media Driver (VAAPI / QuickSync) hardware decoding and H.264/HEVC transcoding.
- Explicitly exclude the discrete AMD Radeon RX 6700 XT (`03:00.0`, `/dev/dri/by-path/pci-0000:03:00.0-*`).
- Grant container video and render group permissions (`video: 983`, `render: 226` or passing devices directly).

### Rationale
- Hardware transcoding reduces CPU utilization during video streaming from ~80% down to <20%, leaving CPU headroom for system services.
- Deterministic PCI symlinks (`by-path`) prevent device renumbering across kernel boots or driver reload events.
- Isolating the AMD GPU protects the workstation gaming/compute workload from container resource contention.

### Alternatives Considered
- Passing all `/dev/dri` devices indiscriminately: Rejected because it violates Principle IV (Enforced Boundaries) and exposes the host's primary discrete GPU to container processes.
- CPU-only video transcoding: Rejected because 4K 60fps mobile phone video transcoding causes immediate CPU starvation and unacceptable playback buffering.

---

## 4. Ingress, TLS Termination & Upload Buffering (Caddy Integration)

### Question / Unknown
How should Immich be published to homelab clients over local LAN and Tailscale while supporting multi-gigabyte photo and video uploads without connection drops or proxy timeouts?

### Decision
- Create drop-in Caddy configuration: `/etc/caddy/conf.d/30-immich.caddy`.
- Upstream loopback proxy: `immich-server` binds port `2283` exclusively to `127.0.0.1:2283` (never exposed directly on public network interfaces).
- Domain routing: Caddy routes `photos.lan` and `photos.{{ homelab_domain }}` / Tailscale magic DNS name to `http://127.0.0.1:2283`.
- Ingress parameters:
  - `request_body { max_size 50GB }` to accommodate multi-gigabyte video uploads.
  - Generous transport timeouts (`dial_timeout 30s`, `response_header_timeout 300s`) for large file streaming.
  - Native WebSocket support (Caddy handles WebSockets transparently without special proxy modules).

### Rationale
- Eliminates cleartext traffic over Wi-Fi and VPN tunnels.
- Eliminates HTTP 413 "Request Entity Too Large" errors typical of default reverse proxy settings.
- Enforces Principle IV by keeping application listening ports bound to loopback behind firewall and proxy controls.

### Alternatives Considered
- Direct host port publishing (`0.0.0.0:2283`): Rejected because it bypasses TLS encryption and network firewall access control.
- Nginx or Traefik: Rejected because Caddy is the established homelab2 standard (Phase 3).

---

## 5. Continuous Disaster Recovery & Atomic Database Backup Integration

### Question / Unknown
How should Immich database records, vector search embeddings, and photo library files be atomically captured and integrated into the host Restic + Backblaze B2 pipeline in compliance with Constitution Principle V?

### Decision
- Deploy pre-backup and post-restore hook: `/etc/homelab/backup.d/30-immich.sh`.
- **Pre-Backup Workflow**:
  1. Invokes PostgreSQL atomic dump:
     `docker compose exec -T database pg_dump -U immich -d immich --clean --if-exists --format=custom -f /backups/immich_db_backup.dump`
  2. Verifies dump artifact exists and is non-empty (`test -s /opt/services/immich/backups/immich_db_backup.dump`).
  3. Sets restrictive permissions (`0640`) on the dump artifact.
- **Offsite Restic Inclusion**:
  - `/opt/services/immich` (configuration `.env`, `compose.yml`, and `backups/immich_db_backup.dump`) is captured by Restic into Backblaze B2.
  - `/mnt/storage/media/photos/library` is included in the offsite backup stream for irreplaceable photos.
- **Offsite Restic Exclusion**:
  - `/opt/services/immich/data/postgres` (live database files excluded in favor of atomic dump).
  - `/opt/services/immich/data/thumbs` and `data/model-cache` (excluded; can be regenerated from source media and ML models).
  - `/mnt/storage/media/photos/encoded-video` and `upload` (transient caches excluded).
- **Post-Restore Workflow**:
  - Starts database container and restores dump using `pg_restore` into fresh PostgreSQL instance.

### Rationale
- Taking raw filesystem copies of running PostgreSQL data files results in corrupt or inconsistent database states. A custom-format `pg_dump` provides complete transaction consistency and includes all `pgvecto.rs` vector indices.
- Excluding thumbnails, ML weights, and transcoded videos saves hundreds of gigabytes of costly offsite B2 bandwidth and storage without compromising data safety.

### Alternatives Considered
- Live container filesystem freeze: Rejected due to operational complexity and potential I/O hangs.
- Cold database stops during backups: Rejected because taking Immich down daily for hours disrupts background mobile synchronization.

---

## 6. Service Supervision & Systemd Integration

### Question / Unknown
How should the Immich Docker Compose stack be supervised by the operating system to survive host reboots, manage startup dependencies, and integrate with system logging?

### Decision
- Deploy systemd oneshot wrapper unit: `/etc/systemd/system/immich.service`.
- Configuration:
  - `Requires=docker.service local-fs.target`
  - `After=docker.service network-online.target local-fs.target`
  - `RequiresMountsFor=/opt/services /mnt/storage`
  - `WorkingDirectory=/opt/services/immich`
  - `ExecStart=/usr/bin/docker compose up -d --remove-orphans`
  - `ExecStop=/usr/bin/docker compose down`
  - `ExecReload=/usr/bin/docker compose up -d --remove-orphans`
  - `TimeoutStartSec=300`
- Logs stream to `journald` tagged with unit identifier `immich.service`.

### Rationale
- Enforces strict startup ordering: Immich will not start until Docker is ready and `/mnt/storage` is mounted, preventing accidental writes to an unmounted root directory.
- Standardizes container lifecycle management across all homelab services (`frigate.service`, `vaultwarden.service`, `immich.service`).

---

## 7. Automated Acceptance Verification Suite

### Question / Unknown
How will the deployment be verified against Constitution Principle III (*Zero Automated Test Files, Static Verification & Live Acceptance Verification*)?

### Decision
- Implement `scripts/verify-phase5-immich.sh` (Bash) and `scripts/verify-phase5-immich.ps1` (PowerShell) enforcing the 9-point assertion matrix `IMM-01` through `IMM-09`:
  - `IMM-01`: Systemd service `immich.service` is active, all 4 containers running, zero crash loops.
  - `IMM-02`: HTTP ping probe `/api/server/ping` returns HTTP 200 within 500ms.
  - `IMM-03`: Intel UHD Graphics 770 iGPU node passed through; AMD GPU unreferenced.
  - `IMM-04`: Storage layout verified: NVMe (`/opt/services/immich`) and MergerFS (`/mnt/storage/media/photos`).
  - `IMM-05`: Secret isolation: `.env` mode `0600`, `.env.example` committed, zero git secret leaks.
  - `IMM-06`: Caddy drop-in config validated via `caddy validate`.
  - `IMM-07`: File ownership: `PUID=1000` / `PGID=1001` aligned on storage paths.
  - `IMM-08`: Backup hook `/etc/homelab/backup.d/30-immich.sh` generates valid non-empty database dump.
  - `IMM-09`: Journald and container logs stream without unhandled exception tracebacks.
- Integrate into Ansible verification playbook `ansible/playbooks/verify-phase5-immich.yml` and master `ansible/playbooks/verify.yml`.
- In strict adherence to Principle III, zero unit test suites (`pytest`, `jest`, test mocks) are created anywhere in the workspace.
