# Research & Architectural Decisions: Media & Arr Stack — Stage 1

**Feature**: `015-media-arr-stage1`  
**Date**: 2026-11-17  
**Status**: Completed  
**Governing Documents**: `.specify/memory/constitution.md`, `.specify/memory/coding-standards.md`, `.specify/memory/logging-standards.md`, `specs/015-media-arr-stage1/spec.md`

---

## 1. Container Workload Architecture, Dual-Mode VPN Gateway & Tag Pinning

### Question / Unknown
Which upstream container distributions and pinned image versions should be selected for the Stage 1 VPN gateway (`vpn`), `qbittorrent`, and `jellyfin` to support the operator's **Tailscale Mullvad / Exit Node WireGuard VPN** while satisfying Constitution Principle V (*Centralized Dependencies, Stability-First*) and `FR-001` / `FR-006` (`PUID=1000`, `PGID=1001`, `UMASK=002`)?

### Decision
Deploy a three-container Stage 1 Docker Compose stack (`/opt/services/arr/compose.yml`) using pinned upstream release tags and a configurable `arr_vpn_mode` (`"tailscale"` by default, or `"gluetun"` for standalone WireGuard keys):
1. **VPN Gateway (`vpn` / `arr_vpn`)**:
   - **Primary Default (`arr_vpn_mode: "tailscale"`)**: `ghcr.io/tailscale/tailscale:v1.76.6`
     - Official Tailscale container running kernel WireGuard (`/dev/net/tun`, `TS_USERSPACE=false`) as a dedicated tailnet node (`TS_HOSTNAME=fidelacchius-arr-vpn`) routing outbound traffic through a configured Tailscale Mullvad or custom exit node (`TS_EXIT_NODE`), paired with a strict kernel netfilter (`iptables`/`ip6tables`) kill-switch (`/opt/services/arr/vpn/killswitch.sh`) and exit-node healthcheck (`/opt/services/arr/vpn/healthcheck.sh`).
   - **Optional Fallback (`arr_vpn_mode: "gluetun"`)**: `ghcr.io/qdm12/gluetun:v3.39.1`
     - Lightweight Go-based standalone WireGuard/OpenVPN client container with built-in netfilter kill-switch, selectable if the operator ever switches to raw non-Tailscale WireGuard credentials.
2. **Download Client (`qbittorrent` / `arr_qbittorrent`)**: `lscr.io/linuxserver/qbittorrent:5.0.2`
   - LinuxServer.io packaging of qBittorrent 5.0.x with native `PUID=1000`, `PGID=1001`, `UMASK=002`, and `WEBUI_PORT=8080` support, attached via `network_mode: "service:vpn"`.
3. **Media Server (`jellyfin` / `arr_jellyfin`)**: `lscr.io/linuxserver/jellyfin:10.10.3`
   - LinuxServer.io packaging of Jellyfin 10.10.3 bundling `jellyfin-ffmpeg` with Intel `iHD` VAAPI/QuickSync runtime drivers and native `PUID=1000`, `PGID=1001`, `UMASK=002` s6-overlay initialization.

### Rationale
- Running a dedicated `arr_vpn` Tailscale container (`fidelacchius-arr-vpn`) instead of toggling `--exit-node` on the host's `tailscaled` daemon is essential on `fidelacchius`: the host `tailscaled` (`100.103.39.60`, `fidelacchius.fable-mackarel.ts.net`) actively serves **Tailscale Funnel on port 443 for Vaultwarden** (`127.0.0.1:8088`), SSH administration, Immich, and Backblaze B2 backups. Isolating the Mullvad exit node inside `arr_vpn` routes 100% of `qbittorrent` traffic through Mullvad WireGuard while leaving host traffic and Tailscale Funnel untouched.
- Standardizing the Compose service name as `vpn` (`container_name: arr_vpn`) means `qbittorrent` (`network_mode: "service:vpn"`) and all verification probes work identically whether `arr_vpn_mode` is `"tailscale"` or `"gluetun"`.

### Alternatives Considered
- Enabling `--exit-node` on host `tailscaled`: Rejected because routing the entire host `fidelacchius` through a Mullvad exit node breaks incoming Tailscale Funnel traffic for Vaultwarden and forces Backblaze B2 backups and SSH through Mullvad.
- Floating `:latest` tags: Rejected per Constitution Principle V (*Centralized, Locked Supply Chain*).

---

## 2. Tailscale WireGuard Exit Node & Strict Kernel Netfilter Kill-Switch (`FR-002`)

### Question / Unknown
How should `qbittorrent` (`arr_qbittorrent`) be isolated inside `arr_vpn` (`ghcr.io/tailscale/tailscale:v1.76.6`) so that:
1. 100% of peer traffic traverses the Tailscale Mullvad / exit node WireGuard tunnel (`tailscale0`),
2. Zero packets ever leak over the container's `eth0` bridge to the host WAN—even before `tailscaled` finishes authenticating or if the exit node disconnects, and
3. The qBittorrent WebUI remains reachable on host loopback `127.0.0.1:8080`?
Furthermore, what Tailscale Admin Console settings are required for a container node to use Mullvad exit nodes?

### Decision
1. **Shared Network Namespace**:
   - Configure `qbittorrent` with `network_mode: "service:vpn"` and `depends_on: vpn: condition: service_healthy`.
   - Publish `127.0.0.1:8080:8080` on the `vpn` service definition.
2. **UID-Isolated Kernel Netfilter Kill-Switch (`/opt/services/arr/vpn/killswitch.sh`)**:
   - Inside the shared `service:vpn` network namespace, `tailscaled` runs as `root` (`UID 0`) while `qbittorrent` (`lscr.io/linuxserver/qbittorrent`) drops privileges to `PUID=1000` (`PGID=1001`).
   - Before `containerboot` starts `tailscaled`, `/usr/local/bin/arr-vpn-killswitch.sh` installs strict `iptables` and `ip6tables` `OUTPUT` rules using the kernel `owner` match module (`-m owner --uid-owner 1000`):
     - Allow loopback (`-o lo -j ACCEPT`).
     - Allow TCP WebUI responses from source port `8080` on `eth0` (`iptables -I OUTPUT -o eth0 -p tcp --sport 8080 -m owner --uid-owner 1000 -j ACCEPT`) so host loopback (`127.0.0.1:8080`) and Caddy can reach the qBittorrent WebUI over the Docker bridge.
     - **Unconditionally DROP all other IPv4 traffic from `UID 1000` on `eth0`**:
       `iptables -A OUTPUT -o eth0 -m owner --uid-owner 1000 -j DROP`
     - **Unconditionally DROP all non-loopback IPv6 traffic from `UID 1000`**:
       `ip6tables -A OUTPUT ! -o lo -m owner --uid-owner 1000 -j DROP`
   - Because `UID 0` (`tailscaled`) is not matched by `--uid-owner 1000`, `tailscaled` can freely communicate with Tailscale coordination servers and establish encrypted WireGuard UDP tunnels over `eth0`, while `qbittorrent` (`UID 1000`) is physically incapable of sending any packet out `eth0` except TCP port `8080` WebUI replies.
3. **Exit-Node Online Guard & Healthcheck (`/opt/services/arr/vpn/healthcheck.sh`)**:
   - Executed every 15s by Docker healthcheck (`test: ["CMD", "/usr/local/bin/arr-vpn-healthcheck.sh"]`):
     - Verifies the `iptables` `OUTPUT -o eth0 -m owner --uid-owner 1000 -j DROP` rule is active.
     - Queries `tailscale status --json` to verify `BackendState == "Running"` and `ExitNodeStatus.Online == true`.
     - If `ExitNodeStatus` is missing or `Online != true`, inserts `iptables -I OUTPUT -o tailscale0 -m owner --uid-owner 1000 -j DROP` and exits `1` (`unhealthy`), blocking `UID 1000` on `tailscale0` as well so zero packets leave `qbittorrent` when the exit node is down. When `ExitNodeStatus.Online == true`, removes the temporary `tailscale0` block and verifies external IP connectivity.
4. **Required Tailscale Admin Console Configuration**:
   - **Why `tailscale exit-node list` initially shows `no exit nodes found`**: In Tailscale, Mullvad VPN exit nodes are only visible to tailnet nodes that have been explicitly granted a Mullvad device slot or the `mullvad` node attribute in the Tailscale Admin Console.
   - **Step A (ACL `nodeAttrs` or Mullvad Device Assignment)**:
     - In **Tailscale Admin Console -> Access Controls** (`https://login.tailscale.com/admin/acls`), grant `mullvad` to `tag:arr-vpn` (or `autogroup:member`):
       ```json
       "tagOwners": {
         "tag:arr-vpn": ["autogroup:admin"]
       },
       "nodeAttrs": [
         {
           "target": ["tag:arr-vpn", "autogroup:member"],
           "attr": ["mullvad"]
         }
       ]
       ```
       Alternatively, in **Tailscale Admin Console -> Mullvad VPN** (`https://login.tailscale.com/admin/mullvad`), toggle on the device slot for `fidelacchius-arr-vpn`.
   - **Step B (Auth Key & Exit Node Identifier)**:
     - Generate a reusable Auth Key (tagged `tag:arr-vpn`) in **Settings -> Keys** and store it as `vault_arr_tailscale_auth_key` in `ansible/inventory/group_vars/all/vault.yml`.
     - Set `vault_arr_tailscale_exit_node` in `vault.yml` to the desired Mullvad exit node hostname or IP (discoverable via `tailscale exit-node list`, e.g., `us-nyc-wg-301.mullvad.ts.net`).

### Rationale
- Combining Linux network namespace sharing (`service:vpn`), kernel `xt_owner` (`--uid-owner 1000`) `DROP` rules on `eth0`, and active `ExitNodeStatus.Online` verification provides a defense-in-depth kill-switch that is mathematically impervious to application bypass, DNS leaks, or exit-node dropouts (`SC-002`).

---

## 3. Three-Tier Storage Architecture, Atomic Moves & SnapRAID Exclusions (`FR-004`, `FR-005`, `FR-006`)

### Question / Unknown
How should directories, mounts, and SnapRAID parity rules be structured across NVMe, scratch, and MergerFS so that active torrent downloads never cause parity churn while completed downloads can be atomically hardlinked/moved into media libraries?

### Decision
1. **Tier 0 Fast NVMe (`/opt/services/arr`)**:
   - Create Stage 1 active directories:
     - `/opt/services/arr/vpn/config` (`0700`, `root:root` for `tailscaled` state `tailscaled.state`)
     - `/opt/services/arr/gluetun/config` (`0775`, `1000:1001` for optional Gluetun mode)
     - `/opt/services/arr/qbittorrent/config` (`0775`, `1000:1001`)
     - `/opt/services/arr/jellyfin/config` (`0775`, `1000:1001`)
   - Pre-create Stage 2A/2B/2C config directory scaffolding (`FR-004`):
     - `/opt/services/arr/{ersatztv,jellyseerr,prowlarr,radarr,sonarr}/config` (`0775`, `1000:1001`)
   - Create backup staging directory: `/opt/services/arr/backups` (`0750`, `root:root`).
2. **Tier 2 Non-Parity Scratch (`/mnt/scratch/downloads/incomplete`)**:
   - Bind-mount `/mnt/scratch/downloads/incomplete:/mnt/scratch/downloads/incomplete` into `qbittorrent`.
3. **Tier 1 Pooled MergerFS (`/mnt/storage`)**:
   - Create `/mnt/storage/downloads/complete`, `/mnt/storage/media/movies`, and `/mnt/storage/media/tv` with `admin:storage` (`1000:1001`) ownership and `2775` setgid mode.
   - Bind-mount the single `/mnt/storage:/mnt/storage` root into `qbittorrent` so `/mnt/storage/downloads/complete` and `/mnt/storage/media/{movies,tv}` share one filesystem device ID (`st_dev`) for instant `link(2)` / `rename(2)` atomic operations in Stage 2C.
4. **SnapRAID Exclusion (`FR-005`)**:
   - Add `/downloads/` to `snapraid_excludes` in `ansible/roles/snapraid/defaults/main.yml` so `/mnt/disks/data*/downloads/` is excluded from SnapRAID parity calculations while `/media/` remains parity-protected.

---

## 4. Hardware-Accelerated Transcoding on Intel UHD 770 (`FR-003`)

### Decision
- Pass deterministic PCI udev device paths into `jellyfin`:
  - `/dev/dri/by-path/pci-0000:00:02.0-render:/dev/dri/renderD128`
  - `/dev/dri/by-path/pci-0000:00:02.0-card:/dev/dri/card0`
- Set `LIBVA_DRIVER_NAME=iHD` in `jellyfin` environment variables.
- Strictly prohibit any reference to `pci-0000:03:00.0` (AMD Radeon RX 6700 XT).

---

## 5. Internal-Only Reverse Proxy Ingress & Tailscale Subnet Routing (`FR-007`)

### Question / Unknown
How should Stage 1 Web UIs be exposed over internal LAN and Tailscale via Caddy (`/etc/caddy/conf.d/40-arr.caddy`) given that `/etc/caddy/Caddyfile` uses `default_bind 127.0.0.1 192.168.4.57` (so port 443 on `100.103.39.60` remains dedicated to Vaultwarden Tailscale Funnel)?

### Decision
- Bind container ports strictly to host loopback (`127.0.0.1:8096:8096` on `arr_jellyfin`, `127.0.0.1:8080:8080` on `arr_vpn`).
- Deploy `/etc/caddy/conf.d/40-arr.caddy` defining virtual hosts `jellyfin.{$HOMELAB_DOMAIN:lan}` and `qbittorrent.{$HOMELAB_DOMAIN:lan}` with:
  - `tls internal`
  - Explicit internal client IP guard (`@internal remote_ip 127.0.0.0/8 192.168.4.0/24 100.64.0.0/10 ::1`) proxying to `127.0.0.1:8096` and `127.0.0.1:8080` and returning `403` to any other source.
- Document Tailscale Subnet Routing (`sudo tailscale set --advertise-routes=192.168.4.0/24` on `fidelacchius`) so remote tailnet devices (`iphone173`, `mattframework`) seamlessly reach `192.168.4.57:443` (`jellyfin.lan`, `qbittorrent.lan`) without disturbing Tailscale Funnel on `100.103.39.60:443`.

---

## 6. Continuous Backup Hook & Offsite Restic Exclusions (`FR-008`)

### Decision
- Deploy `/etc/homelab/backup.d/40-arr.sh` supporting `pre-backup` and `post-restore`:
  - **`pre-backup`**: Scans `/opt/services/arr/*/config` for SQLite databases (`*.db`, `*.sqlite3`), runs `sqlite3 "<db>" "VACUUM INTO '<snapshot>'"` + `PRAGMA integrity_check` (`ok` required), and archives service configs (`vpn`, `gluetun`, `qbittorrent`, `jellyfin`) into `/opt/services/arr/backups/arr-configs-snapshot.tar.gz` (`0640`).
  - **`post-restore`**: Restores missing SQLite databases and configs, enforces `0600` on `/opt/services/arr/.env`, `0700` on `/opt/services/arr/vpn/config`, and `1000:1001` on media/download service configs.
- Update `ansible/roles/backup/defaults/main.yml` and `ansible/roles/backup/templates/backup-excludes.txt.j2` to exclude `/mnt/storage/downloads/**`, `/mnt/storage/media/movies/**`, `/mnt/storage/media/tv/**`, live `*.db`/`*.sqlite3` files under `config/`, and Jellyfin `cache/`, `metadata/`, and `transcodes/`.

---

## 7. Automated Live Acceptance Verification Suite (`FR-009`, `FR-012`)

### Decision
- Implement `scripts/verify-phase5-arr.sh`, `scripts/verify-phase5-arr.ps1`, and `ansible/playbooks/verify-phase5-arr.yml` enforcing the 10-point assertion matrix `ARR-01` through `ARR-10`:
  - `ARR-01`: `arr.service` active and 3 containers (`arr_vpn`, `arr_qbittorrent`, `arr_jellyfin`) running healthy with 0 restarts.
  - `ARR-02`: `arr_vpn` tunnel and exit node online (`tailscale status --json` `ExitNodeStatus.Online == true` in `tailscale` mode, or Gluetun healthy in `gluetun` mode), external IP observed inside `arr_vpn`/`arr_qbittorrent` differs from host WAN IP (`!=` host WAN IP), and kernel netfilter kill-switch (`DROP` on `eth0` for `UID 1000`) active.
  - `ARR-03`: `arr_qbittorrent` network namespace isolated inside `arr_vpn` (`container:<arr_vpn_id>`) with zero independent bridge interfaces.
  - `ARR-04`: Jellyfin `/health` (`http://127.0.0.1:8096/health`) returns HTTP 200 (`Healthy`) and qBittorrent WebUI (`http://127.0.0.1:8080`) returns HTTP 200.
  - `ARR-05`: Loopback binding (`127.0.0.1:8096`, `127.0.0.1:8080`) verified; `/etc/caddy/conf.d/40-arr.caddy` validates and enforces internal-only access.
  - `ARR-06`: Intel UHD 770 iGPU (`/dev/dri/by-path/pci-0000:00:02.0-render`) bound to `arr_jellyfin` with `LIBVA_DRIVER_NAME=iHD`; discrete AMD GPU (`03:00.0`) completely isolated.
  - `ARR-07`: Three-tier storage layout (`/opt/services/arr` Stage 1+2 scaffold, `/mnt/scratch/downloads/incomplete`, `/mnt/storage/downloads/complete`, `/mnt/storage/media/{movies,tv}` on single `/mnt/storage` mount) and `/etc/snapraid.conf` `/downloads/` exclusion verified.
  - `ARR-08`: Unified permissions (`PUID=1000`, `PGID=1001`, `UMASK=002`, mode `2775` setgid) verified across scratch, complete downloads, and media directories.
  - `ARR-09`: Secret isolation (`.env` `0600`, `.env.example` exists, 0 git secret leaks) and `/etc/homelab/backup.d/40-arr.sh pre-backup` snapshot integrity verified.
  - `ARR-10`: Structured `journald` and container telemetry free of unhandled fatal errors or leaked credentials.
