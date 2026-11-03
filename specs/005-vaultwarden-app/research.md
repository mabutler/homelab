# Research: Vaultwarden Application Deployment & Resiliency

**Feature**: `005-vaultwarden-app` | **Date**: 2026-11-01

## Executive Summary

Phase 5 introduces the application platform layer to `homelab2`, beginning with Vaultwarden as the inaugural stateful service deployed to production target `admin@192.168.4.57`. This research resolves technical unknowns regarding container engine selection, database concurrency and transactional backup routines, reverse proxy ingress drop-in structure, and least-privilege secret management.

---

## 1. Container Runtime & Stack Management

### Decision
Deploy Docker CE with the Docker Compose plugin (`docker` and `docker-compose` on Arch Linux) managed through declarative Compose files at `/opt/services/vaultwarden/compose.yml`, orchestrated via a dedicated systemd service unit (`vaultwarden.service`).

### Rationale
- **Declarative & Standardized**: Conforms directly to the roadmap specification (`/opt/services/<app>/compose.yml`).
- **Lifecycle Integration**: A systemd unit running `docker compose up --detach` and `docker compose down` links container lifecycle to systemd startup/shutdown order, restart policies, and journald telemetry.
- **Portability & Upstream Alignment**: Vaultwarden's primary upstream distribution format is OCI container images (`vaultwarden/server`).

### Alternatives Considered
- **Podman with Quadlets**: Podman Quadlets are clean, but Docker Compose remains the widely documented standard across homelab services. Adding Docker and `docker-compose-plugin` creates a uniform execution engine for all Phase 5 apps (Home Assistant, Immich, Frigate, Vaultwarden).
- **Bare-metal binary compilation**: Compiling Vaultwarden from Rust source directly on the host increases build time, package dependency churn, and maintenance toil, violating Principle VII (Stability-First & Low Toil).

---

## 2. Database Engine & Write Durability

### Decision
Utilize SQLite with Write-Ahead Logging (WAL) enabled (`ENABLE_DB_WAL=true`), stored on the Tier 0 Fast NVMe App Data tier at `/opt/services/vaultwarden/data/db.sqlite3`.

### Rationale
- **Zero Daemon Overhead**: Sized for household scale (1–10 users). Avoids running a separate database daemon (PostgreSQL/MySQL), reducing CPU, memory footprint, and network latency (Principle Operational Standards: Minimalist Footprint).
- **Concurrent Non-Blocking Reads**: SQLite WAL mode permits multiple concurrent read queries while a write operation is in-flight, preventing database locks during sync operations.
- **ACID Crash Resilience**: Coupled with NVMe storage and synchronous mode, WAL ensures full transactional durability even in unexpected power interruption scenarios.

### Alternatives Considered
- **PostgreSQL**: While supported by Vaultwarden, a dedicated PostgreSQL database container introduces ~150MB baseline RAM usage, connection management overhead, and separate backup mechanics without tangible benefit for household concurrency.

---

## 3. Online Transactional Backup & Restore Strategy

### Decision
Implement an automated host-level backup script (`/opt/services/vaultwarden/scripts/backup.sh`) scheduled via systemd timer (`vaultwarden-backup.timer`), utilizing SQLite `VACUUM INTO` / `.backup` to generate an atomic, crash-consistent snapshot of `db.sqlite3` while the container is actively running. Verify backup integrity immediately using `sqlite3 <snapshot> "PRAGMA integrity_check;"`, bundle file attachments and configuration into a timestamped gzip archive, and enforce a 30-day retention pruning policy.

### Rationale
- **Zero Service Interruption**: `VACUUM INTO` is natively atomic and transactional in SQLite 3.27+. It generates a clean point-in-time copy without taking down the Vaultwarden container or locking out client synchronization.
- **Continuous Backup Gate Compliance**: Adheres directly to Constitution Principle V and the Phase 5 mandatory per-application backup gate.
- **Automated Quality Verification**: Calling `PRAGMA integrity_check;` immediately after snapshot creation catches corruption early before the archive is marked successful.
- **Rapid Disaster Recovery**: Restoring consists simply of untarring the backup bundle into `/opt/services/vaultwarden/data` and restarting the container (completes in < 2 minutes).

### Alternatives Considered
- **Raw filesystem copy (`cp db.sqlite3`)**: Dangerous with active SQLite WAL databases; copying while active writes are occurring can yield a torn or corrupted database snapshot.
- **Stopping container during backup**: Guarantees consistency but causes periodic client disconnection and sync errors, violating the zero-downtime requirement.

---

## 4. Ingress & Reverse Proxy Integration

### Decision
Integrate Vaultwarden with the existing Caddy reverse proxy via a modular configuration drop-in `/etc/caddy/conf.d/20-vaultwarden.caddy`. Bind the Vaultwarden container's web port exclusively to loopback (`127.0.0.1:8088`). Forward traffic from Caddy using `reverse_proxy 127.0.0.1:8088`.

### Rationale
- **Single Port WebSocket Routing**: Modern Vaultwarden releases integrate WebSocket notifications (`/notifications/hub`) on the primary Rocket HTTP port. Caddy's `reverse_proxy` directive automatically handles HTTP/1.1 WebSocket upgrade handshakes and HTTP/2 multiplexing out of the box.
- **TLS Enforcement**: Caddy automatically manages internal TLS certificates (`tls internal`) or ACME certificates, satisfying modern browser/mobile WebCrypto encryption prerequisites (FR-006).
- **Network Boundary Security**: Binding to `127.0.0.1` prevents raw container port exposure on untrusted physical or overlay interfaces. Only the hardened reverse proxy communicates with the backend container.

### Alternatives Considered
- **Exposing port 80/443 directly from container**: Conflicts with Caddy, breaks centralized ingress routing, and complicates TLS certificate management.
- **Separate port 3012 WebSocket proxying**: Legacy Vaultwarden required a dedicated WebSocket port (`WEBSOCKET_PORT=3012`). Modern Vaultwarden versions natively handle `/notifications/hub` on Rocket's primary port, rendering secondary port mappings redundant.

---

## 5. Security Hardening & Secret Isolation

### Decision
- **Non-Root Execution**: Run Vaultwarden with non-root ownership (`PUID=1000`, `PGID=1000` or dedicated `vaultwarden` service account UID/GID), with restricted directory permissions (`0750` / `0700`) on `/opt/services/vaultwarden`.
- **SOPS Secret Decoupling**: Store the admin interface secret (`ADMIN_TOKEN`) in the SOPS-encrypted `ansible/inventory/group_vars/all/vault.sops.yml`. At provisioning time, Ansible securely renders `/opt/services/vaultwarden/.env` with `0600` permissions.
- **Argon2id Hashed Token**: Store `ADMIN_TOKEN` as an Argon2id PHC string generated via `vaultwarden hash` (or Python `argon2_cffi`), protecting the admin portal even if the `.env` file were compromised.
- **Public Signups Disabled**: Set `SIGNUPS_ALLOWED=false` and `INVITATIONS_ALLOWED=true` to prevent unauthorized self-registration from discovered ingress routes.

### Rationale
- Complies with Principle IV (Zero Cleartext Secrets) and Principle VI (Least Privilege Execution).
- Argon2id hashing prevents rainbow-table or brute-force recovery of the master admin secret.

---

## 6. Telemetry & Acceptance Verification Architecture

### Decision
Create automated verification scripts (`scripts/verify-phase5-vaultwarden.sh` and `ansible/playbooks/verify-phase5.yml`) that test:
1. Docker daemon and systemd unit health (`systemctl is-active vaultwarden.service`).
2. Container non-root process ownership and directory permissions.
3. Vaultwarden HTTP endpoint response (`curl -fsS http://127.0.0.1:8088/alive` -> 200 OK).
4. Caddy reverse proxy HTTPS routing and TLS termination.
5. Caddy `/notifications/hub` WebSocket upgrade handshake (verifying HTTP 101 Switching Protocols or WebSocket headers).
6. Execution of the transactional backup routine, verifying `PRAGMA integrity_check` clean exit and backup file creation.
7. Verification that zero cleartext secrets exist in git.

### Rationale
- Directly satisfies Constitution Principle III and the mandatory Phase 5 per-application completion gate.
- Enables continuous automated testing and regression detection on every deployment.
