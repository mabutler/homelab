# homelab2 Logging Standards

<!--
Template Resolution Hierarchy Specification:
This template is resolved by agent skills using the native 4-tier template resolution hierarchy:
- Tier 1 (Overrides): .specify/templates/overrides/logging-standards-template.md
- Tier 2 (Presets): .specify/presets/<preset-id>/templates/logging-standards-template.md (evaluated per .specify/presets/.registry sorted ascending by priority; strategy: replace, prepend, append, wrap)
- Tier 3 (Extensions): .specify/extensions/<ext-id>/templates/logging-standards-template.md (evaluated per .specify/extensions/.registry sorted ascending by priority)
- Tier 4 (Core Fallback): .specify/templates/logging-standards-template.md

Invariant: If a requested template is not found in any of the 4 tiers, the agent MUST fail closed and emit an error per Principle II.
-->

## Constitutional Authority & Precedence

This document operationalizes the telemetry, logging, and observability principles established in the **homelab2 Constitution** into concrete operational standards.

- **Authority Link**: Governed by the rules and principles defined in `.specify/memory/constitution.md` (or `constitution.md`), specifically Principle II (*Two-Tier Failure Model, Fail Closed on Required State & Strict Idempotency*), Principle III (*Automated Verification & Continuous Telemetry Gates*), and Principle VII (*Code Hygiene, Ubiquitous Language & Safe Logging*).
- **Precedence Declaration**: The Constitution ranks highest in authority. In any conflict between this Logging Standards document and the Core Principles of the Constitution, the Constitution strictly prevails.
- **Scope**: Applies to all production services, systemd units, maintenance timers, container workloads, operator CLI scripts, and diagnostic telemetry sinks across this repository.

---

## Severity Taxonomy

Telemetric event logging divides into four core severity levels mapped to the Two-Tier Failure Model, plus an optional fifth level (`TRACE`) for mechanical function tracing:

- **CRITICAL** — System, service unit, or convergence script halting immediately. Fatal defect invariants, violated preconditions, missing required secrets/mounts, or corrupted state (e.g., failed SQLite integrity check or storage array fault). MUST include failure context, exit code, and trigger immediate operator notification (via `ntfy.sh` alert hooks where applicable).
- **WARN** — Recoverable operation rejection, transient boundary failure, or threshold warning (e.g., disk usage >85% warning threshold, cooldown-suppressed duplicate alert, or non-critical probe retry) where execution continues. Declined or failed operations MUST NOT be hidden in DEBUG.
- **INFO** — Significant lifecycle milestone. States the operational or system outcome rather than internal diagnostic data; should read like an audit trail (e.g., backup snapshot creation start/completion, service convergence complete, healthcheck ping sent). Significant actions MUST log both attempt and result so mid-operation crashes leave a forensic record.
- **DEBUG** — Application or script interpretation of state and diagnostic reasoning prior to a milestone ("engineer's working notes", enabled via `--verbose` in operator scripts). Carries internal diagnostic reasoning; MUST NOT leak into INFO.
- **TRACE (Optional)** — Mechanical entry and exit logging on every function and return path with parameter and return values, when enabled by the project.

---

## Level Placement & Logging Mechanics

1. **Outcome vs. Diagnostic Reasoning**:
   - `INFO` states what happened (e.g., `"INFO: Restic backup snapshot completed for /opt/services/vaultwarden"`). `DEBUG` carries the diagnostic reasoning (e.g., `"DEBUG: Probe latency 42ms within 500ms threshold"`). Never put verbose diagnostic dumps in `INFO`.
2. **Attempt and Result Logging**:
   - Significant actions being taken (not just final outcomes) belong at `INFO` — log both the attempt and the result (e.g., `homelab-hc-run` `/start` ping and exit status ping) so that a crash or power loss mid-operation leaves a verifiable forensic record.
3. **Failures and Rejections**:
   - Declined, rejected, or failed-but-continuing operations MUST be logged at `WARN`, never hidden in `DEBUG`.
4. **Lifecycle Actions in Verbose Layers**:
   - An internal daemon, container service, or systemd oneshot unit logs its startup, initialization, and shutdown milestones at `INFO`. Recurring high-frequency polling work logs at `DEBUG` unless a state transition or failure occurs.
5. **No Redundant Callee Logging (When TRACE Is Enabled)**:
   - Do not re-log what a callee's `TRACE` already shows. If data is significant enough for `DEBUG`, prefer promoting that `TRACE` line to `DEBUG` over adding duplicate lines.

---

## TRACE Entry & Exit Rules (Optional)

*Applies only when mechanical `TRACE`-level function tracing is enabled for this project. Status for `homelab2`: **OMITTED** (disabled by default to maintain lean journald storage footprint).*

1. **Comprehensive Coverage**:
   - Mechanical entry and exit logging on every function and every return path.
   - An exit `TRACE` is required even when an `INFO` or `WARN` immediately precedes the return statement.
2. **Complex Object Representation**:
   - For complex object parameters, use a `ToString` override or a dedicated `ToTrace` helper with a fixed set of cheap properties. Do not select or extract arbitrary fields inline at each call site.
3. **External Library Seam**:
   - External library calls have no `TRACE`. Log what was returned or observed at `DEBUG` in the caller instead.

---

## Ambient Scope Correlation & Context

1. **Scope-Driven Correlation Tokens**:
   - Systemd unit invocations automatically bind `_SYSTEMD_UNIT`, `_PID`, and `SYSLOG_IDENTIFIER` in `journald`. Operator verification and maintenance scripts attach structured context fields (`host`, `phase`, `assertion_id`, `service_unit`, `timestamp`).
   - NEVER pass ad-hoc correlation strings manually across unrelated call sites when ambient unit/script metadata provides them.
2. **Structured Semantic Templates**:
   - All log messages and verification outputs MUST use consistent, parseable key-value or JSON structures (e.g., `"PASS: VW-05 - Local backend health probe (http://127.0.0.1:8088/alive -> HTTP 200)"` or `--json` structured payloads).
   - Unstructured, ambiguous free-text error messages that omit the failing component or assertion ID are prohibited.

---

## Forbidden Data & Redaction Policy

1. **Strictly Forbidden Data**:
   - Passwords, tokens, secrets, API keys, authentication credentials, and cryptographic private keys (including Backblaze B2 keys, Restic repository passwords, Tailscale auth keys, Vaultwarden admin tokens, ntfy tokens, Healthchecks.io ping keys, SOPS Age private keys, and SSH private keys) MUST NEVER appear in `journald`, console stdout/stderr, `ntfy.sh` push payloads, or persisted log files.
   - Full credit card numbers, SSNs, government identification numbers, or raw PII (Personally Identifiable Information) MUST NEVER be logged.
2. **Permitted Identifiers**:
   - Non-sensitive internal infrastructure identifiers (such as hostname `fidelacchius`, systemd unit names, assertion IDs like `VW-01` or `MON-01`, Restic snapshot short IDs, container names, and local mount paths) are permitted.

---

## Performance & Testing Boundary Rules

1. **Performance Level Guards**:
   - Guard verbose command outputs or diagnostic dumps behind explicit `VERBOSE=true` (`--verbose`) checks in shell scripts.
   - High-frequency events and repeated unit failures MUST be throttled or deduplicated (e.g., the 900-second `monitoring_cooldown_sec` alert suppression window in `/run/homelab-monitoring/`) rather than flooding `journald` or remote push notification channels.
2. **Testing Boundary Rule**:
   - Automated acceptance verification scripts (`scripts/verify-phase*.sh`) MUST verify live behavioral state contracts (HTTP status codes, systemd `is-active` states, file permissions, socket handshakes, Restic snapshot integrity) rather than brittle substring matching on human display formatting.

---

## Project Telemetry Configuration

This section specifies project-specific telemetry libraries, sinks, formats, and retention rules for **homelab2**.

### Logging Framework & Abstraction
- **Framework**: `systemd-journald` (`journalctl` / `systemd-cat`) for all host daemons, systemd timers, and Docker Compose service units; POSIX standard stream separation (`stdout` for primary output / `--json` payloads, `stderr` for diagnostic and error logging) with explicit severity prefixes (`CRITICAL`, `WARN`, `INFO`, `DEBUG`) in Bash and PowerShell automation scripts; Ansible `default` YAML stdout callback (`result_format = yaml` in `ansible/ansible.cfg`).

### Sinks, Destinations & Output Formats
- **Sinks & Formats**:
  1. **Local Persistent Journal**: `systemd-journald` storing structured binary/indexed logs under `/var/log/journal/` (`journald_storage: "persistent"`).
  2. **Off-Host Push Alerting & Dead-Man's Switch Telemetry**: `ntfy.sh` push alerts (triggered via `homelab-alert` and global `systemd` failure hooks) and `healthchecks.io` dead-man's switch heartbeats (via `homelab-hc-run` and 5-minute composite health sweeps).
  3. **Operator Verification Output**: Human-readable `PASS`/`FAIL` console output on `stdout`/`stderr`, or structured JSON report objects when `--json` is passed to `scripts/verify-phase*.sh`.

### Correlation Identifier Schema
- **Correlation Schema**: Systemd unit identifier (`_SYSTEMD_UNIT` / `SYSLOG_IDENTIFIER`, e.g., `vaultwarden.service`, `homelab-backup.service`), verification assertion ID (`VW-01..09`, `BK-01..08`, `AG-001..008`, `MON-01..10`), and Healthchecks.io check slug / UUID mapped in `/etc/homelab/hc-checks.json`.

### Redaction & Sanitization Mechanism
- **Redaction Engine**: Ansible `no_log: true` on all tasks handling secrets, tokens, or environment templates; isolated gitignored secret files (`/etc/homelab/vault.yml`, `/opt/services/*/.env`, `/etc/homelab/monitoring.env`) enforced at mode `0600`; and payload sanitization in `homelab-alert` ensuring push notifications transmit only unit names, exit statuses, and sanitized summary lines without environment variables or secret values.

### Retention & High-Frequency Sampling Policy
- **Retention & Sampling**: `systemd-journald` persistent storage is hard-capped at `2G` (`journald_system_max_use: "2G"` in `ansible/inventory/group_vars/all/vars.yml`) with automatic rotation. Alert notifications enforce a 15-minute per-unit deduplication cooldown (`monitoring_cooldown_sec: 900`) with state-machine recovery notifications. Mechanical `TRACE` entry/exit logging is `OMITTED`.
