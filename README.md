# homelab2 (Fidelacchius)

Resilient, declarative-first personal server platform hosted on bare-metal node **fidelacchius** (the sword of faith) running Arch Linux with zero unnecessary operational toil.

## Architecture & Roadmap Overview

- **Phase 1: Bare-Metal Live Bootstrap & Base OS Provisioning** *(Completed)*: Idempotent Arch Linux installation directly onto target hardware (`192.168.4.57`).
- **Phase 2: Base System Hardening & Configuration Management** *(Completed)*: Ansible IaC foundation, secrets isolation, OpenSSH hardening, sudo rules, hardware udev rules, chrony, and system safeguards.
- **Phase 3: Network & Remote Access Overlay** *(Completed)*: Tailscale mesh VPN (`fidelacchius.fable-mackarel.ts.net`), nftables default-drop firewall, Caddy reverse proxy with internal TLS and modular ingress drop-ins.
- **Phase 4: Storage Pooling & Data Resiliency Layer** *(Completed)*: NVMe fast tier (`/opt/services`), MergerFS unified pool (`/mnt/storage`), SnapRAID parity snapshots, and isolated scratch disk (`/mnt/scratch`).
- **Phase 5: Application Platform** *(In Progress)*: Containerized service workloads supervised via systemd units and isolated Docker Compose stacks.
  - **Vaultwarden** *(Completed)*: Bitwarden-compatible password manager bound to loopback `127.0.0.1:8088`, exposed publicly via Tailscale Funnel at `https://fidelacchius.fable-mackarel.ts.net` with automated TLS, WebSocket push notifications, transactional SQLite online backups, and client-side encrypted offsite backups to Backblaze B2 bucket `fidelacchius-backups`.
  - **Immich** *(Completed)*: High-performance photo and video management platform (`v1.118.2`) bound to loopback `127.0.0.1:2283`, fronted by Caddy reverse proxy at `photos.{$HOMELAB_DOMAIN:lan}` and `https://photos.fidelacchius.ts.net` with 50GB streaming upload buffers. Configured with two-tier storage (NVMe database/thumbnails and MergerFS library pool with `2775` permissions), Intel UHD 770 iGPU hardware transcoding, transactional PostgreSQL dump backups via `/etc/homelab/backup.d/30-immich.sh`, and Restic offsite synchronization.
  - **Media & Arr Stack — Stage 1** *(Completed)*: Core household media streaming and VPN-isolated torrent download foundation supervised by `arr.service` at `/opt/services/arr`. Consists of `arr_vpn` (`ghcr.io/tailscale/tailscale:v1.76.6` Tailscale Mullvad / Exit Node WireGuard gateway by default, or optional `gluetun:v3.39.1`, enforced by kernel netfilter `UID 1000` `eth0` `DROP` kill-switch), `arr_qbittorrent` (`lscr.io/linuxserver/qbittorrent:5.0.2` isolated inside `network_mode: "service:vpn"`), and `arr_jellyfin` (`lscr.io/linuxserver/jellyfin:10.10.3` with Intel UHD 770 `iHD` iGPU hardware transcoding). Configured across three storage tiers (NVMe `/opt/services/arr` with Stage 2A/2B/2C config scaffolding, Tier 2 scratch `/mnt/scratch/downloads/incomplete`, and Tier 1 MergerFS `/mnt/storage/{downloads/complete,media/movies,media/tv}` with `2775` `admin:storage` permissions and SnapRAID `/downloads/` exclusion), internal-only Caddy reverse proxy (`/etc/caddy/conf.d/40-arr.caddy`), online SQLite snapshot hook (`/etc/homelab/backup.d/40-arr.sh`), and Restic bulk media exclusions.

### Port Allocations

| Service | Internal Port | Ingress Domain / Route | Ingress Type |
|---|---|---|---|
| Caddy Health | 80 | `http://127.0.0.1:80/health` | Local / Ingress health |
| Vaultwarden | 8088 | `https://fidelacchius.fable-mackarel.ts.net` | Tailscale Funnel / Public HTTPS |
| Immich Server | 2283 | `photos.{$HOMELAB_DOMAIN:lan}`, `https://photos.fidelacchius.ts.net` | Caddy Reverse Proxy (LAN & Tailscale) |
| Jellyfin (`arr_jellyfin`) | 8096 | `jellyfin.{$HOMELAB_DOMAIN:lan}` | Caddy Internal-Only Proxy (LAN & Tailscale) |
| qBittorrent (`arr_qbittorrent` via `arr_vpn`) | 8080 | `qbittorrent.{$HOMELAB_DOMAIN:lan}` | Caddy Internal-Only Proxy (LAN & Tailscale) |

## Convergence & Verification

### Convergence Runners

```powershell
# From Windows Operator Workstation (Media & Arr Stage 1):
./scripts/apply-phase5-arr.ps1 -Host 192.168.4.57 -User admin

# Immich:
./scripts/apply-phase5-immich.ps1 -HostAddress 192.168.4.57 -User admin

# Vaultwarden:
./scripts/apply-phase5.ps1 -HostAddress 192.168.4.58 -User admin
```

```bash
# From POSIX / Linux / SSH (Media & Arr Stage 1):
./scripts/apply-phase5-arr.sh --host 192.168.4.57 --user admin

# Immich:
./scripts/apply-phase5-immich.sh --host 192.168.4.57 --user admin

# Vaultwarden:
./scripts/apply-phase5.sh --host 192.168.4.58 --user admin
```

### Acceptance Verification

```powershell
# Run Backup & Staged Disaster Recovery acceptance suite (12-point matrix BK-001 through BK-012):
./scripts/verify-phase5-backup.ps1 -TargetHost 192.168.4.57 -User admin

# Run Media & Arr Stage 1 acceptance suite (10-point matrix ARR-01 through ARR-10):
./scripts/verify-phase5-arr.ps1 -Host 192.168.4.57 -User admin

# Run Immich acceptance test suite (9-point matrix):
./scripts/verify-phase5-immich.ps1 -TargetHost 192.168.4.57 -User admin

# Vaultwarden:
./scripts/verify-phase5-vaultwarden.ps1 -TargetHost 192.168.4.58 -User admin
```

```bash
# Run Backup & Staged Disaster Recovery acceptance suite on target host:
sudo ./scripts/verify-phase5-backup.sh

# Run structured JSON report:
sudo ./scripts/verify-phase5-backup.sh --json

# Run Media & Arr Stage 1 acceptance test suite locally or via SSH:
./scripts/verify-phase5-arr.sh --local

# Run Media & Arr Stage 1 structured JSON report:
./scripts/verify-phase5-arr.sh --local --json

# Run Immich acceptance test suite on target host or via SSH:
./scripts/verify-phase5-immich.sh

# Run structured JSON report:
./scripts/verify-phase5-immich.sh --json
```

### Staged Disaster Recovery Tooling

Bare-metal disaster recovery from Backblaze B2 is decoupled into automated stages to prevent bare-metal dependency loops and eliminate root NVMe disk leakage:

- **Stage 1 (Bootstrap & Secrets)**: Restores `/etc/homelab/vault.yml`, SSH keys, and project repos on clean hardware, syncs `vault.yml` to the Ansible inventory, and strictly excludes `/mnt/storage`:
  ```bash
  sudo -E ./scripts/restore-from-b2.sh --stage config --target-dir / --force
  ```
- **Inter-Stage Platform Convergence**: Run `ansible-playbook -i inventory/hosts.yml playbooks/site.yml --connection=local` to partition and mount the MergerFS storage pool at `/mnt/storage` and configure Docker.
- **Stage 2 (Bulk Data & Database Hooks)**: Enforces active mountpoint verification (`mountpoint -q /mnt/storage`) to prevent NVMe leakage, restores `/opt/services` and `/mnt/storage/media/photos`, starts container services, and executes post-restore database hooks:
  ```bash
  sudo -E ./scripts/restore-from-b2.sh --stage data --target-dir / --force
  ```
- **Workstation Orchestration**: Run remotely from Windows/Linux operator workstations:
  ```powershell
  ./scripts/restore-from-b2.ps1 -HostAddress 192.168.4.57 -User admin -Stage config -Force
  ./scripts/restore-from-b2.ps1 -HostAddress 192.168.4.57 -User admin -Stage data -Force
  ```

## Governance & Documentation

- [Full Bare-Metal Disaster Recovery & Restore Runbook](docs/full-restore-runbook.md)
- [Operational Runbook (Antigravity & Immich)](docs/operations.md)
- [Phase 1 Bare-Metal Arch Installer Guide](scripts/install/README.md)
- [Roadmap & Vision](ROADMAP.md)
- [Constitution](.specify/memory/constitution.md)
