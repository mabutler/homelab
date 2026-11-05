# Feature Specification: Automated Platform Monitoring & Alerting (`ntfy` & `Healthchecks`)

**Feature Branch**: `011-monitoring-ntfy-healthchecks`

**Created**: 2026-11-05

**Status**: Draft

**Input**: User description: "We need monitoring. I've used ntfy.sh and healthchecks.io before; I didn't mind them. I want this plugged into all existing apps and infrastructure and anything we add in the future. I don't want to have to manually configure everything within those; let's keep that minimal"

## Clarifications

### Session 2026-11-05

- Q: Hosting Model (`ntfy.sh` & `healthchecks.io`) (`FR-001`) → A: Option A — Hosted Cloud Services (`ntfy.sh` + `healthchecks.io`). No local monitoring containers are hosted on `fidelacchius`, ensuring dead-man's-switch alerts still fire during total server power loss or internet outages while requiring only API/topic credentials in `vault.yml`.
- Q: Notification Channel Routing (`FR-004`) → A: Option A — Unified `ntfy.sh` Push Channel. Both direct host alerts and `healthchecks.io` missed-heartbeat alerts route to the operator's `ntfy.sh` topic (with `healthchecks.io` checks automatically bound to all configured project channels, `channels: "*"`, via the Management API).
- Q: Alerting Verbosity & Trigger Policy (`FR-005`) → A: Option A — Failures, Warnings & Recoveries Only (Silent When Healthy). Routine healthy operations and scheduled jobs silently check in to `healthchecks.io`, while `ntfy.sh` notifications are dispatched strictly on failures, threshold warnings, missed heartbeats, and subsequent recoveries.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Immediate Event Alerting Across All Existing & Future Services (Priority: P1)

As a homelab administrator, I want any service crash, failed background task, disk health warning, storage capacity breach, or unhealthy application container across the entire server—including any service or application added in the future—to automatically trigger an actionable push notification via `ntfy`, so that I am immediately aware of failures without having to manually wire up each individual service.

**Why this priority**: Real-time failure awareness is the primary value of monitoring. Automatic catch-all hooks ensure that both today's stack and future additions are protected by default without ongoing manual configuration toil.

**Independent Test**: Can be fully tested by triggering a controlled synthetic service failure or test alert on the host and confirming that a structured notification containing the host name, failing component, severity, and diagnostic context arrives on the configured `ntfy` channel within seconds.

**Acceptance Scenarios**:

1. **Given** any existing system or user service (such as Vaultwarden, Frigate, Caddy, Tailscale, Docker, SnapRAID, Restic Backup, or Antigravity Remote Control), **When** the service unexpectedly exits with a failure status, **Then** the system automatically dispatches a high-priority notification with the failing unit name and recent diagnostic log lines.
2. **Given** a brand-new service or containerized application deployed in the future, **When** that new service fails or becomes unhealthy, **Then** it automatically triggers a failure notification without requiring the operator to manually register the new service in a monitoring dashboard.
3. **Given** physical disks or storage pools monitored on the host, **When** a disk reports a SMART health warning/temperature breach or a storage tier exceeds its safe capacity threshold, **Then** the system immediately sends a warning or critical alert identifying the affected disk or mount point.

---

### User Story 2 - Dead-Man's-Switch Heartbeats for Scheduled Jobs & Host Liveness (Priority: P1)

As a homelab administrator, I want periodic dead-man's-switch checks via `Healthchecks` for overall host liveness and every critical scheduled maintenance job (daily offsite backups, weekly backup integrity checks, Vaultwarden database snapshots, SnapRAID parity syncs, and SnapRAID parity scrubs), so that I am alerted even if a scheduled job silently fails to run or the entire server loses power or internet connectivity.

**Why this priority**: Push notifications sent directly from the server cannot fire if the server itself is powered off, hung, or disconnected from the network, or if a timer silently stops running. External or dead-man's-switch heartbeat monitoring closes this blind spot.

**Independent Test**: Can be tested independently by executing a scheduled job wrapper (such as the backup or parity runner) and verifying that `Healthchecks` records the start and completion (or failure) signals for that check, and that pausing a heartbeat past its grace window triggers a missed-heartbeat alert.

**Acceptance Scenarios**:

1. **Given** the host liveness heartbeat service, **When** the server is operating normally and connected to the network, **Then** it periodically pings its liveness check; if the server goes offline or hangs beyond the configured grace period, `Healthchecks` triggers an outage alert.
2. **Given** any scheduled maintenance job (offsite Restic backup, Restic repository check, Vaultwarden snapshot, SnapRAID sync, or SnapRAID scrub), **When** the job starts and finishes, **Then** the system signals job start, success, or failure to `Healthchecks` along with execution status context.
3. **Given** a scheduled maintenance job that fails to run on schedule (e.g., disabled timer or stalled process), **When** the expected schedule plus grace period elapses without a completion signal, **Then** `Healthchecks` raises a missed-check alert to the operator.

---

### User Story 3 - Zero-Touch Auto-Provisioning & Minimal Manual Setup (Priority: P1)

As a homelab administrator who wants minimal manual configuration inside `ntfy` and `Healthchecks`, I want to supply only a minimal set of bootstrap credentials in the local secret store (such as an API key and notification topic/endpoint), and have the automation automatically create, update, tag, and configure all required checks, schedules, grace periods, and notification bindings on my behalf.

**Why this priority**: The user explicitly requested keeping manual configuration within `ntfy.sh` and `healthchecks.io` to a bare minimum and ensuring future apps/infrastructure plug in automatically.

**Independent Test**: Can be tested by starting with a blank `Healthchecks` project and an empty `ntfy` topic, running the deployment automation with only the bootstrap credentials configured in the local secret store, and verifying that all checks, schedules, and notification channels are provisioned and active with zero manual UI setup.

**Acceptance Scenarios**:

1. **Given** a valid API key and notification topic in the host's isolated secret configuration, **When** the monitoring automation runs, **Then** it automatically provisions or updates all expected checks (names, slugs, schedules, and grace periods) via the service API without duplicating existing checks.
2. **Given** a new scheduled job or application added to the platform in the future, **When** it uses the standard monitoring wrapper or declarative role defaults, **Then** its corresponding check is automatically created and configured on first deployment or execution without the operator logging into the `Healthchecks` web interface.
3. **Given** the repository source tree, **When** audited for secrets, **Then** zero API keys, private topic tokens, or webhook credentials exist in version control (only sanitized `.example` templates are committed), and all local monitoring secrets are included in the encrypted offsite backup.

---

### User Story 4 - Application & Container Health Verification (Priority: P2)

As a homelab administrator, I want continuous health verification across all running applications and infrastructure endpoints (Caddy ingress, Vaultwarden, Frigate NVR, Docker container health statuses, storage mounts, and Tailscale VPN connectivity), so that degraded application states are detected and reported even when the underlying service process has not completely exited.

**Why this priority**: A container or web application can hang or fail its internal health check while the parent service wrapper remains active. Monitoring application-level readiness ensures comprehensive end-to-end coverage.

**Independent Test**: Can be tested by simulating an unhealthy container or unreachable local application health endpoint and confirming that the monitoring check detects the unhealthy state and dispatches an alert.

**Acceptance Scenarios**:

1. **Given** all running application containers with health checks (such as Vaultwarden and Frigate) and core endpoints (such as Caddy `/health`), **When** periodic health verification runs and all components are healthy, **Then** the system records healthy status and sends the host/application heartbeat ping.
2. **Given** an application container that enters an `unhealthy` state or fails its local HTTP health probe, **When** the condition persists beyond the transient retry window, **Then** the system sends a targeted alert identifying the unhealthy application and suppresses duplicate spam until recovery.

---

### Edge Cases

- **Total Server Power Loss or Internet Outage**: What happens if the homelab server (`fidelacchius`) loses power completely, suffers a kernel panic, or loses WAN connectivity?
  *Requirement: Dead-man's-switch checks must detect the missing heartbeat after the configured grace period and dispatch an outage notification without relying on the offline homelab server to send the alert.*
- **Alert Storms & Flapping Services**: What happens if a failing service restarts repeatedly in a tight loop or multiple dependent components fail simultaneously?
  *Requirement: The notification dispatcher must apply rate-limiting/deduplication (cooldown window per component) so the operator receives a clear failure notification rather than hundreds of duplicate push alerts.*
- **Transient Network Blips During Outbound Alerts**: What happens if the server experiences a brief 10-second DNS or WAN drop right when a job finishes or a service alert is triggered?
  *Requirement: Outbound notification and heartbeat calls must include automatic retry with backoff and log any delivery failure to the system journal without crashing the monitored workload.*
- **Unconfigured or Placeholder Secrets During Initial Setup**: What happens if the playbook or verification suite runs before the operator has populated real external credentials, or during dry-run checks?
  *Requirement: Pre-flight validation must clearly verify required secret variables and fail fast with actionable instructions if required secrets are missing or left as template placeholders.*
- **Disk Space Exhaustion on Storage Tiers**: What happens when the root filesystem, `/opt/services`, `/mnt/storage` (MergerFS/data disks), or `/mnt/scratch` approaches capacity?
  *Requirement: Proactive disk usage checks must alert when any monitored filesystem crosses a configurable warning threshold (e.g., 85% full) and critical threshold (e.g., 95% full) before writes fail.*

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST integrate the hosted cloud services `ntfy.sh` (for real-time push notifications) and `healthchecks.io` (for external dead-man's-switch heartbeat monitoring) without deploying self-hosted monitoring server containers on `fidelacchius`, ensuring outage detection survives complete host power loss or WAN disconnection.
- **FR-002**: System MUST automatically reconcile and provision all `healthchecks.io` check entries (including name, unique slug, tags, expected schedule/period, grace time, and `channels: "*"` binding) via the `healthchecks.io` Management API so the operator does not have to manually create or update individual checks in the web interface.
- **FR-003**: System MUST require only a minimal set of operator-supplied bootstrap values in the gitignored secret store (`vault.yml` — specifically the `healthchecks.io` Read/Write Project API Key, optional `ntfy.sh` access token, and target `ntfy.sh` topic/server URL), accompanied by committed `.example` templates documenting each variable.
- **FR-004**: System MUST use the operator's `ntfy.sh` topic as the unified notification destination for both direct host event alerts and `healthchecks.io` missed-heartbeat alerts (automatically attaching all provisioned checks to the project's configured `ntfy.sh` integration channel via API).
- **FR-005**: System MUST enforce a silent-when-healthy alerting policy where push notifications are dispatched strictly on failures, threshold warnings, missed heartbeats, and subsequent recoveries, while routine scheduled job completions silently record success in `healthchecks.io`.
- **FR-006**: System MUST install a global, catch-all service failure hook across systemd system and user units so that any existing or future service/timer failure automatically triggers an `ntfy` alert containing the hostname, unit name, failure status, and recent journal log excerpt without requiring manual per-unit monitoring configuration.
- **FR-007**: System MUST provide a reusable command wrapper or hook mechanism for scheduled jobs that automatically signals job start (`/start`), completion (`/0`), or failure (`/<exit-code>` plus diagnostic log payload) to `Healthchecks` and dispatches an `ntfy` alert on failure, auto-creating the check if it does not yet exist.
- **FR-008**: System MUST integrate all existing scheduled maintenance jobs into dead-man's-switch and failure monitoring:
  - Daily offsite Restic backup (`homelab-backup.service` / `.timer`)
  - Weekly Restic repository integrity check (`homelab-backup-check.service` / `.timer`)
  - Daily Vaultwarden SQLite transactional backup (`vaultwarden-backup.service` / `.timer`)
  - Daily SnapRAID parity sync (`snapraid-sync.service` / `.timer`)
  - Weekly SnapRAID parity scrub (`snapraid-scrub.service` / `.timer`)
- **FR-009**: System MUST monitor all existing continuous infrastructure and application services—including `sshd`, `chronyd`, `smartd`, `systemd-oomd`, `nftables`, `tailscaled`, `caddy`, `docker`, `vaultwarden`, `frigate`, and `agy-remote-control`—for both unit failure and container/endpoint health readiness.
- **FR-010**: System MUST automatically discover and evaluate all running Docker containers on the host (current and future) during periodic health sweeps, alerting if any container enters an `unhealthy`, `restarting`, or unexpected exited state.
- **FR-011**: System MUST integrate physical disk SMART monitoring (`smartd`) and filesystem capacity checks (`/`, `/opt/services`, `/mnt/storage`, `/mnt/disks/*`, `/mnt/scratch`) with the notification dispatcher to alert immediately on disk errors, temperature threshold breaches, missing mounts, or low disk space.
- **FR-012**: System MUST run a periodic host liveness and composite health heartbeat that pings `Healthchecks` only when core network, storage mounts, and critical services pass health verification, ensuring dead-man's-switch alerts trigger if the host goes offline or critical subsystems hang.
- **FR-013**: System MUST implement per-component alert deduplication/cooldown suppression to prevent notification flooding during repeated restart loops or cascading failures, while guaranteeing recovery notifications when a failing component returns to a healthy state.
- **FR-014**: System MUST include all local monitoring configuration and gitignored secret files in the host's encrypted offsite Restic backup manifest and verify that zero plaintext or encrypted secrets are tracked in Git.
- **FR-015**: System MUST provide an automated verification playbook and script that validates end-to-end monitoring configuration, secret isolation, check registration, hook installation, and live test alert/heartbeat connectivity.

### Key Entities

- **Notification Channel (`ntfy` Topic)**: The push notification destination carrying structured alert messages with title, severity priority, descriptive tags, and diagnostic context.
- **Heartbeat Check (`Healthchecks` Check)**: A dead-man's-switch monitor identified by a deterministic slug (e.g., `fidelacchius-host-heartbeat`, `fidelacchius-backup-daily`, `fidelacchius-snapraid-sync`), configured with an expected schedule/interval, grace period, and current status (`up`, `down`, `grace`, `new`).
- **Alert Event**: A discrete failure, warning, or recovery event generated by a service failure hook, disk/storage monitor, container health sweep, or failed scheduled task, tracked locally for cooldown/deduplication state.
- **Monitoring Bootstrap Profile**: The minimal set of operator credentials stored in the local gitignored secret store used to authenticate against `ntfy` and `Healthchecks` and automatically manage checks.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Adding a new systemd service or Docker container with a standard healthcheck requires 0 manual configuration changes in `ntfy` or `Healthchecks` for failure alerts to function automatically.
- **SC-002**: 100% of existing scheduled maintenance jobs (Restic backup, Restic check, Vaultwarden backup, SnapRAID sync, SnapRAID scrub) and host liveness checks are automatically provisioned and tracked in `Healthchecks` during deployment without manual UI interaction.
- **SC-003**: Simulated service failures or disk/storage warnings generate and deliver a structured push notification to `ntfy` within 30 seconds of failure detection.
- **SC-004**: During a simulated service crash loop (e.g., 5 consecutive restarts within 5 minutes), the operator receives 1 initial failure alert and 1 recovery alert upon resolution, preventing duplicate alert flooding.
- **SC-005**: 100% of automated verification checks pass (confirming active systemd hooks, auto-provisioned healthchecks, disk/storage alert wiring, backup inclusion, and zero secrets in version control).

## Assumptions

- **Platform Prerequisites**: Phases 1 through 5 and Phase 7 (`fidelacchius` host, systemd, Docker, Caddy, Tailscale, MergerFS/SnapRAID, Restic B2 backup, Vaultwarden, Frigate, and Antigravity Remote Control) are already deployed and managed via Ansible in this repository.
- **External Cloud Services & Minimal Bootstrap**: `ntfy.sh` and `healthchecks.io` are consumed as hosted cloud SaaS services. The operator only needs to perform a one-time setup of a `healthchecks.io` project (configuring its built-in `ntfy` / webhook integration pointing to their `ntfy.sh` topic and copying the Project API Key) and place the `healthchecks.io` API key and `ntfy.sh` topic/token into `vault.yml`. All individual checks, schedules, tags, and channel bindings (`channels: "*"`) are automatically provisioned by the platform.
- **Network Connectivity**: The homelab host has outbound HTTPS connectivity to `https://ntfy.sh` and `https://healthchecks.io` (and `https://hc-ping.com`).
- **Idempotent Upsert via Slug/Name**: `healthchecks.io` supports unique check creation and updates via its Management API (`POST /api/v3/checks/` with `"unique": ["name", "slug"]`), allowing Ansible and host wrapper scripts to idempotently ensure checks exist without creating duplicates on repeated runs.
- **Reasonable Default Thresholds**: Unless overridden by host variables, filesystem capacity warnings default to 85% usage (critical at 95%), host liveness heartbeats run every 5 minutes with a 10-minute grace period, and alert deduplication cooldown defaults to 15 minutes per failing component.
