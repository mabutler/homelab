# Contract: Phase 5 Vaultwarden Acceptance & Verification Test Suite

**Feature**: `005-vaultwarden-app` | **Date**: 2026-11-01

This contract specifies the automated verification suite (`verify-phase5-vaultwarden.sh` and `verify-phase5-vaultwarden.ps1`) executing the acceptance gates mandated by Constitution Principles III and V.

---

## 1. CLI Execution Contract

```bash
# On target Arch Linux host (192.168.4.57)
./scripts/verify-phase5-vaultwarden.sh [--json] [--verbose]

# From administrative workstation via Ansible / SSH targeting admin@192.168.4.57
./scripts/verify-phase5-vaultwarden.ps1 -TargetHost "192.168.4.57" -User "admin"
```

### Exit Codes
- `0`: All verification checks passed without error.
- `1`: One or more verification checks failed.

---

## 2. Test Matrix Specifications

| Check ID | Verification Area | Target / Command | Pass Criteria |
|---|---|---|---|
| **VW-01** | Docker Engine & Compose | `docker --version`, `docker compose version` | Docker CE and Compose plugin installed and responding. |
| **VW-02** | Systemd Service Unit | `systemctl is-active vaultwarden.service` | Output equals `"active"`. |
| **VW-03** | Least Privilege & Ownership | `stat -c "%u:%g %a" /opt/services/vaultwarden/data` | Ownership matches non-root UID (e.g. 1000:1000), mode `0750` or `0700`. Container process UID is non-zero. |
| **VW-04** | Secret Decoupling & Isolation | `stat -c "%a" /opt/services/vaultwarden/.env`, `git grep -i "ADMIN_TOKEN" :^ansible/inventory/group_vars/all/vault.sops.yml` | `.env` permissions are `0600`. Zero plaintext secrets present in git. |
| **VW-05** | Local Backend Health | `curl -fsS http://127.0.0.1:8088/alive` | Returns HTTP 200 within 500ms. |
| **VW-06** | Reverse Proxy HTTPS & Ingress | `curl -k -fsS https://127.0.0.1/alive -H "Host: vaultwarden.lan"` | Reverse proxy routes HTTPS to backend and returns HTTP 200. |
| **VW-07** | WebSocket Upgrade Handshake | `curl -k -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" -H "Host: vaultwarden.lan" -H "Sec-WebSocket-Key: SGVsbG8sIHdvcmxkIQ==" -H "Sec-WebSocket-Version: 13" https://127.0.0.1/notifications/hub` | Response headers include `101 Switching Protocols` or `Upgrade: websocket`. |
| **VW-08** | Transactional Backup Execution | `/opt/services/vaultwarden/scripts/backup.sh` | Script exits 0, SQLite snapshot passes `PRAGMA integrity_check;`, archive generated in `backups/`. |
| **VW-09** | Systemd Backup Timer | `systemctl is-enabled vaultwarden-backup.timer` | Timer unit is enabled and scheduled in systemd. |

---

## 3. Structured Output Schema (JSON Mode)

```json
{
  "feature": "005-vaultwarden-app",
  "timestamp": "2026-11-01T22:00:00Z",
  "passed": true,
  "summary": {
    "total": 9,
    "passed": 9,
    "failed": 0
  },
  "checks": [
    { "id": "VW-01", "name": "Docker Engine & Compose", "status": "PASS", "details": "Docker 27.x, Compose 2.29.x" },
    { "id": "VW-02", "name": "Systemd Service Unit", "status": "PASS", "details": "vaultwarden.service is active" },
    { "id": "VW-03", "name": "Least Privilege & Ownership", "status": "PASS", "details": "UID 1000:1000, 0750" },
    { "id": "VW-04", "name": "Secret Decoupling & Isolation", "status": "PASS", "details": ".env mode 0600, no git leaks" },
    { "id": "VW-05", "name": "Local Backend Health", "status": "PASS", "details": "HTTP 200 in 42ms" },
    { "id": "VW-06", "name": "Reverse Proxy HTTPS & Ingress", "status": "PASS", "details": "Caddy reverse proxy 200 OK" },
    { "id": "VW-07", "name": "WebSocket Upgrade Handshake", "status": "PASS", "details": "101 Switching Protocols" },
    { "id": "VW-08", "name": "Transactional Backup Execution", "status": "PASS", "details": "VACUUM INTO + PRAGMA integrity_check ok" },
    { "id": "VW-09", "name": "Systemd Backup Timer", "status": "PASS", "details": "vaultwarden-backup.timer is enabled" }
  ]
}
```
