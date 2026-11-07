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

### Port Allocations

| Service | Internal Port | Ingress Domain / Route | Ingress Type |
|---|---|---|---|
| Caddy Health | 80 | `http://127.0.0.1:80/health` | Local / Ingress health |
| Vaultwarden | 8088 | `https://fidelacchius.fable-mackarel.ts.net` | Tailscale Funnel / Public HTTPS |
| Immich Server | 2283 | `photos.{$HOMELAB_DOMAIN:lan}`, `https://photos.fidelacchius.ts.net` | Caddy Reverse Proxy (LAN & Tailscale) |

## Convergence & Verification

### Convergence Runners

```powershell
# From Windows Operator Workstation (Immich):
./scripts/apply-phase5-immich.ps1 -HostAddress 192.168.4.57 -User admin

# Vaultwarden:
./scripts/apply-phase5.ps1 -HostAddress 192.168.4.58 -User admin
```

```bash
# From POSIX / Linux / SSH (Immich):
./scripts/apply-phase5-immich.sh --host 192.168.4.57 --user admin

# Vaultwarden:
./scripts/apply-phase5.sh --host 192.168.4.58 --user admin
```

### Acceptance Verification

```powershell
# Run Immich acceptance test suite (9-point matrix):
./scripts/verify-phase5-immich.ps1 -TargetHost 192.168.4.57 -User admin

# Vaultwarden:
./scripts/verify-phase5-vaultwarden.ps1 -TargetHost 192.168.4.58 -User admin
```

```bash
# Run Immich acceptance test suite on target host or via SSH:
./scripts/verify-phase5-immich.sh

# Run structured JSON report:
./scripts/verify-phase5-immich.sh --json
```

## Governance & Documentation

- [Roadmap & Vision](ROADMAP.md)
- [Constitution](.specify/memory/constitution.md)
- [Vaultwarden Feature Specification](specs/005-vaultwarden-app/spec.md)
- [Vaultwarden Implementation Plan](specs/005-vaultwarden-app/plan.md)
- [Quickstart & Operational Runbook](specs/005-vaultwarden-app/quickstart.md)
