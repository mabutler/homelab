# Contract: Composite Health Sweep, Dynamic Container Discovery & Storage/SMART Monitoring (`MON-SWEEP-V1`)

**Feature**: `011-monitoring-ntfy-healthchecks`  
**Date**: 2026-11-05  
**Requirements Covered**: FR-009, FR-010, FR-011, FR-012, FR-013, SC-001, SC-003

---

## 1. Periodic Health Sweep & Heartbeat Timer (`homelab-heartbeat.service` / `.timer`)

### 1.1 Systemd Units

- **`/etc/systemd/system/homelab-heartbeat.service`**:
  ```ini
  [Unit]
  Description=Homelab2 Composite Health Sweep & Dead-Man's-Switch Heartbeat
  After=network-online.target docker.service
  Wants=network-online.target

  [Service]
  Type=oneshot
  User=root
  Group=root
  EnvironmentFile=/etc/homelab/monitoring.env
  ExecStart=/usr/local/bin/homelab-health-sweep
  StandardOutput=journal
  StandardError=journal
  TimeoutSec=60
  ```
- **`/etc/systemd/system/homelab-heartbeat.timer`**:
  ```ini
  [Unit]
  Description=Homelab2 5-Minute Composite Health Sweep & Heartbeat Timer

  [Timer]
  OnBootSec=2min
  OnUnitActiveSec=5min
  AccuracySec=15s
  Persistent=true

  [Install]
  WantedBy=timers.target
  ```

---

## 2. Composite Health Sweep Evaluation Contract (`/usr/local/bin/homelab-health-sweep`)

Each execution of `/usr/local/bin/homelab-health-sweep` performs the following checks, updating per-component deduplication/recovery state via `/usr/local/bin/homelab-ntfy`:

### 2.1 Continuous Infrastructure & Application Services (FR-009)
- Asserts `systemctl is-active --quiet <unit>` for:
  - `sshd.service`, `chronyd.service`, `smartd.service`, `systemd-oomd.service`, `nftables.service`, `tailscaled.service`, `caddy.service`, `docker.service`, `vaultwarden.service`, `frigate.service`
- Asserts user unit `agy-remote-control.service` for operator `admin` when `/home/admin/.gemini/oauth_creds.json` is present.
- Component key format: `service-<unit>` (e.g., `service-vaultwarden.service`).

### 2.2 Dynamic Docker Container Discovery (Current & Future) (FR-010, SC-001)
- Dynamically inspects all Docker containers via `docker ps -a --format '{{.Names}}'`.
- For each container `<name>`:
  - Reads `.State.Status`, `.State.ExitCode`, and `.State.Health.Status` (if a container healthcheck is defined).
  - Marks `container-<name>` as `failing` (`Priority: high`, tags `whale,warning`) if:
    - `.State.Status == "restarting"` or `.State.Status == "dead"`, OR
    - `.State.Status == "exited"` and `.State.ExitCode != 0`, OR
    - `.State.Health.Status == "unhealthy"`.
  - Otherwise marks `container-<name>` as `ok` (triggering a recovery alert if it was previously unhealthy).

### 2.3 Application & Overlay Readiness Probes (User Story 4, FR-009)
- Performs up to 3 attempts (2s delay between retries) for each probe:
  - `probe-caddy-health`: `curl -fsS --max-time 5 http://127.0.0.1:80/health` → HTTP 200
  - `probe-vaultwarden-alive`: `curl -fsS --max-time 5 http://127.0.0.1:8088/alive` → HTTP 200
  - `probe-frigate-api`: `curl -fsS --max-time 5 http://127.0.0.1:5000/api/version` → HTTP 200
  - `probe-tailscale-status`: `tailscale status --json | jq -e '.BackendState == "Running"'`

### 2.4 Storage Mounts & Filesystem Capacity Thresholds (FR-011)
- Verifies each required mount point is active (`mountpoint -q <path>` for `/mnt/disks/data1`, `/mnt/disks/data2`, `/mnt/disks/parity1`, `/mnt/storage`, `/mnt/scratch`) and directory `/opt/services` exists.
- Evaluates filesystem usage percentage (`df -P <path>`) for `/`, `/opt/services`, `/mnt/storage`, `/mnt/disks/data1`, `/mnt/disks/data2`, `/mnt/disks/parity1`, and `/mnt/scratch`:
  - Usage $\ge$ `MONITORING_DISK_CRIT_PCT` (default `95%`): dispatches `failing` alert (`Priority: urgent`, tags `rotating_light,floppy_disk`).
  - Usage $\ge$ `MONITORING_DISK_WARN_PCT` (default `85%`): dispatches `warning` alert (`Priority: high`, tags `warning,floppy_disk`).
  - Usage $<$ `MONITORING_DISK_WARN_PCT`: records `ok` for `disk-space-<sanitized-mount>` (sending recovery notification if previously over threshold).

### 2.5 Composite Heartbeat Signal (FR-012)
- If **0** critical subsystems failed during the sweep:
  - Calls `/usr/local/bin/homelab-hc-ping --slug fidelacchius-host-heartbeat --event success`.
- If **$\ge 1$** critical subsystems failed:
  - Calls `/usr/local/bin/homelab-hc-ping --slug fidelacchius-host-heartbeat --event fail --message "${FAILURE_SUMMARY}"` so `healthchecks.io` also records the degraded host state.

---

## 3. Physical Disk SMART Alert Hook (`/usr/local/bin/homelab-smartd-alert`)

### 3.1 `smartd.conf` Integration (`ansible/roles/disk_health`)

`/etc/smartd.conf` is rendered with:
```text
DEVICESCAN -a -o on -S on -s (S/../.././02|L/../../6/03) -H -C 197+ -U 198+ -W 4,45,55 -m <nomailer> -M exec /usr/local/bin/homelab-smartd-alert
```

### 3.2 Execution Contract

When `smartd` detects a SMART health failure, offline uncorrectable sector, current pending sector, or temperature threshold breach ($\ge 45^\circ\text{C}$ warning / $\ge 55^\circ\text{C}$ critical), it invokes `/usr/local/bin/homelab-smartd-alert` with environment variables:
- `SMARTD_DEVICE` (e.g., `/dev/sda`)
- `SMARTD_FAILTYPE` (e.g., `Temperature`, `FailedHealthCheck`, `CurrentPendingSector`, `EmailTest`)
- `SMARTD_MESSAGE` (one-line summary)
- `SMARTD_FULLMESSAGE` (full diagnostic report)

`homelab-smartd-alert` forwards the event to `/usr/local/bin/homelab-ntfy` with:
- `--component "smartd-${SMARTD_DEVICE:-disk}-${SMARTD_FAILTYPE:-alert}"`
- `--status failing` (or `test` when `SMARTD_FAILTYPE == "EmailTest"`)
- `--priority urgent` (or `default` for `EmailTest`)
- `--tags "rotating_light,cd"`
- `--title "[SMART ALERT] fidelacchius: ${SMARTD_DEVICE} (${SMARTD_FAILTYPE})"`
- `--message "${SMARTD_FULLMESSAGE:-$SMARTD_MESSAGE}"`
