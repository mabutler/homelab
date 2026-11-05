# Contract: Automated Acceptance Verification (`FRIGATE-VERIFY-V1`)

**Feature**: `009-frigate-nvr-setup`  
**Date**: 2026-11-04  
**Requirements Covered**: FR-012, SC-001 through SC-005, Constitution Principle III

---

## 1. Verification Suite Overview

- **Target Host Script**: `scripts/verify-phase5-frigate.sh` (supports `--json` output mode)
- **Workstation Wrapper**: `scripts/verify-phase5-frigate.ps1`
- **Ansible Verification Playbook**: `ansible/playbooks/verify-phase5-frigate.yml` (imported into `ansible/playbooks/verify.yml`)

---

## 2. Acceptance Test Matrix (`FRG-01` to `FRG-09`)

| Check ID | Requirement | Assertion Description | Verification Command / Condition |
|---|---|---|---|
| **FRG-01** | FR-001, SC-002 | Frigate systemd service & container active with 0 restart loops | `systemctl is-active frigate.service` is `active` AND `docker inspect -f '{{.State.Status}}:{{.RestartCount}}' frigate` is `running:0` |
| **FRG-02** | FR-002, SC-001 | Frigate HTTP API (`/api/version` & `/api/stats`) responds HTTP 200 within 2s | `curl -fsS --max-time 2 http://127.0.0.1:5000/api/version` returns `0.14.1` and `/api/stats` returns JSON with `detectors.ov` |
| **FRG-03** | FR-013 | Intel UHD Graphics 770 iGPU PCI device bound & OpenVINO detector configured (no Coral TPU, no AMD GPU in container) | Container devices map `/dev/dri/by-path/pci-0000:00:02.0-render`, omit `pci-0000:03:00.0`, and `/api/config` has `detectors.ov.type == "openvino"` |
| **FRG-04** | FR-003, FR-004 | Pre-staged `camera_1` and `camera_2` slots exist with dual-stream `detect` and `record` roles and retention (`7`d / `14`d) | `/api/config` JSON contains `cameras.camera_1` and `cameras.camera_2`, `record.retain.days == 7`, and `record.events.retain.default == 14` |
| **FRG-05** | FR-005, Principle IV | Secret isolation: `.env` has `0600` permissions, `.env.example` exists, and zero real credentials tracked in git | `stat -c '%a' /opt/services/frigate/.env` is `600` and ` [ -f /opt/services/frigate/.env.example ] ` |
| **FRG-06** | FR-006, FR-007, FR-008, SC-004 | Tiered storage & shared memory: `/config` on `/opt/services/frigate/config` (with `frigate.db`), `/media/frigate` on `/mnt/scratch/frigate/media`, and `/dev/shm` $\ge 256\text{ MB}$ | Container mount inspection confirms `/opt/services/frigate/config`, `/mnt/scratch/frigate/media`, and `ShmSize >= 268435456` |
| **FRG-07** | FR-010 | Network isolation: LAN (`192.168.4.0/24`) and `tailscale0` allowed in nftables; Frigate ports NOT exposed on Tailscale Funnel | `nft list table inet filter` permits `5000` for `192.168.4.0/24` & `tailscale0`, and `tailscale funnel status` contains no reference to `5000` or `8971` |
| **FRG-08** | FR-011, SC-004, Principle V | Backup hook `/etc/homelab/backup.d/20-frigate.sh` executes online `VACUUM INTO` snapshot + integrity check, and `/mnt/scratch` is excluded from Restic backups | `/etc/homelab/backup.d/20-frigate.sh pre-backup` exits `0`, creates `/opt/services/frigate/backups/snapshot.sqlite3`, and `/etc/homelab/backup-excludes.txt` excludes `/mnt/scratch` |
| **FRG-09** | FR-012, SC-002 | Structured logs accessible via `journalctl` / `docker logs` with zero unhandled crash tracebacks | `journalctl -u frigate.service --no-pager` exits `0` and container health status is `healthy` |
