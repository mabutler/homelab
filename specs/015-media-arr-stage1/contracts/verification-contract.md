# Contract: Media & Arr Stage 1 Acceptance Verification & Telemetry Matrix (`ARR-VERIFY-V1`)

**Feature**: `015-media-arr-stage1`  
**Date**: 2026-11-17  
**Requirements Covered**: FR-009, FR-011, FR-012, SC-001 through SC-007, Principle III

---

## 1. Automated 10-Point Assertion Matrix (`ARR-01` through `ARR-10`)

| Assertion ID | Exit Code | Target Check | Assertion Command / Probe | Success Criteria |
|---|---|---|---|---|
| **ARR-01** | `1` | Service & Containers Active | `systemctl is-active arr.service` & `docker ps --filter 'name=arr_'` | `arr.service` is `active`; all 3 containers (`arr_vpn`, `arr_qbittorrent`, `arr_jellyfin`) running without restart loops. |
| **ARR-02** | `2` | VPN Exit-Node Tunnel & Kill-Switch IP Isolation | Verify `arr_vpn` exit node online (`tailscale status --json` `ExitNodeStatus.Online == true` in `tailscale` mode, or Gluetun healthy in `gluetun` mode), compare host WAN IP vs. `arr_qbittorrent`/`arr_vpn` external IP, & inspect `iptables` kill-switch | `arr_vpn` reports online exit-node tunnel, valid external VPN IP (`!=` host WAN IP), and active kernel netfilter kill-switch (`DROP` on `eth0` for `UID 1000` in `tailscale` mode or default `DROP` in `gluetun` mode). |
| **ARR-03** | `3` | qBittorrent Network Namespace Isolation | `docker inspect arr_qbittorrent --format '{{.HostConfig.NetworkMode}}'` | `NetworkMode` is `container:<arr_vpn_id>` (`service:vpn`) with zero independent bridge interfaces (`Networks` map empty). |
| **ARR-04** | `4` | Jellyfin `/health` & qBittorrent WebUI Probes | `curl -fsS http://127.0.0.1:8096/health` & `curl -fsS -o /dev/null -w '%{http_code}' http://127.0.0.1:8080` | Jellyfin returns HTTP 200 `"Healthy"`; qBittorrent WebUI returns HTTP 200 on loopback within 500ms. |
| **ARR-05** | `5` | Loopback Binding & Internal Caddy Ingress | Inspect `docker port` / `ss -tln` for `8096`, `8080` & `caddy validate --config /etc/caddy/Caddyfile` | Published ports (`8096`, `8080`) bind strictly to `127.0.0.1` (never `0.0.0.0`); `/etc/caddy/conf.d/40-arr.caddy` exists, enforces `@internal`, and passes `caddy validate`. |
| **ARR-06** | `6` | Intel UHD 770 iGPU Hardware Acceleration & AMD Isolation | Inspect `/opt/services/arr/compose.yml` & `docker inspect arr_jellyfin` devices/env | `pci-0000:00:02.0-render` (`renderD128`) and `LIBVA_DRIVER_NAME=iHD` present in `arr_jellyfin`; discrete AMD GPU (`03:00.0`) strictly unreferenced. |
| **ARR-07** | `7` | Three-Tier Storage Layout & SnapRAID Exclusion | Check Stage 1+2 `/opt/services/arr/*/config` scaffold, `/mnt/scratch/downloads/incomplete`, `/mnt/storage/{downloads/complete,media/movies,media/tv}` same device ID, and `/etc/snapraid.conf` | All Tier 0 (including `vpn/config` and Stage 2A/2B/2C scaffold), Tier 1, and Tier 2 directories exist on mounted tiers; `/mnt/storage/downloads/complete` and `/mnt/storage/media/{movies,tv}` share one `st_dev` mount; `/etc/snapraid.conf` excludes `/downloads/`. |
| **ARR-08** | `8` | Unified Non-Root Ownership & Permissions | `stat -c '%a %u:%g'` on scratch, complete, and media dirs & container `PUID`/`PGID`/`UMASK` | `PUID=1000`, `PGID=1001` (`storage`), `UMASK=002` configured; `/mnt/scratch/downloads/incomplete`, `/mnt/storage/downloads/complete`, and `/mnt/storage/media/{movies,tv}` owned by `1000:1001` with mode `2775`. |
| **ARR-09** | `9` | Secret Isolation & Pre-Backup Hook Readiness | Check `/opt/services/arr/.env` (`0600`), `.env.example`, git leak scan, Restic excludes, and run `/etc/homelab/backup.d/40-arr.sh pre-backup` | `.env` mode `0600`, `.env.example` exists, 0 cleartext Tailscale/VPN keys in git, `40-arr.sh pre-backup` succeeds with verified SQLite `PRAGMA integrity_check` & config archive, and `/etc/homelab/backup-excludes.txt` excludes media/downloads. |
| **ARR-10** | `10` | Structured Telemetry & Redacted Logs | `journalctl -u arr.service -n 50` & `docker logs` across `arr_vpn`, `arr_qbittorrent`, `arr_jellyfin` | Logs flow cleanly with zero fatal panics/segfaults and zero leaked `tskey-auth` tokens, WireGuard private keys, or raw secret placeholders. |

---

## 2. Verification Harness Implementations

The assertion matrix is executed via:
1. **Linux POSIX Runner**: `scripts/verify-phase5-arr.sh` (supports `--local`, `--json`, `--verbose`, `--host`, `--user`, exit codes `1..10` on failure).
2. **Workstation PowerShell Runner**: `scripts/verify-phase5-arr.ps1` (for Windows operator workstation).
3. **Ansible Verification Playbook**: `ansible/playbooks/verify-phase5-arr.yml` (imported into `ansible/playbooks/verify.yml`).

---

## 3. Strict Principle III Compliance Statement (`FR-012`)

In accordance with Constitution Principle III (*Static Verification & Zero Automated Tests*):
- ZERO unit test suites, test files, or mock frameworks are created anywhere in the repository.
- All verification is performed via static linters (`ansible-lint`, `shellcheck`, `bash -n`) and the live acceptance scripts (`scripts/verify-phase5-arr.{sh,ps1}`).
