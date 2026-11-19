# Implementation Plan: Media & Arr Stack — Stage 1 (Core Media & VPN Download Foundation)

**Branch**: `015-media-arr-stage1` | **Date**: 2026-11-17 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/015-media-arr-stage1/spec.md`

---

## Summary

Deploy Stage 1 of the Media & Arr Stack (`vpn` [`arr_vpn`], `qbittorrent` [`arr_qbittorrent`], and `jellyfin` [`arr_jellyfin`]) on `fidelacchius` to establish a hardware-accelerated household media streaming platform and a VPN-isolated torrent download foundation using **WireGuard through Tailscale (Mullvad VPN / Exit Node)** (Phase 5 of the repository Roadmap). The technical approach uses a dedicated Ansible role (`ansible/roles/arr`) managing a modular Docker Compose stack supervised by systemd (`arr.service`), consisting of three pinned Stage 1 containers:
1. `vpn` (`arr_vpn`, running `ghcr.io/tailscale/tailscale:v1.76.6` by default when `arr_vpn_mode: "tailscale"`, or `ghcr.io/qdm12/gluetun:v3.39.1` when `arr_vpn_mode: "gluetun"`) — dedicated containerized Tailscale WireGuard gateway authenticating as `fidelacchius-arr-vpn` and routing outbound traffic through a configured Tailscale Mullvad or custom exit node (`TS_EXIT_NODE`), enforced by a kernel netfilter (`iptables`/`ip6tables`) UID-owner kill-switch (`/opt/services/arr/vpn/killswitch.sh`) and exit-node healthcheck (`/opt/services/arr/vpn/healthcheck.sh`). Running Tailscale inside `arr_vpn` keeps the host `fidelacchius` `tailscaled` daemon (which serves Vaultwarden Tailscale Funnel on `100.103.39.60:443`) completely unaffected.
2. `qbittorrent` (`arr_qbittorrent`, `lscr.io/linuxserver/qbittorrent:5.0.2`) — isolated inside the `vpn` container network namespace (`network_mode: "service:vpn"`) and running as `PUID=1000` (`PGID=1001`) so that 100% of peer traffic traverses `tailscale0` (`TS_EXIT_NODE`) and any non-tunnel traffic on `eth0` or disconnected exit-node traffic is unconditionally `DROP`ped at the kernel netfilter layer.
3. `jellyfin` (`arr_jellyfin`, `lscr.io/linuxserver/jellyfin:10.10.3`) — household media server indexing `/mnt/storage/media/{movies,tv}` with Intel Alder Lake-S UHD Graphics 770 (`00:02.0`, `LIBVA_DRIVER_NAME=iHD` QSV/VAAPI) hardware transcoding while keeping the discrete AMD Radeon RX 6700 XT (`03:00.0`) strictly isolated.

The deployment enforces a three-tier storage architecture with unified `admin:storage` (`PUID=1000`, `PGID=1001`, `UMASK=002`, mode `2775` directories and `0664` files) ownership:
- **Tier 0 Fast NVMe (`/opt/services/arr`)**: Service configurations, Tailscale state (`/opt/services/arr/vpn/config`), kill-switch/healthcheck scripts (`/opt/services/arr/vpn/{killswitch,healthcheck}.sh`), SQLite databases, and pre-created Stage 2A/2B/2C directory scaffolding (`/opt/services/arr/{vpn,gluetun,qbittorrent,jellyfin,ersatztv,jellyseerr,prowlarr,radarr,sonarr}/config`).
- **Tier 2 Non-Parity Scratch (`/mnt/scratch/downloads/incomplete`)**: Active incomplete torrent swarms isolated from parity drives.
- **Tier 1 Pooled MergerFS (`/mnt/storage/downloads/complete` & `/mnt/storage/media/{movies,tv}`)**: Single `/mnt/storage` mount (`atomic_rename=true`) enabling instant atomic file moves/hardlinks, with SnapRAID configured to exclude `/downloads/` while protecting `/media/`.

All Web UI ports (`127.0.0.1:8096` for Jellyfin and `127.0.0.1:8080` for qBittorrent via `arr_vpn`) bind exclusively to host loopback and are published internally over LAN and Tailscale via Caddy (`/etc/caddy/conf.d/40-arr.caddy`). Continuous disaster recovery integrates an online SQLite snapshot and config backup hook (`/etc/homelab/backup.d/40-arr.sh`) into the Backblaze B2 + Restic pipeline while excluding bulk media and download caches, verified by a 10-point live acceptance suite (`scripts/verify-phase5-arr.{sh,ps1}`).

---

## Technical Context

**Language/Version**:
- Container Workloads: Tailscale `v1.76.6` (Go, kernel WireGuard) / Gluetun `v3.39.1` (Go), qBittorrent `5.0.2` (C++/Qt6 via LinuxServer.io), Jellyfin `10.10.3` (.NET 8 + FFmpeg via LinuxServer.io)
- Database: Embedded SQLite 3 (`jellyfin.db`, `library.db`)
- Automation & Tooling: Ansible Core 2.16+ (YAML / Jinja2), POSIX Bash 5.2+, PowerShell 7+

**Primary Dependencies**:
- Container Runtime: Docker Engine & Docker Compose v2 (`ansible/roles/docker`)
- VPN & Kill-Switch Subsystem: Linux kernel WireGuard (`/dev/net/tun`) + `NET_ADMIN`/`NET_RAW` netfilter (`iptables`/`ip6tables` `-m owner --uid-owner 1000`) kill-switch inside `arr_vpn` connected to Tailscale Mullvad / Exit Node
- Hardware Acceleration: Intel Media Driver (`LIBVA_DRIVER_NAME=iHD`, VAAPI / QuickSync) on Intel Alder Lake-S UHD Graphics 770 (`pci-0000:00:02.0`)
- Process Supervision: systemd (`arr.service`)
- Reverse Proxy & Ingress: Caddy 2 (`/etc/caddy/conf.d/40-arr.caddy`)
- Storage & Parity: MergerFS (`/mnt/storage`, `atomic_rename=true`), SnapRAID (`/etc/snapraid.conf` excluding `/downloads/`), dedicated scratch (`/mnt/scratch`)
- Backup Pipeline: Restic + Backblaze B2 (`/etc/homelab/backup.d/40-arr.sh` using `sqlite3` `VACUUM INTO` + `PRAGMA integrity_check`)

**Storage**:
- **Tier 0 Fast NVMe App Storage (`/opt/services/arr` on `/dev/nvme0n1p2`)**: `compose.yml` (`0644`), `.env` (`0600`), `.env.example` (`0644`), `backups/` (`0750`), `vpn/{killswitch,healthcheck}.sh` (`0755`), `vpn/config` (`0700`, `root:root`), and `{gluetun,qbittorrent,jellyfin,ersatztv,jellyseerr,prowlarr,radarr,sonarr}/config` (`0775`, `1000:1001`)
- **Tier 2 Scratch Storage (`/mnt/scratch/downloads/incomplete`)**: Active incomplete torrent swarms (`2775`, `1000:1001`), excluded from SnapRAID and Restic
- **Tier 1 Pooled Bulk Storage (`/mnt/storage` on MergerFS `storage_pool`)**: `/mnt/storage/downloads/complete` (excluded from SnapRAID and Restic) and `/mnt/storage/media/{movies,tv}` (protected by SnapRAID parity, excluded from Restic offsite backup), all with `2775` setgid and `admin:storage` (`1000:1001`) ownership

**Testing**:
- In strict adherence to Constitution Principle III (`FR-012`), ZERO automated unit test suites, test runners, or mock frameworks are created.
- Static Analysis & Linting: `ansible-lint`, `shellcheck`, and `bash -n` syntax checks across all scripts and playbooks.
- Automated Acceptance Suite: `scripts/verify-phase5-arr.sh` and `scripts/verify-phase5-arr.ps1` enforcing the 10-point assertion matrix `ARR-01` through `ARR-10`, integrated into `ansible/playbooks/verify-phase5-arr.yml` and `ansible/playbooks/verify.yml`.

**Target Platform**:
- Arch Linux x86_64 host (`fidelacchius`) with Intel Alder Lake-S UHD Graphics 770 iGPU (`00:02.0`), discrete AMD Radeon RX 6700 XT (`03:00.0`), and active Tailscale mesh (`fidelacchius.fable-mackarel.ts.net`).

**Project Type**:
- Infrastructure-as-Code (Ansible role, playbooks, SnapRAID/Restic rule updates, Caddy drop-in configuration, Tailscale exit-node kill-switch scripts, SQLite backup hook, and operator convergence/verification scripts) for a staged containerized media and VPN download stack.

**Performance Goals**:
- Jellyfin `/health` and qBittorrent WebUI respond with HTTP 200 in `< 500ms` over loopback/internal ingress (`FR-009`).
- Hardware-accelerated video playback starts within `< 3s` of selection while maintaining host general CPU utilization `< 50%` during single-stream transcoding (`SC-001`).
- Automated live acceptance verification suite completes all 10 assertions within `< 30s` per run (`SC-006`).

**Constraints**:
- 100% of `qbittorrent` traffic must route through `arr_vpn` (`network_mode: "service:vpn"`) with 0% fallback to host WAN on VPN/exit-node drop (`FR-002`, `SC-002`).
- Host `fidelacchius` `tailscaled` (serving Vaultwarden Tailscale Funnel on port 443) must remain unaffected by the download container's Mullvad exit node.
- Discrete AMD Radeon RX 6700 XT GPU (`03:00.0`) must remain completely isolated and unreferenced (`Principle IV`).
- Zero cleartext Tailscale auth keys, VPN credentials, private keys, or WebUI passwords committed to version control; real secrets reside exclusively in gitignored `vault.yml` and `/opt/services/arr/.env` (`0600`) (`FR-010`, `SC-007`).
- All Stage 1 Web UI ports bind strictly to `127.0.0.1` and are exposed only to internal LAN/Tailscale clients via Caddy (`FR-007`, `SC-004`).
- Bulk media files (`/mnt/storage/media/{movies,tv}`), completed downloads (`/mnt/storage/downloads/complete`), and scratch downloads (`/mnt/scratch/downloads/incomplete`) must be excluded from offsite Backblaze B2 backups (`FR-008`, `SC-005`).

**Scale/Scope**:
- Household multi-user media server and VPN download client supporting multi-terabyte movie and TV libraries on MergerFS, staged to seamlessly accept Stage 2A (`ersatztv`), Stage 2B (`jellyseerr`), and Stage 2C (`prowlarr`, `radarr`, `sonarr`) without data migration or re-permissioning.

**Documentation Impact**:
- `USER_FACING`: Updates repository root `README.md` (adding Media & Arr Stage 1 services, loopback ports, and apply/verify runners), `ROADMAP.md` (updating Phase 5 Media & Arr Stage 1 status), `docs/roadmap.md` (reconciling Stage 1 implementation details), and `docs/operations.md` (documenting Tailscale Admin Console Mullvad exit-node setup, auth key configuration, subnet routing, Jellyfin/qBittorrent onboarding, and backup/restore procedures).

---

## Constitution Check

*GATE: Evaluated prior to Phase 0 research. Re-evaluated and confirmed post-Phase 1 design.*

| Principle / Gate | Compliance Analysis | Status |
|---|---|---|
| **I. Evidence Over Invention, Bounded Investigation & Pragmatic Declarative-First Automation** | All Stage 1 infrastructure (`ansible/roles/arr`, Tailscale exit-node kill-switch scripts, SnapRAID exclusions, backup exclusions, Caddy drop-in, and systemd supervision) is declared via Ansible and modular shell scripts following verified repository conventions (`ansible/roles/immich`, `ansible/roles/vaultwarden`). Hardware paths (`pci-0000:00:02.0-render`), mount paths (`/opt/services`, `/mnt/storage`, `/mnt/scratch`), and UID/GID (`1000:1001`) trace directly to verified host inventory. | **PASS** |
| **II. Two-Tier Failure Model, Fail Closed on Required State & Strict Idempotency** | Preflight tasks fail closed (`assert` / `fail`) if `/opt/services`, `/mnt/storage`, `/mnt/scratch`, `/dev/net/tun`, or `/dev/dri/by-path/pci-0000:00:02.0-render` are missing, or if required vault credentials (`vault_arr_tailscale_auth_key` and `vault_arr_tailscale_exit_node` in `tailscale` mode) are unset. `arr.service` enforces `RequiresMountsFor=/opt/services /mnt/storage /mnt/scratch`. Re-running `arr.yml` against a converged target is strictly idempotent (`changed=0`). All shell scripts enforce `set -euo pipefail`. | **PASS** |
| **III. Behavioral, Value-Driven Testing, Deterministic Execution & Live Acceptance Gates** | In strict compliance with Principle III (`FR-012`), zero unit test files, test runners, or mock frameworks are created. Verification is performed via `ansible-lint`, `shellcheck`, `bash -n`, and the 10-point live acceptance suite (`scripts/verify-phase5-arr.{sh,ps1}`, assertions `ARR-01` through `ARR-10`). | **PASS** |
| **IV. Single Authoritative State, Enforced Boundaries, Safe Concurrency & Zero Secrets in Git** | Tailscale auth keys and VPN credentials reside solely in gitignored `ansible/inventory/group_vars/all/vault.yml` and `/opt/services/arr/.env` (`0600`), while only `.env.example` and `vault.yml.example` are committed. `qbittorrent` is isolated inside `service:vpn`. Web UIs bind exclusively to `127.0.0.1` and are restricted to internal LAN/Tailscale subnets in Caddy. The discrete AMD GPU (`03:00.0`) is untouched. | **PASS** |
| **V. Centralized Dependencies, Protected Toolchain Gate & Disaster Recovery by Design** | Container images (`ghcr.io/tailscale/tailscale:v1.76.6`, `ghcr.io/qdm12/gluetun:v3.39.1`, `lscr.io/linuxserver/qbittorrent:5.0.2`, `lscr.io/linuxserver/jellyfin:10.10.3`) are pinned centrally in role defaults. No new OS packages or Ansible collections are added (`sqlite3` is already installed). Disaster recovery is guaranteed via `/etc/homelab/backup.d/40-arr.sh` performing online SQLite `VACUUM INTO` + `PRAGMA integrity_check` and config staging into Restic/B2 while excluding bulk media and downloads. | **PASS** |
| **VI. Bounded Resources & Verify-Before-Destroy** | Hardware transcoding offloads video processing to the Intel UHD 770 iGPU, keeping CPU usage `< 50%`. Systemd unit enforces explicit startup/shutdown timeouts and relies on host `systemd-oomd` and `2G` journald limits. No destructive disk operations are performed. | **PASS** |
| **VII. Code Hygiene, Ubiquitous Language & Safe Logging** | All scripts and playbooks pass `bash -n`, `shellcheck`, and `ansible-lint` with zero warnings. Logs flow to `journald` and standard streams using `CRITICAL`, `WARN`, `INFO`, `DEBUG` prefixes with `no_log: true` on secret tasks and zero VPN/Tailscale key leakage. Human-facing documentation (`README.md`, `ROADMAP.md`, `docs/roadmap.md`, `docs/operations.md`) is updated in the same change. | **PASS** |

**Gate Evaluation**: **PASS** (Pre-Phase 0 and Post-Phase 1). Zero constitutional violations.

---

## Project Structure

### Documentation (this feature)

```text
specs/015-media-arr-stage1/
├── spec.md                              # Feature specification (FR-001..FR-012, SC-001..SC-007)
├── plan.md                              # This implementation plan (/speckit-plan output)
├── research.md                          # Phase 0 architectural decisions & technical research
├── data-model.md                        # Phase 1 three-tier storage, permissions & state models
├── quickstart.md                        # Phase 1 Tailscale Mullvad setup, deployment & verification runbook
├── contracts/                           # Phase 1 explicit interface & verification contracts
│   ├── arr-service-contract.md          # Compose stack, Tailscale/Gluetun kill-switch, iGPU & storage contract
│   ├── backup-restore-contract.md       # 40-arr.sh SQLite snapshot hook & Restic exclusion contract
│   ├── caddy-ingress-contract.md        # 40-arr.caddy internal-only reverse proxy ingress contract
│   └── verification-contract.md         # Automated acceptance matrix assertions ARR-01 through ARR-10
├── checklists/
│   └── requirements.md                  # Specification quality checklist
└── tasks.md                             # Phase 2 actionable task breakdown (/speckit-tasks output)
```

### Source Code (repository root)

```text
ansible/
├── inventory/
│   └── group_vars/
│       └── all/
│           ├── vars.yml                 # Non-sensitive Media & Arr Stage 1 defaults (vpn_mode, ports, paths, versions)
│           └── vault.yml.example        # Sanitized placeholders for vault_arr_tailscale_* and vault_arr_vpn_*
├── playbooks/
│   ├── site.yml                         # Master convergence playbook (includes arr role)
│   ├── arr.yml                          # Dedicated Phase 5 Media & Arr Stage 1 convergence playbook
│   ├── verify-phase5-arr.yml            # Dedicated Phase 5 Media & Arr acceptance verification playbook
│   └── verify.yml                       # Master platform verification playbook (imports verify-phase5-arr.yml)
└── roles/
    ├── arr/
    │   ├── defaults/
    │   │   └── main.yml                 # Pinned container images, arr_vpn_mode: tailscale, ports, 3-tier paths, PUID/PGID
    │   ├── files/
    │   │   └── env.example              # Committed .env.example template with sanitized placeholders
    │   ├── handlers/
    │   │   └── main.yml                 # Systemd daemon-reload, arr.service restart, and Caddy reload handlers
    │   ├── tasks/
    │   │   ├── main.yml                 # Task orchestrator (preflight, layout, config, service, backup, caddy)
    │   │   ├── preflight.yml            # Assertions for Docker, /mnt/storage, /mnt/scratch, /dev/net/tun, iGPU
    │   │   ├── layout.yml               # Creation of Tier 0 (Stage 1+2 scaffold), Tier 1, Tier 2 dirs & 2775 perms
    │   │   ├── config.yml               # Rendering of .env (0600), .env.example, killswitch.sh, healthcheck.sh & compose.yml
    │   │   ├── service.yml              # Deployment of arr.service systemd unit and service activation
    │   │   ├── backup.yml               # Deployment of /etc/homelab/backup.d/40-arr.sh backup hook
    │   │   └── caddy.yml                # Deployment of /etc/caddy/conf.d/40-arr.caddy internal ingress drop-in
    │   └── templates/
    │       ├── 40-arr.sh.j2             # Transactional SQLite VACUUM INTO & config snapshot backup hook
    │       ├── 40-arr.caddy.j2          # Internal-only Caddy reverse proxy drop-in template
    │       ├── compose.yml.j2           # Stage 1 Docker Compose manifest template (vpn, qbittorrent, jellyfin)
    │       ├── env.j2                   # Environment file template (.env) with no_log protection
    │       ├── killswitch.sh.j2         # Kernel netfilter UID 1000 kill-switch script for arr_vpn
    │       ├── healthcheck.sh.j2        # ExitNodeStatus.Online + kill-switch + external IP healthcheck script
    │       └── arr.service.j2           # Systemd service unit template with mount dependency guards
    ├── snapraid/
    │   └── defaults/
    │       └── main.yml                 # Updated snapraid_excludes to exclude /downloads/
    └── backup/
        ├── defaults/
        │   └── main.yml                 # Updated backup_exclude_patterns for Arr media, downloads & caches
        └── templates/
            └── backup-excludes.txt.j2   # Updated Restic exclusion template for Arr bulk media & caches

scripts/
├── apply-phase5-arr.sh                  # POSIX operator convergence runner for Media & Arr Stage 1
├── apply-phase5-arr.ps1                 # PowerShell operator convergence runner for Media & Arr Stage 1
├── verify-phase5-arr.sh                 # POSIX automated acceptance suite (ARR-01 through ARR-10)
└── verify-phase5-arr.ps1                # PowerShell automated acceptance suite (ARR-01 through ARR-10)

docs/
├── roadmap.md                           # Updated Phase 5 Media & Arr Stage 1 architecture & gate status
└── operations.md                        # Updated Media & Arr Stage 1 runbook, Tailscale Mullvad config & DR guide

README.md                                # Root README updated with Media & Arr Stage 1 services, ports & scripts
ROADMAP.md                               # Strategic roadmap updated marking Media & Arr Stage 1 implemented
```

**Structure Decision**:
Follows the exact infrastructure-as-code layout established by `ansible/roles/immich`, `ansible/roles/frigate`, and `ansible/roles/vaultwarden`. The `ansible/roles/arr` role encapsulates Stage 1 service provisioning (defaulting to Tailscale Mullvad / Exit Node mode via `arr_vpn`) while pre-creating `/opt/services/arr/{ersatztv,jellyseerr,prowlarr,radarr,sonarr}/config` and modular compose/caddy/backup structure so Stages 2A, 2B, and 2C can be layered additively.

---

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

*Zero constitutional violations identified. No complexity exceptions required.*
