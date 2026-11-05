# Quickstart & Validation Guide: Frigate NVR Pre-Arrival Setup for Two Cameras

**Feature**: `009-frigate-nvr-setup`  
**Date**: 2026-11-04  
**Spec**: [spec.md](./spec.md) | **Contracts**: [contracts/](./contracts/)

---

## 1. Prerequisites

1. **Platform Foundation**: Phases 1 through 4 and Phase 5 container/backup infrastructure must be active on the host:
   - Docker CE & Compose plugin running (`systemctl is-active docker`)
   - Tier 0 NVMe application directory mounted at `/opt/services`
   - Tier 2 dedicated scratch disk mounted at `/mnt/scratch`
   - Intel UHD Graphics 770 iGPU PCI DRM render device present at `/dev/dri/by-path/pci-0000:00:02.0-render`
   - Local gitignored secrets file present at `ansible/inventory/group_vars/all/vault.yml`

---

## 2. Deployment (Pre-Arrival Setup)

Run the Frigate deployment playbook (or convergence wrapper) from the repository root:

```bash
# Using the Bash orchestrator on the target host or workstation
./scripts/apply-phase5-frigate.sh

# Or directly via ansible-playbook
cd ansible
ansible-playbook playbooks/frigate.yml
```

*(From a Windows workstation, run `.\scripts\apply-phase5-frigate.ps1`.)*

---

## 3. Pre-Arrival Validation Scenarios (Before Cameras Arrive)

### Scenario A: Service Health & Zero-Camera Stability (User Story 1)
Verify that Frigate starts cleanly, binds the Intel iGPU, and serves its web UI and API with zero physical cameras connected:

```bash
# 1. Confirm systemd unit and container status
systemctl status frigate.service --no-pager
docker ps --filter name=frigate

# 2. Query API version and live OpenVINO detector stats
curl -fsS http://127.0.0.1:5000/api/version
curl -fsS http://127.0.0.1:5000/api/stats | jq '.detectors, .service'
```

**Expected Outcome**:
- `frigate.service` is `active (exited)` and the `frigate` container status is `Up ... (healthy)` with `0` restarts.
- `/api/version` returns `0.14.1`.
- `/api/stats` reports `detectors.ov` active with a valid PID and inference speed metric.
- Opening `http://<host-lan-ip>:5000` (from the `192.168.4.0/24` LAN) or `http://<tailscale-ip>:5000` (over Tailscale VPN) loads the Frigate dashboard.

### Scenario B: Storage Tier Separation & Transactional Backup Check (User Stories 3 & 4)
Verify that metadata lives on `/opt/services/frigate`, video media is mapped to `/mnt/scratch/frigate/media`, and the Restic pre-backup hook creates a verified SQLite snapshot:

```bash
# 1. Verify SQLite database on Tier 0 NVMe and media directory on Tier 2 Scratch
ls -lh /opt/services/frigate/config/frigate.db
df -h /opt/services/frigate/config /mnt/scratch/frigate/media

# 2. Execute the Frigate pre-backup hook and Restic dry-run
sudo /etc/homelab/backup.d/20-frigate.sh pre-backup
sudo /usr/local/bin/homelab-backup run --dry-run
```

**Expected Outcome**:
- `20-frigate.sh pre-backup` outputs `frigate transactional pre-backup snapshot verified ok.` and writes `/opt/services/frigate/backups/snapshot.sqlite3`.
- `homelab-backup run --dry-run` succeeds while excluding `/mnt/scratch`.

### Scenario C: Automated Verification Gate (`FRG-01` to `FRG-09`)
Run the full acceptance test suite:

```bash
# Run standalone verification script
sudo ./scripts/verify-phase5-frigate.sh

# Or run the Ansible verification playbook
cd ansible
ansible-playbook playbooks/verify-phase5-frigate.yml
```

**Expected Outcome**: All 9 assertions (`FRG-01` through `FRG-09`) report `PASS`.

---

## 4. Delivery-Day Onboarding Runbook (< 5 Minutes) (User Story 2)

When the two ordered cameras arrive and are connected to the local network:

1. **Add Camera RTSP URLs to `ansible/inventory/group_vars/all/vault.yml`** (or directly in `/opt/services/frigate/.env`):
   ```yaml
   vault_frigate_camera_1_rtsp_main_url: "rtsp://admin:YOUR_CAM1_PASS@192.168.4.201:554/h264Preview_01_main"
   vault_frigate_camera_1_rtsp_sub_url: "rtsp://admin:YOUR_CAM1_PASS@192.168.4.201:554/h264Preview_01_sub"
   vault_frigate_camera_2_rtsp_main_url: "rtsp://admin:YOUR_CAM2_PASS@192.168.4.202:554/h264Preview_01_main"
   vault_frigate_camera_2_rtsp_sub_url: "rtsp://admin:YOUR_CAM2_PASS@192.168.4.202:554/h264Preview_01_sub"
   ```
2. **Enable Both Camera Slots** in `ansible/inventory/group_vars/all/vars.yml`:
   ```yaml
   frigate_camera_1_enabled: true
   frigate_camera_2_enabled: true
   ```
3. **Apply Configuration**:
   ```bash
   ./scripts/apply-phase5-frigate.sh
   ```
   *(Alternatively, if editing directly on the host without Ansible, update `/opt/services/frigate/.env`, set `enabled: true` under `camera_1` and `camera_2` in `/opt/services/frigate/config/config.yml`, and run `sudo systemctl restart frigate.service`.)*
4. **Verify Live Streams & Recordings**:
   - Open the Frigate dashboard and confirm live feeds for `camera_1` and `camera_2`.
   - Confirm video segments are being written to `/mnt/scratch/frigate/media/recordings`.
