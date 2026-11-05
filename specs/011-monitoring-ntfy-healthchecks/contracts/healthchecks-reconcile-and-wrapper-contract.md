# Contract: `Healthchecks.io` API Reconciliation & Job Wrapper (`MON-HC-V1`)

**Feature**: `011-monitoring-ntfy-healthchecks`  
**Date**: 2026-11-05  
**Requirements Covered**: FR-001, FR-002, FR-003, FR-004, FR-005, FR-007, FR-008, SC-001, SC-002

---

## 1. Zero-Touch API Reconciler (`/usr/local/bin/homelab-hc-reconcile`)

### 1.1 Synopsis

```bash
# Reconcile all checks defined in /etc/homelab/monitoring/checks-catalog.json
/usr/local/bin/homelab-hc-reconcile [--catalog /etc/homelab/monitoring/checks-catalog.json]

# Dynamically ensure a single ad-hoc or new check exists by slug (used by homelab-hc-run / homelab-hc-ping)
/usr/local/bin/homelab-hc-reconcile \
  --ensure-slug <slug> \
  [--name "<name>"] \
  [--timeout <sec> | --schedule "<cron>"] \
  [--tz "<timezone>"] \
  [--grace <sec>] \
  [--tags "<space-separated-tags>"]
```

### 1.2 API v3 Upsert Contract

For each check entry, `homelab-hc-reconcile` sends an HTTP `POST` request to `${HEALTHCHECKS_API_URL}/checks/` (`https://healthchecks.io/api/v3/checks/`):
- **Headers**:
  - `X-Api-Key: ${HEALTHCHECKS_API_KEY}`
  - `Content-Type: application/json`
- **Payload**:
  ```json
  {
    "name": "fidelacchius: Restic Offsite Daily Backup",
    "slug": "fidelacchius-backup-daily",
    "tags": "fidelacchius homelab backup restic b2",
    "desc": "Daily Restic encrypted backup to Backblaze B2 (homelab-backup.service)",
    "schedule": "30 2 * * *",
    "tz": "America/New_York",
    "grace": 3600,
    "channels": "*",
    "unique": ["name", "slug"]
  }
  ```
- **Response Handling**:
  - Accepts HTTP `200` (updated existing check) or HTTP `201` (created new check).
  - Extracts `.ping_url` and `.uuid` from the JSON response and persists the mapping to `/var/lib/homelab/monitoring/checks.json` (`0600 root:root`).

---

## 2. Heartbeat Signal Helper (`/usr/local/bin/homelab-hc-ping`)

### 2.1 Synopsis

```bash
/usr/local/bin/homelab-hc-ping \
  --slug <slug> \
  --event <start|success|fail|stop> \
  [--exit-code <0-255>] \
  [--unit <systemd-unit-name>] \
  [--message "<diagnostic-log-excerpt>"]
```

### 2.2 Resolution & Auto-Provisioning Flow

1. Looks up `.checks["<slug>"].ping_url` in `/var/lib/homelab/monitoring/checks.json`.
2. If `<slug>` is not yet in `checks.json`:
   - If `HEALTHCHECKS_PING_KEY` is configured in `/etc/homelab/monitoring.env`, constructs `${HEALTHCHECKS_PING_BASE_URL}/${HEALTHCHECKS_PING_KEY}/${SLUG}?create=1`.
   - Otherwise, invokes `/usr/local/bin/homelab-hc-reconcile --ensure-slug "${SLUG}"` to auto-create the check via API v3 and cache its `ping_url` (satisfying FR-007 and SC-001).
3. Determines endpoint suffix:
   - `start`: `${PING_URL}/start`
   - `success`: `${PING_URL}` (or `${PING_URL}/0`)
   - `fail`: `${PING_URL}/${EXIT_CODE:-fail}`
   - `stop` (systemd `ExecStopPost=` mode): inspects systemd's `$SERVICE_RESULT` and `$EXIT_STATUS`:
     - If `${SERVICE_RESULT:-success} == "success"` and `${EXIT_STATUS:-0} == "0"`: signals `${PING_URL}` and notifies `homelab-ntfy --component "job-${SLUG}" --status ok` (which stays silent unless recovering from a prior failure).
     - Otherwise: collects the last 25 journal lines for `--unit`, posts them to `${PING_URL}/${EXIT_STATUS:-fail}`, and invokes `homelab-ntfy --component "job-${SLUG}" --status failing` to alert the operator immediately.

---

## 3. Reusable Job Wrapper CLI (`/usr/local/bin/homelab-hc-run`)

### 3.1 Synopsis

```bash
/usr/local/bin/homelab-hc-run \
  --slug <slug> \
  [--name "<check-name>"] \
  [--schedule "<cron>" | --timeout <sec>] \
  [--grace <sec>] \
  -- <command> [args...]
```

### 3.2 Execution Lifecycle

1. Signals `/start` via `homelab-hc-ping --slug <slug> --event start` (auto-creating `<slug>` if needed).
2. Executes `<command> [args...]`, teeing/capturing the last 50 lines of combined `stdout`/`stderr` while preserving standard output/error streams to journald.
3. Captures `<command>` exit code `RC`:
   - If `RC == 0`: calls `homelab-hc-ping --slug <slug> --event success` and `homelab-ntfy --component "job-${SLUG}" --status ok`, then exits `0`.
   - If `RC != 0`: calls `homelab-hc-ping --slug <slug> --event fail --exit-code "${RC}" --message "${OUTPUT_TAIL}"`, dispatches an immediate failure notification via `homelab-ntfy`, and exits `${RC}`.

---

## 4. Scheduled Maintenance Job Systemd Drop-In Bindings (FR-008)

All 5 existing scheduled maintenance services are instrumented via `/etc/systemd/system/<unit>.service.d/10-healthchecks.conf`:

| Systemd Service | Drop-In Path | Bound Check Slug |
|---|---|---|
| `homelab-backup.service` | `/etc/systemd/system/homelab-backup.service.d/10-healthchecks.conf` | `fidelacchius-backup-daily` |
| `homelab-backup-check.service` | `/etc/systemd/system/homelab-backup-check.service.d/10-healthchecks.conf` | `fidelacchius-backup-check` |
| `vaultwarden-backup.service` | `/etc/systemd/system/vaultwarden-backup.service.d/10-healthchecks.conf` | `fidelacchius-vaultwarden-backup` |
| `snapraid-sync.service` | `/etc/systemd/system/snapraid-sync.service.d/10-healthchecks.conf` | `fidelacchius-snapraid-sync` |
| `snapraid-scrub.service` | `/etc/systemd/system/snapraid-scrub.service.d/10-healthchecks.conf` | `fidelacchius-snapraid-scrub` |
