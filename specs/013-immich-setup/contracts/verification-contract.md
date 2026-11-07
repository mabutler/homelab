# Contract: Immich Acceptance Verification & Telemetry Matrix (`IMMICH-VERIFY-V1`)

**Feature**: `013-immich-setup`  
**Date**: 2026-11-06  
**Requirements Covered**: FR-008, FR-011, SC-004, SC-007, Principle III

---

## 1. Automated Assertion Matrix (`IMM-01` through `IMM-09`)

| Assertion ID | Exit Code | Target Check | Assertion Command / Probe | Success Criteria |
|---|---|---|---|---|
| **IMM-01** | `1` | Service & Containers Active | `systemctl is-active immich.service` & `docker compose ps --format json` | `immich.service` is active; 4 containers (`immich_server`, `immich_machine_learning`, `immich_database`, `immich_redis`) running without restart loops. |
| **IMM-02** | `2` | HTTP API Ping Probe | `curl -fsS -m 2 http://127.0.0.1:2283/api/server/ping` | Returns HTTP 200 with JSON payload `{"res":"pong"}` within 500ms. |
| **IMM-03** | `3` | Intel UHD 770 iGPU Device Binding | Inspect `/opt/services/immich/compose.yml` & container `/dev/dri` | Render device `pci-0000:00:02.0-render` (`renderD128`) mounted; AMD discrete GPU `03:00.0` completely unreferenced. |
| **IMM-04** | `4` | Tiered Storage Topology | Inspect filesystem mounts and volume targets | NVMe holds `/opt/services/immich/data`; MergerFS holds `/mnt/storage/media/photos`. |
| **IMM-05** | `5` | Secret Isolation & Permissions | `stat -c "%a" /opt/services/immich/.env` & git leak check | `.env` file exists with mode `0600`; `.env.example` committed; 0 cleartext passwords in version control. |
| **IMM-06** | `6` | Caddy Ingress Configuration | `caddy validate --config /etc/caddy/Caddyfile` | Caddyfile validation passes with drop-in `/etc/caddy/conf.d/30-immich.caddy` routing to `127.0.0.1:2283`. |
| **IMM-07** | `7` | Storage Group & Ownership | Inspect permissions on `/mnt/storage/media/photos` | `PUID=1000` / `PGID=1001` (`storage` group) with setgid `2775` permission flags. |
| **IMM-08** | `8` | Transactional Backup Hook Execution | Run `/etc/homelab/backup.d/30-immich.sh pre-backup` | Generates non-empty `immich_db_backup.dump` in `/opt/services/immich/backups/`; exit code 0. |
| **IMM-09** | `9` | Structured Telemetry & Clean Logs | `journalctl -u immich.service -n 50` & container logs | Logs flow to journald with zero unhandled fatal exceptions, panic dumps, or leaked credentials. |

---

## 2. Verification Harness Implementations

The assertion matrix is executed via:
1. **Linux POSIX Runner**: `scripts/verify-phase5-immich.sh` (supports `--local`, `--json`, `--verbose`, exit codes 1-9 on failure).
2. **Workstation PowerShell Runner**: `scripts/verify-phase5-immich.ps1` (for Windows operator workstation).
3. **Ansible Verification Playbook**: `ansible/playbooks/verify-phase5-immich.yml` (imported into `ansible/playbooks/verify.yml`).

---

## 3. Strict Principle III Compliance Statement

In accordance with Constitution Principle III (*Zero Automated Test Files, Static Verification & Live Acceptance Verification*):
- ZERO unit test frameworks (`pytest`, `jest`, `mocha`), test runners, or mock frameworks are created.
- Verification is accomplished purely through declarative syntax validation, linters (`ansible-lint`, `shellcheck`, `bash -n`), and live acceptance assertions against running infrastructure.
