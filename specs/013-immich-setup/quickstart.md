# Quickstart & Verification Guide: Immich Photo Management Platform

**Feature**: `013-immich-setup`  
**Date**: 2026-11-06  
**Status**: Ready  

This guide provides step-by-step instructions for converging the Immich deployment on `fidelacchius`, running the automated acceptance suite, onboarding the initial administrator account, and testing disaster recovery backups.

---

## 1. Prerequisites

Before deploying Immich, confirm that core platform prerequisites are met:

```bash
# 1. Verify Docker and systemd are operational
docker --version
docker compose version

# 2. Verify storage mounts are online
df -h /opt/services /mnt/storage

# 3. Verify Intel UHD Graphics 770 iGPU render node exists
ls -la /dev/dri/by-path/pci-0000:00:02.0-render
```

---

## 2. Deployment & Convergence

### Option A: Local Convergence (on host `fidelacchius`)

```bash
cd /home/admin/projects/homelab2

# Execute the Phase 5 Immich convergence runner locally
./scripts/apply-phase5-immich.sh --local
```

### Option B: Remote Operator Convergence (from workstation)

```bash
# Via POSIX Bash runner:
./scripts/apply-phase5-immich.sh --host 192.168.4.57 --user admin

# Or via PowerShell 7+ on Windows:
pwsh ./scripts/apply-phase5-immich.ps1 -Host 192.168.4.57 -User admin
```

### Option C: Direct Ansible Playbook Invocations

```bash
# Check mode (dry run / idempotency verification)
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/immich.yml --check

# Apply convergence
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/immich.yml
```

---

## 3. Automated Acceptance Verification

Run the automated acceptance suite to validate all 9 operational assertions (`IMM-01` through `IMM-09`):

```bash
# Run acceptance assertions locally:
./scripts/verify-phase5-immich.sh --local

# Or with JSON structured output:
./scripts/verify-phase5-immich.sh --local --json

# Expected output:
# [PASS] IMM-01: Immich service and containers active with 0 restart loops
# [PASS] IMM-02: HTTP API ping (/api/server/ping) responded HTTP 200 within 500ms
# [PASS] IMM-03: Intel UHD 770 iGPU render device bound; discrete AMD GPU untouched
# [PASS] IMM-04: Tiered storage mounts verified (NVMe DB/cache + MergerFS photos)
# [PASS] IMM-05: Secret isolation verified (.env mode 0600, zero leaks in git)
# [PASS] IMM-06: Caddy reverse proxy drop-in validated and syntax check passed
# [PASS] IMM-07: Media directory ownership verified (PUID=1000, PGID=1001, mode 2775)
# [PASS] IMM-08: Transactional backup hook executed and non-empty dump verified
# [PASS] IMM-09: Journald telemetry streaming with zero fatal tracebacks
# Exit Code: 0 (All assertions passed)
```

---

## 4. Initial Administrator Account Setup

1. Open your browser and navigate to the Immich web interface:
   - Over LAN: `https://photos.lan` (or `http://192.168.4.57:2283` if accessing port directly during bootstrap)
   - Over Tailscale: `https://photos.fidelacchius.ts.net`
2. Complete the onboarding wizard:
   - Click **Getting Started**.
   - Enter Administrator Name, Email Address, and Master Password.
   - Click **Sign Up**.
3. Storage Template & Preferences:
   - Navigate to **Administration** -> **Settings** -> **Storage Template**.
   - Verify template pattern: `{{y}}/{{y}}-{{MM}}-{{dd}}/{{filename}}`.
4. Mobile App Synchronization:
   - Install the Immich mobile app on iOS / Android.
   - Enter Server Endpoint: `https://photos.fidelacchius.ts.net` (or local LAN URL).
   - Authenticate with the administrator or household user credentials.
   - Enable background camera backup.

---

## 5. Backup & Disaster Recovery Verification

Verify that atomic PostgreSQL dumps and vector embeddings are captured without service downtime:

```bash
# 1. Trigger the pre-backup hook manually
sudo /etc/homelab/backup.d/30-immich.sh pre-backup

# 2. Inspect the generated snapshot
ls -lh /opt/services/immich/backups/immich_db_backup.dump

# 3. Verify dump is a valid PostgreSQL custom format archive
file /opt/services/immich/backups/immich_db_backup.dump
# Expected output: PostgreSQL custom database dump

# 4. Run automated Restic backup to verify Backblaze B2 capture
sudo /usr/local/bin/homelab-backup
```

---

## 6. Troubleshooting & Diagnostics

- **Inspect Container Logs**:
  ```bash
  cd /opt/services/immich && docker compose logs -f immich-server
  ```
- **Inspect Machine Learning Logs**:
  ```bash
  cd /opt/services/immich && docker compose logs -f immich-machine-learning
  ```
- **Check Database Connectivity**:
  ```bash
  docker compose -f /opt/services/immich/compose.yml exec database \
      pg_isready -U immich -d immich
  ```
- **Check Hardware Acceleration (VAAPI)**:
  ```bash
  docker compose -f /opt/services/immich/compose.yml exec immich-server \
      vainfo --display drm --device /dev/dri/renderD128
  ```
