# Tasks: Media & Arr Stack — Stage 1 (Core Media & VPN Download Foundation)

**Input**: Design documents from `/specs/015-media-arr-stage1/`
**Prerequisites**: `plan.md` (required), `spec.md` (required), `research.md`, `data-model.md`, `quickstart.md`, `contracts/`
**Documentation Impact**: `USER_FACING` (`README.md`, `ROADMAP.md`, `docs/roadmap.md`, `docs/operations.md`)
**Tests**: In strict adherence to Constitution Principle III (`FR-012`), **ZERO** automated unit test files, test directories, test harnesses, or mock frameworks are generated. Verification relies exclusively on static linters (`bash -n`, `shellcheck`, `ansible-lint`), Ansible `--check` dry runs, and the 10-point live acceptance suite (`scripts/verify-phase5-arr.{sh,ps1}`, assertions `ARR-01` through `ARR-10`).

**Organization**: Tasks are organized into Setup, Foundational, User Story phases ordered by priority (`US1`, `US2`, `US3`, `US5` at Priority P1; `US4` at Priority P2), and a final Polish phase for cross-cutting integration, human-facing documentation, and pre-PR static gates.

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel within the same phase (mutually disjoint file paths, no intra-phase dependencies)
- **[Story]**: User story label (`[US1]` through `[US5]`) applied exclusively to User Story phase tasks
- Every task includes exact repository file paths and verbatim contract/data-model constraints

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Initialize the `ansible/roles/arr` role skeleton and centralized non-sensitive defaults (`FR-001`, `FR-002`, `FR-004`, `FR-006`, `FR-007`, Constitution Principle V).

- [x] T001 Create `ansible/roles/arr/{defaults,files,handlers,tasks,templates}` role directory layout matching existing application roles (`ansible/roles/immich`, `ansible/roles/frigate`) in `ansible/roles/arr/`
- [x] T002 [P] Add non-sensitive Media & Arr Stage 1 global defaults (`arr_vpn_mode: "tailscale"`, `arr_ts_hostname: "fidelacchius-arr-vpn"`, `arr_host_bind: "127.0.0.1"`, `arr_jellyfin_port: 8096`, `arr_qbittorrent_webui_port: 8080`, `arr_gluetun_control_port: 8000`, `arr_service_dir: "/opt/services/arr"`, `arr_scratch_incomplete_dir: "/mnt/scratch/downloads/incomplete"`, `arr_storage_root: "/mnt/storage"`, `arr_storage_complete_dir: "/mnt/storage/downloads/complete"`, `arr_storage_movies_dir: "/mnt/storage/media/movies"`, `arr_storage_tv_dir: "/mnt/storage/media/tv"`, `arr_puid: 1000`, `arr_pgid: 1001`, `arr_umask: "002"`) to `ansible/inventory/group_vars/all/vars.yml`
- [x] T003 [P] Define pinned Stage 1 container image tags (`arr_tailscale_version: "v1.76.6"`, `arr_gluetun_version: "v3.39.1"`, `arr_qbittorrent_version: "5.0.2"`, `arr_jellyfin_version: "10.10.3"`), `arr_vpn_mode: "tailscale"`, `arr_ts_hostname: "fidelacchius-arr-vpn"`, `arr_libva_driver_name: "iHD"`, `arr_tz: "America/New_York"`, `arr_backups_dir: "/opt/services/arr/backups"`, `arr_firewall_outbound_subnets: "192.168.4.0/24"`, loopback port variables, three-tier storage paths, `PUID=1000`, `PGID=1001`, `UMASK=002`, and `vault_arr_tailscale_*` / `vault_arr_vpn_*` default fallbacks in `ansible/roles/arr/defaults/main.yml`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish fail-closed host preflight assertions, systemd service supervision, role orchestration, and dedicated convergence entry point before implementing user stories (`FR-001`, `FR-002`, `FR-003`, `FR-004`, Constitution Principle II).

**⚠️ CRITICAL**: No user story implementation begins until preflight, handlers, systemd supervision, and role orchestration scaffolding are defined.

- [x] T004 [P] Implement fail-closed preflight assertions (`docker` daemon active, `/opt/services`, `/mnt/storage`, and `/mnt/scratch` active mountpoints, `/dev/net/tun` character device present, Intel UHD 770 `/dev/dri/by-path/pci-0000:00:02.0-render` and `/dev/dri/by-path/pci-0000:00:02.0-card` nodes present with zero reference to discrete AMD GPU `03:00.0`, and non-empty `vault_arr_tailscale_auth_key` + `vault_arr_tailscale_exit_node` when `arr_vpn_mode == 'tailscale'`) in `ansible/roles/arr/tasks/preflight.yml`
- [x] T005 [P] Implement role handlers (`Reload systemd` via `systemd: daemon_reload: true`, `Restart arr stack` via `systemd: name: arr state: restarted`, and `Reload caddy` via `systemd: name: caddy state: reloaded`) in `ansible/roles/arr/handlers/main.yml`
- [x] T006 [P] Create systemd unit template (`Type=oneshot`, `RemainAfterExit=yes`, `WorkingDirectory=/opt/services/arr`, `Requires=docker.service local-fs.target`, `After=docker.service network-online.target local-fs.target`, `Wants=network-online.target`, `RequiresMountsFor=/opt/services /mnt/storage /mnt/scratch`, `ExecStart=/usr/bin/docker compose up -d --remove-orphans`, `ExecStop=/usr/bin/docker compose down`, `ExecReload=/usr/bin/docker compose up -d --remove-orphans`, `TimeoutStartSec=300`, `TimeoutStopSec=90`, `[Install] WantedBy=multi-user.target`) in `ansible/roles/arr/templates/arr.service.j2`
- [x] T007 Implement systemd unit deployment (`/etc/systemd/system/arr.service`, `root:root`, mode `0644`, notifying `Reload systemd` and `Restart arr stack`) and service enablement/activation (`arr.service` enabled and started) in `ansible/roles/arr/tasks/service.yml` (depends on T005, T006)
- [x] T008 Create role task orchestrator importing `preflight.yml`, `layout.yml`, `config.yml`, `service.yml`, `backup.yml`, and `caddy.yml` in sequential order in `ansible/roles/arr/tasks/main.yml` (depends on T004, T007)
- [x] T009 Create dedicated Phase 5 Media & Arr Stage 1 convergence playbook (including controller `vault.yml` fail-closed pre-task check, `docker`, `caddy`, and `arr` roles, and `post_tasks` verifying `arr.service` active, `http://127.0.0.1:8096/health` HTTP 200, and `http://127.0.0.1:8080` HTTP 200) in `ansible/playbooks/arr.yml` (depends on T008)

**Checkpoint**: Role orchestration, fail-closed preflight checks, and systemd supervision (`arr.service`) are ready.

---

## Phase 3: User Story 1 - Hardware-Accelerated Household Media Streaming (Priority: P1) 🎯 MVP

**Goal**: Deploy Jellyfin (`arr_jellyfin`) serving household movie and TV libraries with Intel Alder Lake-S UHD Graphics 770 (`00:02.0`, `LIBVA_DRIVER_NAME=iHD` QSV/VAAPI) hardware transcoding while keeping the discrete AMD Radeon RX 6700 XT (`03:00.0`) isolated (`FR-001`, `FR-003`, `FR-006`, `SC-001`, `ARR-04`, `ARR-06`).

**Independent Test**: Start `arr_jellyfin`, place sample movie/TV files in `/mnt/storage/media/{movies,tv}`, confirm `http://127.0.0.1:8096/health` returns HTTP 200 `"Healthy"`, verify `docker inspect arr_jellyfin` binds `pci-0000:00:02.0-render` (`renderD128`) and `LIBVA_DRIVER_NAME=iHD` with zero `03:00.0` device references, and confirm hardware-accelerated playback keeps host CPU utilization `< 50%`.

### Implementation for User Story 1

- [x] T010 [US1] Create initial Stage 1 Docker Compose manifest template defining `jellyfin` (`container_name: arr_jellyfin`, `image: lscr.io/linuxserver/jellyfin:${JELLYFIN_VERSION:-10.10.3}`, `restart: unless-stopped`, `stop_grace_period: 30s`, `ports: ["${ARR_HOST_BIND:-127.0.0.1}:${JELLYFIN_HTTP_PORT:-8096}:8096"]`, `environment` with `PUID=${PUID:-1000}`, `PGID=${PGID:-1001}`, `UMASK=${UMASK:-002}`, `TZ=${TZ:-America/New_York}`, `LIBVA_DRIVER_NAME=${LIBVA_DRIVER_NAME:-iHD}`, `devices` mapping `/dev/dri/by-path/pci-0000:00:02.0-render:/dev/dri/renderD128` and `/dev/dri/by-path/pci-0000:00:02.0-card:/dev/dri/card0` with zero reference to `03:00.0`, `volumes` `/etc/localtime:/etc/localtime:ro`, `${ARR_SERVICE_DIR:-/opt/services/arr}/jellyfin/config:/config`, `${ARR_STORAGE_MOVIES_DIR:-/mnt/storage/media/movies}:/mnt/storage/media/movies`, `${ARR_STORAGE_TV_DIR:-/mnt/storage/media/tv}:/mnt/storage/media/tv`, `healthcheck` `curl -fsS http://127.0.0.1:8096/health` `interval: 30s`, `timeout: 10s`, `retries: 3`, `start_period: 45s`, plus Stage 2A/2B/2C extension comment) in `ansible/roles/arr/templates/compose.yml.j2`
- [x] T011 [US1] Implement `compose.yml` template rendering (`/opt/services/arr/compose.yml`, `root:root`, mode `0644`, notifying `Restart arr stack`) in `ansible/roles/arr/tasks/config.yml` (depends on T010)

**Checkpoint**: Jellyfin (`arr_jellyfin`) is independently deployable and verifiable for hardware-accelerated media streaming (MVP increment).

---

## Phase 4: User Story 2 - VPN-Isolated Download Foundation with Strict Kill-Switch (Priority: P1)

**Goal**: Deploy `vpn` (`arr_vpn`, running `ghcr.io/tailscale/tailscale:v1.76.6` connected to a Tailscale Mullvad / Exit Node by default when `arr_vpn_mode == 'tailscale'`, or `ghcr.io/qdm12/gluetun:v3.39.1` when `arr_vpn_mode == 'gluetun'`) with a strict kernel netfilter (`iptables`/`ip6tables`) kill-switch (`/opt/services/arr/vpn/killswitch.sh` and `healthcheck.sh`), and isolate `qbittorrent` (`arr_qbittorrent`) inside `network_mode: "service:vpn"` with zero host WAN egress (`FR-001`, `FR-002`, `FR-006`, `SC-002`, `ARR-01`, `ARR-02`, `ARR-03`, `ARR-04`).

**Independent Test**: Verify `arr_qbittorrent` `HostConfig.NetworkMode` equals `container:<arr_vpn_id>` with an empty `Networks` map, verify `tailscale status --json` inside `arr_vpn` shows `ExitNodeStatus.Online == true`, verify `docker exec arr_qbittorrent` external IP differs from the host public WAN IP while host `fidelacchius` WAN IP and Vaultwarden Tailscale Funnel remain unchanged, confirm `iptables` in `arr_vpn` enforces `-o eth0 -m owner --uid-owner 1000 -j DROP`, and confirm `http://127.0.0.1:8080` returns HTTP 200.

### Implementation for User Story 2

- [x] T012 [P] [US2] Create kernel netfilter kill-switch script template (`iptables`/`ip6tables` rules allowing `lo`, allowing TCP `--sport 8080` WebUI replies for `UID 1000` on `eth0`, and unconditionally `DROP`ping all other `UID 1000` IPv4 `eth0` and IPv6 non-loopback packets) and exit-node healthcheck script template (verifying `eth0` `DROP` rule active, `tailscale status --json` `BackendState == "Running"` and `ExitNodeStatus.Online == true`, and blocking `UID 1000` on `tailscale0` whenever the exit node is offline) per `contracts/arr-service-contract.md` in `ansible/roles/arr/templates/killswitch.sh.j2` and `ansible/roles/arr/templates/healthcheck.sh.j2`
- [x] T013 [US2] Extend `ansible/roles/arr/templates/compose.yml.j2` and `ansible/roles/arr/tasks/config.yml` to render `/opt/services/arr/vpn/killswitch.sh` (`0755`) and `/opt/services/arr/vpn/healthcheck.sh` (`0755`) and define `vpn` (`container_name: arr_vpn`, defaulting in `tailscale` mode to `ghcr.io/tailscale/tailscale:${TAILSCALE_VERSION:-v1.76.6}` with `cap_add: [NET_ADMIN, NET_RAW]`, `/dev/net/tun:/dev/net/tun`, `127.0.0.1:8080:8080`, `TS_AUTHKEY`, `TS_EXIT_NODE`, `TS_USERSPACE=false`, `entrypoint` executing `/usr/local/bin/arr-vpn-killswitch.sh && exec /usr/local/bin/containerboot`, `healthcheck` `/usr/local/bin/arr-vpn-healthcheck.sh`, or in `gluetun` mode `ghcr.io/qdm12/gluetun:${GLUETUN_VERSION:-v3.39.1}`) and `qbittorrent` (`container_name: arr_qbittorrent`, `image: lscr.io/linuxserver/qbittorrent:${QBITTORRENT_VERSION:-5.0.2}`, `network_mode: "service:vpn"`, `depends_on: vpn: condition: service_healthy`, `PUID=1000`, `PGID=1001`, `UMASK=002`) per `contracts/arr-service-contract.md` (depends on T010, T011, T012)
- [x] T014 [P] [US2] Add sanitized `vault_arr_tailscale_*` (`vault_arr_tailscale_auth_key`, `vault_arr_tailscale_exit_node`) and optional `vault_arr_vpn_*` credential placeholders to `ansible/inventory/group_vars/all/vault.yml.example` and create committed `.env.example` template with exact schema variables (`ARR_VPN_MODE=tailscale`, `TAILSCALE_VERSION=v1.76.6`, `GLUETUN_VERSION=v3.39.1`, `QBITTORRENT_VERSION=5.0.2`, `JELLYFIN_VERSION=10.10.3`, `TS_HOSTNAME=fidelacchius-arr-vpn`, `TS_AUTHKEY`, `TS_EXIT_NODE`, `TS_STATE_DIR=/var/lib/tailscale`, `TS_USERSPACE=false`, `TS_ACCEPT_DNS=true`, `TS_EXTRA_ARGS`, `PUID=1000`, `PGID=1001`, `UMASK=002`, loopback ports, and storage paths) in `ansible/roles/arr/files/env.example`

**Checkpoint**: VPN-isolated download foundation (`arr_vpn` + `arr_qbittorrent`), kernel netfilter kill-switch, and sanitized credential templates are complete.

---

## Phase 5: User Story 3 - Three-Tier Storage Architecture & Unified Permissions (Priority: P1)

**Goal**: Provision all Tier 0 NVMe directories (including `vpn/config` and Stage 2A/2B/2C config scaffolding), Tier 2 non-parity scratch download directories, and Tier 1 MergerFS completion/library directories with unified `admin:storage` (`1000:1001`) ownership and `2775`/`0775` permissions, and exclude `/downloads/` from SnapRAID parity (`FR-004`, `FR-005`, `FR-006`, `SC-003`, `ARR-07`, `ARR-08`).

**Independent Test**: Confirm `/opt/services/arr/vpn` (`0755`, `root:root`), `/opt/services/arr/vpn/config` (`0700`, `root:root`), `/opt/services/arr/{gluetun,qbittorrent,jellyfin,ersatztv,jellyseerr,prowlarr,radarr,sonarr}/config` (`0775`, `1000:1001`), `/opt/services/arr/backups` (`0750`, `root:root`), `/mnt/scratch/downloads/incomplete` (`2775`, `1000:1001`), `/mnt/storage/downloads/complete` (`2775`, `1000:1001`), and `/mnt/storage/media/{movies,tv}` (`2775`, `1000:1001`) all exist on their designated mounts, confirm `downloads/complete` and `media/{movies,tv}` share one `st_dev` MergerFS mount, and confirm `/etc/snapraid.conf` excludes `/downloads/` and `/mnt/scratch/`.

### Implementation for User Story 3

- [x] T015 [P] [US3] Create three-tier directory and permission provisioning tasks (`/opt/services/arr` `root:root` `0755`, `/opt/services/arr/backups` `root:root` `0750`, `/opt/services/arr/vpn` `root:root` `0755`, `/opt/services/arr/vpn/config` `root:root` `0700`, `/opt/services/arr/{gluetun,qbittorrent,jellyfin,ersatztv,jellyseerr,prowlarr,radarr,sonarr}/config` `1000:1001` `0775`, `/mnt/scratch/downloads` and `/mnt/scratch/downloads/incomplete` `admin:storage` `1000:1001` `2775`, and `/mnt/storage/downloads`, `/mnt/storage/downloads/complete`, `/mnt/storage/media`, `/mnt/storage/media/movies`, `/mnt/storage/media/tv` `admin:storage` `1000:1001` `2775`) in `ansible/roles/arr/tasks/layout.yml`
- [x] T016 [P] [US3] Add `"/downloads/"` alongside `"/mnt/scratch/"` in `snapraid_excludes` so SnapRAID excludes completed downloads while protecting `media/` in `ansible/roles/snapraid/defaults/main.yml`
- [x] T017 [US3] Configure `qbittorrent` storage volume mounts (`/etc/localtime:/etc/localtime:ro`, `${ARR_SERVICE_DIR:-/opt/services/arr}/qbittorrent/config:/config`, `${ARR_SCRATCH_INCOMPLETE_DIR:-/mnt/scratch/downloads/incomplete}:/mnt/scratch/downloads/incomplete`, and single `${ARR_STORAGE_ROOT:-/mnt/storage}:/mnt/storage` mount preserving single `st_dev` for atomic renames/hardlinks) in `ansible/roles/arr/templates/compose.yml.j2`

**Checkpoint**: Three-tier storage hierarchy, Stage 2 config scaffolding, unified `2775`/`1000:1001` permissions, and SnapRAID parity exclusions are configured.

---

## Phase 6: User Story 5 - Continuous Backup Integration & Live Telemetry Verification (Priority: P1)

**Goal**: Implement the `/etc/homelab/backup.d/40-arr.sh` online SQLite (`VACUUM INTO` + `PRAGMA integrity_check`) and config archive hook, exclude bulk media/downloads/caches from Restic offsite backups, and deliver the automated 10-point live acceptance verification suite (`ARR-01` through `ARR-10`) (`FR-008`, `FR-009`, `FR-011`, `FR-012`, `SC-005`, `SC-006`, `ARR-09`, `ARR-10`).

**Independent Test**: Execute `sudo /etc/homelab/backup.d/40-arr.sh pre-backup` to verify online SQLite snapshots pass `PRAGMA integrity_check` (`ok`) and `arr-configs-snapshot.tar.gz` (`0640`) is created without stopping Jellyfin, inspect `/etc/homelab/backup-excludes.txt` for bulk media/download/cache exclusions, and execute `./scripts/verify-phase5-arr.sh --local --json` to confirm structured assertion telemetry completes in `< 30s` with zero secret leakage.

### Implementation for User Story 5

- [x] T018 [P] [US5] Create backup integration hook template (`set -euo pipefail`, `pre-backup` scanning `/opt/services/arr/*/config/*` for `*.db`/`*.sqlite3`, running `sqlite3 <db> "VACUUM INTO '<target>'"` and `PRAGMA integrity_check;` aborting exit `1` unless `ok`, archiving configs into `/opt/services/arr/backups/arr-configs-snapshot.tar.gz` mode `0640` excluding `*.db`, `*.sqlite3`, `*.db-wal`, `*.db-shm`, `*/cache/*`, `*/metadata/*`, `*/transcodes/*`, `backups/*`; `post-restore` restoring missing snapshots/configs and enforcing `0600` on `.env`, `0700` on `vpn/config`, and `1000:1001` ownership; `INFO`/`CRITICAL` structured logging) per `contracts/backup-restore-contract.md` in `ansible/roles/arr/templates/40-arr.sh.j2`
- [x] T019 [P] [US5] Add Arr media, download, live SQLite database, and Jellyfin cache exclusions (`/mnt/storage/downloads/**`, `/mnt/storage/media/movies/**`, `/mnt/storage/media/tv/**`, `/opt/services/arr/*/config/**/*.db`, `/opt/services/arr/*/config/**/*.sqlite3`, `/opt/services/arr/jellyfin/config/cache/**`, `/opt/services/arr/jellyfin/config/metadata/**`, `/opt/services/arr/jellyfin/config/transcodes/**`) to `backup_exclude_patterns` in `ansible/roles/backup/defaults/main.yml`
- [x] T020 [P] [US5] Update Restic exclusion template to enforce Arr exclusion guards (`/mnt/storage/downloads/**`, `/mnt/storage/media/movies/**`, `/mnt/storage/media/tv/**`, `/opt/services/arr/*/config/**/*.db`, `/opt/services/arr/*/config/**/*.sqlite3`, `/opt/services/arr/jellyfin/config/cache/**`, `/opt/services/arr/jellyfin/config/metadata/**`, `/opt/services/arr/jellyfin/config/transcodes/**`) even when `backup_exclude_patterns` is overridden in `ansible/roles/backup/templates/backup-excludes.txt.j2`
- [x] T021 [US5] Implement backup hook deployment task (`/etc/homelab/backup.d/40-arr.sh`, `root:root`, mode `0750`, ensuring `/etc/homelab/backup.d` exists) in `ansible/roles/arr/tasks/backup.yml` (depends on T018)
- [x] T022 [P] [US5] Create POSIX live acceptance verification script implementing the 10-point Assertion Matrix `ARR-01` through `ARR-10` (verifying `arr_vpn` Tailscale `ExitNodeStatus.Online == true` or Gluetun health, `UID 1000` `eth0` `DROP` kill-switch, external VPN IP != host WAN IP, `arr_qbittorrent` `container:` netns isolation, Jellyfin/qBittorrent HTTP 200, loopback binding & `40-arr.caddy`, Intel `00:02.0-render` & `iHD`, three-tier layout & SnapRAID `/downloads/` exclusion, `2775` permissions, `.env` `0600` & `40-arr.sh`, and clean redacted telemetry) with deterministic exit codes `1..10`, `--local`, `--json`, `--verbose`, `--host`, `--user`, `--identity`, `set -euo pipefail` per `contracts/verification-contract.md` in `scripts/verify-phase5-arr.sh`
- [x] T023 [P] [US5] Create PowerShell 7+ live acceptance verification runner enforcing `ARR-01` through `ARR-10` locally or over SSH with `-Host`, `-User`, `-Identity`, `-Local`, `-Json`, `-Verbose`, and `$ErrorActionPreference = "Stop"` in `scripts/verify-phase5-arr.ps1`
- [x] T024 [P] [US5] Create Ansible live acceptance verification playbook asserting `ARR-01` through `ARR-10` (active `arr.service` & 3 healthy containers `arr_vpn`/`arr_qbittorrent`/`arr_jellyfin`, `arr_vpn` exit-node tunnel online & external VPN IP != host WAN IP & `DROP` kill-switch, `arr_qbittorrent` `container:` network mode, Jellyfin `/health` & qBittorrent HTTP 200, loopback binding & `40-arr.caddy` validation, Intel `00:02.0-render` & `iHD` with AMD `03:00.0` isolated, three-tier storage & SnapRAID `/downloads/` exclusion, `2775` `1000:1001` permissions, `.env` `0600` & `40-arr.sh pre-backup` snapshot integrity, and clean `journald`/container logs) in `ansible/playbooks/verify-phase5-arr.yml`
- [x] T025 [US5] Import `verify-phase5-arr.yml` into the master platform verification playbook in `ansible/playbooks/verify.yml` (depends on T024)

**Checkpoint**: Offsite backup integration (`40-arr.sh`, Restic exclusions) and live acceptance verification (`ARR-01`..`ARR-10`) are complete.

---

## Phase 7: User Story 4 - Internal-Only Reverse Proxy Ingress & Credential Isolation (Priority: P2)

**Goal**: Publish Stage 1 Web UIs internally over LAN and Tailscale via Caddy (`/etc/caddy/conf.d/40-arr.caddy`) while returning HTTP `403` to non-internal clients, and render `/opt/services/arr/.env` (`0600`) with `no_log: true` from gitignored `vault.yml` (`FR-007`, `FR-010`, `FR-011`, `SC-004`, `SC-007`, `ARR-05`, `ARR-09`).

**Independent Test**: Confirm `ss -tln` and `docker port` show ports `8096` and `8080` bound solely to `127.0.0.1`, run `caddy validate --config /etc/caddy/Caddyfile`, verify HTTPS access to `jellyfin.lan` and `qbittorrent.lan` from LAN/Tailscale (`127.0.0.0/8 192.168.4.0/24 100.64.0.0/10 ::1`) and HTTP `403` outside `@internal`, verify `/opt/services/arr/.env` mode `0600`, and verify zero cleartext Tailscale/VPN keys in git.

### Implementation for User Story 4

- [x] T026 [P] [US4] Create Caddy internal-only reverse proxy drop-in template (`jellyfin.{$HOMELAB_DOMAIN:lan}` -> `127.0.0.1:8096` and `qbittorrent.{$HOMELAB_DOMAIN:lan}` -> `127.0.0.1:8080`, `tls internal`, `log { output stderr; format console; level INFO }`, `@internal { remote_ip 127.0.0.0/8 192.168.4.0/24 100.64.0.0/10 ::1 }`, `respond "Forbidden: Internal network access only" 403` fallback, and reserved Stage 2A/2B/2C comments) per `contracts/caddy-ingress-contract.md` in `ansible/roles/arr/templates/40-arr.caddy.j2`
- [x] T027 [P] [US4] Create `.env` Jinja2 template rendering `ARR_VPN_MODE`, pinned versions (`TAILSCALE_VERSION`, `GLUETUN_VERSION`, `QBITTORRENT_VERSION`, `JELLYFIN_VERSION`), `PUID`/`PGID`/`UMASK`, `ARR_HOST_BIND=127.0.0.1`, loopback ports, storage paths, `LIBVA_DRIVER_NAME=iHD`, `TS_HOSTNAME`, `TS_AUTHKEY`, `TS_EXIT_NODE`, `TS_STATE_DIR`, `TS_USERSPACE=false`, `TS_ACCEPT_DNS=true`, `TS_EXTRA_ARGS`, and optional `vault_arr_vpn_*` credentials in `ansible/roles/arr/templates/env.j2`
- [x] T028 [US4] Implement Caddy drop-in deployment (`/etc/caddy/conf.d/40-arr.caddy`, `root:root`, mode `0644`, running `caddy validate --config /etc/caddy/Caddyfile` validation check and notifying `Reload caddy`) in `ansible/roles/arr/tasks/caddy.yml` (depends on T026)
- [x] T029 [US4] Extend `ansible/roles/arr/tasks/config.yml` to deploy `/opt/services/arr/.env` (`root:root`, mode `0600`, `no_log: true`, notifying `Restart arr stack`) and copy `files/env.example` to `/opt/services/arr/.env.example` (`root:root`, mode `0644`) (depends on T027)

**Checkpoint**: All five user stories (`US1`–`US5`) are completely implemented with strict secret isolation and internal-only Caddy ingress.

---

## Phase 8: Polish, Operator Convergence, Documentation & Pre-PR Static Gates

**Purpose**: Integrate `arr` into master convergence, deliver operator apply runners, reconcile permanent documentation (`USER_FACING` per `plan.md`), and execute pre-PR static verification gates (`FR-009`, `FR-012`, Constitution Principles III & VII).

- [x] T030 [P] Add `arr` role (`tags: [arr, app]`) after `immich` and before `backup` in the master convergence playbook `ansible/playbooks/site.yml`
- [x] T031 [P] Create POSIX operator convergence runner (`--host`, `--user`, `--identity`, `--playbook` defaulting to `playbooks/arr.yml`, `--tags`, `--local`, `--check`, `--age-key`, `set -euo pipefail`) matching repository runner conventions in `scripts/apply-phase5-arr.sh`
- [x] T032 [P] Create PowerShell 7+ operator convergence runner (`-Host`, `-User`, `-Identity`, `-Playbook`, `-Tags`, `-Local`, `-Check`, `$ErrorActionPreference = "Stop"`) in `scripts/apply-phase5-arr.ps1`
- [x] T033 [P] Update repository root `README.md` with Media & Arr Stage 1 (`arr_vpn` Tailscale Mullvad / Exit Node gateway, `arr_qbittorrent`, `arr_jellyfin`) architecture overview, loopback port bindings (`8096`, `8080`), three-tier storage summary, `apply-phase5-arr.{sh,ps1}`, and `verify-phase5-arr.{sh,ps1}` usage reference
- [x] T034 [P] Update `ROADMAP.md` marking Phase 5 Media & Arr Stage 1 implemented with authoritative state ownership (`ansible/roles/arr`) and Stage 2A/2B/2C scaffolding
- [x] T035 [P] Update `docs/roadmap.md` reconciling Phase 5 Media & Arr Stage 1 architecture, Tailscale exit-node VPN kill-switch, three-tier storage/SnapRAID/Restic rules, and acceptance gate (`ARR-01`..`ARR-10`) coverage
- [x] T036 [P] Update `docs/operations.md` documenting Tailscale Admin Console Mullvad exit-node setup (`nodeAttrs` `mullvad` / device slot assignment, `TS_AUTHKEY` generation, `tailscale exit-node list`), host subnet routing (`--advertise-routes=192.168.4.0/24`), Jellyfin iGPU and qBittorrent initial onboarding, `40-arr.sh` backup/restore procedures, and `verify-phase5-arr.sh` diagnostics (aligned with `specs/015-media-arr-stage1/quickstart.md` without citing `specs/` or `FR-XXX` IDs per Constitution workflow rules)
- [x] T037 Execute pre-PR static verification gates (`bash -n scripts/*.sh`, `shellcheck scripts/*.sh`, `ansible-lint`), verify zero unit test files or mock frameworks exist (`FR-012`), verify zero cleartext Tailscale/VPN keys or credentials exist in git (`SC-007`), and validate `specs/015-media-arr-stage1/quickstart.md` command and file-link accuracy (depends on T001–T036)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Starts immediately (`T001` → `T002`, `T003` in parallel).
- **Foundational (Phase 2)**: Depends on Phase 1 completion — blocks all user stories (`T004`–`T006` in parallel → `T007` → `T008` → `T009`).
- **User Story 1 (Phase 3, P1 - MVP)**: Depends on Phase 2 (`T010` → `T011`).
- **User Story 2 (Phase 4, P1)**: `T012` and `T014` run in parallel; `T013` sequentially updates `compose.yml.j2` and `config.yml` after `T010`, `T011`, and `T012`.
- **User Story 3 (Phase 5, P1)**: `T015` and `T016` run in parallel after Phase 2; `T017` sequentially updates `compose.yml.j2` after `T013`.
- **User Story 5 (Phase 6, P1)**: Depends on Phase 2 (`T018`–`T020`, `T022`–`T024` in parallel; `T021` after `T018`; `T025` after `T024`). Live execution of `verify-phase5-arr.{sh,ps1}` requires US1–US4 deployed.
- **User Story 4 (Phase 7, P2)**: Depends on Phase 2 (`T026`, `T027` in parallel; `T028` after `T026`; `T029` after `T027` and `T013`).
- **Polish & Pre-PR Gates (Phase 8)**: `T030`–`T036` run in parallel once role/scripts stabilize; `T037` runs last after `T001`–`T036`.

### Requirement, Contract & Success Criterion Traceability

| Requirement / Contract / SC | Covered By Tasks |
|---|---|
| **FR-001** (Stage 1 Compose + `arr.service` + Stage 2 extensibility) | T001, T006, T007, T008, T009, T010, T013 |
| **FR-002** (`qbittorrent` in `service:vpn` + Tailscale exit node & UID 1000 kill-switch) | T002, T003, T004, T012, T013, T014 |
| **FR-003** (`jellyfin` media mounts + Intel UHD 770 `iHD`, AMD isolated) | T003, T004, T010 |
| **FR-004** (Three-tier layout + Stage 2A/2B/2C NVMe scaffold + single `/mnt/storage`) | T002, T003, T015, T017 |
| **FR-005** (SnapRAID `/downloads/` exclusion, `/media/` protected) | T016 |
| **FR-006** (`PUID=1000`, `PGID=1001`, `UMASK=002`, `2775`/`0775`) | T002, T003, T010, T013, T015 |
| **FR-007** (`127.0.0.1` loopback + `40-arr.caddy` internal-only ingress) | T002, T010, T013, T026, T028 |
| **FR-008** (`40-arr.sh` SQLite `VACUUM INTO` + Restic excludes) | T018, T019, T020, T021 |
| **FR-009** (`apply-phase5-arr` & `verify-phase5-arr` `ARR-01`..`ARR-10`) | T022, T023, T024, T025, T030, T031, T032 |
| **FR-010** (Vault/SOPS + `.env` `0600` + `.example` templates, 0 git secrets) | T014, T027, T029, T037 |
| **FR-011** (Structured `journald`/`stdout`/`stderr` logs, secret redaction) | T018, T022, T026, T029 |
| **FR-012** (Principle III: ZERO unit tests; static linters + live acceptance only) | T022, T023, T024, T037 |
| **ARR-01..ARR-10** (Live acceptance verification matrix) | T022, T023, T024, T025 |
| **SC-001..SC-007** (Streaming CPU, VPN kill-switch, storage/perms, ingress, backup, `<30s` verify, 0 git secrets) | T010–T029, T037 |

---

## Parallel Examples

```bash
# Phase 2 Foundational parallel batch (disjoint files):
# T004: ansible/roles/arr/tasks/preflight.yml
# T005: ansible/roles/arr/handlers/main.yml
# T006: ansible/roles/arr/templates/arr.service.j2

# Phase 6 US5 parallel batch (disjoint files):
# T018: ansible/roles/arr/templates/40-arr.sh.j2
# T019: ansible/roles/backup/defaults/main.yml
# T020: ansible/roles/backup/templates/backup-excludes.txt.j2
# T022: scripts/verify-phase5-arr.sh
# T023: scripts/verify-phase5-arr.ps1
# T024: ansible/playbooks/verify-phase5-arr.yml

# Phase 8 Polish parallel batch (disjoint files):
# T030: ansible/playbooks/site.yml
# T031: scripts/apply-phase5-arr.sh
# T032: scripts/apply-phase5-arr.ps1
# T033: README.md
# T034: ROADMAP.md
# T035: docs/roadmap.md
# T036: docs/operations.md
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 (Setup: `T001`–`T003`) and Phase 2 (Foundational: `T004`–`T009`).
2. Complete Phase 3 (User Story 1: `T010`–`T011`).
3. **STOP and VALIDATE**: Converge `arr_jellyfin`, verify `http://127.0.0.1:8096/health` HTTP 200 and Intel UHD 770 `iHD` hardware transcoding (`ARR-04`, `ARR-06`).

### Incremental Delivery

1. Setup + Foundational → `ansible/roles/arr` skeleton and `arr.service` supervision ready.
2. Add User Story 1 (`jellyfin`) → Hardware-accelerated streaming operational (MVP).
3. Add User Story 2 (`arr_vpn` Tailscale Exit Node + `arr_qbittorrent` + kernel netfilter kill-switch) → VPN-isolated download foundation operational.
4. Add User Story 3 (`layout.yml` + `snapraid`) → Three-tier storage, Stage 2 scaffolding, and `2775` permissions converged.
5. Add User Story 5 (`40-arr.sh`, Restic excludes, `verify-phase5-arr`) → Backup hook and acceptance verification suite ready.
6. Add User Story 4 (`40-arr.caddy`, `.env` `0600`) → Internal-only ingress and credential isolation enforced.
7. Complete Phase 8 (Polish) → `site.yml`, `apply-phase5-arr.{sh,ps1}`, documentation updates (`README.md`, `ROADMAP.md`, `docs/roadmap.md`, `docs/operations.md`), and pre-PR static checks (`bash -n`, `shellcheck`, `ansible-lint`) pass with zero warnings.


---

## Phase 9: Convergence

- [x] T038 CRITICAL: Resolve `ansible-lint` `yaml[line-length]` (line 44) and `yaml[empty-lines]` (line 138) violations in `ansible/inventory/group_vars/all/vars.yml` and `risky-shell-pipe` warnings (lines 110, 124) in `ansible/playbooks/verify.yml` so all feature-touched Ansible files pass `ansible-lint` with zero warnings per Constitution VII / FR-012 (partial)
