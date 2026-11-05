# Contract: `ntfy.sh` Notification Dispatcher & Systemd Failure Hook (`MON-NTFY-V1`)

**Feature**: `011-monitoring-ntfy-healthchecks`  
**Date**: 2026-11-05  
**Requirements Covered**: FR-001, FR-003, FR-004, FR-005, FR-006, FR-013, SC-001, SC-003, SC-004

---

## 1. Notification Dispatcher CLI (`/usr/local/bin/homelab-ntfy`)

### 1.1 Synopsis

```bash
/usr/local/bin/homelab-ntfy \
  --component <component-key> \
  --status <failing|warning|ok|test> \
  --title "<notification-title>" \
  --message "<diagnostic-body>" \
  [--priority <default|high|urgent|3|4|5>] \
  [--tags "<comma-separated-ntfy-tags>"] \
  [--force]
```

### 1.2 Inputs & Environment

- **Configuration File**: Sources `/etc/homelab/monitoring.env` (`0600 root:root`):
  - `NTFY_SERVER_URL` (default: `https://ntfy.sh`)
  - `NTFY_TOPIC` (required secret topic identifier)
  - `NTFY_TOKEN` (optional access token; when non-empty, passes `-H "Authorization: Bearer ${NTFY_TOKEN}"`)
  - `MONITORING_COOLDOWN_SEC` (default: `900`)
  - `MONITORING_STATE_DIR` (default: `/var/lib/homelab/monitoring/state`)

### 1.3 Deduplication & Silent-When-Healthy Behavior

1. Acquires an exclusive lock on `${MONITORING_STATE_DIR}/.lock` via `flock -w 10`.
2. Reads `${MONITORING_STATE_DIR}/${SAFE_COMPONENT_KEY}.json` if present (defaulting prior `status` to `"ok"`).
3. Evaluates transition:
   - **`--status ok` and prior `status == "ok"`**:
     - Exits `0` silently without calling `ntfy.sh` (FR-005).
   - **`--status ok` and prior `status` in `("failing", "warning")`**:
     - Transitions state to `"ok"`, resets `first_failure_epoch: 0` and `suppressed_count: 0`, and immediately dispatches a recovery notification to `${NTFY_SERVER_URL}/${NTFY_TOPIC}` with `Priority: default` (`3`), `Tags: white_check_mark,tada`, and title `[RECOVERED] fidelacchius: <component>` (including how many duplicate alerts were suppressed during the incident).
   - **`--status warning|failing` and prior `status` in `("failing", "warning")` with `(now - last_sent_epoch) < MONITORING_COOLDOWN_SEC` and no severity escalation (`warning -> urgent`) and `--force` not set**:
     - Increments `suppressed_count` in the state file, logs suppression notice to `systemd-cat -t homelab-ntfy`, and exits `0` without calling `ntfy.sh` (FR-013, SC-004).
   - **`--status warning|failing` (new incident, severity escalation, expired cooldown, or `--force`) or `--status test`**:
     - Dispatches HTTP `POST ${NTFY_SERVER_URL}/${NTFY_TOPIC}` with headers:
       - `Title: <title>`
       - `Priority: <priority>` (`high` / `4` for warnings and service failures; `urgent` / `5` for critical disk/host failures; `default` / `3` for tests/recoveries)
       - `Tags: <tags>`
     - Updates `${MONITORING_STATE_DIR}/${SAFE_COMPONENT_KEY}.json` atomically via `.tmp` + `mv`.

### 1.4 Network Resilience & Exit Contract

- Uses `curl -fsS --retry 3 --retry-delay 2 --retry-all-errors --connect-timeout 5 --max-time 15`.
- Logs all outbound deliveries and any HTTP/network errors to `journald` (`homelab-ntfy` tag).

---

## 2. Global Systemd Failure Hook (`/usr/local/bin/homelab-unit-alert`)

### 2.1 Global Drop-In Files

1. **System Units**: `/etc/systemd/system/service.d/99-homelab-failure-alert.conf`
   ```ini
   # Managed by Ansible (role: monitoring)
   [Unit]
   OnFailure=homelab-alert@%n.service
   ```
2. **User Units**: `/etc/systemd/user/service.d/99-homelab-failure-alert.conf`
   ```ini
   # Managed by Ansible (role: monitoring)
   [Unit]
   OnFailure=homelab-alert@%n.service
   ```
3. **Recursion Guards (Mandatory)**:
   - `/etc/systemd/system/homelab-alert@.service.d/99-zz-no-recursion.conf`:
     ```ini
     # Prevent infinite OnFailure recursion on the alert service itself
     [Unit]
     OnFailure=
     ```
   - `/etc/systemd/user/homelab-alert@.service.d/99-zz-no-recursion.conf`:
     ```ini
     # Prevent infinite OnFailure recursion on the user alert service itself
     [Unit]
     OnFailure=
     ```

### 2.2 Template Service Units

- **System Unit (`/etc/systemd/system/homelab-alert@.service`)**:
  ```ini
  [Unit]
  Description=Homelab2 Failure Alert Dispatcher for %i
  After=network-online.target
  OnFailure=

  [Service]
  Type=oneshot
  User=root
  Group=root
  ExecStart=-/usr/local/bin/homelab-unit-alert --scope system --unit %i
  StandardOutput=journal
  StandardError=journal
  TimeoutSec=30
  ```
- **User Unit (`/etc/systemd/user/homelab-alert@.service`)**:
  ```ini
  [Unit]
  Description=Homelab2 User Failure Alert Dispatcher for %i
  OnFailure=

  [Service]
  Type=oneshot
  ExecStart=-/usr/bin/sudo -n /usr/local/bin/homelab-unit-alert --scope user --user %u --unit %i
  StandardOutput=journal
  StandardError=journal
  TimeoutSec=30
  ```

### 2.3 Diagnostic Payload Format

When `homelab-unit-alert` is triggered for `<unit>`:
1. Immediately exits `0` if `<unit>` matches `homelab-alert@*`.
2. Collects unit metadata (`ActiveState`, `SubState`, `Result`, `ExecMainCode`, `ExecMainStatus`) and the last 20 journal lines (`journalctl -u <unit> -n 20 --no-pager`).
3. Calls `/usr/local/bin/homelab-ntfy --component "unit-${SCOPE}-${UNIT}" --status failing --priority high --tags "rotating_light,systemd" --title "[FAILURE] fidelacchius: ${UNIT} (${SCOPE})" --message "${DIAGNOSTIC_PAYLOAD}"`.
