# Quickstart & Validation Guide: Vaultwarden Application Deployment

**Feature**: `005-vaultwarden-app` | **Date**: 2026-11-01

This guide provides step-by-step instructions for deploying, operating, and verifying the Phase 5 Vaultwarden deployment on `homelab2`.

---

## 1. Prerequisites

Before running the deployment automation, ensure:
1. Target host `192.168.4.57` is reachable via SSH as user `admin`.
2. Phase 1 through Phase 4 are completed and verified on `admin@192.168.4.57` (Base OS, Core Hardening, Network/Caddy, Storage Array).
3. Workstation has access to `admin@192.168.4.57` over SSH with passwordless sudo privileges.
4. SOPS decryption key (`keys.txt` / age private key) is loaded on the administrative workstation (`~/.config/sops/age/keys.txt`).

---

## 2. Deployment Workflow

### Step 1: Run Ansible Provisioning Against `admin@192.168.4.57`

From the administrative workstation (Windows / macOS / Linux), deploy directly to the target host:

```powershell
# From Windows workstation targeting admin@192.168.4.57
.\scripts\apply-phase5.ps1 -HostAddress 192.168.4.57 -User admin
```
or via Bash runner:
```bash
# From Linux / macOS workstation targeting admin@192.168.4.57
./scripts/apply-phase5.sh --host 192.168.4.57 --user admin
```
or directly via Ansible:
```bash
# Direct Ansible push targeting admin@192.168.4.57 from inventory
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml --tags vaultwarden
```

### Step 2: Validate Container & Service Status on `admin@192.168.4.57`
Verify the systemd unit and Docker container status via SSH on the target host:

```bash
# Check systemd service unit on target host
ssh admin@192.168.4.57 "systemctl status vaultwarden.service"

# Check running container status on target host
ssh admin@192.168.4.57 "docker compose -f /opt/services/vaultwarden/compose.yml ps"
```
**Expected Outcome**: Status shows `active (exited)` for the oneshot systemd unit and `Up (healthy)` for the `vaultwarden` container.

---

## 3. End-to-End Validation Scenarios

### Scenario 1: Health Endpoint Probe
Validate that the Vaultwarden health check responds locally:

```bash
curl -fsS http://127.0.0.1:8088/alive
```
**Expected Outcome**: Returns HTTP 200 within 500ms.

### Scenario 2: Caddy Ingress & TLS Verification
Validate that Caddy routes incoming HTTPS traffic to Vaultwarden:

```bash
curl -k -fsS https://127.0.0.1/alive -H "Host: vaultwarden.lan"
```
**Expected Outcome**: Returns HTTP 200 with valid TLS headers.

### Scenario 3: Real-Time WebSocket Handshake
Validate WebSocket protocol switching on the notification path:

```bash
curl -k -i -N \
  -H "Connection: Upgrade" \
  -H "Upgrade: websocket" \
  -H "Host: vaultwarden.lan" \
  -H "Sec-WebSocket-Key: SGVsbG8sIHdvcmxkIQ==" \
  -H "Sec-WebSocket-Version: 13" \
  https://127.0.0.1/notifications/hub
```
**Expected Outcome**: HTTP status line `101 Switching Protocols` with `Upgrade: websocket`.

### Scenario 4: Automated Transactional Backup Run
Trigger an on-demand transactional backup snapshot:

```bash
/opt/services/vaultwarden/scripts/backup.sh
```
**Expected Outcome**:
- Executes without stopping the container.
- Verifies SQLite snapshot with `PRAGMA integrity_check;` returning `ok`.
- Creates a timestamped archive under `/opt/services/vaultwarden/backups/`.
- Prunes archives older than 30 days.

### Scenario 5: Disaster Recovery Drill (Isolated Target)
Validate that a backup snapshot can be restored safely:

```bash
# List available archives
ls -lh /opt/services/vaultwarden/backups/

# Run restore script in dry-run/simulation or isolated drill
/opt/services/vaultwarden/scripts/restore.sh $(ls -t /opt/services/vaultwarden/backups/*.tar.gz | head -n 1) --force
```
**Expected Outcome**: Service cleanly restarts and `/alive` returns HTTP 200 within 30 seconds.

---

## 4. Automated Phase 5 Acceptance Suite

Execute the unified automated verification suite remotely against `admin@192.168.4.57` to validate all 9 acceptance checks:

```powershell
# Remotely from Windows workstation targeting admin@192.168.4.57
.\scripts\verify-phase5-vaultwarden.ps1 -TargetHost 192.168.4.57 -User admin
```
or directly on `192.168.4.57` over SSH:
```bash
ssh admin@192.168.4.57 "sudo /opt/services/vaultwarden/scripts/verify-phase5-vaultwarden.sh"
```

**Expected Outcome**: All tests (VW-01 through VW-09) pass with exit code `0`.
