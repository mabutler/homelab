# Feature Specification: Immich Photo Management Platform Deployment

**Feature Branch**: `013-immich-setup`

**Created**: 2026-11-06

**Status**: Draft

**Input**: User description: "I think immich is the next app to install" (Phase 5 of repository Roadmap: Application Platform & Continuous Backblaze Backups)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Self-Hosted Photo and Video Management & Seamless Ingest (Priority: P1)

As a household member and homelab user, I want a high-performance self-hosted photo and video management platform accessible from desktop web browsers and mobile devices, so that I can automatically back up, catalog, view, search, and share my family photo and video collection without relying on commercial cloud photo services.

**Why this priority**: Photo and video preservation is a core pillar of the homelab application tier. Immich provides a modern, responsive user experience comparable to commercial alternatives while keeping personal memories completely private and under local ownership.

**Independent Test**: Can be tested independently by logging into the web interface, uploading photo and video files via web and mobile client interfaces, verifying that media assets appear immediately on the chronological timeline, and confirming smooth playback of high-definition video assets.

**Acceptance Scenarios**:

1. **Given** an operational photo management service, **When** an authenticated user uploads image files (JPEG, PNG, HEIC, RAW) via web or mobile application, **Then** files are safely stored, cataloged, and rendered in chronological order on the user's timeline.
2. **Given** uploaded video assets, **When** a user initiates playback from a browser or mobile device, **Then** video streams smoothly with adaptive transcoding and proper audio-video synchronization.
3. **Given** a collection of cataloged photos, **When** a user browses the gallery, **Then** pre-generated thumbnails and EXIF metadata (camera model, exposure, capture date, geolocation) load with low visual latency.
4. **Given** multiple household users, **When** individual accounts are established, **Then** user photo libraries remain completely isolated by default with opt-in shared album capabilities.

---

### User Story 2 - Resilient Multi-Tier Storage Architecture (Priority: P1)

As a homelab systems architect, I want service state partitioned across storage tiers—placing databases, caches, and thumbnails on high-speed NVMe storage while preserving original photos and videos on pooled mass storage—so that interactive responsiveness remains fast without exhausting high-speed storage or risking photo library integrity.

**Why this priority**: Media libraries grow to multiple terabytes, exceeding cost-effective NVMe capacity. Splitting storage ensures fast database queries and responsive thumbnail feeds while storing bulk media on resilient, pooled disks.

**Independent Test**: Can be tested independently by verifying directory mappings and filesystem mounts: confirming that database files, vector tables, and thumbnails reside on `/opt/services/immich`, while original full-resolution media files are written directly to `/mnt/storage/media/photos` with proper group ownership (`PUID`/`PGID`).

**Acceptance Scenarios**:

1. **Given** the service storage topology, **When** database transactions and thumbnail caching occur, **Then** all read and write I/O operations execute against the NVMe application tier (`/opt/services/immich`).
2. **Given** a newly uploaded full-resolution photo or video asset, **When** written to persistent storage, **Then** the file is placed within the pooled mass storage path (`/mnt/storage/media/photos`) preserving the original file without lossy re-encoding.
3. **Given** multiple system services accessing shared media directories, **When** files are created by the photo service, **Then** permissions and ownership align with the homelab storage group standard (`PUID=1000`/`PGID=1001`, group `storage`), preventing access contention.

---

### User Story 3 - Hardware-Accelerated Video Transcoding & Machine Learning (Priority: P2)

As a homelab administrator, I want the photo management service to utilize host graphics hardware (`/dev/dri`) for video decoding/transcoding and machine learning inference (facial recognition, CLIP semantic search), so that media ingest and search indexing run with low latency without starving host CPU resources.

**Why this priority**: Video transcoding and machine learning are computationally intensive. Utilizing hardware acceleration ensures rapid processing of newly ingested media while keeping overall system resource consumption within bounded platform limits.

**Independent Test**: Can be tested independently by ingesting a video requiring transcoding and triggering a machine learning indexing job, verifying that GPU/iGPU device handles (`/dev/dri`) are accessed and host CPU utilization remains bounded.

**Acceptance Scenarios**:

1. **Given** an uploaded video in a high-bitrate or non-native browser format, **When** background transcoding commences, **Then** hardware video acceleration processes the stream without exceeding general host CPU thresholds.
2. **Given** newly uploaded photos, **When** the machine learning engine processes image recognition and semantic indexing, **Then** models execute inference utilizing available hardware acceleration without causing service unresponsiveness.
3. **Given** a host environment without discrete graphics, **When** configuring the service, **Then** the stack defaults to available integrated graphics acceleration or graceful fallback without crashing container services.

---

### User Story 4 - Continuous Disaster Recovery & Atomic Database Backups (Priority: P1)

As a homelab operator, I want automated, consistent database dumps (capturing relational tables and vector embeddings) synchronized with the host's centralized Backblaze B2 and Restic backup pipeline, so that the entire photo catalog and user configuration can be reliably restored following hardware loss.

**Why this priority**: In accordance with Constitution Principle V (Disaster Recovery & Backup by Design) and Phase 5 completion gates, each application must verify its backup strategy and offsite integration before sign-off. Photo metadata and facial recognition embeddings must be atomically backed up alongside library files.

**Independent Test**: Can be tested independently by executing the service backup hook, verifying that an atomic PostgreSQL dump (including vector tables) is generated, confirming data integrity, and verifying that the snapshot is captured by the Restic backup runner into Backblaze B2.

**Acceptance Scenarios**:

1. **Given** an active photo management deployment, **When** the scheduled backup routine executes, **Then** an atomic database dump is generated without interrupting active client uploads or causing database lockouts.
2. **Given** generated backup artifacts, **When** validated by automated verification routines, **Then** database dump integrity and companion configuration files are confirmed non-empty and restorable.
3. **Given** the host Restic backup pipeline, **When** the offsite backup snapshot runs, **Then** database dumps and service configuration are included in the offsite replication target.
4. **Given** a disaster recovery scenario, **When** restoring from backup onto a clean host, **Then** user accounts, albums, metadata, and search embeddings are completely restored.

---

### User Story 5 - Automated Health Telemetry & Service Observability (Priority: P2)

As an operator and automated monitor, I want automated health assertion scripts, uptime probes, and structured journal telemetry integrated into the service deployment, so that container degradation, database disconnects, or storage unreachability are detected and reported promptly.

**Why this priority**: In accordance with Constitution Principle III (Automated Verification & Continuous Telemetry Gates), Phase 5 applications require explicit health assertions (`/api/server/ping`, container status, ML reachability) and structured logging before deployment sign-off.

**Independent Test**: Can be tested independently by running the automated acceptance script (`scripts/verify-phase5-immich.sh` or equivalent), verifying HTTP 200 responses from `/api/server/ping`, inspecting container health status, and confirming that structured log messages flow to system log sinks.

**Acceptance Scenarios**:

1. **Given** a healthy photo service stack, **When** an automated health probe queries `/api/server/ping`, **Then** the endpoint returns HTTP 200 OK within 500 milliseconds.
2. **Given** an impaired component (e.g., database connection loss or machine learning service failure), **When** health assertions run, **Then** the probe fails fast with actionable diagnostic output indicating the exact failure reason.
3. **Given** active service operations, **When** administrative or user actions take place, **Then** structured operational log records stream to system log sinks (`journald`) without leaking user credentials, session tokens, or private metadata.

---

### User Story 6 - Reverse Proxy Ingress & Network Security (Priority: P2)

As a security-conscious administrator, I want the photo management service published behind the reverse proxy with automated TLS termination and optimized upload buffering, so that connections over local networks and Tailscale VPN overlays remain encrypted and large multi-gigabyte media uploads do not timeout.

**Why this priority**: Reverse proxy integration guarantees encrypted transport across all client connections, provides friendly domain routing, and protects internal application ports from unauthenticated exposure.

**Independent Test**: Can be tested independently by issuing HTTPS requests to the photo service hostname through the reverse proxy, verifying TLS certificate validity, uploading a large video file (> 1 GB), and verifying persistent WebSocket connectivity for client notifications.

**Acceptance Scenarios**:

1. **Given** the reverse proxy configuration, **When** an incoming request arrives over an authorized network interface, **Then** traffic is routed securely to the internal photo service loopback binding.
2. **Given** a client uploading a large video file (e.g., 2 GB+), **When** transmitting data through the reverse proxy, **Then** the proxy allows the upload without HTTP 413 (Payload Too Large) or client timeout errors.
3. **Given** real-time status updates and background task notifications, **When** clients connect via WebSockets, **Then** the reverse proxy maintains bidirectional persistent connections without dropped frames.

---

### Edge Cases

- **Storage Pool Unavailability**: What happens if `/mnt/storage` is temporarily unmounted or fails during an upload?
  *Requirement: The service must fail closed and reject uploads with an informative error rather than silently writing raw media files to the root or NVMe filesystem.*
- **Abrupt Power Loss or Host Reboot**: How does the system handle database state when interrupted mid-transaction?
  *Requirement: PostgreSQL write-ahead logging (WAL) and atomic container shutdown signals ensure transactional consistency; pending ingest tasks resume cleanly upon system boot.*
- **Storage Exhaustion on NVMe**: What happens if thumbnail generation or transcode caching consumes remaining NVMe space?
  *Requirement: Storage capacity must be bounded; cache cleanup policies must prune old transcode artifacts before critical database operations are starved.*
- **Non-Standard or Raw Media Formats**: How does the system process specialized camera RAW files or Apple Live Photos?
  *Requirement: The service preserves original media files bit-for-bit while generating standard web-compatible preview thumbnails and video companions for interactive viewing.*
- **Large Video Transcode Timeout**: What happens when a user requests an unusually long or high-bitrate video?
  *Requirement: Transcoding pipelines must stream progressive segments with adaptive buffering to prevent client timeouts.*

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST deploy Immich as a containerized stack (Server, Machine Learning, PostgreSQL with `pgvector`, and Redis) orchestrated via Docker Compose and supervised by systemd.
- **FR-002**: System MUST store persistent databases, vector index embeddings, Redis cache, thumbnails, and machine learning models on high-speed NVMe storage at `/opt/services/immich`.
- **FR-003**: System MUST store primary full-resolution photo and video libraries on pooled storage at `/mnt/storage/media/photos`.
- **FR-004**: System MUST execute container processes under explicit user and group permissions (`PUID`/`PGID`) matching the homelab storage management group to guarantee consistent file access across services.
- **FR-005**: System MUST configure host device passthrough (`/dev/dri`) to grant container services access to hardware video acceleration and ML compute.
- **FR-006**: System MUST integrate service web and API ingress behind the Caddy reverse proxy bound to loopback `127.0.0.1`, terminating TLS and supporting large payload streaming and WebSockets.
- **FR-007**: System MUST provide an automated database backup hook executing atomic PostgreSQL dumps (including vector data) integrated with the host Restic backup framework and Backblaze B2 replication.
- **FR-008**: System MUST implement an automated verification and telemetry script asserting container health, `/api/server/ping` HTTP 200 response, database connectivity, and hardware transcode capability.
- **FR-009**: System MUST isolate all credentials, database passwords, and cryptographic keys in gitignored configuration files with committed `.example` template companions in compliance with Constitution Principle IV.
- **FR-010**: System MUST configure structured logging directed to standard system sinks (`journald`) with sensitive authentication tokens and credentials redacted in compliance with logging standards.
- **FR-011**: In accordance with Constitution Principle III, verification MUST rely exclusively on static analysis, configuration linting (`ansible-lint`, `shellcheck`), and live acceptance verification scripts—generating ZERO automated unit test suites, test mocks, or test frameworks.

### Key Entities *(include if feature involves data)*

- **Media Asset**: Represents an ingested photo, video, or composite Live Photo, including original binary storage path, unique checksum, capture timestamp, EXIF metadata, and resolution attributes.
- **Vector Embedding**: High-dimensional vector array generated by the machine learning service (stored in PostgreSQL via `pgvector`) representing facial features, image objects, and semantic concepts for similarity search.
- **Album / Collection**: User-defined or smart virtual grouping of Media Assets with permission scopes, ordering, and optional shared access tokens.
- **User Account**: Administrative or household user profile defining authentication credentials, library boundaries, and storage consumption.
- **Backup Snapshot**: Consistent database dump archive and companion configuration snapshot captured for offsite disaster recovery replication.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can upload a 100MB batch of photos and view them rendered in chronological order on their timeline within 30 seconds of upload completion.
- **SC-002**: Cached gallery browsing and thumbnail rendering achieve visual response times of under 500 milliseconds per viewport scroll.
- **SC-003**: Video playback begins streaming to connected client devices within 2 seconds of user selection.
- **SC-004**: Automated health assertion probes verify service ping (`/api/server/ping`) and container reachability in under 500 milliseconds per invocation.
- **SC-005**: Scheduled atomic database backups execute without service downtime, write locks, or user-facing error rates exceeding 0%.
- **SC-006**: Disaster recovery procedures verify 100% restoration of user accounts, photo libraries, and search metadata from offsite backup archives.
- **SC-007**: Hardware-accelerated video decoding maintains host general CPU utilization below 50% during active single-stream transcode operations.
- **SC-008**: Zero cleartext secrets, database credentials, or tokens are committed to repository version control.

## Assumptions

- Docker CE and Docker Compose are installed and operational on the host system.
- Caddy reverse proxy is deployed and managing TLS certificates across homelab network overlays (Phase 3).
- Storage pooling (`/mnt/storage`) and NVMe application storage (`/opt/services`) are active, mounted, and operational (Phase 4).
- Backblaze B2 and Restic backup infrastructure (Feature 006) is configured with operational backup timers and hook directories (`/etc/homelab/backup.d/`).
- Host machine is equipped with graphics hardware supporting `/dev/dri` device access for video acceleration.
- In accordance with Constitution Principle III, zero automated test files, test suites, or test harnesses are generated; verification is performed exclusively via declarative syntax checks, linters (`ansible-lint`, `shellcheck`), and live acceptance scripts.
