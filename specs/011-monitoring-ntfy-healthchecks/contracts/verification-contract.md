# Contract: Automated Acceptance Verification (`MON-VERIFY-V1`)

**Feature**: `011-monitoring-ntfy-healthchecks`  
**Date**: 2026-11-05  
**Requirements Covered**: FR-001 through FR-015, SC-001 through SC-005, Constitution Principles III, IV, V

---

## 1. Verification Suite Overview

- **Target Host Script**: `scripts/verify-phase8-monitoring.sh` (supports `--json` output mode)
- **Workstation Wrapper**: `scripts/verify-phase8-monitoring.ps1`
- **Ansible Verification Playbook**: `ansible/playbooks/verify-phase8-monitoring.yml` (imported into `ansible/playbooks/verify.yml`)

---

## 2. Acceptance Test Matrix (`MON-01` to `MON-10`)

| Check ID | Requirement | Assertion Description | Verification Command / Condition |
|---|---|---|---|
| **MON-01** | FR-001, FR-003, FR-014, Principle IV | Secret isolation & zero secrets in Git: `/etc/homelab/monitoring.env` exists with `0600` (`root:root`), `/etc/homelab/monitoring.env.example` (`0644`) exists, `vault.yml.example` documents monitoring variables, and zero real API keys/tokens are tracked in Git | `stat -c '%a:%u:%g' /etc/homelab/monitoring.env` is `600:0:0`, `monitoring.env.example` exists, and `git grep` finds no real tokens |
| **MON-02** | FR-006, SC-001 | Global catch-all systemd failure hooks installed for both system and user units with recursion guards | `/etc/systemd/system/service.d/99-homelab-failure-alert.conf`, `/etc/systemd/user/service.d/99-homelab-failure-alert.conf`, `/etc/systemd/system/homelab-alert@.service`, `/etc/systemd/user/homelab-alert@.service`, and `99-zz-no-recursion.conf` drop-ins exist; `systemctl show sshd.service -p OnFailure` contains `homelab-alert@sshd.service` while `systemctl show homelab-alert@sshd.service -p OnFailure` is empty |
| **MON-03** | FR-002, FR-004, SC-002 | Zero-touch `healthchecks.io` reconciliation & local check registry (`checks.json`) | `/usr/local/bin/homelab-hc-reconcile` is executable (`0755`), `/etc/homelab/monitoring/checks-catalog.json` defines all 6 canonical slugs with `channels: "*"` and `unique: ["name", "slug"]`, and `/var/lib/homelab/monitoring/checks.json` (`0600`) contains resolved `ping_url` entries for all 6 checks |
| **MON-04** | FR-007, FR-008, SC-002 | Scheduled maintenance job instrumentation across all 5 platform timers + reusable `homelab-hc-run` wrapper | `/usr/local/bin/homelab-hc-run` and `/usr/local/bin/homelab-hc-ping` are executable (`0755`), and `10-healthchecks.conf` drop-ins are active on `homelab-backup.service`, `homelab-backup-check.service`, `vaultwarden-backup.service`, `snapraid-sync.service`, and `snapraid-scrub.service` (`systemctl show <unit> -p ExecStartPre -p ExecStopPost` references `homelab-hc-ping`) |
| **MON-05** | FR-009, FR-010, FR-012 | Composite health sweep service & 5-minute heartbeat timer active | `systemctl is-enabled homelab-heartbeat.timer` and `systemctl is-active homelab-heartbeat.timer` are `enabled`/`active`, and executing `/usr/local/bin/homelab-health-sweep` exits `0` |
| **MON-06** | FR-011 | Physical disk SMART alert hook & storage capacity monitoring | `/etc/smartd.conf` includes `-M exec /usr/local/bin/homelab-smartd-alert`, `/usr/local/bin/homelab-smartd-alert` is executable (`0755`), and `smartd.service` is `active` |
| **MON-07** | FR-005, FR-013, SC-004 | Alert deduplication, cooldown suppression & recovery state machine verification | Simulating 5 consecutive failure calls for a synthetic component `verify-flapping-test` within cooldown sends 1 initial alert and increments `suppressed_count == 4` in `/var/lib/homelab/monitoring/state/verify-flapping-test.json`, followed by `--status ok` dispatching 1 recovery alert and resetting state to `ok` |
| **MON-08** | FR-001, FR-004, SC-003 | Live `ntfy.sh` & `healthchecks.io` connectivity and synthetic failure hook delivery | Sending a synthetic unit failure / test alert and heartbeat ping succeeds within `< 30` seconds with HTTP `200`/`201` |
| **MON-09** | FR-014, Principle V | Offsite Restic backup coverage of monitoring configuration & secrets | `/etc/homelab/backup-include.txt` includes `/etc/homelab` (covering `/etc/homelab/monitoring.env` and `/etc/homelab/vault.yml`) and `/var/lib/homelab/monitoring/checks.json` |
| **MON-10** | FR-015, Principle III | Zero self-hosted monitoring containers & clean journal logs | `docker ps -a` contains no local `ntfy` or `healthchecks` server containers (FR-001), and `journalctl -u homelab-heartbeat.service` has zero unhandled script errors |
