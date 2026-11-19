# Feature Specification: Media & Arr Stack — Stage 1 (Core Media & VPN Download Foundation)

**Feature Branch**: `015-media-arr-stage1`

**Created**: 2026-11-17

**Status**: Draft

**Input**: User description: "Let's implement stage 1 of the Media and Arr stack"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Hardware-Accelerated Household Media Streaming (Priority: P1)

As a household media consumer, I want a private self-hosted media server that organizes our movie and TV show collections and streams them smoothly to browsers, TVs, and mobile devices using hardware-accelerated transcoding, so that family members can watch media across any device without buffering or overloading the server.

**Why this priority**: Delivering reliable, private media playback is the primary end-user value of Stage 1 and establishes the media library foundation that all subsequent Media & Arr stages depend on.

**Independent Test**: Can be tested independently by placing sample movie and TV media files into the library directories, accessing the media server over the internal network, scanning the library, and initiating video playback on a client requiring transcoding while confirming hardware acceleration is active and host CPU load remains low.

**Acceptance Scenarios**:

1. **Given** an operational media server connected to the movie and TV library folders, **When** a household user signs in over the internal network and triggers a library scan, **Then** movies and TV episodes are indexed with metadata and displayed in the media catalog.
2. **Given** a video file requiring format or bitrate adaptation for a playback device, **When** a user starts playback, **Then** video transcoding runs via host integrated graphics acceleration with smooth audio-video synchronization and bounded host CPU usage.
3. **Given** multiple household user profiles, **When** each member accesses the media server, **Then** watch history, playback progress, and library access permissions remain cleanly isolated per user.

---

### User Story 2 - VPN-Isolated Download Foundation with Strict Kill-Switch (Priority: P1)

As a privacy- and security-conscious homelab operator using WireGuard through Tailscale (Mullvad VPN exit nodes or a dedicated Tailscale exit node), I want all torrent download client traffic routed exclusively through a dedicated containerized VPN gateway with a strict kernel firewall kill-switch, so that no download traffic can ever leak over the host's public internet connection if the VPN exit node disconnects, while keeping the host's own Tailscale Funnel and LAN services completely unaffected.

**Why this priority**: Unprotected torrent traffic over the host public network violates operator privacy and network policy. Establishing the dedicated VPN container + kill-switch architecture in Stage 1 is a mandatory prerequisite before any automated media acquisition services are introduced.

**Independent Test**: Can be tested independently by checking the external IP observed from inside the download client's network context to confirm it matches the Tailscale Mullvad / VPN exit node rather than the host public IP, verifying the host's own WAN IP and Tailscale Funnel remain unchanged, and testing an exit-node interruption to verify all outbound download connectivity halts immediately with zero fallback to the host network.

**Acceptance Scenarios**:

1. **Given** an active VPN gateway container (`arr_vpn`) connected to the configured Tailscale Mullvad exit node (or standalone WireGuard provider), **When** the download client establishes outbound peer connections, **Then** 100% of download traffic traverses the encrypted WireGuard VPN tunnel (`tailscale0` / `tun0`) and its observed external IP differs from the host public IP.
2. **Given** an operational download client (`arr_qbittorrent`, running as `UID 1000`) isolated inside the VPN gateway's network boundary (`service:vpn`), **When** the VPN tunnel or exit node drops or fails health checks, **Then** the kernel netfilter kill-switch blocks all non-tunnel traffic (`eth0` and unrouted `tailscale0`) immediately so zero packets route through the host public interface.
3. **Given** active or completed download tasks, **When** the operator manages downloads through the download client web interface, **Then** the interface is reachable only over the internal private network and never exposed to the public internet.

---

### User Story 3 - Three-Tier Storage Architecture & Unified Permissions (Priority: P1)

As a homelab systems architect, I want service configurations, active incomplete downloads, and finalized media libraries placed on their designated storage tiers with unified storage-group ownership, so that active torrent swarming never causes parity disk churn, service databases remain fast on solid-state storage, and future automated media organizers can perform instant atomic file moves within a single storage pool.

**Why this priority**: Misplaced downloads or mismatched file permissions cause severe disk thrashing, unnecessary parity recalculations, and duplicated disk writes when organizing media. Establishing the exact directory and permission layout in Stage 1 prevents costly data migrations later.

**Independent Test**: Can be tested independently by inspecting storage path mappings, verifying parity exclusion rules for download directories, creating a test download file, and confirming consistent directory and file permissions across configuration, active scratch, completed download, and media library paths.

**Acceptance Scenarios**:

1. **Given** the Stage 1 stack, **When** services write configuration files, VPN state, and internal databases, **Then** all state persists on the fast NVMe application storage tier with directory scaffolding ready for future Stage 2 additions.
2. **Given** an active in-progress download, **When** torrent pieces are being written, **Then** incomplete data resides exclusively on the dedicated non-parity scratch storage tier.
3. **Given** a finished download moved to completion or media stored in the library, **When** written to the pooled mass storage tier, **Then** completed downloads and media libraries share a single storage pool mount supporting atomic renames, parity protection covers media while excluding downloads, and shared storage-group permissions apply consistently.

---

### User Story 4 - Internal-Only Reverse Proxy Ingress & Credential Isolation (Priority: P2)

As a security-conscious administrator, I want Stage 1 web interfaces bound strictly to internal host loopback and published only over the private mesh/LAN via the reverse proxy, with all Tailscale/VPN auth keys and service credentials isolated in encrypted secret storage, so that household media tools remain convenient to use without any public internet attack surface or credential exposure.

**Why this priority**: Unlike public-facing services, media management and download interfaces must never be reachable from the open internet. Loopback binding, internal-only reverse proxy routing, and encrypted secret isolation enforce homelab security boundaries from day one.

**Independent Test**: Can be tested independently by verifying service ports listen exclusively on host loopback, accessing the media and download web interfaces over the private mesh/LAN to confirm HTTPS reachability, verifying public/untrusted interfaces reject access, and scanning version-controlled files to confirm zero plaintext secrets are committed.

**Acceptance Scenarios**:

1. **Given** running Stage 1 services, **When** host listening sockets are inspected, **Then** web interface ports bind strictly to local loopback and never to all external interfaces.
2. **Given** the internal reverse proxy routing configuration, **When** an authorized client on the private mesh VPN or trusted LAN accesses the media server or download client URLs, **Then** requests route cleanly over HTTPS while untrusted public connections are rejected.
3. **Given** sensitive Tailscale auth keys, VPN keys, and service passwords, **When** deployment automation converges the stack, **Then** secrets are sourced solely from encrypted gitignored vaults and restricted host environment files while only template examples exist in version control.

---

### User Story 5 - Continuous Backup Integration & Live Telemetry Verification (Priority: P1)

As a homelab operator, I want automated consistent database and configuration backups integrated into the host offsite backup pipeline and an automated live acceptance check verifying VPN exit-node isolation, kill-switch enforcement, service health, hardware acceleration, and storage invariants, so that Stage 1 satisfies platform backup and telemetry completion gates before any Stage 2 services are added.

**Why this priority**: Platform governance forbids marking any application deployment complete until both its backup strategy and live telemetry/health verification gates pass.

**Independent Test**: Can be tested independently by invoking the pre-backup hook to confirm consistent database snapshots and service configurations are staged while media libraries and download caches are excluded, and by running the live acceptance verification command to confirm all checks pass with structured output.

**Acceptance Scenarios**:

1. **Given** an active Stage 1 deployment, **When** the scheduled pre-backup hook executes, **Then** consistent online database snapshots (verified for integrity) and service configurations are staged cleanly for offsite backup without stopping the media server.
2. **Given** the host offsite backup rules, **When** backup inclusion and exclusion patterns are evaluated, **Then** service configurations and database snapshots are captured while bulk media libraries and download caches are excluded.
3. **Given** a converged host, **When** the operator executes the acceptance verification suite, **Then** all health, VPN external IP, kill-switch, network isolation, hardware acceleration, ingress, storage, permission, and backup checks pass and emit structured telemetry without leaking credentials.

---

### Edge Cases

- **VPN Exit Node Drop, Deselection, or Authentication Failure**: What happens if the Tailscale Mullvad exit node (or WireGuard endpoint) becomes unreachable, has not been granted the `mullvad` node attribute in Tailscale Admin Console, or disconnects?
  *Requirement: The VPN gateway kernel netfilter kill-switch (`iptables`/`ip6tables` owner-match `DROP` on `eth0` and conditional `tailscale0` guard) MUST block all outbound download traffic (`UID 1000`) immediately; traffic MUST NOT silently fall back to the host public network interface or unrouted tailnet.*
- **Host Tailscale Funnel Isolation**: What happens to host `fidelacchius` services (such as Vaultwarden Tailscale Funnel on port 443, SSH, Immich, and Backblaze B2 backups) when the download VPN is active?
  *Requirement: The VPN gateway MUST run inside an isolated container network namespace (`arr_vpn`) with its own Tailscale state (`/opt/services/arr/vpn/config`) so the host `tailscaled` daemon never routes host traffic through the Mullvad exit node.*
- **Storage Mount Unavailability**: What happens if the pooled storage mount or scratch mount is unmounted or unavailable?
  *Requirement: Service startup and verification MUST fail closed with an actionable diagnostic error rather than allowing services to write gigabytes of media or downloads into the root OS filesystem.*
- **Hardware Transcode Device Access Failure**: What happens if host graphics device permissions or driver configuration are missing or misconfigured?
  *Requirement: Verification probes MUST detect missing hardware transcode device access and fail fast rather than silently falling back to CPU-intensive software transcoding.*
- **Database Write Contention During Backup**: What happens if scheduled offsite backups run while the media server is actively scanning libraries or tracking playback?
  *Requirement: The pre-backup hook MUST capture consistent online database snapshots and verify snapshot integrity before offsite upload, preventing database locks or corrupted copies.*
- **Future Stage 2 Extensibility**: What happens when virtual TV channels, media requests, or automated indexers/managers are added in Stages 2A, 2B, and 2C?
  *Requirement: Stage 1 directory scaffolding, unified storage-group permissions, single-pool layout, modular reverse proxy drop-in, and pre-backup hook MUST support additive Stage 2 deployment without migrating or re-permissioning Stage 1 data.*

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST deploy Stage 1 of the Media & Arr stack (`vpn` [`arr_vpn`], `qbittorrent` [`arr_qbittorrent`], and `jellyfin` [`arr_jellyfin`]) as a modular Docker Compose stack supervised by systemd (`arr.service`), scoped strictly to Stage 1 runtime containers while preserving clean extensibility for future Stages 2A, 2B, and 2C.
- **FR-002**: System MUST isolate `qbittorrent` inside the `vpn` container network namespace (`network_mode: "service:vpn"`) with an active kernel netfilter (`iptables`/`ip6tables`) kill-switch. By default (`arr_vpn_mode: "tailscale"`), `arr_vpn` MUST run a dedicated Tailscale WireGuard gateway container (`ghcr.io/tailscale/tailscale:v1.76.6`) connected to a configured Tailscale Mullvad or custom exit node (`TS_EXIT_NODE`) with an owner-match netfilter kill-switch (`/opt/services/arr/vpn/killswitch.sh` and `healthcheck.sh`) that unconditionally drops all non-tunnel `UID 1000` (`qbittorrent`) traffic on `eth0`/IPv6 and halts traffic if the exit node disconnects (`arr_vpn_mode: "gluetun"` using `ghcr.io/qdm12/gluetun:v3.39.1` MAY optionally be selected for standalone WireGuard/OpenVPN configs).
- **FR-003**: System MUST configure `jellyfin` with media library mounts pointing to `/mnt/storage/media/movies` and `/mnt/storage/media/tv` and pass through host Intel UHD 770 integrated graphics (`/dev/dri/by-path/pci-0000:00:02.0-render` and `pci-0000:00:02.0-card`, `LIBVA_DRIVER_NAME=iHD` QSV/VAAPI) for hardware-accelerated video transcoding while keeping the discrete AMD GPU (`03:00.0`) completely isolated.
- **FR-004**: System MUST enforce the three-tier storage layout: Tier 0 NVMe configs and SQLite databases under `/opt/services/arr/{vpn,gluetun,qbittorrent,jellyfin}/config` (with directory scaffolding cleanly supporting future Stage 2A/2B/2C service directories under `/opt/services/arr/{ersatztv,jellyseerr,prowlarr,radarr,sonarr}/config`), Tier 2 scratch incomplete downloads under `/mnt/scratch/downloads/incomplete`, and Tier 1 MergerFS completed downloads and media libraries under `/mnt/storage/downloads/complete` and `/mnt/storage/media/{movies,tv}` sharing the single `/mnt/storage` mount (`atomic_rename` enabled).
- **FR-005**: System MUST configure SnapRAID exclusion rules so `/downloads/` is excluded from parity calculations while `/media/` remains parity-protected.
- **FR-006**: System MUST execute Stage 1 media and download workloads with unified non-root ownership (`PUID=1000`, `PGID=1001` matching the `storage` group) and `UMASK=002` (`2775` directories and `664` files) to guarantee cross-service file access interoperability.
- **FR-007**: System MUST bind all Stage 1 Web UI ports strictly to host loopback (`127.0.0.1`) and expose them exclusively over Tailscale/LAN via a dedicated Caddy drop-in (`/etc/caddy/conf.d/40-arr.caddy`), prohibiting public internet exposure.
- **FR-008**: System MUST implement an automated pre-backup hook (`/etc/homelab/backup.d/40-arr.sh`) that creates integrity-checked online SQLite database snapshots (`VACUUM INTO` + `PRAGMA integrity_check`) and captures XML/YAML/JSON/CONF service configurations for deployed Stage 1 services (`jellyfin`, `qbittorrent`, `vpn`/`gluetun`) into the host Restic/Backblaze B2 backup pipeline, while excluding bulk media libraries and download caches from offsite backups.
- **FR-009**: System MUST provide idempotent convergence tooling (`scripts/apply-phase5-arr.sh` and `scripts/apply-phase5-arr.ps1`) and an automated live acceptance verification suite (`scripts/verify-phase5-arr.sh` and `scripts/verify-phase5-arr.ps1`) asserting: `arr.service` active status, `arr_vpn` exit-node tunnel health, external VPN IP differs from host WAN IP, kernel netfilter kill-switch active, `qbittorrent` network namespace isolation, Jellyfin `/health` HTTP 200, qBittorrent WebUI HTTP 200, internal Caddy ingress reachability, `/dev/dri` hardware acceleration access, storage mount/permission/SnapRAID-exclusion invariants, and backup hook readiness.
- **FR-010**: System MUST isolate all VPN credentials (Tailscale `TS_AUTHKEY` and `TS_EXIT_NODE`, or standalone WireGuard/OpenVPN private keys), WebUI credentials, and sensitive environment variables in gitignored secrets (SOPS/Age vault and `0600` host `.env` files) accompanied by committed `.example` templates, with zero cleartext secrets in version control.
- **FR-011**: System MUST direct service and verification logs to standard system sinks (`journald`, `stdout`, `stderr`) using structured severity levels (`CRITICAL`, `WARN`, `INFO`, `DEBUG`) and redacting all secrets, Tailscale auth keys, VPN keys, and authentication tokens.
- **FR-012**: In accordance with Constitution Principle III, verification MUST rely exclusively on static validation, configuration linting (`ansible-lint`, `shellcheck`, `bash -n`), and live acceptance verification scripts—generating ZERO automated unit test suites, test files, or test mocks.

### Key Entities *(include if feature involves data)*

- **VPN Gateway (`arr_vpn`)**: Isolated network gateway container maintaining an encrypted WireGuard tunnel (via Tailscale Mullvad / Exit Node by default, or Gluetun) and a strict kernel netfilter kill-switch for attached download workloads.
- **Download Client (`arr_qbittorrent`)**: Torrent client operating as `PUID=1000`/`PGID=1001` inside the VPN gateway's network boundary (`service:vpn`), writing active swarms to scratch storage and moving completed payloads to pooled storage.
- **Media Server (`arr_jellyfin`)**: Media catalog and streaming engine serving household movie and TV libraries with hardware-accelerated transcoding and per-user playback state.
- **Three-Tier Media Storage Contract**: Coordinated directory and permission boundary spanning fast application storage (`/opt/services/arr`), non-parity scratch (`/mnt/scratch/downloads/incomplete`), and single-pool completion/library storage (`/mnt/storage`).
- **Backup Snapshot & Acceptance Contract**: Consistent database/config snapshot state produced by the pre-backup hook and live verification assertions enforced by the acceptance suite.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Authorized household users can browse indexed movie and TV libraries and start hardware-accelerated video playback within 3 seconds of selection while keeping host general CPU utilization below 50% during single-stream transcoding.
- **SC-002**: 100% of download client outbound traffic exits through the active VPN exit node tunnel with an external IP distinct from the host public WAN IP, and 0% of traffic leaks onto the host public network if the VPN exit node disconnects.
- **SC-003**: Active incomplete downloads generate zero disk writes to parity-protected media directories, while completed downloads and media libraries reside on the unified storage pool with consistent shared-group permissions (`2775`/`664`).
- **SC-004**: 100% of Stage 1 web interfaces are reachable over internal private network ingress and 0% are exposed on public internet interfaces.
- **SC-005**: Scheduled backup snapshots capture 100% of Stage 1 service configurations and consistent databases with zero media server downtime or database corruption, while excluding 100% of bulk media files and download caches from offsite backup volume.
- **SC-006**: The automated live acceptance verification suite validates all Stage 1 health, VPN IP, kill-switch, ingress, storage, permission, and backup assertions within 30 seconds per run with deterministic pass/fail exit codes.
- **SC-007**: Zero cleartext Tailscale auth keys, VPN credentials, private keys, or service passwords exist in repository version control.

## Assumptions

- Host base OS, container runtime, systemd supervision, reverse proxy (Phase 3), pooled mass storage `/mnt/storage` (`atomic_rename` enabled), parity protection, `/mnt/scratch` (Phase 4), and encrypted offsite backup pipeline (Features 006 / 014) are deployed and operational.
- The host machine provides an active Intel UHD 770 iGPU exposing `/dev/dri` render devices with `iHD` QSV/VAAPI support.
- For the default Tailscale VPN mode (`arr_vpn_mode: "tailscale"`), the operator enables Mullvad VPN exit-node access for the `fidelacchius-arr-vpn` node (or `tag:arr-vpn` ACL `mullvad` nodeAttr) in the Tailscale Admin Console and supplies `vault_arr_tailscale_auth_key` and `vault_arr_tailscale_exit_node` in `ansible/inventory/group_vars/all/vault.yml` prior to live convergence.
- Stage 1 explicitly deploys only `vpn` (`arr_vpn`), `qbittorrent` (`arr_qbittorrent`), and `jellyfin` (`arr_jellyfin`); Stage 2A (`ersatztv`), Stage 2B (`jellyseerr`), and Stage 2C (`prowlarr`, `radarr`, `sonarr`) are deferred to subsequent feature specifications.
- Because `qbittorrent` shares `vpn`'s network namespace (`service:vpn`), loopback port publishing for the qBittorrent WebUI (`127.0.0.1:8080`) is declared on the `vpn` service definition while Caddy proxies internal Tailscale/LAN requests to those loopback endpoints.
- In accordance with Constitution Principle III, zero automated unit test files, test suites, or mock frameworks are created; all verification uses static linting (`ansible-lint`, `shellcheck`, `bash -n`) and live acceptance scripts (`scripts/verify-phase5-arr.sh` / `.ps1`).
