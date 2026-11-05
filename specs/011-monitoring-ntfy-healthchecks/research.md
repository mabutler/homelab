# Phase 0 Research: Automated Platform Monitoring & Alerting (`ntfy` & `Healthchecks`)

**Feature**: `011-monitoring-ntfy-healthchecks`  
**Date**: 2026-11-05  
**Spec**: [spec.md](./spec.md)

---

## 1. Cloud-Hosted `ntfy.sh` & `healthchecks.io` Architecture (Zero Local Containers)

- **Decision**:
  - Consume `https://ntfy.sh` (push notifications) and `https://healthchecks.io` / `https://hc-ping.com` (dead-man's-switch heartbeat monitoring) as external hosted SaaS services without deploying local `ntfy` or `healthchecks` Docker containers on `fidelacchius`.
  - Route both direct host event notifications (`homelab-ntfy`) and `healthchecks.io` missed-heartbeat alerts (`channels: "*"`) to the operator's unified `ntfy.sh` topic.
- **Rationale**:
  - Satisfies FR-001, FR-004, and Constitution Operational Standards (*Minimalist Footprint / YAGNI*): a self-hosted dead-man's-switch running on the same physical server (`fidelacchius`) cannot alert the operator if `fidelacchius` suffers a power outage, kernel panic, or ISP disconnection.
  - Eliminates container runtime, database, and SMTP/Push gateway maintenance overhead on the homelab host while requiring only 2 mandatory bootstrap secrets in `vault.yml` (`vault_ntfy_topic` and `vault_healthchecks_api_key`, plus optional `vault_ntfy_token` and `vault_healthchecks_ping_key`).
- **Alternatives Considered**:
  - Self-hosting `binwiederhier/ntfy` and `healthchecks/healthchecks` in Docker on `fidelacchius`: Rejected by user clarification (FR-001) and because local hosting defeats outage detection during host power or WAN loss.
  - Prometheus + Alertmanager + Grafana stack: Rejected due to heavy memory/storage footprint and manual dashboard/rule maintenance toil that violates the user's minimal-configuration requirement.

---

## 2. Zero-Touch `healthchecks.io` API v3 Reconciliation & Slug-Based Pinging

- **Decision**:
  - Use the `healthchecks.io` Management API v3 (`POST https://healthchecks.io/api/v3/checks/` authenticated via `X-Api-Key: <HEALTHCHECKS_API_KEY>`) with `"unique": ["name", "slug"]` and `"channels": "*"` to idempotently create or update all platform checks during Ansible deployment and via `/usr/local/bin/homelab-hc-reconcile`.
  - Discover or store the project's `ping_key` (or each check's `ping_url` cached in `/var/lib/homelab/monitoring/checks.json`, mode `0600`) so runtime scripts (`homelab-hc-ping`, `homelab-hc-run`, `homelab-health-sweep`) can ping checks by deterministic slug (`https://hc-ping.com/<ping_key>/<slug>[/start|/fail|/<exit-code>]` with `?create=1` or cached UUID `ping_url` returned by the Management API).
  - Pre-register 6 canonical platform checks out of the box:
    1. `fidelacchius-host-heartbeat` (`timeout: 300`, `grace: 600` — 5m period, 10m grace)
    2. `fidelacchius-backup-daily` (`schedule: "30 2 * * *"`, `grace: 3600`, `tz: "America/New_York"` or host timezone)
    3. `fidelacchius-backup-check` (`schedule: "0 4 * * 0"`, `grace: 7200`, `tz`: host timezone)
    4. `fidelacchius-vaultwarden-backup` (`schedule: "30 3 * * *"`, `grace: 1800`, `tz`: host timezone)
    5. `fidelacchius-snapraid-sync` (`schedule: "0 3 * * *"`, `grace: 7200`, `tz`: host timezone)
    6. `fidelacchius-snapraid-scrub` (`schedule: "0 4 * * 0"`, `grace: 14400`, `tz`: host timezone)
- **Rationale**:
  - `healthchecks.io` API v3 natively supports idempotent upsert when `"unique": ["name", "slug"]` is passed in the JSON request body: if a check with the matching `slug` already exists, `healthchecks.io` updates its schedule, grace period, tags, and `channels: "*"` binding in place and returns HTTP `200 OK` (or `201 Created` on initial creation) along with its `ping_url` (`https://hc-ping.com/<uuid>`).
  - Caching the `slug -> ping_url` map in `/var/lib/homelab/monitoring/checks.json` during reconciliation—and automatically invoking `homelab-hc-reconcile --ensure-slug <slug>` if an unknown slug is passed by a future service or job—means operators **never** have to copy-paste individual check UUIDs into config files or log into the `healthchecks.io` web UI when adding new jobs (FR-002, FR-003, SC-001, SC-002).
- **Alternatives Considered**:
  - Hardcoding individual `healthchecks.io` check UUIDs in `vault.yml`: Rejected because it forces the operator to manually create 6+ checks in the web UI and copy-paste 6+ UUIDs, directly violating User Story 3 and FR-002.

---

## 3. Global Catch-All Systemd Service Failure Hook (System & User Units)

- **Decision**:
  - Leverage systemd 250+ (host runs `systemd 262`) top-level unit type drop-in directories to attach a global failure handler to **every** existing and future systemd service on the host:
    - System units: `/etc/systemd/system/service.d/99-homelab-failure-alert.conf` containing:
      ```ini
      [Unit]
      OnFailure=homelab-alert@%n.service
      ```
    - User units: `/etc/systemd/user/service.d/99-homelab-failure-alert.conf` containing:
      ```ini
      [Unit]
      OnFailure=homelab-alert@%n.service
      ```
  - Prevent infinite alert recursion using a three-layer guard:
    1. Dedicated unit-specific drop-ins `/etc/systemd/system/homelab-alert@.service.d/99-zz-no-recursion.conf` and `/etc/systemd/user/homelab-alert@.service.d/99-zz-no-recursion.conf` setting an empty `OnFailure=` (which overrides `service.d/` in systemd's drop-in precedence and clears the `OnFailure` list for `homelab-alert@*.service`).
    2. `homelab-unit-alert` script immediately exits `0` if the target unit name matches `homelab-alert@*`.
    3. `ExecStart=-/usr/local/bin/homelab-unit-alert ...` inside `homelab-alert@.service` uses systemd's `-` prefix so any unexpected error inside the alert handler never marks `homelab-alert@.service` itself as failed.
  - For user units (such as `agy-remote-control.service` / `antigravity-cli-daemon.service` running under `admin`), `/etc/systemd/user/homelab-alert@.service` invokes `ExecStart=-/usr/bin/sudo -n /usr/local/bin/homelab-unit-alert --scope user --user %u --unit %i`, utilizing the existing `wheel` passwordless sudo policy while keeping `/etc/homelab/monitoring.env` strictly `0600 root:root`.
- **Rationale**:
  - Satisfies FR-006, User Story 1, and SC-001: any new systemd service or container wrapper deployed in the future automatically inherits `OnFailure=homelab-alert@%n.service` with zero per-service monitoring configuration.
  - Captures the failing unit's `ActiveState`, `SubState`, `ExecMainStatus`, `Result`, and the last 25 lines of `journalctl` output and dispatches a high-priority (`Priority: high` / `4`, tags `rotating_light,skull`) notification to `ntfy.sh`.
- **Alternatives Considered**:
  - Adding `OnFailure=` individually to each role's `.service.j2` template: Rejected because it requires touching every existing and future role and misses standard OS daemons (`sshd`, `chronyd`, `smartd`, `docker`, `tailscaled`, `caddy`, `nftables`).
  - Running a persistent journald log-scraping daemon: Rejected because event-driven `OnFailure=` is native to systemd, consumes zero idle memory/CPU, and triggers immediately on unit failure.

---

## 4. Scheduled Maintenance Job Instrumentation (Drop-In Hooks + Reusable Wrapper)

- **Decision**:
  - Provide `/usr/local/bin/homelab-hc-run --slug <slug> [--schedule <cron>] [--timeout <sec>] [--grace <sec>] -- <command> [args...]` as the universal CLI wrapper for any command or script (FR-007).
  - Provide `/usr/local/bin/homelab-hc-ping` and attach modular systemd drop-ins (`/etc/systemd/system/<unit>.service.d/10-healthchecks.conf`) to all 5 existing scheduled maintenance services (FR-008):
    - `homelab-backup.service` → slug `fidelacchius-backup-daily`
    - `homelab-backup-check.service` → slug `fidelacchius-backup-check`
    - `vaultwarden-backup.service` → slug `fidelacchius-vaultwarden-backup`
    - `snapraid-sync.service` → slug `fidelacchius-snapraid-sync`
    - `snapraid-scrub.service` → slug `fidelacchius-snapraid-scrub`
  - Each `10-healthchecks.conf` drop-in defines:
    ```ini
    [Service]
    ExecStartPre=-/usr/local/bin/homelab-hc-ping --slug <slug> --event start --unit %n
    ExecStopPost=-/usr/local/bin/homelab-hc-ping --slug <slug> --event stop --unit %n
    ```
  - During `ExecStopPost`, systemd sets `$SERVICE_RESULT` (`success`, `exit-code`, `timeout`, `signal`, etc.), `$EXIT_CODE`, and `$EXIT_STATUS`:
    - When `$SERVICE_RESULT == "success"` and `$EXIT_STATUS == "0"`, `homelab-hc-ping` silently signals `/0` (success) to `healthchecks.io` (and sends a recovery `ntfy` alert only if the component was previously in a failed state).
    - When `$SERVICE_RESULT != "success"`, `homelab-hc-ping` attaches the last 25 journal lines for `%n` to the `healthchecks.io` `/fail` (`/<exit-code>`) POST body, while the global `OnFailure=homelab-alert@%n.service` (or `homelab-hc-ping` via shared deduplication state) dispatches the immediate `ntfy.sh` failure notification without duplicating alerts.
- **Rationale**:
  - Satisfies Constitution Principle VI (*Modular & Decoupled Architecture*) and FR-007/FR-008: using systemd drop-ins in `/etc/systemd/system/<unit>.service.d/10-healthchecks.conf` instruments all 5 scheduled maintenance jobs without modifying the upstream `backup`, `vaultwarden`, or `snapraid` role service templates, while `homelab-hc-run` gives any future script or manual job a single-command wrapper that auto-creates its check on first execution.
- **Alternatives Considered**:
  - Modifying `homelab-backup`, `snapraid-runner.sh`, and `vaultwarden/scripts/backup.sh` directly to embed `curl` calls: Rejected because it tightly couples backup/storage logic with telemetry endpoints and wouldn't catch failures that happen before the script starts or after systemd kills a timed-out service.

---

## 5. Composite Host Liveness, Container Discovery, Endpoint Probes & Disk/SMART Monitoring

- **Decision**:
  - Deploy `/usr/local/bin/homelab-health-sweep` executed every 5 minutes by `homelab-heartbeat.service` / `homelab-heartbeat.timer` (`OnBootSec=2min`, `OnUnitActiveSec=5min`).
  - Each sweep performs 5 categories of verification:
    1. **Core System & User Daemons**: Verifies active state of `sshd`, `chronyd`, `smartd`, `systemd-oomd`, `nftables`, `tailscaled`, `caddy`, `docker`, `vaultwarden`, `frigate`, and user service `agy-remote-control.service` (when OAuth credentials exist).
    2. **Dynamic Docker Container Discovery (Current & Future)**: Queries `docker ps -a --format '{{.Names}}|{{.State}}|{{.Status}}'` and `docker inspect` health status for **all** containers on the host—automatically detecting any container in `unhealthy`, `restarting`, `dead`, or unexpected non-zero `exited` state without requiring a static container list (FR-010, SC-001).
    3. **Application & Ingress Readiness Probes**: Probes Caddy (`http://127.0.0.1:80/health`), Vaultwarden (`http://127.0.0.1:8088/alive`), Frigate (`http://127.0.0.1:5000/api/version`), and Tailscale backend state (`tailscale status --json` → `BackendState == "Running"`), with 3 transient retries (2s apart) before raising an alert (User Story 4).
    4. **Storage Mounts & Filesystem Capacity Thresholds**: Confirms mount points (`/mnt/disks/data1`, `/mnt/disks/data2`, `/mnt/disks/parity1`, `/mnt/storage`, `/mnt/scratch`, `/opt/services`) are active and evaluates `df -P` capacity usage against configurable warning (`85%`) and critical (`95%`) thresholds (FR-011).
    5. **Composite Heartbeat Signal**:
       - If all critical checks pass, `homelab-health-sweep` pings `fidelacchius-host-heartbeat` (`/0`) on `healthchecks.io` silently.
       - If any subsystem fails, `homelab-health-sweep` dispatches a deduplicated `ntfy.sh` alert per failing component and signals `/fail` (with diagnostic summary) to `fidelacchius-host-heartbeat`.
  - Integrate physical disk SMART alerts by configuring `/etc/smartd.conf` (`ansible/roles/disk_health`) with `-m <nomailer> -M exec /usr/local/bin/homelab-smartd-alert`, which translates `smartd` environment variables (`SMARTD_DEVICE`, `SMARTD_FAILTYPE`, `SMARTD_MESSAGE`, `SMARTD_FULLMESSAGE`) into high-priority `ntfy.sh` alerts (FR-011).
- **Rationale**:
  - Satisfies FR-009, FR-010, FR-011, FR-012, and User Stories 2 & 4: combines continuous application/container readiness checks with the dead-man's-switch liveness ping so neither hung containers, full disks, nor total host power loss can go unnoticed.
- **Alternatives Considered**:
  - Separate timers for container checks, disk space checks, and host heartbeat: Rejected under Minimalist Footprint because a single lightweight 5-minute sweep script (`homelab-health-sweep`) executes in `< 2` seconds, shares deduplication state cleanly, and gates the host heartbeat on overall platform health.

---

## 6. Alert Deduplication, Cooldown State Machine & Outbound Retry Policy

- **Decision**:
  - Centralize all outbound `ntfy.sh` notifications in `/usr/local/bin/homelab-ntfy`, maintaining per-component state files under `/var/lib/homelab/monitoring/state/<component_key>.json` (protected by `flock` on `/var/lib/homelab/monitoring/state/.lock`).
  - State machine rules (FR-005, FR-013, SC-004):
    - **Healthy (`status: "ok"`) when no prior failure state exists**: Silent no-op (zero `ntfy.sh` traffic when healthy).
    - **Failure/Warning (`status: "failing"` or `"warning"`) when component is currently `"ok"` or unseen, or when severity escalates (`warning` → `critical`)**: Immediately dispatch `ntfy.sh` notification and record `last_sent_epoch`, `status`, `severity`, and `message_hash`.
    - **Repeated Failure/Warning for same component within `MONITORING_COOLDOWN_SEC` (default `900` seconds / 15 minutes)**: Suppress duplicate notification and increment `suppressed_count` in state file, logging suppression to journald.
    - **Persistent Failure after cooldown expires**: Optionally re-notify only if `MONITORING_REPEAT_AFTER_COOLDOWN=true` (defaults to `true` with `3600s` repeat reminder, while flapping restarts within the 15-minute cooldown window are strictly suppressed so 5 consecutive restarts within 5 minutes emit exactly 1 failure alert and 1 recovery alert per SC-004).
    - **Recovery (`status: "ok"`) when component state was previously `"failing"` or `"warning"`**: Immediately clear the failure state and dispatch a recovery `ntfy.sh` notification (`Priority: default` / `3`, tags `white_check_mark,tada`, title `[RECOVERED] fidelacchius: <component>`).
  - Outbound HTTP calls (`curl`) to `ntfy.sh` and `healthchecks.io` use `--retry 3 --retry-delay 2 --retry-all-errors --connect-timeout 5 --max-time 15` so transient WAN/DNS blips are automatically retried with backoff without crashing the caller.
- **Rationale**:
  - Directly satisfies Edge Cases 2 & 3, FR-005, FR-013, and SC-004.

---

## 7. Secret Isolation & Offsite Restic Backup Integration

- **Decision**:
  - Define bootstrap credentials in `ansible/inventory/group_vars/all/vault.yml` (gitignored) and document sanitized placeholders in `ansible/inventory/group_vars/all/vault.yml.example`:
    - `vault_ntfy_server_url` (default `"https://ntfy.sh"`)
    - `vault_ntfy_topic` (mandatory secret topic name, e.g., `"fidelacchius-alerts-CHANGE_ME"`)
    - `vault_ntfy_token` (optional bearer token `tk_...` for protected topics, defaults to `""`)
    - `vault_healthchecks_api_key` (mandatory Read/Write Project API key from `healthchecks.io`)
    - `vault_healthchecks_ping_key` (optional project ping key; auto-discovered/cached via API v3 check URLs when omitted)
  - Render runtime environment file to `/etc/homelab/monitoring.env` (`0600 root:root`) and committed template to `/etc/homelab/monitoring.env.example` (`0644 root:root`).
  - Include `/etc/homelab/monitoring.env` and `/var/lib/homelab/monitoring/checks.json` in the Restic offsite backup manifest (`backup_include_paths` in `ansible/roles/backup/defaults/main.yml`).
- **Rationale**:
  - Satisfies Constitution Principles IV and V, FR-003, and FR-014: zero secrets exist in Git, only 2 mandatory secret values are required from the operator, and full disaster recovery restores both `vault.yml` and `/etc/homelab/monitoring.env` from Backblaze B2.
