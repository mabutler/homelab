# Contract: Media & Arr Stage 1 Service, VPN Kill-Switch, iGPU & Storage (`ARR-SERVICE-V1`)

**Feature**: `015-media-arr-stage1`  
**Date**: 2026-11-17  
**Requirements Covered**: FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-010, FR-011

---

## 1. Three-Tier Directory & Permission Contract

| Host Path | Owner:Group | Mode | Storage Tier | Purpose |
|---|---|---|---|---|
| `/opt/services/arr` | `root:root` | `0755` | Tier 0 NVMe | Media & Arr stack root directory |
| `/opt/services/arr/compose.yml` | `root:root` | `0644` | Tier 0 NVMe | Declarative Docker Compose manifest (Stage 1) |
| `/opt/services/arr/.env` | `root:root` | `0600` | Tier 0 NVMe | Isolated Tailscale auth key, exit node, VPN keys & env vars |
| `/opt/services/arr/.env.example` | `root:root` | `0644` | Tier 0 NVMe | Committed sanitized environment template |
| `/opt/services/arr/backups` | `root:root` | `0750` | Tier 0 NVMe | Staging directory for online SQLite & config snapshots |
| `/opt/services/arr/vpn` | `root:root` | `0755` | Tier 0 NVMe | VPN gateway scripts & state parent directory |
| `/opt/services/arr/vpn/killswitch.sh` | `root:root` | `0755` | Tier 0 NVMe | Kernel `iptables`/`ip6tables` `UID 1000` kill-switch enforcement |
| `/opt/services/arr/vpn/healthcheck.sh` | `root:root` | `0755` | Tier 0 NVMe | ExitNodeStatus.Online + kill-switch + external IP probe |
| `/opt/services/arr/vpn/config` | `root:root` | `0700` | Tier 0 NVMe | Dedicated Tailscale state (`tailscaled.state`) for `arr_vpn` |
| `/opt/services/arr/gluetun/config` | `1000:1001` | `0775` | Tier 0 NVMe | Optional Gluetun VPN state directory (`arr_vpn_mode: gluetun`) |
| `/opt/services/arr/qbittorrent/config` | `1000:1001` | `0775` | Tier 0 NVMe | qBittorrent configuration and fastresume state |
| `/opt/services/arr/jellyfin/config` | `1000:1001` | `0775` | Tier 0 NVMe | Jellyfin SQLite databases, XML configs, and metadata |
| `/opt/services/arr/ersatztv/config` | `1000:1001` | `0775` | Tier 0 NVMe | Pre-created config scaffolding for Stage 2A (`ersatztv`) |
| `/opt/services/arr/jellyseerr/config` | `1000:1001` | `0775` | Tier 0 NVMe | Pre-created config scaffolding for Stage 2B (`jellyseerr`) |
| `/opt/services/arr/prowlarr/config` | `1000:1001` | `0775` | Tier 0 NVMe | Pre-created config scaffolding for Stage 2C (`prowlarr`) |
| `/opt/services/arr/radarr/config` | `1000:1001` | `0775` | Tier 0 NVMe | Pre-created config scaffolding for Stage 2C (`radarr`) |
| `/opt/services/arr/sonarr/config` | `1000:1001` | `0775` | Tier 0 NVMe | Pre-created config scaffolding for Stage 2C (`sonarr`) |
| `/mnt/scratch/downloads` | `admin:storage` (`1000:1001`) | `2775` | Tier 2 Scratch | Root download directory on dedicated non-parity scratch |
| `/mnt/scratch/downloads/incomplete` | `admin:storage` (`1000:1001`) | `2775` | Tier 2 Scratch | Active in-progress torrent swarms (off parity drives) |
| `/mnt/storage/downloads` | `admin:storage` (`1000:1001`) | `2775` | Tier 1 MergerFS | Completed download parent on pooled storage (SnapRAID excluded) |
| `/mnt/storage/downloads/complete` | `admin:storage` (`1000:1001`) | `2775` | Tier 1 MergerFS | Finished torrent payloads sharing `/mnt/storage` mount |
| `/mnt/storage/media` | `admin:storage` (`1000:1001`) | `2775` | Tier 1 MergerFS | Parity-protected media library root |
| `/mnt/storage/media/movies` | `admin:storage` (`1000:1001`) | `2775` | Tier 1 MergerFS | Household movie library (SnapRAID parity-protected) |
| `/mnt/storage/media/tv` | `admin:storage` (`1000:1001`) | `2775` | Tier 1 MergerFS | Household TV show library (SnapRAID parity-protected) |

---

## 2. Docker Compose Manifest Contract (`/opt/services/arr/compose.yml`)

### 2.1 Default Mode (`arr_vpn_mode: "tailscale"` — Tailscale Mullvad / Exit Node WireGuard)

```yaml
# Docker Compose manifest for Media & Arr Stack - Stage 1
# Managed by Ansible - homelab2
# Contract: ARR-SERVICE-V1

services:
  vpn:
    container_name: arr_vpn
    image: ghcr.io/tailscale/tailscale:${TAILSCALE_VERSION:-v1.76.6}
    hostname: ${TS_HOSTNAME:-fidelacchius-arr-vpn}
    restart: unless-stopped
    stop_grace_period: 30s
    cap_add:
      - NET_ADMIN
      - NET_RAW
    devices:
      - /dev/net/tun:/dev/net/tun
    ports:
      - "${ARR_HOST_BIND:-127.0.0.1}:${QBITTORRENT_WEBUI_PORT:-8080}:${QBITTORRENT_WEBUI_PORT:-8080}"
    env_file:
      - .env
    environment:
      - TZ=${TZ:-America/New_York}
      - TS_AUTHKEY=${TS_AUTHKEY}
      - TS_HOSTNAME=${TS_HOSTNAME:-fidelacchius-arr-vpn}
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_USERSPACE=false
      - TS_ACCEPT_DNS=true
      - TS_EXTRA_ARGS=--exit-node=${TS_EXIT_NODE} --exit-node-allow-lan-access=true --accept-dns=true
    entrypoint:
      - /bin/sh
      - -c
      - "/usr/local/bin/arr-vpn-killswitch.sh && exec /usr/local/bin/containerboot"
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - ${ARR_SERVICE_DIR:-/opt/services/arr}/vpn/config:/var/lib/tailscale
      - ${ARR_SERVICE_DIR:-/opt/services/arr}/vpn/killswitch.sh:/usr/local/bin/arr-vpn-killswitch.sh:ro
      - ${ARR_SERVICE_DIR:-/opt/services/arr}/vpn/healthcheck.sh:/usr/local/bin/arr-vpn-healthcheck.sh:ro
    healthcheck:
      test: ["CMD", "/usr/local/bin/arr-vpn-healthcheck.sh"]
      interval: 15s
      timeout: 10s
      retries: 3
      start_period: 30s

  qbittorrent:
    container_name: arr_qbittorrent
    image: lscr.io/linuxserver/qbittorrent:${QBITTORRENT_VERSION:-5.0.2}
    restart: unless-stopped
    stop_grace_period: 30s
    network_mode: "service:vpn"
    depends_on:
      vpn:
        condition: service_healthy
    environment:
      - PUID=${PUID:-1000}
      - PGID=${PGID:-1001}
      - UMASK=${UMASK:-002}
      - TZ=${TZ:-America/New_York}
      - WEBUI_PORT=${QBITTORRENT_WEBUI_PORT:-8080}
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - ${ARR_SERVICE_DIR:-/opt/services/arr}/qbittorrent/config:/config
      - ${ARR_SCRATCH_INCOMPLETE_DIR:-/mnt/scratch/downloads/incomplete}:/mnt/scratch/downloads/incomplete
      - ${ARR_STORAGE_ROOT:-/mnt/storage}:/mnt/storage
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:${QBITTORRENT_WEBUI_PORT:-8080} >/dev/null || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  jellyfin:
    container_name: arr_jellyfin
    image: lscr.io/linuxserver/jellyfin:${JELLYFIN_VERSION:-10.10.3}
    restart: unless-stopped
    stop_grace_period: 30s
    ports:
      - "${ARR_HOST_BIND:-127.0.0.1}:${JELLYFIN_HTTP_PORT:-8096}:8096"
    environment:
      - PUID=${PUID:-1000}
      - PGID=${PGID:-1001}
      - UMASK=${UMASK:-002}
      - TZ=${TZ:-America/New_York}
      - LIBVA_DRIVER_NAME=${LIBVA_DRIVER_NAME:-iHD}
    devices:
      - source: /dev/dri/by-path/pci-0000:00:02.0-render
        target: /dev/dri/renderD128
        permissions: rwm
      - source: /dev/dri/by-path/pci-0000:00:02.0-card
        target: /dev/dri/card0
        permissions: rwm
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - ${ARR_SERVICE_DIR:-/opt/services/arr}/jellyfin/config:/config
      - ${ARR_STORAGE_MOVIES_DIR:-/mnt/storage/media/movies}:/mnt/storage/media/movies
      - ${ARR_STORAGE_TV_DIR:-/mnt/storage/media/tv}:/mnt/storage/media/tv
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://127.0.0.1:8096/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 45s

  # Stage 2A (ersatztv), Stage 2B (jellyseerr), and Stage 2C (prowlarr, radarr, sonarr)
  # extend this compose stack additively in subsequent stages.
```

*(Note: When `arr_vpn_mode: "gluetun"` is configured, `ansible/roles/arr/templates/compose.yml.j2` renders the `vpn` service (`container_name: arr_vpn`) using `ghcr.io/qdm12/gluetun:${GLUETUN_VERSION:-v3.39.1}` with `FIREWALL=on` and `127.0.0.1:8000:8000` while `qbittorrent` and `jellyfin` remain identical.)*

---

## 3. Kernel Netfilter Kill-Switch & Healthcheck Contracts (`/opt/services/arr/vpn/`)

### 3.1 Kill-Switch Script (`/opt/services/arr/vpn/killswitch.sh`)

```sh
#!/bin/sh
# /opt/services/arr/vpn/killswitch.sh
# Managed by Ansible - homelab2
# Enforces kernel netfilter kill-switch for UID 1000 (arr_qbittorrent) inside arr_vpn
set -eu

QBIT_UID="${PUID:-1000}"
WEBUI_PORT="${QBITTORRENT_WEBUI_PORT:-8080}"

# 1. Ensure loopback traffic is permitted
iptables -C OUTPUT -o lo -j ACCEPT 2>/dev/null || iptables -I OUTPUT 1 -o lo -j ACCEPT

# 2. Permit qBittorrent WebUI TCP responses on eth0 (bound to 127.0.0.1:${WEBUI_PORT} on host)
iptables -C OUTPUT -o eth0 -p tcp --sport "${WEBUI_PORT}" -m owner --uid-owner "${QBIT_UID}" -j ACCEPT 2>/dev/null || \
    iptables -I OUTPUT 2 -o eth0 -p tcp --sport "${WEBUI_PORT}" -m owner --uid-owner "${QBIT_UID}" -j ACCEPT

# 3. Unconditionally DROP all other IPv4 egress from UID 1000 on eth0 (prevents any WAN/LAN leak)
iptables -C OUTPUT -o eth0 -m owner --uid-owner "${QBIT_UID}" -j DROP 2>/dev/null || \
    iptables -A OUTPUT -o eth0 -m owner --uid-owner "${QBIT_UID}" -j DROP

# 4. Unconditionally DROP all non-loopback IPv6 egress from UID 1000
if command -v ip6tables >/dev/null 2>&1; then
    ip6tables -C OUTPUT -o lo -j ACCEPT 2>/dev/null || ip6tables -I OUTPUT 1 -o lo -j ACCEPT
    ip6tables -C OUTPUT ! -o lo -m owner --uid-owner "${QBIT_UID}" -j DROP 2>/dev/null || \
        ip6tables -A OUTPUT ! -o lo -m owner --uid-owner "${QBIT_UID}" -j DROP
fi

echo "INFO: arr_vpn kernel netfilter kill-switch active for UID ${QBIT_UID} (eth0 DROP enforced)."
```

### 3.2 Healthcheck & Exit-Node Guard Script (`/opt/services/arr/vpn/healthcheck.sh`)

```sh
#!/bin/sh
# /opt/services/arr/vpn/healthcheck.sh
# Managed by Ansible - homelab2
# Verifies kill-switch rules, Tailscale BackendState, and active ExitNodeStatus.Online
set -eu

QBIT_UID="${PUID:-1000}"

# 1. Verify eth0 kill-switch rule is present (re-apply if missing)
if ! iptables -C OUTPUT -o eth0 -m owner --uid-owner "${QBIT_UID}" -j DROP 2>/dev/null; then
    /usr/local/bin/arr-vpn-killswitch.sh
fi

# 2. Query tailscale status --json and verify Running + ExitNodeStatus.Online == true
STATUS_JSON="$(tailscale status --json 2>/dev/null || true)"
if [ -z "${STATUS_JSON}" ]; then
    iptables -C OUTPUT -o tailscale0 -m owner --uid-owner "${QBIT_UID}" -j DROP 2>/dev/null || \
        iptables -I OUTPUT 1 -o tailscale0 -m owner --uid-owner "${QBIT_UID}" -j DROP
    echo "CRITICAL: tailscale status unavailable" >&2
    exit 1
fi

# Check BackendState == Running and ExitNodeStatus.Online == true
if ! printf '%s\n' "${STATUS_JSON}" | grep -q '"BackendState": *"Running"' || \
   ! printf '%s\n' "${STATUS_JSON}" | tr -d '\n\r ' | grep -q '"ExitNodeStatus":{[^}]*"Online":true'; then
    iptables -C OUTPUT -o tailscale0 -m owner --uid-owner "${QBIT_UID}" -j DROP 2>/dev/null || \
        iptables -I OUTPUT 1 -o tailscale0 -m owner --uid-owner "${QBIT_UID}" -j DROP
    echo "CRITICAL: Tailscale exit node is not online; UID ${QBIT_UID} blocked on tailscale0" >&2
    exit 1
fi

# 3. Exit node is online -> ensure tailscale0 block is removed so UID 1000 can use exit node
while iptables -C OUTPUT -o tailscale0 -m owner --uid-owner "${QBIT_UID}" -j DROP 2>/dev/null; do
    iptables -D OUTPUT -o tailscale0 -m owner --uid-owner "${QBIT_UID}" -j DROP || break
done

exit 0
```

---

## 4. Systemd Unit Contract (`/etc/systemd/system/arr.service`)

```ini
[Unit]
Description=Media & Arr Stack (Docker Compose)
Requires=docker.service local-fs.target
After=docker.service network-online.target local-fs.target
Wants=network-online.target
RequiresMountsFor=/opt/services /mnt/storage /mnt/scratch

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/services/arr
ExecStart=/usr/bin/docker compose up -d --remove-orphans
ExecStop=/usr/bin/docker compose down
ExecReload=/usr/bin/docker compose up -d --remove-orphans
TimeoutStartSec=300
TimeoutStopSec=90

[Install]
WantedBy=multi-user.target
```

---

## 5. SnapRAID Exclusion Contract (`/etc/snapraid.conf`)

`/etc/snapraid.conf` (managed via `ansible/roles/snapraid/defaults/main.yml`) MUST include:
```ini
exclude /mnt/scratch/
exclude /downloads/
```
so that both `/mnt/scratch/downloads/incomplete` and `/mnt/storage/downloads/complete` (`/mnt/disks/data*/downloads/`) are excluded from SnapRAID parity calculations while `/mnt/storage/media/{movies,tv}` remains parity-protected (`FR-005`).
